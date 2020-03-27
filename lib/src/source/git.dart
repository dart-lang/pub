// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:pub_semver/pub_semver.dart';

import '../git.dart' as git;
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'cached.dart';

/// A package source that gets packages from Git repos.
class GitSource extends Source {
  @override
  final name = 'git';

  @override
  BoundGitSource bind(SystemCache systemCache) =>
      BoundGitSource(this, systemCache);

  /// Returns a reference to a git package with the given [name] and [url].
  ///
  /// If passed, [reference] is the Git reference. It defaults to `"HEAD"`.
  PackageRef refFor(String name, String url, {String reference, String path}) {
    if (path != null) assert(p.url.isRelative(path));
    return PackageRef(name, this,
        {'url': url, 'ref': reference ?? 'HEAD', 'path': path ?? '.'});
  }

  /// Given a valid git package description, returns the URL of the repository
  /// it pulls from.
  String urlFromDescription(description) => description['url'];

  @override
  PackageRef parseRef(String name, description, {String containingPath}) {
    // TODO(rnystrom): Handle git URLs that are relative file paths (#8570).
    if (description is String) description = {'url': description};

    if (description is! Map) {
      throw FormatException('The description must be a Git URL or a map '
          "with a 'url' key.");
    }

    if (description['url'] is! String) {
      throw FormatException("The 'url' field of the description must be a "
          'string.');
    }

    _validateUrl(description['url']);

    var ref = description['ref'];
    if (ref != null && ref is! String) {
      throw FormatException("The 'ref' field of the description must be a "
          'string.');
    }

    var path = description['path'];
    if (path != null) {
      if (path is! String) {
        throw FormatException(
            "The 'path' field of the description must be a string.");
      } else if (!p.url.isRelative(path)) {
        throw FormatException(
            "The 'path' field of the description must be relative.");
      } else if (!p.url.isWithin('.', path)) {
        throw FormatException(
            "The 'path' field of the description must not reach outside the "
            'repository.');
      }

      _validateUrl(path);
    }

    return PackageRef(name, this,
        {'url': description['url'], 'ref': ref ?? 'HEAD', 'path': path ?? '.'});
  }

  @override
  PackageId parseId(String name, Version version, description,
      {String containingPath}) {
    if (description is! Map) {
      throw FormatException("The description must be a map with a 'url' "
          'key.');
    }

    if (description['url'] is! String) {
      throw FormatException("The 'url' field of the description must be a "
          'string.');
    }

    _validateUrl(description['url']);

    var ref = description['ref'];
    if (ref != null && ref is! String) {
      throw FormatException("The 'ref' field of the description must be a "
          'string.');
    }

    if (description['resolved-ref'] is! String) {
      throw FormatException("The 'resolved-ref' field of the description "
          'must be a string.');
    }

    var path = description['path'];
    if (path != null) {
      if (path is! String) {
        throw FormatException(
            "The 'path' field of the description must be a string.");
      } else if (!p.url.isRelative(path)) {
        throw FormatException(
            "The 'path' field of the description must be relative.");
      }

      _validateUrl(path);
    }

    return PackageId(name, this, version, {
      'url': description['url'],
      'ref': ref ?? 'HEAD',
      'resolved-ref': description['resolved-ref'],
      'path': path ?? '.'
    });
  }

  /// Throws a [FormatException] if [url] isn't a valid Git URL.
  void _validateUrl(String url) {
    // If the URL contains an @, it's probably an SSH hostname, which we don't
    // know how to validate.
    if (url.contains('@')) return;

    // Otherwise, we use Dart's URL parser to validate the URL.
    Uri.parse(url);
  }

  /// If [description] has a resolved ref, print it out in short-form.
  ///
  /// This helps distinguish different git commits with the same pubspec
  /// version.
  @override
  String formatDescription(description) {
    if (description is Map && description.containsKey('resolved-ref')) {
      var result = "${description['url']} at "
          "${description['resolved-ref'].substring(0, 6)}";
      if (description['path'] != '.') result += " in ${description["path"]}";
      return result;
    } else {
      return super.formatDescription(description);
    }
  }

  /// Two Git descriptions are equal if both their URLs and their refs are
  /// equal.
  @override
  bool descriptionsEqual(description1, description2) {
    // TODO(nweiz): Do we really want to throw an error if you have two
    // dependencies on some repo, one of which specifies a ref and one of which
    // doesn't? If not, how do we handle that case in the version solver?
    if (description1['url'] != description2['url']) return false;
    if (description1['ref'] != description2['ref']) return false;
    if (description1['path'] != description2['path']) return false;

    if (description1.containsKey('resolved-ref') &&
        description2.containsKey('resolved-ref')) {
      return description1['resolved-ref'] == description2['resolved-ref'];
    }

    return true;
  }

