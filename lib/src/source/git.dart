// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
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
import 'path.dart';
import 'root.dart';

typedef TaggedVersion = ({Version version, String commitId});

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
    ResolvedDescription? containingDescription,
    required LanguageVersion languageVersion,
  }) {
    String url;
    String? ref;
    String? path;
    String? tagPattern;
    if (description is String) {
      url = description;
    } else if (description is! Map) {
      throw const FormatException(
        'The description must be a Git URL or a map '
        "with a 'url' key.",
      );
    } else {
      final descriptionUrl = description['url'];
      if (descriptionUrl is! String) {
        throw const FormatException(
          "The 'url' field of a description must be a string.",
        );
      }
      url = descriptionUrl;

      final descriptionRef = description['ref'];
      if (descriptionRef is! String?) {
        throw const FormatException(
          "The 'ref' field of the description must be a "
          'string.',
        );
      }
      ref = descriptionRef;

      final descriptionPath = description['path'];
      if (descriptionPath is! String?) {
        throw const FormatException(
          "The 'path' field of the description must be a "
          'string.',
        );
      }
      path = descriptionPath;

      // TODO: can we avoid relying on key presence?
      if (description.containsKey('tag_pattern')) {
        if (!languageVersion.supportsTagPattern) {
          throw FormatException(
            'Using `git: {tagPattern: }` is only supported with a minimum SDK '
            'constraint of ${LanguageVersion.firstVersionWithTagPattern}.',
          );
        }
        switch (description['tag_pattern']) {
          case final String descriptionTagPattern:
            tagPattern = descriptionTagPattern;
            // Do an early compilation to validate the format.
            compileTagPattern(tagPattern);
          default:
            throw const FormatException(
              "The 'tag_pattern' field of the description "
              'must be a string or null.',
            );
        }
      }

      if (ref != null && tagPattern != null) {
        throw const FormatException(
          'A git description cannot have both a ref and a `tag_pattern`.',
        );
      }
      if (languageVersion.forbidsUnknownDescriptionKeys) {
        for (final key in description.keys) {
          if (!['url', 'ref', 'path', 'tag_pattern'].contains(key)) {
            throw FormatException('Unknown key "$key" in description.');
          }
        }
      }
    }

    final containingDir = switch (containingDescription?.description) {
      RootDescription(path: final path) => path,
      PathDescription(path: final path) => path,
      _ => null,
    };

    return PackageRef(
      name,
      GitDescription(
        url: url,
        containingDir: containingDir,
        ref: ref,
        path: _validatedPath(path),
        tagPattern: tagPattern,
      ),
    );
  }

  @override
  PackageId parseId(
    String name,
    Version version,
    Object? description, {
    String? containingDir,
  }) {
    if (description is! Map) {
      throw const FormatException(
        "The description must be a map with a 'url' "
        'key.',
      );
    }

    final ref = description['ref'];
    if (ref is! String?) {
      throw const FormatException(
        "The 'ref' field of the description must be a "
        'string.',
      );
    }

    final resolvedRef = description['resolved-ref'];
    if (resolvedRef is! String) {
      throw const FormatException(
        "The 'resolved-ref' field of the description "
        'must be a string.',
      );
    }

    final url = description['url'];
    if (url is! String) {
      throw const FormatException(
        "The 'url' field of the description "
        'must be a string.',
      );
    }

    final tagPattern = description['tag_pattern'];
    if (tagPattern is! String?) {
      throw const FormatException(
        "The 'tag_pattern' field of the description "
        'must be a string.',
      );
    }

    return PackageId(
      name,
      version,
      ResolvedGitDescription(
        GitDescription(
          url: url,
          ref: ref,
          path: _validatedPath(description['path']),
          containingDir: containingDir,
          tagPattern: tagPattern,
        ),
        resolvedRef,
      ),
    );
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
          throw FormatException(
            '"$url" is a relative path, but this '
            'isn\'t a local pubspec.',
          );
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
      throw const FormatException(
        "The 'path' field of the description must be a "
        'string.',
      );
    }

    // Use Dart's URL parser to validate the URL.
    final parsed = Uri.parse(path);
    if (parsed.hasAbsolutePath ||
        parsed.hasScheme ||
        parsed.hasAuthority ||
        parsed.hasFragment ||
        parsed.hasQuery) {
      throw const FormatException(
        "The 'path' field of the description must be a relative path URL.",
      );
    }
    if (!p.url.isWithin('.', path) && !p.url.equals('.', path)) {
      throw const FormatException(
        "The 'path' field of the description must not reach outside the "
        'repository.',
      );
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
  final _revisionCacheClones = <String, Future<void>>{};

  /// The paths to the canonical clones of repositories for which "git fetch"
  /// has already been run during this run of pub.
  final _updatedRepos = <String>{};

  /// Given a Git repo that contains a pub package, gets the name of the pub
  /// package.
  ///
  /// Will download the repo to the system cache under the assumption that the
  /// package will be downloaded afterwards.
  Future<String> getPackageNameFromRepo(
    String url,
    String? ref,
    String? path,
    SystemCache cache, {
    required String relativeTo,
    required String? tagPattern,
  }) async {
    if (ref != null && tagPattern != null) {
      fail('Cannot have both a `tagPattern` and a `ref`');
    }
    final description = GitDescription(
      url: url,
      ref: ref,
      path: path,
      containingDir: relativeTo,
      tagPattern: tagPattern, // TODO
    );
    return await _pool.withResource(() async {
      await _ensureRepoCache(description, cache);
      final path = _repoCachePath(description, cache);

      final revision =
          tagPattern != null
              ? (await _listTaggedVersions(
                path,
                compileTagPattern(tagPattern),
              )).last.commitId
              : await _firstRevision(path, description.ref);
      final resolvedDescription = ResolvedGitDescription(description, revision);

      return Pubspec.parse(
        await _showFileAtRevision(resolvedDescription, 'pubspec.yaml', cache),
        cache.sources,
        containingDescription: resolvedDescription,
      ).name;
    });
  }

  /// Lists the file as it is represented at the revision of
  /// [resolvedDescription].
  ///
  /// Assumes that revision is present in the cache already (can be done with
  /// [_ensureRevision]).
  Future<String> _showFileAtRevision(
    ResolvedGitDescription resolvedDescription,
    String pathInProject,
    SystemCache cache,
  ) async {
    final description = resolvedDescription.description;
    // Normalize the path because Git treats "./" at the beginning of a path
    // specially.
    var pathInCache = p.normalize(
      p.join(p.fromUri(description.path), pathInProject),
    );

    // Git doesn't recognize backslashes in paths, even on Windows.
    if (Platform.isWindows) pathInCache = pathInCache.replaceAll('\\', '/');

    final repoPath = _repoCachePath(description, cache);
    final revision = resolvedDescription.resolvedRef;

    try {
      return await git.run([
        _gitDirArg(repoPath),
        'show',
        '$revision:$pathInCache',
      ], workingDir: repoPath);
    } on git.GitException catch (_) {
      fail(
        'Could not find a file named "$pathInCache" in '
        '${GitDescription.prettyUri(description.url)} $revision.',
      );
    }
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
      await _ensureRepoCache(description, cache);
      final path = _repoCachePath(description, cache);
      final result = <PackageId>[];
      if (description.tagPattern case final String tagPattern) {
        final versions = await _listTaggedVersions(
          path,
          compileTagPattern(tagPattern),
        );
        for (final version in versions) {
          result.add(
            PackageId(
              ref.name,
              version.version,
              ResolvedGitDescription(description, version.commitId),
            ),
          );
        }
        return result;
      } else {
        final revision = await _firstRevision(path, description.ref);

        final Pubspec pubspec;
        pubspec = await _describeUncached(ref, revision, cache);
        result.add(
          PackageId(
            ref.name,
            pubspec.version,
            ResolvedGitDescription(description, revision),
          ),
        );
        return [
          PackageId(
            ref.name,
            pubspec.version,
            ResolvedGitDescription(description, revision),
          ),
        ];
      }
    });
  }

  /// Since we don't have an easy way to read from a remote Git repo, this
  /// just installs [id] into the system cache, then describes it from there.
  @override
  Future<Pubspec> describeUncached(PackageId id, SystemCache cache) async {
    final description = id.description;
    if (description is! ResolvedGitDescription) {
      throw StateError('Called with wrong ref');
    }
    final pubspec = await _pool.withResource(
      () => _describeUncached(id.toRef(), description.resolvedRef, cache),
    );
    if (pubspec.version != id.version) {
      throw PackageNotFoundException(
        'Expected ${id.name} version ${id.version} '
        'at commit ${description.resolvedRef}, '
        'found ${pubspec.version}.',
      );
    }
    return pubspec;
  }

  final Map<(PackageRef, String), Pubspec> _pubspecAtRevisionCache = {};

  /// Like [describeUncached], but takes a separate [ref] and Git [revision]
  /// rather than a single ID.
  Future<Pubspec> _describeUncached(
    PackageRef ref,
    String revision,
    SystemCache cache,
  ) async {
    final description = ref.description;
    if (description is! GitDescription) {
      throw ArgumentError('Wrong source');
    }
    return _pubspecAtRevisionCache[(ref, revision)] ??= await () async {
      await _ensureRevision(description, revision, cache);
      final resolvedDescription = ResolvedGitDescription(description, revision);
      return Pubspec.parse(
        await _showFileAtRevision(resolvedDescription, 'pubspec.yaml', cache),
        cache.sources,
        expectedName: ref.name,
        containingDescription: resolvedDescription,
      );
    }();
  }

  /// Clones a Git repo to the local filesystem.
  ///
  /// The Git cache directory is a little idiosyncratic. At the top level, it
  /// contains a directory for each commit of each repository, named
  /// `<package name>-<commit hash>`. These are the canonical package
  /// directories that are linked to from the `.dart_tool/package_config.json`
  /// file.
  ///
  /// In addition, the Git system cache contains a subdirectory named `cache/`
  /// which contains a directory for each separate repository URL, named
  /// `<package name>-<url hash>`. These are used to check out the repository
  /// itself; each of the commit-specific directories are clones of a directory
  /// in `cache/`.
  @override
  Future<DownloadPackageResult> downloadToSystemCache(
    PackageId id,
    SystemCache cache,
  ) async {
    return await _pool.withResource(() async {
      var didUpdate = false;
      final ref = id.toRef();
      final description = ref.description;
      if (description is! GitDescription) {
        throw ArgumentError('Wrong source');
      }
      if (!git.isInstalled) {
        fail(
          'Cannot get ${id.name} from Git (${description.url}).\n'
          'Please ensure Git is correctly installed.',
        );
      }

      ensureDir(p.join(cache.rootDirForSource(this), 'cache'));
      final resolvedRef =
          (id.description as ResolvedGitDescription).resolvedRef;

      didUpdate |= await _ensureRevision(description, resolvedRef, cache);

      final revisionCachePath = _revisionCachePath(id, cache);
      final path = description.path;
      await _revisionCacheClones.putIfAbsent(revisionCachePath, () async {
        if (!entryExists(revisionCachePath)) {
          await _cloneViaTemp(
            _repoCachePath(description, cache),
            revisionCachePath,
            cache,
          );
          await _checkOut(revisionCachePath, resolvedRef);
          _writePackageList(revisionCachePath, [path]);
          didUpdate = true;
        } else {
          didUpdate |= _updatePackageList(revisionCachePath, path);
        }
      });
      return DownloadPackageResult(id, didUpdate: didUpdate);
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
      "The git source doesn't support listing its cached packages yet.",
    );
  }

  /// Resets all cached packages back to the pristine state of the Git
  /// repository at the revision they are pinned to.
  @override
  Future<Iterable<RepairResult>> repairCachedPackages(SystemCache cache) async {
    final rootDir = cache.rootDirForSource(this);
    if (!dirExists(rootDir)) return [];

    final result = <RepairResult>[];

    final packages =
        listDir(rootDir)
            .where((entry) => dirExists(p.join(entry, '.git')))
            .expand((revisionCachePath) {
              return _readPackageList(revisionCachePath).map((relative) {
                // If we've already failed to load another package from this
                // repository, ignore it.
                if (!dirExists(revisionCachePath)) return null;

                final packageDir = p.join(revisionCachePath, relative);
                try {
                  return Package.load(
                    packageDir,
                    loadPubspec: Pubspec.loadRootWithSources(cache.sources),
                  );
                } catch (error, stackTrace) {
                  log.error('Failed to load package', error, stackTrace);
                  final name = p.basename(revisionCachePath).split('-').first;
                  result.add(
                    RepairResult(name, Version.none, this, success: false),
                  );
                  tryDeleteEntry(revisionCachePath);
                  return null;
                }
              });
            })
            .nonNulls
            .toList();

    // Note that there may be multiple packages with the same name and version
    // (pinned to different commits). The sort order of those is unspecified.
    packages.sort(Package.orderByNameAndVersion);

    for (var package in packages) {
      // If we've already failed to repair another package in this repository,
      // ignore it.
      if (!dirExists(package.dir)) continue;

      log.message(
        'Resetting Git repository for '
        '${log.bold(package.name)} ${package.version}...',
      );

      try {
        // Remove all untracked files.
        await git.run([
          'clean',
          '-d',
          '--force',
          '-x',
        ], workingDir: package.dir);

        // Discard all changes to tracked files.
        await git.run(['reset', '--hard', 'HEAD'], workingDir: package.dir);

        result.add(
          RepairResult(package.name, package.version, this, success: true),
        );
      } on git.GitException catch (error, stackTrace) {
        log.error(
          'Failed to reset ${log.bold(package.name)} '
          '${package.version}. Error:\n$error',
        );
        log.fine(stackTrace.toString());
        result.add(
          RepairResult(package.name, package.version, this, success: false),
        );

        // Delete the revision cache path, not the subdirectory that contains
        // the package.
        final repoRoot = git.repoRoot(package.dir);
        if (repoRoot != null) tryDeleteEntry(repoRoot);
      }
    }

    return result;
  }

  /// Ensures that the canonical clone of the repository referred to by
  /// [description] contains the given Git [revision].
  Future<bool> _ensureRevision(
    GitDescription description,
    String revision,
    SystemCache cache,
  ) async {
    final path = _repoCachePath(description, cache);
    if (_updatedRepos.contains(path)) return false;

    await _deleteGitRepoIfInvalid(path);

    if (!entryExists(path)) await _createRepoCache(description, cache);

    // Try to list the revision. If it doesn't exist, git will fail and we'll
    // know we have to update the repository.
    try {
      await _firstRevision(path, revision);
    } on git.GitException catch (_) {
      await _updateRepoCache(description, cache);
      return true;
    }
    return false;
  }

  /// Ensures that the canonical clone of the repository referred to by
  /// [description] exists and is up-to-date.
  ///
  /// Returns `true` if it had to update anything.
  Future<bool> _ensureRepoCache(
    GitDescription description,
    SystemCache cache,
  ) async {
    final path = _repoCachePath(description, cache);
    if (_updatedRepos.contains(path)) return false;

    await _deleteGitRepoIfInvalid(path);

    if (!entryExists(path)) {
      await _createRepoCache(description, cache);
      return true;
    } else {
      return await _updateRepoCache(description, cache);
    }
  }

  /// Creates the canonical clone of the repository referred to by
  /// [description].
  ///
  /// This assumes that the canonical clone doesn't yet exist.
  Future<void> _createRepoCache(
    GitDescription description,
    SystemCache cache,
  ) async {
    final path = _repoCachePath(description, cache);
    assert(!_updatedRepos.contains(path));
    try {
      await _cloneViaTemp(description.url, path, cache, mirror: true);
    } catch (_) {
      await _deleteGitRepoIfInvalid(path);
      rethrow;
    }
    _updatedRepos.add(path);
  }

  /// Runs "git fetch" in the canonical clone of the repository referred to by
  /// [description].
  ///
  /// This assumes that the canonical clone already exists.
  ///
  /// Returns `true` if it had to update anything.
  Future<bool> _updateRepoCache(
    GitDescription description,
    SystemCache cache,
  ) async {
    final path = _repoCachePath(description, cache);
    if (_updatedRepos.contains(path)) return false;
    await git.run([_gitDirArg(path), 'fetch'], workingDir: path);
    _updatedRepos.add(path);
    return true;
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
      final result = await git.run([
        _gitDirArg(dirPath),
        'rev-parse',
        '--is-inside-git-dir',
      ], workingDir: dirPath);
      if (result.trim() != 'true') {
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
  ///
  /// Returns `true` if it had to update anything.
  bool _updatePackageList(String revisionCachePath, String path) {
    final packages = _readPackageList(revisionCachePath);
    if (packages.contains(path)) return false;

    _writePackageList(revisionCachePath, packages..add(path));
    return true;
  }

  /// Returns the list of packages in [revisionCachePath].
  List<String> _readPackageList(String revisionCachePath) {
    final path = _packageListPath(revisionCachePath);

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

  ///
  Future<List<TaggedVersion>> _listTaggedVersions(
    String path,
    RegExp compiledTagPattern,
  ) async {
    final output = await git.run([
      'tag',
      '--list',
      '--format',
      // We can use space here, as it is not allowed in a git tag
      // https://git-scm.com/docs/git-check-ref-format
      '%(refname:lstrip=2) %(objectname)',
    ], workingDir: path);
    final lines = output.trim().split('\n');
    final result = <TaggedVersion>[];
    for (final line in lines) {
      final parts = line.split(' ');
      if (parts.length != 2) {
        throw PackageNotFoundException('Bad output from `git tag --list`');
      }
      final match = compiledTagPattern.firstMatch(parts[0]);
      if (match == null) continue;
      final version = Version.parse(match[1]!);
      result.add((version: version, commitId: parts[1]));
    }
    return result;
  }

  /// Runs "git rev-list" on [reference] in [path] and returns the first result.
  ///
  /// This assumes that the canonical clone already exists.
  Future<String> _firstRevision(String path, String reference) async {
    final String output;
    try {
      output =
          (await git.run([
            _gitDirArg(path),
            'rev-list',
            '--max-count=1',
            reference,
          ], workingDir: path)).trim();
    } on git.GitException catch (e) {
      throw PackageNotFoundException(
        "Could not find git ref '$reference' (${e.stderr})",
      );
    }
    if (output.isEmpty) {
      throw PackageNotFoundException("Could not find git ref '$reference'.");
    }
    return output;
  }

  /// Clones the repo at the URI [from] to the path [to] on the local
  /// filesystem.
  ///
  /// If [mirror] is true, creates a bare, mirrored clone. This doesn't check
  /// out the working tree, but instead makes the repository a local mirror of
  /// the remote repository. See the manpage for `git clone` for more
  /// information.
  Future<void> _clone(String from, String to, {bool mirror = false}) async {
    // Git on Windows does not seem to automatically create the destination
    // directory.
    ensureDir(to);
    final args = ['clone', if (mirror) '--mirror', from, to];

    await git.run(args);
  }

  /// Like [_clone], but clones to a temporary directory (inside the [cache])
  /// and moves
  Future<void> _cloneViaTemp(
    String from,
    String to,
    SystemCache cache, {
    bool mirror = false,
  }) async {
    final tempDir = cache.createTempDir();
    try {
      await _clone(from, tempDir, mirror: mirror);
    } catch (_) {
      deleteEntry(tempDir);
      rethrow;
    }
    // Now that the clone has succeeded, move it to the real location in the
    // cache.
    //
    // If this fails with a "directory not empty" exception we assume that
    // another pub process has installed the same package version while we
    // cloned. In that case [tryRenameDir] will delete the folder for us.
    tryRenameDir(tempDir, to);
  }

  /// Checks out the reference [ref] in [repoPath].
  Future<void> _checkOut(String repoPath, String ref) {
    return git
        .run(['checkout', ref], workingDir: repoPath)
        .then((result) => null);
  }

  String _revisionCachePath(PackageId id, SystemCache cache) => p.join(
    cache.rootDirForSource(this),
    '${_repoName(id.description.description as GitDescription)}-'
    '${(id.description as ResolvedGitDescription).resolvedRef}',
  );

  /// Returns the path to the canonical clone of the repository referred to by
  /// [description] (the one in `<system cache>/git/cache`).
  String _repoCachePath(GitDescription description, SystemCache cache) {
    final repoCacheName = '${_repoName(description)}-${sha1(description.url)}';
    return p.join(cache.rootDirForSource(this), 'cache', repoCacheName);
  }

  /// Returns a short, human-readable name for the repository URL in
  /// [description].
  ///
  /// This name is not guaranteed to be unique.
  String _repoName(GitDescription description) {
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
  /// This will not always parse as a [Uri] due the fact that `Uri.parse` does
  /// not allow strings of the form: 'git@github.com:dart-lang/pub.git'.
  final String url;

  final String? tagPattern;

  /// `true` if [url] was parsed from a relative url.
  final bool relative;

  /// The git ref to resolve for finding the commit.
  final String ref;

  /// Relative path of the package inside the git repo.
  ///
  /// Represented as a relative url.
  final String path;

  late final RegExp compiledTagPattern = compileTagPattern(tagPattern!);

  GitDescription.raw({
    required this.url,
    required this.relative,
    required String? ref,
    required String? path,
    required this.tagPattern,
  }) : ref = ref ?? 'HEAD',
       path = path ?? '.';

  factory GitDescription({
    required String url,
    required String? ref,
    required String? path,
    required String? containingDir,
    required String? tagPattern,
  }) {
    final validatedUrl = GitSource._validatedUrl(url, containingDir);
    return GitDescription.raw(
      url: validatedUrl.url,
      relative: validatedUrl.wasRelative,
      ref: ref,
      path: path,
      tagPattern: tagPattern,
    );
  }

  @override
  String format() {
    var result =
        '${prettyUri(url)} at '
        '$ref';
    if (path != '.') result += ' in $path';
    return result;
  }

  @override
  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    final relativeUrl =
        containingDir != null && relative
            ? p.url.relative(
              url,
              from: p.toUri(p.normalize(p.absolute(containingDir))).toString(),
            )
            : url;
    if (ref == 'HEAD' && path == '.') return relativeUrl;
    return {
      'url': relativeUrl,
      if (ref != 'HEAD') 'ref': ref,
      if (path != '.') 'path': path,
      if (tagPattern != null) 'tag_pattern': tagPattern,
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

  GitDescription withRef(String newRef) => GitDescription.raw(
    url: url,
    relative: relative,
    ref: newRef,
    path: path,
    tagPattern: tagPattern,
  );

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

  @override
  bool get hasMultipleVersions => tagPattern != null;
}

class ResolvedGitDescription extends ResolvedDescription {
  @override
  GitDescription get description => super.description as GitDescription;

  final String resolvedRef;

  ResolvedGitDescription(GitDescription super.description, this.resolvedRef);

  @override
  String format() {
    var result =
        '${GitDescription.prettyUri(description.url)} at '
        '${resolvedRef.substring(0, 6)}';
    if (description.path != '.') result += ' in ${description.path}';
    return result;
  }

  @override
  Object? serializeForLockfile({required String? containingDir}) {
    final url =
        description.relative && containingDir != null
            ? p.url.relative(
              description.url,
              from: Uri.file(p.absolute(containingDir)).toString(),
            )
            : description.url;
    return {
      'url': url,
      'ref': description.ref,
      if (description.tagPattern != null) 'tag-pattern': description.tagPattern,
      'resolved-ref': resolvedRef,
      'path': description.path,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ResolvedGitDescription &&
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

String _gitDirArg(String path) {
  path = p.absolute(path);
  final forwardSlashPath =
      Platform.isWindows ? path.replaceAll('\\', '/') : path;
  return '--git-dir=$forwardSlashPath';
}

final tagPatternPattern = RegExp(r'^(.*){{version}}(.*)$');

// Adapted from pub_semver-2.1.4/lib/src/version.dart
const versionPattern =
    r'(\d+)\.(\d+)\.(\d+)' // Version number.
    r'(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?' // Pre-release.
    r'(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?'; // build

/// Takes a [tagPattern] and returns a [RegExp] matching the relevant tags.
///
/// The tagPattern should contain '{{version}}' which will match a pub_semver
/// version. The rest of the tagPattern is matched verbatim.
RegExp compileTagPattern(String tagPattern) {
  final match = tagPatternPattern.firstMatch(tagPattern);
  if (match == null) {
    throw const FormatException(
      'The `tag_pattern` must contain "{{version}}" '
      'to match different versions',
    );
  }
  final before = RegExp.escape(match[1]!);
  final after = RegExp.escape(match[2]!);

  return RegExp(
    r'^'
    '$before($versionPattern)$after'
    r'$',
  );
}
