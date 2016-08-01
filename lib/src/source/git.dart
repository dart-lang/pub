// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../git.dart' as git;
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';
import 'cached.dart';

/// A package source that gets packages from Git repos.
class GitSource extends Source {
  final name = "git";

  BoundGitSource bind(SystemCache systemCache) =>
      new BoundGitSource(this, systemCache);

  /// Returns a reference to a git package with the given [name] and [url].
  ///
  /// If passed, [reference] is the Git reference. It defaults to `"HEAD"`.
  PackageRef refFor(String name, String url, {String reference}) =>
      new PackageRef(name, this, {'url': url, 'ref': reference ?? 'HEAD'});

  /// Given a valid git package description, returns the URL of the repository
  /// it pulls from.
  String urlFromDescription(description) => description["url"];

  PackageRef parseRef(String name, description, {String containingPath}) {
    // TODO(rnystrom): Handle git URLs that are relative file paths (#8570).
    if (description is String) description = {'url': description};

    if (description is! Map) {
      throw new FormatException("The description must be a Git URL or a map "
          "with a 'url' key.");
    }

    if (description["url"] is! String) {
      throw new FormatException("The 'url' field of the description must be a "
          "string.");
    }

    _validateUrl(description["url"]);

    var ref = description["ref"];
    if (ref != null && ref is! String) {
      throw new FormatException("The 'ref' field of the description must be a "
          "string.");
    }

    return new PackageRef(name, this, {
      "url": description["url"],
      "ref": description["ref"] ?? "HEAD"
    });
  }

  PackageId parseId(String name, Version version, description) {
    if (description is! Map) {
      throw new FormatException("The description must be a map with a 'url' "
          "key.");
    }

    if (description["url"] is! String) {
      throw new FormatException("The 'url' field of the description must be a "
          "string.");
    }

    _validateUrl(description["url"]);

    var ref = description["ref"];
    if (ref != null && ref is! String) {
      throw new FormatException("The 'ref' field of the description must be a "
          "string.");
    }

    if (description["resolved-ref"] is! String) {
      throw new FormatException("The 'resolved-ref' field of the description "
          "must be a string.");
    }

    return new PackageId(name, this, version, {
      "url": description["url"],
      "ref": description["ref"] ?? "HEAD",
      "resolved-ref": description["resolved-ref"]
    });
  }

  /// Throws a [FormatException] if [url] isn't a valid Git URL.
  void _validateUrl(String url) {
    // If the URL contains an @, it's probably an SSH hostname, which we don't
    // know how to validate.
    if (url.contains("@")) return;

    // Otherwise, we use Dart's URL parser to validate the URL.
    Uri.parse(url);
  }

  /// If [description] has a resolved ref, print it out in short-form.
  ///
  /// This helps distinguish different git commits with the same pubspec
  /// version.
  String formatDescription(String containingPath, description) {
    if (description is Map && description.containsKey('resolved-ref')) {
      return "${description['url']} at "
          "${description['resolved-ref'].substring(0, 6)}";
    } else {
      return super.formatDescription(containingPath, description);
    }
  }

  /// Two Git descriptions are equal if both their URLs and their refs are
  /// equal.
  bool descriptionsEqual(description1, description2) {
    // TODO(nweiz): Do we really want to throw an error if you have two
    // dependencies on some repo, one of which specifies a ref and one of which
    // doesn't? If not, how do we handle that case in the version solver?
    if (description1['url'] != description2['url']) return false;
    if (description1['ref'] != description2['ref']) return false;

    if (description1.containsKey('resolved-ref') &&
        description2.containsKey('resolved-ref')) {
      return description1['resolved-ref'] == description2['resolved-ref'];
    }

    return true;
  }

  int hashDescription(description) {
    // Don't include the resolved ref in the hash code because we ignore it in
    // [descriptionsEqual] if only one description defines it.
    return description['url'].hashCode ^ description['ref'].hashCode;
  }
}

/// The [BoundSource] for [GitSource].
class BoundGitSource extends CachedSource {
  final GitSource source;

  final SystemCache systemCache;

  BoundGitSource(this.source, this.systemCache);

  /// The paths to the canonical clones of repositories for which "git fetch"
  /// has already been run during this run of pub.
  final _updatedRepos = new Set<String>();

  /// Given a Git repo that contains a pub package, gets the name of the pub
  /// package.
  Future<String> getPackageNameFromRepo(String repo) {
    // Clone the repo to a temp directory.
    return withTempDir((tempDir) async {
      await _clone(repo, tempDir, shallow: true);
      var pubspec = new Pubspec.load(tempDir, systemCache.sources);
      return pubspec.name;
    });
  }

  Future<List<PackageId>> doGetVersions(PackageRef ref) async {
    await _ensureRepoCache(ref);
    var path = _repoCachePath(ref);
    var revision = await _firstRevision(path, ref.description['ref']);
    var pubspec = await _describeUncached(ref, revision);

    return [
      new PackageId(ref.name, source, pubspec.version, {
        'url': ref.description['url'],
        'ref': ref.description['ref'],
        'resolved-ref': revision
      })
    ];
  }

  /// Since we don't have an easy way to read from a remote Git repo, this
  /// just installs [id] into the system cache, then describes it from there.
  Future<Pubspec> describeUncached(PackageId id) =>
      _describeUncached(id.toRef(), id.description['resolved-ref']);

