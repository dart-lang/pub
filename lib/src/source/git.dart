// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub.source.git;

import 'dart:async';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../git.dart' as git;
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../pubspec.dart';
import '../utils.dart';
import 'cached.dart';

/// A package source that gets packages from Git repos.
class GitSource extends CachedSource {
  /// Given a valid git package description, returns the URL of the repository
  /// it pulls from.
  static String urlFromDescription(description) => description["url"];

  final name = "git";

  /// The paths to the canonical clones of repositories for which "git fetch"
  /// has already been run during this run of pub.
  final _updatedRepos = new Set<String>();

  /// Given a Git repo that contains a pub package, gets the name of the pub
  /// package.
  Future<String> getPackageNameFromRepo(String repo) {
    // Clone the repo to a temp directory.
    return withTempDir((tempDir) {
      return _clone(repo, tempDir, shallow: true).then((_) {
        var pubspec = new Pubspec.load(tempDir, systemCache.sources);
        return pubspec.name;
      });
    });
  }

  /// Gets the list of all versions from git tags.
  /// Anything that Version.parse understands is considered a version,
  /// it will also attempt to strip off a preceding 'v' e.g. v1.0.0
  Future<List<Pubspec>> getVersions(String name, description) async {
    if (!_useVersionTags(description)) {
      // No need to get versions if the useVersionTags option is false
      return super.getVersions(name, description);
    }

    var ref = new PackageRef(name, this.name, _getDescription(description));
    await _ensureRepo(ref);

    var cachePath = _repoCachePath(ref);
    List results = await git.run(['tag', '-l', '*.*.*'], workingDir: cachePath);
    Map<String, Pubspec> validVersionPubspecs = {};
    for (String tag in results) {
      // Strip preceding 'v' character so 'v1.0.0' can be parsed into a Version
      String versionTag = tag;
      if (versionTag.startsWith('v')) {
        versionTag = versionTag.substring(1);
      }
      try {
        // Use Version.parse to determine valid version tags
        new Version.parse(versionTag);
        // Fetch the pubspec for this version
        Pubspec pubspec = await _getPubspec(cachePath, tag);
        // Skip this version if a pubspec didn't exist
        if (pubspec != null) {
          // This logic prevents duplicate versions and prefers the non-"v"
          // tag in the case of "1.0.0" and "v1.0.0"
          if (!validVersionPubspecs.containsKey(versionTag)
              || !tag.startsWith('v')) {
            validVersionPubspecs[versionTag] = pubspec;
          }
        }
      } on FormatException {}
    }

    if (validVersionPubspecs.isNotEmpty) {
      return validVersionPubspecs.values.toList();
    }

    // No valid version tags were found, defer to super
    return super.getVersions(name, description);
  }

  /// Since we don't have an easy way to read from a remote Git repo, this
  /// just installs [id] into the system cache, then describes it from there.
  Future<Pubspec> describeUncached(PackageId id) {
    return downloadToSystemCache(id).then((package) => package.pubspec);
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
    if (!git.isInstalled) {
      fail("Cannot get ${id.name} from Git (${_getUrl(id)}).\n"
          "Please ensure Git is correctly installed.");
    }

    ensureDir(path.join(systemCacheRoot, 'cache'));
    await _ensureRevision(id);
    var revisionCachePath = getDirectory(await resolveId(id));
    if (!entryExists(revisionCachePath)) {
      var cachePath = _repoCachePath(id.toRef());
      await _clone(cachePath, revisionCachePath, mirror: false);
    }

    var ref = await _getRev(id);
    if (ref != 'HEAD') await _checkOut(revisionCachePath, ref);

    return new Package.load(id.name, revisionCachePath, systemCache.sources);
  }

  /// Returns the path to the revision-specific cache of [id].
  String getDirectory(PackageId id) {
    if (id.description is! Map || !id.description.containsKey('resolved-ref')) {
      throw new ArgumentError("Can't get the directory for unresolved id $id.");
    }

    return path.join(systemCacheRoot,
        "${id.name}-${id.description['resolved-ref']}");
  }

