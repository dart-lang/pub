// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'barback/transformer_id.dart';
import 'git.dart' as git;
import 'io.dart';
import 'package_name.dart';
import 'pubspec.dart';
import 'source_registry.dart';
import 'utils.dart';

final _README_REGEXP = new RegExp(r"^README($|\.)", caseSensitive: false);

/// A named, versioned, unit of code and resource reuse.
class Package {
  /// Compares [a] and [b] orders them by name then version number.
  ///
  /// This is normally used as a [Comparator] to pass to sort. This does not
  /// take a package's description or root directory into account, so multiple
  /// distinct packages may order the same.
  static int orderByNameAndVersion(Package a, Package b) {
    var name = a.name.compareTo(b.name);
    if (name != 0) return name;

    return a.version.compareTo(b.version);
  }

  /// The path to the directory containing the package.
  final String dir;

  /// The name of the package.
  String get name {
    if (pubspec.name != null) return pubspec.name;
    if (dir != null) return p.basename(dir);
    return null;
  }

  /// The package's version.
  Version get version => pubspec.version;

  /// The parsed pubspec associated with this package.
  final Pubspec pubspec;

  /// The immediate dependencies this package specifies in its pubspec.
  List<PackageDep> get dependencies => pubspec.dependencies;

  /// The immediate dev dependencies this package specifies in its pubspec.
  List<PackageDep> get devDependencies => pubspec.devDependencies;

  /// The dependency overrides this package specifies in its pubspec.
  List<PackageDep> get dependencyOverrides => pubspec.dependencyOverrides;

  /// All immediate dependencies this package specifies.
  ///
  /// This includes regular, dev dependencies, and overrides.
  List<PackageDep> get immediateDependencies {
    var deps = <String, PackageDep>{};

    addToMap(dep) {
      deps[dep.name] = dep;
    }

    dependencies.forEach(addToMap);
    devDependencies.forEach(addToMap);

    // Make sure to add these last so they replace normal dependencies.
    dependencyOverrides.forEach(addToMap);

    return deps.values.toList();
  }

  /// Returns a list of asset ids for all Dart executables in this package's bin
  /// directory.
  List<AssetId> get executableIds {
    return ordered(listFiles(beneath: "bin", recursive: false))
        .where((executable) => p.extension(executable) == '.dart')
        .map((executable) {
      return new AssetId(
          name, p.toUri(p.relative(executable, from: dir)).toString());
    }).toList();
  }

  /// Returns the path to the README file at the root of the entrypoint, or null
  /// if no README file is found.
  ///
  /// If multiple READMEs are found, this uses the same conventions as
  /// pub.dartlang.org for choosing the primary one: the README with the fewest
  /// extensions that is lexically ordered first is chosen.
  String get readmePath {
    var readmes = listFiles(recursive: false, useGitIgnore: true)
        .map(p.basename)
        .where((entry) => entry.contains(_README_REGEXP));
    if (readmes.isEmpty) return null;

    return p.join(dir, readmes.reduce((readme1, readme2) {
      var extensions1 = ".".allMatches(readme1).length;
      var extensions2 = ".".allMatches(readme2).length;
      var comparison = extensions1.compareTo(extensions2);
      if (comparison == 0) comparison = readme1.compareTo(readme2);
      return (comparison <= 0) ? readme1 : readme2;
    }));
  }

  /// Returns whether or not this package is in a Git repo.
  bool get _inGitRepo {
    if (_inGitRepoCache != null) return _inGitRepoCache;

    if (dir == null || !git.isInstalled) {
      _inGitRepoCache = false;
    } else {
      // If the entire package directory is ignored, don't consider it part of a
      // git repo. `git check-ignore` will return a status code of 0 for
      // ignored, 1 for not ignored, and 128 for not a Git repo.
      var result = runProcessSync(git.command, ['check-ignore', '--quiet', '.'],
          workingDir: dir);
      _inGitRepoCache = result.exitCode == 1;
    }

    return _inGitRepoCache;
  }