  /// Like [describeUncached], but takes a separate [ref] and Git [revision]
  /// rather than a single ID.
  Future<Pubspec> _describeUncached(PackageRef ref, String revision) async {
    await _ensureRevision(ref, revision);
    var path = _repoCachePath(ref);

    var lines;
    try {
      lines = await git.run(["show", "$revision:pubspec.yaml"],
          workingDir: path);
    } on git.GitException catch (_) {
      fail('Could not find a file named "pubspec.yaml" in '
          '${ref.description['url']} $revision.');
    }

    return new Pubspec.parse(lines.join("\n"), systemCache.sources,
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
  Future<Package> downloadToSystemCache(PackageId id) async {
    var ref = id.toRef();
    if (!git.isInstalled) {
      fail("Cannot get ${id.name} from Git (${ref.description['url']}).\n"
          "Please ensure Git is correctly installed.");
    }

    ensureDir(path.join(systemCacheRoot, 'cache'));
    await _ensureRevision(ref, id.description['resolved-ref']);

    var revisionCachePath = getDirectory(id);
    if (!entryExists(revisionCachePath)) {
      await _clone(_repoCachePath(ref), revisionCachePath);
      await _checkOut(revisionCachePath, id.description['resolved-ref']);
    }

    return new Package.load(id.name, revisionCachePath, systemCache.sources);
  }

  /// Returns the path to the revision-specific cache of [id].
  String getDirectory(PackageId id) => path.join(
      systemCacheRoot, "${id.name}-${id.description['resolved-ref']}");

  List<Package> getCachedPackages() {
    // TODO(keertip): Implement getCachedPackages().
    throw new UnimplementedError(
        "The git source doesn't support listing its cached packages yet.");
  }

  /// Resets all cached packages back to the pristine state of the Git
  /// repository at the revision they are pinned to.
  Future<Pair<List<PackageId>, List<PackageId>>> repairCachedPackages() async {
    if (!dirExists(systemCacheRoot)) return new Pair([], []);

    var successes = <PackageId>[];
    var failures = <PackageId>[];

    var packages = listDir(systemCacheRoot)
        .where((entry) => dirExists(path.join(entry, ".git")))
        .map((packageDir) => new Package.load(
            null, packageDir, systemCache.sources))
        .toList();

    // Note that there may be multiple packages with the same name and version
    // (pinned to different commits). The sort order of those is unspecified.
    packages.sort(Package.orderByNameAndVersion);

    for (var package in packages) {
      var id = new PackageId(package.name, source, package.version, null);

      log.message("Resetting Git repository for "
          "${log.bold(package.name)} ${package.version}...");

      try {
        // Remove all untracked files.
        await git.run(["clean", "-d", "--force", "-x"],
            workingDir: package.dir);

        // Discard all changes to tracked files.
        await git.run(["reset", "--hard", "HEAD"], workingDir: package.dir);

        successes.add(id);
      } on git.GitException catch (error, stackTrace) {
        log.error("Failed to reset ${log.bold(package.name)} "
            "${package.version}. Error:\n$error");
        log.fine(stackTrace);
        failures.add(id);

        tryDeleteEntry(package.dir);
      }
    }

    return new Pair(successes, failures);
  }

  /// Ensures that the canonical clone of the repository referred to by [ref]
  /// contains the given Git [revision].
  Future _ensureRevision(PackageRef ref, String revision) async {
    var path = _repoCachePath(ref);
    if (_updatedRepos.contains(path)) return;

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

    await _clone(ref.description['url'], path, mirror: true);
    _updatedRepos.add(path);
  }

  /// Runs "git fetch" in the canonical clone of the repository referred to by
  /// [ref].
  ///
  /// This assumes that the canonical clone already exists.
  Future _updateRepoCache(PackageRef ref) async {
    var path = _repoCachePath(ref);
    if (_updatedRepos.contains(path)) return new Future.value();
    await git.run(["fetch"], workingDir: path);
    _updatedRepos.add(path);
  }

  /// Runs "git rev-list" on [reference] in [path] and returns the first result.
  ///
  /// This assumes that the canonical clone already exists.
  Future<String> _firstRevision(String path, String reference) async {
    var lines = await git.run(["rev-list", "--max-count=1", reference],
        workingDir: path);
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
  Future _clone(String from, String to, {bool mirror: false,
      bool shallow: false}) {
    return new Future.sync(() {
      // Git on Windows does not seem to automatically create the destination
      // directory.
      ensureDir(to);
      var args = ["clone", from, to];

      if (mirror) args.insert(1, "--mirror");
      if (shallow) args.insertAll(1, ["--depth", "1"]);

      return git.run(args);
    }).then((result) => null);
  }

  /// Checks out the reference [ref] in [repoPath].
  Future _checkOut(String repoPath, String ref) {
    return git.run(["checkout", ref], workingDir: repoPath).then(
        (result) => null);
  }

  /// Returns the path to the canonical clone of the repository referred to by
  /// [id] (the one in `<system cache>/git/cache`).
  String _repoCachePath(PackageRef ref) {
    var repoCacheName = '${ref.name}-${sha1(ref.description['url'])}';
    return path.join(systemCacheRoot, 'cache', repoCacheName);
  }
}