  /// Ensures [description] is a Git URL.
  dynamic parseDescription(String containingPath, description,
                           {bool fromLockFile: false}) {
    // TODO(rnystrom): Handle git URLs that are relative file paths (#8570).
    // TODO(rnystrom): Now that this function can modify the description, it
    // may as well canonicalize it to a map so that other code in the source
    // can assume that.
    // A single string is assumed to be a Git URL.
    if (description is String) return description;
    if (description is! Map || !description.containsKey('url')) {
      throw new FormatException("The description must be a Git URL or a map "
          "with a 'url' key.");
    }

    var parsed = new Map.from(description);
    parsed.remove('url');
    parsed.remove('ref');
    parsed.remove('use_version_tags');
    if (fromLockFile) parsed.remove('resolved-ref');

    if (!parsed.isEmpty) {
      var plural = parsed.length > 1;
      var keys = parsed.keys.join(', ');
      throw new FormatException("Invalid key${plural ? 's' : ''}: $keys.");
    }

    return description;
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
    if (_getUrl(description1) != _getUrl(description2)) return false;
    if (_getRef(description1) != _getRef(description2)) return false;

    if (description1 is Map && description1.containsKey('resolved-ref') &&
        description2 is Map && description2.containsKey('resolved-ref')) {
      return description1['resolved-ref'] == description2['resolved-ref'];
    }

    return true;
  }

  /// Attaches a specific commit to [id] to disambiguate it.
  Future<PackageId> resolveId(PackageId id) {
    return _ensureRevision(id).then((revision) {
      var description = {'url': _getUrl(id), 'ref': _getRef(id)};
      bool useVersionTags = _useVersionTags(id);
      if (useVersionTags) {
        description['use_version_tags'] = useVersionTags;
      }
      description['resolved-ref'] = revision;
      return new PackageId(id.name, name, id.version, description);
    });
  }

  List<Package> getCachedPackages() {
    // TODO(keertip): Implement getCachedPackages().
    throw new UnimplementedError(
        "The git source doesn't support listing its cached packages yet.");
  }

