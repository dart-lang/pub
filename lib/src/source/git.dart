// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart' show IterableNullableExtension;
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:pub_semver/pub_semver.dart';

import '../git.dart' as git;
import '../io.dart';
import '../language_version.dart';
import '../log.dart' as log;
import '../package.dart';
import '../package_name.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'cached.dart';

/// A package source that gets packages from Git repos.
class GitSource extends CachedSource {
  static GitSource instance = GitSource._();

  GitSource._();

  @override
  final name = 'git';

  @override
  PackageRef parseRef(
    String name,
    Object? description, {
    String? containingDir,
    LanguageVersion? languageVersion,
  }) {
    String url;
    String? ref;
    String? path;
    if (description is String) {
      url = description;
    } else if (description is! Map) {
      throw FormatException('The description must be a Git URL or a map '
          "with a 'url' key.");
    } else {
      final descriptionUrl = description['url'];
      if (descriptionUrl is! String) {
        throw FormatException(
            "The 'url' field of a description must be a string.");
      }
      url = descriptionUrl;

      final descriptionRef = description['ref'];
      if (descriptionRef is! String?) {
        throw FormatException("The 'ref' field of the description must be a "
            'string.');
      }
      ref = descriptionRef;

      final descriptionPath = description['path'];
      if (descriptionPath is! String?) {
        throw FormatException("The 'path' field of the description must be a "
            'string.');
      }
      path = descriptionPath;
    }

    return PackageRef(
      name,
      GitDescription(
        url: url,
        containingDir: containingDir,
        ref: ref,
        path: _validatedPath(path),
      ),
    );
  }

  @override
  PackageId parseId(String name, Version version, description,
      {String? containingDir}) {
    if (description is! Map) {
      throw FormatException("The description must be a map with a 'url' "
          'key.');
    }

    var ref = description['ref'];
    if (ref != null && ref is! String) {
      throw FormatException("The 'ref' field of the description must be a "
          'string.');
    }

    final resolvedRef = description['resolved-ref'];
    if (resolvedRef is! String) {
      throw FormatException("The 'resolved-ref' field of the description "
          'must be a string.');
    }

    final url = description['url'];
    return PackageId(
        name,
        version,
        GitResolvedDescription(
            GitDescription(
                url: url,
                ref: ref ?? 'HEAD',
                path: _validatedPath(
                  description['path'],
                ),
                containingDir: containingDir),
            resolvedRef));
  }

  /// Throws a [FormatException] if [url] isn't a valid Git URL.
  static _ValidatedUrl _validatedUrl(String url, String? containingDir) {
    var relative = false;
    // If the URL contains an @, it's probably an SSH hostname, which we don't
    // know how to validate.
    if (!url.contains('@')) {
      // Otherwise, we use Dart's URL parser to validate the URL.
      final parsed = Uri.parse(url);
      if (!parsed.hasAbsolutePath) {
        // Relative paths coming from pubspecs that are not on the local file
        // system aren't allowed. This can happen if a hosted or git dependency
        // has a git dependency.
        if (containingDir == null) {
          throw FormatException('"$url" is a relative path, but this '
              'isn\'t a local pubspec.');
        }
        // A relative path is stored internally as absolute resolved relative to
        // [containingPath].
        relative = true;
        url = p.url.normalize(
          p.url.join(
            p.toUri(p.absolute(containingDir)).toString(),
            parsed.toString(),
          ),
        );
      }
    }
    return _ValidatedUrl(url, relative);
  }

  /// Normalizes [path].
  ///
  /// Throws a [FormatException] if [path] isn't a [String] parsing as a
  /// relative URL or `null`.
  ///
  /// A relative url here has:
  /// - non-absolute path
  /// - no scheme
  /// - no authority
  String _validatedPath(dynamic path) {
    path ??= '.';
    if (path is! String) {
      throw FormatException("The 'path' field of the description must be a "
          'string.');
    }

    // Use Dart's URL parser to validate the URL.
    final parsed = Uri.parse(path);
    if (parsed.hasAbsolutePath ||
        parsed.hasScheme ||
        parsed.hasAuthority ||
        parsed.hasFragment ||
        parsed.hasQuery) {
      throw FormatException(
          "The 'path' field of the description must be a relative path URL.");
    }
    if (!p.url.isWithin('.', path) && !p.url.equals('.', path)) {
      throw FormatException(
          "The 'path' field of the description must not reach outside the "
          'repository.');
    }
    return p.url.normalize(parsed.toString());
  }

  /// Limit the number of concurrent git operations to 1.
  // TODO(sigurdm): Use RateLimitedScheduler.
  final Pool _pool = Pool(1);

  /// A map from revision cache locations to futures that will complete once
  /// they're finished being cloned.
  ///
  /// This lets us avoid race conditions when getting multiple different
  /// packages from the same repository.
  final _revisionCacheClones = <String, Future>{};