  bool _inGitRepoCache;

  /// Loads the package whose root directory is [packageDir].
  ///
  /// [name] is the expected name of that package (e.g. the name given in the
  /// dependency), or `null` if the package being loaded is the entrypoint
  /// package.
  Package.load(String name, String packageDir, SourceRegistry sources)
      : dir = packageDir,
        pubspec = new Pubspec.load(packageDir, sources, expectedName: name);

  /// Constructs a package with the given pubspec.
  ///
  /// The package will have no directory associated with it.
  Package.inMemory(this.pubspec) : dir = null;

  /// Creates a package with [pubspec] located at [dir].
  Package(this.pubspec, this.dir);

  /// Given a relative path within this package, returns its absolute path.
  ///
  /// This is similar to `p.join(dir, part1, ...)`, except that subclasses may
  /// override it to report that certain paths exist elsewhere than within
  /// [dir]. For example, a [CachedPackage]'s `lib` directory is in the
  /// `.pub/deps` directory.
  String path(String part1,
      [String part2,
      String part3,
      String part4,
      String part5,
      String part6,
      String part7]) {
    if (dir == null) {
      throw new StateError("Package $name is in-memory and doesn't have paths "
          "on disk.");
    }
    return p.join(dir, part1, part2, part3, part4, part5, part6, part7);
  }

  /// Given an absolute path within this package (such as that returned by
  /// [path] or [listFiles]), returns it relative to the package root.
  String relative(String path) {
    if (dir == null) {
      throw new StateError("Package $name is in-memory and doesn't have paths "
          "on disk.");
    }
    return p.relative(path, from: dir);
  }

  /// Returns the path to the library identified by [id] within [this].
  String transformerPath(TransformerId id) {
    if (id.package != name) {
      throw new ArgumentError("Transformer $id isn't in package $name.");
    }

    if (id.path != null) return path('lib', p.fromUri('${id.path}.dart'));

    var transformerPath = path('lib/transformer.dart');
    if (fileExists(transformerPath)) return transformerPath;
    return path('lib/$name.dart');
  }

  /// Returns the type of dependency from this package onto [name].
  DependencyType dependencyType(String name) {
    if (pubspec.fields['dependencies']?.containsKey(name) ?? false) {
      return DependencyType.direct;
    } else if (pubspec.fields['dev_dependencies']?.containsKey(name) ?? false) {
      return DependencyType.dev;
    } else {
      return DependencyType.none;
    }
  }

  /// The basenames of files that are included in [list] despite being hidden.
  static final _WHITELISTED_FILES = const ['.htaccess'];

  /// A set of patterns that match paths to blacklisted files.
  static final _blacklistedFiles = createFileFilter(['pubspec.lock']);

  /// A set of patterns that match paths to blacklisted directories.
  static final _blacklistedDirs = createDirectoryFilter(['packages']);