  @override
  int hashDescription(description) {
    // Don't include the resolved ref in the hash code because we ignore it in
    // [descriptionsEqual] if only one description defines it.
    return description['url'].hashCode ^
        description['ref'].hashCode ^
        description['path'].hashCode;
  }
}

/// The [BoundSource] for [GitSource].
class BoundGitSource extends CachedSource {
  /// Limit the number of concurrent git operations to 1.
  // TODO(sigurdm): Use RateLimitedScheduler.
  final Pool _pool = Pool(1);

  @override
  final GitSource source;

  @override
  final SystemCache systemCache;

  /// A map from revision cache locations to futures that will complete once
  /// they're finished being cloned.
  ///
  /// This lets us avoid race conditions when getting multiple different
  /// packages from the same repository.
  final _revisionCacheClones = <String, Future>{};

  /// The paths to the canonical clones of repositories for which "git fetch"
  /// has already been run during this run of pub.
  final _updatedRepos = <String>{};

  BoundGitSource(this.source, this.systemCache);

  /// Given a Git repo that contains a pub package, gets the name of the pub
  /// package.
  Future<String> getPackageNameFromRepo(String repo) {
    // Clone the repo to a temp directory.
    return withTempDir((tempDir) async {
      await _clone(repo, tempDir, shallow: true);
      var pubspec = Pubspec.load(tempDir, systemCache.sources);
      return pubspec.name;
    });
  }

  @override
  Future<List<PackageId>> doGetVersions(PackageRef ref) async {
    return await _pool.withResource(() async {
      await _ensureRepoCache(ref);
      var path = _repoCachePath(ref);
      var revision = await _firstRevision(path, ref.description['ref']);
      var pubspec =
          await _describeUncached(ref, revision, ref.description['path']);

      return [
        PackageId(ref.name, source, pubspec.version, {
          'url': ref.description['url'],
          'ref': ref.description['ref'],
          'resolved-ref': revision,
          'path': ref.description['path']
        })
      ];
    });
  }

  /// Since we don't have an easy way to read from a remote Git repo, this
  /// just installs [id] into the system cache, then describes it from there.
  @override
  Future<Pubspec> describeUncached(PackageId id) {
    return _pool.withResource(() => _describeUncached(
        id.toRef(), id.description['resolved-ref'], id.description['path']));
  }

  /// Like [describeUncached], but takes a separate [ref] and Git [revision]
  /// rather than a single ID.
  Future<Pubspec> _describeUncached(
      PackageRef ref, String revision, String path) async {
    await _ensureRevision(ref, revision);
    var repoPath = _repoCachePath(ref);

    // Normalize the path because Git treats "./" at the beginning of a path
    // specially.
    var pubspecPath = p.normalize(p.join(p.fromUri(path), 'pubspec.yaml'));

    // Git doesn't recognize backslashes in paths, even on Windows.
    if (Platform.isWindows) pubspecPath = pubspecPath.replaceAll('\\', '/');

    List<String> lines;
    try {
      lines = await git
          .run(['show', '$revision:$pubspecPath'], workingDir: repoPath);
    } on git.GitException catch (_) {
      fail('Could not find a file named "$pubspecPath" in '
          '${ref.description['url']} $revision.');
    }

    return Pubspec.parse(lines.join('\n'), systemCache.sources,
        expectedName: ref.name);
  }

  /// Clones a Git repo to the local filesystem.
  ///
  /// The Git cache directory is a little idiosyncratic. At the top level, it
  /// contains a directory for each commit of each repository, named `<package
  /// name>-<commit hash>`. These are the canonical package directories that are
  /// linked to from the `packages/` directory.
  ///
  /// In addition, the Git system cache contains a subdirectory named `cache/`
  /// which contains a directory for each separate repository URL, named
  /// `<package name>-<url hash>`. These are used to check out the repository
  /// itself; each of the commit-specific directories are clones of a directory
  /// in `cache/`.
  @override
  Future<Package> downloadToSystemCache(PackageId id) async {
    return await _pool.withResource(() async {
      var ref = id.toRef();
      if (!git.isInstalled) {
        fail("Cannot get ${id.name} from Git (${ref.description['url']}).\n"
            'Please ensure Git is correctly installed.');
      }

      ensureDir(p.join(systemCacheRoot, 'cache'));
      await _ensureRevision(ref, id.description['resolved-ref']);

      var revisionCachePath = _revisionCachePath(id);
      await _revisionCacheClones.putIfAbsent(revisionCachePath, () async {
        if (!entryExists(revisionCachePath)) {
          await _clone(_repoCachePath(ref), revisionCachePath);
          await _checkOut(revisionCachePath, id.description['resolved-ref']);
          _writePackageList(revisionCachePath, [id.description['path']]);
        } else {
          _updatePackageList(revisionCachePath, id.description['path']);
        }
      });

      return Package.load(
          id.name,
          p.join(revisionCachePath, id.description['path']),
          systemCache.sources);
    });
  }