  /// The paths to the canonical clones of repositories for which "git fetch"
  /// has already been run during this run of pub.
  final _updatedRepos = <String>{};

  /// Given a Git repo that contains a pub package, gets the name of the pub
  /// package.
  Future<String> getPackageNameFromRepo(String repo, SystemCache cache) {
    // Clone the repo to a temp directory.
    return withTempDir((tempDir) async {
      await _clone(repo, tempDir, shallow: true);
      var pubspec = Pubspec.load(tempDir, cache.sources);
      return pubspec.name;
    });
  }

  @override
  Future<List<PackageId>> doGetVersions(
    PackageRef ref,
    Duration? maxAge,
    SystemCache cache,
  ) async {
    final description = ref.description;
    if (description is! GitDescription) {
      throw StateError('Called with wrong ref');
    }
    return await _pool.withResource(() async {
      await _ensureRepoCache(ref, cache);
      var path = _repoCachePath(ref, cache);
      var revision = await _firstRevision(
          path, description.ref!); // TODO(sigurdm) when can ref be null here?
      var pubspec =
          await _describeUncached(ref, revision, description.path, cache);

      return [
        PackageId(ref.name, pubspec.version,
            GitResolvedDescription(description, revision))
      ];
    });
  }

  /// Since we don't have an easy way to read from a remote Git repo, this
  /// just installs [id] into the system cache, then describes it from there.
  @override
  Future<Pubspec> describeUncached(PackageId id, SystemCache cache) {
    final description = id.description;
    if (description is! GitResolvedDescription) {
      throw StateError('Called with wrong ref');
    }
    return _pool.withResource(() => _describeUncached(
          id.toRef(),
          description.resolvedRef,
          description.description.path,
          cache,
        ));
  }