  /// Returns a list of files that are considered to be part of this package.
  ///
  /// If [beneath] is passed, this will only return files beneath that path,
  /// which is expected to be relative to the package's root directory. If
  /// [recursive] is true, this will return all files beneath that path;
  /// otherwise, it will only return files one level beneath it.
  ///
  /// If [useGitIgnore] is passed, this will take the .gitignore rules into
  /// account if the root directory of the package is (or is contained within) a
  /// Git repository.
  ///
  /// Note that the returned paths won't always be beneath [dir]. To safely
  /// convert them to paths relative to the package root, use [relative].
  List<String> listFiles(
      {String beneath, bool recursive: true, bool useGitIgnore: false}) {
    // An in-memory package has no files.
    if (dir == null) return [];

    if (beneath == null) {
      beneath = dir;
    } else {
      beneath = p.join(dir, beneath);
    }

    if (!dirExists(beneath)) return [];

    // This is used in some performance-sensitive paths and can list many, many
    // files. As such, it leans more havily towards optimization as opposed to
    // readability than most code in pub. In particular, it avoids using the
    // path package, since re-parsing a path is very expensive relative to
    // string operations.
    Iterable<String> files;
    if (useGitIgnore && _inGitRepo) {
      // List all files that aren't gitignored, including those not checked in
      // to Git. Use [beneath] as the working dir rather than passing it as a
      // parameter so that we list a submodule using its own git logic.
      files = git.runSync(
          ["ls-files", "--cached", "--others", "--exclude-standard"],
          workingDir: beneath);

      // If we're not listing recursively, strip out paths that contain
      // separators. Since git always prints forward slashes, we always detect
      // them.
      if (!recursive) files = files.where((file) => !file.contains('/'));

      // Git prints files relative to [beneath], but we want them relative to
      // the pub's working directory. It also prints forward slashes on Windows
      // which we normalize away for easier testing.
      files = files.map((file) {
        if (Platform.operatingSystem != 'windows') return "$beneath/$file";
        return "$beneath\\${file.replaceAll("/", "\\")}";
      }).expand((file) {
        if (fileExists(file)) return [file];
        if (!dirExists(file)) return [];

        // `git ls-files` only returns files, except in the case of a submodule
        // or a symlink to a directory.
        return recursive ? _listWithinDir(file) : [file];
      });
    } else {
      files = listDir(beneath,
          recursive: recursive,
          includeDirs: false,
          whitelist: _WHITELISTED_FILES);
    }

    return files.where((file) {
      // Using substring here is generally problematic in cases where dir has
      // one or more trailing slashes. If you do listDir("foo"), you'll get back
      // paths like "foo/bar". If you do listDir("foo/"), you'll get "foo/bar"
      // (note the trailing slash was dropped. If you do listDir("foo//"),
      // you'll get "foo//bar".
      //
      // This means if you strip off the prefix, the resulting string may have a
      // leading separator (if the prefix did not have a trailing one) or it may
      // not. However, since we are only using the results of that to call
      // contains() on, the leading separator is harmless.
      assert(file.startsWith(beneath));
      file = file.substring(beneath.length);
      return !_blacklistedFiles.any(file.endsWith) &&
          !_blacklistedDirs.any(file.contains);
    }).toList();
  }

  /// List all files recursively beneath [dir], which should be either a symlink
  /// to a directory or a git submodule.
  ///
  /// This is used by [list] when listing a Git repository, since `git ls-files`
  /// can't natively follow symlinks and (as of Git 2.12.0-rc1) can't use
  /// `--recurse-submodules` in conjunction with `--other`.
  Iterable<String> _listWithinDir(String subdir) {
    assert(dirExists(subdir));
    assert(p.isWithin(dir, subdir));

    var target = new Directory(subdir).resolveSymbolicLinksSync();

    List<String> targetFiles;
    if (p.isWithin(dir, target)) {
      // If the link points within this repo, use git to list the target
      // location so we respect .gitignore.
      targetFiles = listFiles(
          beneath: p.relative(target, from: dir),
          recursive: true,
          useGitIgnore: true);
    } else {
      // If the link points outside this repo, just use the default listing
      // logic.
      targetFiles = listDir(target,
          recursive: true, includeDirs: false, whitelist: _WHITELISTED_FILES);
    }

    // Re-write the paths so they're underneath the symlink.
    return targetFiles.map(
        (targetFile) => p.join(subdir, p.relative(targetFile, from: target)));
  }

  /// Returns a debug string for the package.
  String toString() => '$name $version ($dir)';
}

/// The type of dependency from one package to another.
class DependencyType {
  /// A dependency declared in `dependencies`.
  static const direct = const DependencyType._("direct");

  /// A dependency declared in `dev_dependencies`.
  static const dev = const DependencyType._("dev");

  /// No dependency exists.
  static const none = const DependencyType._("none");

  final String _name;

  const DependencyType._(this._name);

  String toString() => _name;
}