  /// Returns the path to the revision-specific cache of [id].
  @override
  String getDirectory(PackageId id) =>
      p.join(_revisionCachePath(id), id.description['path']);

  @override
  List<Package> getCachedPackages() {
    // TODO(keertip): Implement getCachedPackages().
    throw UnimplementedError(
        "The git source doesn't support listing its cached packages yet.");
  }

  /// Resets all cached packages back to the pristine state of the Git
  /// repository at the revision they are pinned to.
  @override
  Future<Iterable<RepairResult>> repairCachedPackages() async {
    if (!dirExists(systemCacheRoot)) return [];

    final result = <RepairResult>[];

    var packages = listDir(systemCacheRoot)
        .where((entry) => dirExists(p.join(entry, '.git')))
        .expand((revisionCachePath) {
          return _readPackageList(revisionCachePath).map((relative) {
            // If we've already failed to load another package from this
            // repository, ignore it.
            if (!dirExists(revisionCachePath)) return null;

            var packageDir = p.join(revisionCachePath, relative);
            try {
              return Package.load(null, packageDir, systemCache.sources);
            } catch (error, stackTrace) {
              log.error('Failed to load package', error, stackTrace);
              var name = p.basename(revisionCachePath).split('-').first;
              result.add(RepairResult(
                  PackageId(name, source, Version.none, '???'),
                  success: false));
              tryDeleteEntry(revisionCachePath);
              return null;
            }
          });
        })
        .where((package) => package != null)
        .toList();

    // Note that there may be multiple packages with the same name and version
    // (pinned to different commits). The sort order of those is unspecified.
    packages.sort(Package.orderByNameAndVersion);

    for (var package in packages) {
      // If we've already failed to repair another package in this repository,
      // ignore it.
      if (!dirExists(package.dir)) continue;

      var id = PackageId(package.name, source, package.version, null);

      log.message('Resetting Git repository for '
          '${log.bold(package.name)} ${package.version}...');

      try {
        // Remove all untracked files.
        await git
            .run(['clean', '-d', '--force', '-x'], workingDir: package.dir);

        // Discard all changes to tracked files.
        await git.run(['reset', '--hard', 'HEAD'], workingDir: package.dir);

        result.add(RepairResult(id, success: true));
      } on git.GitException catch (error, stackTrace) {
        log.error('Failed to reset ${log.bold(package.name)} '
            '${package.version}. Error:\n$error');
        log.fine(stackTrace);
        result.add(RepairResult(id, success: false));

        // Delete the revision cache path, not the subdirectory that contains the package.
        tryDeleteEntry(getDirectory(id));
      }
    }

    return result;
  }

  /// Ensures that the canonical clone of the repository referred to by [ref]
  /// contains the given Git [revision].
  Future _ensureRevision(PackageRef ref, String revision) async {
    var path = _repoCachePath(ref);
    if (_updatedRepos.contains(path)) return;

    await _deleteGitRepoIfInvalid(path);

    if (!entryExists(path)) await _createRepoCache(ref);

    // Try to list the revision. If it doesn't exist, git will fail and we'll
    // know we have to update the repository.
    try {
      await _firstRevision(path, revision);
    } on git.GitException catch (_) {
      await _updateRepoCache(ref);
    }
  }

  /// Ensures that the canonical clone of the repository referred to by [ref]
  /// exists and is up-to-date.
  Future _ensureRepoCache(PackageRef ref) async {
    var path = _repoCachePath(ref);
    if (_updatedRepos.contains(path)) return;

    await _deleteGitRepoIfInvalid(path);

    if (!entryExists(path)) {
      await _createRepoCache(ref);
    } else {
      await _updateRepoCache(ref);
    }
  }

  /// Creates the canonical clone of the repository referred to by [ref].
  ///
  /// This assumes that the canonical clone doesn't yet exist.
  Future _createRepoCache(PackageRef ref) async {
    var path = _repoCachePath(ref);
    assert(!_updatedRepos.contains(path));

    try {
      await _clone(ref.description['url'], path, mirror: true);
    } catch (_) {
      await _deleteGitRepoIfInvalid(path);
      rethrow;
    }
    _updatedRepos.add(path);
  }