  /// Like [describeUncached], but takes a separate [ref] and Git [revision]
  /// rather than a single ID.
  Future<Pubspec> _describeUncached(
    PackageRef ref,
    String revision,
    String path,
    SystemCache cache,
  ) async {
    final description = ref.description;
    if (description is! GitDescription) {
      throw ArgumentError('Wrong source');
    }
    await _ensureRevision(ref, revision, cache);
    var repoPath = _repoCachePath(ref, cache);

    // Normalize the path because Git treats "./" at the beginning of a path
    // specially.
    var pubspecPath = p.normalize(p.join(p.fromUri(path), 'pubspec.yaml'));

    // Git doesn't recognize backslashes in paths, even on Windows.
    if (Platform.isWindows) pubspecPath = pubspecPath.replaceAll('\\', '/');
    late List<String> lines;
    try {
      lines = await git
          .run(['show', '$revision:$pubspecPath'], workingDir: repoPath);
    } on git.GitException catch (_) {
      fail('Could not find a file named "$pubspecPath" in '
          '${p.prettyUri(description.url)} $revision.');
    }

    return Pubspec.parse(
      lines.join('\n'),
      cache.sources,
      expectedName: ref.name,
    );
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
  Future<Package> downloadToSystemCache(PackageId id, SystemCache cache) async {
    return await _pool.withResource(() async {
      final ref = id.toRef();
      final description = ref.description;
      if (description is! GitDescription) {
        throw ArgumentError('Wrong source');
      }
      if (!git.isInstalled) {
        fail('Cannot get ${id.name} from Git (${description.url}).\n'
            'Please ensure Git is correctly installed.');
      }

      ensureDir(p.join(cache.rootDirForSource(this), 'cache'));
      final resolvedRef =
          (id.description as GitResolvedDescription).resolvedRef;

      await _ensureRevision(ref, resolvedRef, cache);

      var revisionCachePath = _revisionCachePath(id, cache);
      final path = description.path;
      await _revisionCacheClones.putIfAbsent(revisionCachePath, () async {
        if (!entryExists(revisionCachePath)) {
          await _clone(_repoCachePath(ref, cache), revisionCachePath);
          await _checkOut(revisionCachePath, resolvedRef);
          _writePackageList(revisionCachePath, [path]);
        } else {
          _updatePackageList(revisionCachePath, path);
        }
      });

      return Package.load(
        id.name,
        p.join(revisionCachePath, p.fromUri(path)),
        cache.sources,
      );
    });
  }

  /// Returns the path to the revision-specific cache of [id].
  @override
  String getDirectoryInCache(PackageId id, SystemCache cache) {
    final description = id.toRef().description;
    if (description is! GitDescription) {
      throw ArgumentError('Wrong source');
    }
    return p.join(_revisionCachePath(id, cache), description.path);
  }

  @override
  List<Package> getCachedPackages(SystemCache cache) {
    // TODO(keertip): Implement getCachedPackages().
    throw UnimplementedError(
        "The git source doesn't support listing its cached packages yet.");
  }

  /// Resets all cached packages back to the pristine state of the Git
  /// repository at the revision they are pinned to.
  @override
  Future<Iterable<RepairResult>> repairCachedPackages(SystemCache cache) async {
    final rootDir = cache.rootDirForSource(this);
    if (!dirExists(rootDir)) return [];

    final result = <RepairResult>[];

    var packages = listDir(rootDir)
        .where((entry) => dirExists(p.join(entry, '.git')))
        .expand((revisionCachePath) {
          return _readPackageList(revisionCachePath).map((relative) {
            // If we've already failed to load another package from this
            // repository, ignore it.
            if (!dirExists(revisionCachePath)) return null;

            var packageDir = p.join(revisionCachePath, relative);
            try {
              return Package.load(null, packageDir, cache.sources);
            } catch (error, stackTrace) {
              log.error('Failed to load package', error, stackTrace);
              var name = p.basename(revisionCachePath).split('-').first;
              result.add(
                RepairResult(name, Version.none, this, success: false),
              );
              tryDeleteEntry(revisionCachePath);
              return null;
            }
          });
        })
        .whereNotNull()
        .toList();

    // Note that there may be multiple packages with the same name and version
    // (pinned to different commits). The sort order of those is unspecified.
    packages.sort(Package.orderByNameAndVersion);

    for (var package in packages) {
      // If we've already failed to repair another package in this repository,
      // ignore it.
      if (!dirExists(package.dir)) continue;

      log.message('Resetting Git repository for '
          '${log.bold(package.name)} ${package.version}...');

      try {
        // Remove all untracked files.
        await git
            .run(['clean', '-d', '--force', '-x'], workingDir: package.dir);

        // Discard all changes to tracked files.
        await git.run(['reset', '--hard', 'HEAD'], workingDir: package.dir);

        result.add(
            RepairResult(package.name, package.version, this, success: true));
      } on git.GitException catch (error, stackTrace) {
        log.error('Failed to reset ${log.bold(package.name)} '
            '${package.version}. Error:\n$error');
        log.fine(stackTrace);
        result.add(
            RepairResult(package.name, package.version, this, success: false));

        // Delete the revision cache path, not the subdirectory that contains the package.
        final repoRoot = git.repoRoot(package.dir);
        if (repoRoot != null) tryDeleteEntry(repoRoot);
      }
    }

    return result;
  }

  /// Ensures that the canonical clone of the repository referred to by [ref]
  /// contains the given Git [revision].
  Future _ensureRevision(
    PackageRef ref,
    String revision,
    SystemCache cache,
  ) async {
    var path = _repoCachePath(ref, cache);
    if (_updatedRepos.contains(path)) return;

    await _deleteGitRepoIfInvalid(path);

    if (!entryExists(path)) await _createRepoCache(ref, cache);

    // Try to list the revision. If it doesn't exist, git will fail and we'll
    // know we have to update the repository.
    try {
      await _firstRevision(path, revision);
    } on git.GitException catch (_) {
      await _updateRepoCache(ref, cache);
    }
  }

  /// Ensures that the canonical clone of the repository referred to by [ref]
  /// exists and is up-to-date.
  Future _ensureRepoCache(PackageRef ref, SystemCache cache) async {
    var path = _repoCachePath(ref, cache);
    if (_updatedRepos.contains(path)) return;

    await _deleteGitRepoIfInvalid(path);

    if (!entryExists(path)) {
      await _createRepoCache(ref, cache);
    } else {
      await _updateRepoCache(ref, cache);
    }
  }

  /// Creates the canonical clone of the repository referred to by [ref].
  ///
  /// This assumes that the canonical clone doesn't yet exist.
  Future _createRepoCache(PackageRef ref, SystemCache cache) async {
    final description = ref.description;
    if (description is! GitDescription) {
      throw ArgumentError('Wrong source');
    }
    var path = _repoCachePath(ref, cache);
    assert(!_updatedRepos.contains(path));
    try {
      await _clone(description.url, path, mirror: true);
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
  Future _updateRepoCache(
    PackageRef ref,
    SystemCache cache,
  ) async {
    var path = _repoCachePath(ref, cache);
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
      if (result.join('\n') != 'true') {
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
  Future _clone(
    String from,
    String to, {
    bool mirror = false,
    bool shallow = false,
  }) {
    return Future.sync(() {
      // Git on Windows does not seem to automatically create the destination
      // directory.
      ensureDir(to);
      var args = [
        'clone',
        if (mirror) '--mirror',
        if (shallow) ...['--depth', '1'],
        from,
        to
      ];

      return git.run(args);
    }).then((result) => null);
  }

  /// Checks out the reference [ref] in [repoPath].
  Future _checkOut(String repoPath, String ref) {
    return git
        .run(['checkout', ref], workingDir: repoPath).then((result) => null);
  }

  String _revisionCachePath(PackageId id, SystemCache cache) => p.join(
      cache.rootDirForSource(this),
      '${_repoName(id.toRef())}-${(id.description as GitResolvedDescription).resolvedRef}');

  /// Returns the path to the canonical clone of the repository referred to by
  /// [id] (the one in `<system cache>/git/cache`).
  String _repoCachePath(PackageRef ref, SystemCache cache) {
    final description = ref.description;
    if (description is! GitDescription) {
      throw ArgumentError('Wrong source');
    }
    final repoCacheName = '${_repoName(ref)}-${sha1(description.url)}';
    return p.join(cache.rootDirForSource(this), 'cache', repoCacheName);
  }

  /// Returns a short, human-readable name for the repository URL in [ref].
  ///
  /// This name is not guaranteed to be unique.
  String _repoName(PackageRef ref) {
    final description = ref.description;
    if (description is! GitDescription) {
      throw ArgumentError('Wrong source');
    }
    var name = p.url.basename(description.url);
    if (name.endsWith('.git')) {
      name = name.substring(0, name.length - '.git'.length);
    }
    name = name.replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_');
    // Shorten name to 50 chars for sanity.
    if (name.length > 50) {
      name = name.substring(0, 50);
    }
    return name;
  }
}

class GitDescription extends Description {
  /// The url of the repo of this package.
  ///
  /// If the url was relative in the pubspec.yaml it will be resolved relative
  /// to the pubspec location, and stored here as an absolute file url, and
  /// [relative] will be true.
  ///
  /// This will not always parse as a [Uri] due the fact that `Uri.parse` does not allow strings of
  /// the form: 'git@github.com:dart-lang/pub.git'.
  final String url;

  /// `true` if [url] was parsed from a relative url.
  final bool relative;

  /// The git ref to resolve for finding the commit.
  final String? ref;

  /// Relative path of the package inside the git repo.
  ///
  /// Represented as a relative url.
  final String path;

  GitDescription._({
    required this.url,
    required this.relative,
    required String? ref,
    required String? path,
  })  : ref = ref ?? 'HEAD',
        path = path ?? '.';

  factory GitDescription({
    required String url,
    required String? ref,
    required String? path,
    required String? containingDir,
  }) {
    final validatedUrl = GitSource._validatedUrl(url, containingDir);
    return GitDescription._(
      url: validatedUrl.url,
      relative: validatedUrl.wasRelative,
      ref: ref,
      path: path,
    );
  }

  @override
  String format() {
    var result = '${prettyUri(url)} at '
        '$ref';
    if (path != '.') result += ' in $path';
    return result;
  }

  @override
  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    final relativeUrl = containingDir != null && relative
        ? p.url.relative(url,
            from: p.toUri(p.normalize(p.absolute(containingDir))).toString())
        : url;
    if (ref == 'HEAD' && path == '.') return relativeUrl;
    return {
      'url': relativeUrl,
      if (ref != 'HEAD') 'ref': ref,
      if (path != '.') 'path': path,
    };
  }

  @override
  GitSource get source => GitSource.instance;

  @override
  bool operator ==(Object other) {
    return other is GitDescription &&
        other.url == url &&
        other.ref == ref &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(url, ref, path);

  // Similar in intend to [p.prettyUri] but does not fail if the input doesn't
  // parse with [Uri.parse].
  static String prettyUri(String url) {
    // HACK: Working around the fact that `Uri.parse` does not allow strings of
    // the form: 'git@github.com:dart-lang/pub.git'.
    final parsedAsUri = Uri.tryParse(url);
    if (parsedAsUri == null) {
      return url;
    }
    return p.prettyUri(url);
  }
}

class GitResolvedDescription extends ResolvedDescription {
  @override
  GitDescription get description => super.description as GitDescription;

  final String resolvedRef;
  GitResolvedDescription(GitDescription description, this.resolvedRef)
      : super(description);

  @override
  String format() {
    var result = '${GitDescription.prettyUri(description.url)} at '
        '${resolvedRef.substring(0, 6)}';
    if (description.path != '.') result += ' in ${description.path}';
    return result;
  }

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    final url = description.relative && containingDir != null
        ? p.url
            .relative(description.url, from: Uri.file(containingDir).toString())
        : description.url;
    return {
      'url': url,
      'ref': description.ref,
      'resolved-ref': resolvedRef,
      'path': description.path,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is GitResolvedDescription &&
        other.description == description &&
        other.resolvedRef == resolvedRef;
  }

  @override
  int get hashCode => Object.hash(description, resolvedRef);
}

class _ValidatedUrl {
  final String url;
  final bool wasRelative;
  _ValidatedUrl(this.url, this.wasRelative);
}