  /// Resets all cached packages back to the pristine state of the Git
  /// repository at the revision they are pinned to.
  Future<Pair<List<PackageId>, List<PackageId>>> repairCachedPackages() async {
    if (!dirExists(systemCacheRoot)) return new Pair([], []);

    var successes = [];
    var failures = [];

    var packages = listDir(systemCacheRoot)
        .where((entry) => dirExists(path.join(entry, ".git")))
        .map((packageDir) => new Package.load(null, packageDir,
            systemCache.sources))
        .toList();

    // Note that there may be multiple packages with the same name and version
    // (pinned to different commits). The sort order of those is unspecified.
    packages.sort(Package.orderByNameAndVersion);

    for (var package in packages) {
      var id = new PackageId(package.name, this.name, package.version, null);

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

  /// Ensure the canonical clone of the repository referred to by [ref] exists.
  ///
  /// Returns a future that completes with true if the repo was cloned, and
  /// false if the repo clone already exists.
  Future<bool> _ensureRepo(PackageRef ref, {mirror: false}) async {
    String cachePath = _repoCachePath(ref);
    if (!entryExists(cachePath)) {
      // Must have the repo cloned in order to list its tags
      await _clone(_getUrl(ref), cachePath, mirror: mirror);
      return true;
    }
    return false;
  }

  /// Ensure that the canonical clone of the repository referred to by [id] (the
  /// one in `<system cache>/git/cache`) exists and contains the revision
  /// referred to by [id].
  ///
  /// Returns a future that completes to the hash of the revision identified by
  /// [id].
  Future<String> _ensureRevision(PackageId id) async {
    PackageRef packageRef = id.toRef();
    if (await _ensureRepo(packageRef, mirror: true)) {
      return _getRev(id);
    }

    // If [id] didn't come from a lockfile, it may be using a symbolic
    // reference. We want to get the latest version of that reference.
    var description = id.description;
    if (description is! Map || !description.containsKey('resolved-ref')) {
      return _updateRepoCache(id).then((_) => _getRev(id));
    }

    // If [id] did come from a lockfile, then we want to avoid running "git
    // fetch" if possible to avoid networking time and errors. See if the
    // revision exists in the repo cache before updating it.
    return _getRev(id).catchError((error) {
      if (error is! git.GitException) throw error;
      return _updateRepoCache(id).then((_) => _getRev(id));
    });
  }

  /// Runs "git fetch" in the canonical clone of the repository referred to by
  /// [id].
  ///
  /// This assumes that the canonical clone already exists.
  Future _updateRepoCache(PackageId id) {
    var path = _repoCachePath(id.toRef());
    if (_updatedRepos.contains(path)) return new Future.value();
    return git.run(["fetch"], workingDir: path).then((_) {
      _updatedRepos.add(path);
    });
  }

  /// Runs "git rev-list" in the canonical clone of the repository referred to
  /// by [id] on the effective ref of [id].
  ///
  /// This assumes that the canonical clone already exists.
  Future<String> _getRev(PackageId id) async {
    var ref = _getEffectiveRef(id);
    try {
      var result = await git.run(["rev-list", "--max-count=1", ref],
          workingDir: _repoCachePath(id.toRef()));
      return result.first;
    } on git.GitException {
      if (ref == id.version.toString()) {
        // Try again with a "v" before the ref in case this was a version tag
        ref = 'v$ref';
        var result = await git.run(["rev-list", "--max-count=1", ref],
            workingDir: _repoCachePath(id.toRef()));
        return result.first;
      }
      rethrow;
    }
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
  Future _checkOut(String repoPath, String ref) async {
    try {
      await git.run(["checkout", ref], workingDir: repoPath);
    } on git.GitException {
      // Try again with a "v" before the ref in case this was a version tag
      await git.run(["checkout", 'v$ref'], workingDir: repoPath);
    }
  }

  /// Use `git show` to get the pubspec.yaml at a particular ref,
  /// then parse it into a Pubspec object
  ///
  /// It is possible that a pubspec didn't always exist, return null if
  /// that is the case.
  Future<Pubspec> _getPubspec(String repoPath, String ref) async {
    try {
      var result = await git.run(['show', '$ref:pubspec.yaml'],
          workingDir: repoPath);
      return new Pubspec.parse(result.join('\n'), systemCache.sources);
    } on git.GitException {
      return null;
    }
  }

  /// Returns the path to the canonical clone of the repository referred to by
  /// [id] (the one in `<system cache>/git/cache`).
  String _repoCachePath(PackageRef ref) {
    var repoCacheName = '${ref.name}-${sha1(_getUrl(ref))}';
    return path.join(systemCacheRoot, 'cache', repoCacheName);
  }

  /// Returns the repository URL for [id].
  ///
  /// [description] may be a description, a [PackageId], or a [PackageRef].
  String _getUrl(description) {
    description = _getDescription(description);
    if (description is String) return description;
    return description['url'];
  }

  /// Returns the commit ref that should be checked out for [description].
  ///
  /// This differs from [_getRef] in that it doesn't just return the ref in
  /// [description]. It will return a sensible default if that ref doesn't
  /// exist, and it will respect the "resolved-ref" parameter set by
  /// [resolveId].
  ///
  /// [description] may be a description, a [PackageId], or a [PackageRef].
  String _getEffectiveRef(PackageId id) {
    Map description = _getDescription(id);
    if (description is Map && description.containsKey('resolved-ref')) {
      return description['resolved-ref'];
    }

    var ref = _getRef(description);
    if (_useVersionTags(description) && id.version != null &&
        id.version != Version.none) {
      return id.version.toString();
    }
    return ref == null ? 'HEAD' : ref;
  }

  /// Returns the commit ref for [description], or null if none is given.
  ///
  /// [description] may be a description or a [PackageId].
  String _getRef(description) {
    description = _getDescription(description);
    if (description is String) return null;
    return description['ref'];
  }

  /// Returns [description] if it's a description, a [PackageId.description] if
  /// it's a [PackageId], or a [PackageRef.description] if it's a [PackageRef].
  _getDescription(description) {
    if (description is PackageId || description is PackageRef) {
      return description.description;
    }
    return description;
  }

  /// Returns value of "use_version_tags" in the description
  ///
  /// [description] may be a description a [PackageId], or a [PackageRef].
  bool _useVersionTags(description) {
    description = _getDescription(description);
    if (description is String) return false;
    return description.containsKey('use_version_tags')
        ? description['use_version_tags'] : false;
  }
}