  /// Runs "git fetch" in the canonical clone of the repository referred to by
  /// [ref].
  ///
  /// This assumes that the canonical clone already exists.
  Future _updateRepoCache(PackageRef ref) async {
    var path = _repoCachePath(ref);
    if (_updatedRepos.contains(path)) return Future.value();
    await git.run(['fetch'], workingDir: path);
    _updatedRepos.add(path);
  }

  /// Clean-up [dirPath] if it's an invalid git repository.
  ///
  /// The git clones in the `PUB_CACHE` folder should never be invalid. But this
  /// can happen if the clone operation failed in some way, and the program did
  /// not exit gracefully, leaving the cache git clone in a dirty state.
  Future<void> _deleteGitRepoIfInvalid(String dirPath) async {
    if (!dirExists(dirPath)) {
      return;
    }
    var isValid = true;
    try {
      final result = await git.run(
        ['rev-parse', '--is-inside-git-dir'],
        workingDir: dirPath,
      );
      if (result?.join('\n') != 'true') {
        isValid = false;
      }
    } on git.GitException {
      isValid = false;
    }
    // If [dirPath] is not a valid git repository we remove it.
    if (!isValid) {
      deleteEntry(dirPath);
    }
  }

  /// Updates the package list file in [revisionCachePath] to include [path], if
  /// necessary.
  void _updatePackageList(String revisionCachePath, String path) {
    var packages = _readPackageList(revisionCachePath);
    if (packages.contains(path)) return;

    _writePackageList(revisionCachePath, packages..add(path));
  }

  /// Returns the list of packages in [revisionCachePath].
  List<String> _readPackageList(String revisionCachePath) {
    var path = _packageListPath(revisionCachePath);

    // If there's no package list file, this cache was created by an older
    // version of pub where pubspecs were only allowed at the root of the
    // repository.
    if (!fileExists(path)) return ['.'];
    return readTextFile(path).split('\n');
  }

  /// Writes a package list indicating that [packages] exist in
  /// [revisionCachePath].
  void _writePackageList(String revisionCachePath, List<String> packages) {
    writeTextFile(_packageListPath(revisionCachePath), packages.join('\n'));
  }

  /// The path in a revision cache repository in which we keep a list of the
  /// packages in the repository.
  String _packageListPath(String revisionCachePath) =>
      p.join(revisionCachePath, '.git/pub-packages');

  /// Runs "git rev-list" on [reference] in [path] and returns the first result.
  ///
  /// This assumes that the canonical clone already exists.
  Future<String> _firstRevision(String path, String reference) async {
    var lines = await git
        .run(['rev-list', '--max-count=1', reference], workingDir: path);
    return lines.first;
  }

  /// Clones the repo at the URI [from] to the path [to] on the local
  /// filesystem.
  ///
  /// If [mirror] is true, creates a bare, mirrored clone. This doesn't check
  /// out the working tree, but instead makes the repository a local mirror of
  /// the remote repository. See the manpage for `git clone` for more
  /// information.
  ///
  /// If [shallow] is true, creates a shallow clone that contains no history
  /// for the repository.
  Future _clone(String from, String to,
      {bool mirror = false, bool shallow = false}) {
    return Future.sync(() {
      // Git on Windows does not seem to automatically create the destination
      // directory.
      ensureDir(to);
      var args = ['clone', from, to];

      if (mirror) args.insert(1, '--mirror');
      if (shallow) args.insertAll(1, ['--depth', '1']);

      return git.run(args);
    }).then((result) => null);
  }

  /// Checks out the reference [ref] in [repoPath].
  Future _checkOut(String repoPath, String ref) {
    return git
        .run(['checkout', ref], workingDir: repoPath).then((result) => null);
  }

  String _revisionCachePath(PackageId id) => p.join(
      systemCacheRoot, "${_repoName(id)}-${id.description['resolved-ref']}");

  /// Returns the path to the canonical clone of the repository referred to by
  /// [id] (the one in `<system cache>/git/cache`).
  String _repoCachePath(PackageRef ref) {
    var repoCacheName = '${_repoName(ref)}-${sha1(ref.description['url'])}';
    return p.join(systemCacheRoot, 'cache', repoCacheName);
  }

  /// Returns a short, human-readable name for the repository URL in [packageName].
  ///
  /// This name is not guaranteed to be unique.
  String _repoName(PackageName packageName) {
    var name = p.url.basename(packageName.description['url']);
    if (name.endsWith('.git')) {
      name = name.substring(0, name.length - '.git'.length);
    }
    return name;
  }
}
