// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'exceptions.dart';
import 'git.dart' as git;
import 'ignore.dart';
import 'io.dart';
import 'log.dart' as log;
import 'package_name.dart';
import 'pubspec.dart';
import 'source_registry.dart';
import 'utils.dart';

final _readmeRegexp = RegExp(r'^README($|\.)', caseSensitive: false);
final _changelogRegexp = RegExp(r'^CHANGELOG($|\.)', caseSensitive: false);

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

  /// An in-memory package can be created for doing a resolution without having
  /// a package on disk. Paths should not be resolved for these.
  bool get _isInMemory => dir == null;

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
  Map<String, PackageRange> get dependencies => pubspec.dependencies;

  /// The immediate dev dependencies this package specifies in its pubspec.
  Map<String, PackageRange> get devDependencies => pubspec.devDependencies;

  /// The dependency overrides this package specifies in its pubspec.
  Map<String, PackageRange> get dependencyOverrides =>
      pubspec.dependencyOverrides;

  /// All immediate dependencies this package specifies.
  ///
  /// This includes regular, dev dependencies, and overrides.
  Map<String, PackageRange> get immediateDependencies {
    // Make sure to add overrides last so they replace normal dependencies.
    return {}
      ..addAll(dependencies)
      ..addAll(devDependencies)
      ..addAll(dependencyOverrides);
  }

  /// Returns a list of asset ids for all Dart executables in this package's bin
  /// directory.
  List<String> get executablePaths {
    return ordered(listFiles(beneath: 'bin', recursive: false))
        .where((executable) => p.extension(executable) == '.dart')
        .map((executable) => p.relative(executable, from: dir))
        .toList();
  }

  List<String> get executableNames =>
      executablePaths.map(p.basenameWithoutExtension).toList();

  /// Returns the path to the README file at the root of the entrypoint, or null
  /// if no README file is found.
  ///
  /// If multiple READMEs are found, this uses the same conventions as
  /// pub.dartlang.org for choosing the primary one: the README with the fewest
  /// extensions that is lexically ordered first is chosen.
  String get readmePath {
    var readmes = listFiles(recursive: false)
        .map(p.basename)
        .where((entry) => entry.contains(_readmeRegexp));
    if (readmes.isEmpty) return null;

    return p.join(dir, readmes.reduce((readme1, readme2) {
      var extensions1 = '.'.allMatches(readme1).length;
      var extensions2 = '.'.allMatches(readme2).length;
      var comparison = extensions1.compareTo(extensions2);
      if (comparison == 0) comparison = readme1.compareTo(readme2);
      return (comparison <= 0) ? readme1 : readme2;
    }));
  }

  /// Returns the path to the CHANGELOG file at the root of the entrypoint, or
  /// null if no CHANGELOG file is found.
  String get changelogPath {
    return listFiles(recursive: false).firstWhere(
        (entry) => p.basename(entry).contains(_changelogRegexp),
        orElse: () => null);
  }

  /// Returns whether or not this package is in a Git repo.
  bool get inGitRepo {
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
  Package.load(String name, this.dir, SourceRegistry sources)
      : pubspec = Pubspec.load(dir, sources, expectedName: name);

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
  /// [dir].
  String path(String part1,
      [String part2,
      String part3,
      String part4,
      String part5,
      String part6,
      String part7]) {
    if (_isInMemory) {
      throw StateError("Package $name is in-memory and doesn't have paths "
          'on disk.');
    }
    return p.join(dir, part1, part2, part3, part4, part5, part6, part7);
  }

  /// Given an absolute path within this package (such as that returned by
  /// [path] or [listFiles]), returns it relative to the package root.
  String relative(String path) {
    if (dir == null) {
      throw StateError("Package $name is in-memory and doesn't have paths "
          'on disk.');
    }
    return p.relative(path, from: dir);
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

  static final _basicIgnoreRules = [
    '.*', // Don't include dot-files.
    '!.htaccess', // Include .htaccess anyways.
    // TODO(sigurdm): consider removing this. `packages` folders are not used
    // anymore.
    'packages/',
    'pubspec.lock',
    '!pubspec.lock/', // We allow a directory called pubspec lock.
  ];

  /// Returns a list of files that are considered to be part of this package.
  ///
  /// If [beneath] is passed, this will only return files beneath that path,
  /// which is expected to be relative to the package's root directory. If
  /// [recursive] is true, this will return all files beneath that path;
  /// otherwise, it will only return files one level beneath it.
  ///
  /// This will take .pubignore and .gitignore files into account. For each
  /// directory a .pubignore takes precedence over a .gitignore.
  ///
  /// Note that the returned paths won't always be beneath [dir]. To safely
  /// convert them to paths relative to the package root, use [relative].
  List<String> listFiles({String beneath, bool recursive = true}) {
    // An in-memory package has no files.
    if (dir == null) return [];
    beneath = beneath == null ? '.' : p.toUri(p.normalize(beneath)).path;
    String resolve(String path) {
      if (Platform.isWindows) {
        return p.joinAll([dir, ...p.posix.split(path)]);
      }
      return p.join(dir, path);
    }

    return Ignore.listFiles(
      beneath: beneath,
      listDir: (dir) {
        var contents = Directory(resolve(dir)).listSync();
        if (!recursive) {
          contents = contents.where((entity) => entity is! Directory).toList();
        }
        return contents.map((entity) {
          if (linkExists(entity.path)) {
            final target = Link(entity.path).targetSync();
            if (dirExists(entity.path)) {
              throw DataException(
                  '''Pub does not support publishing packages with directory symlinks: `${entity.path}`.''');
            }
            if (!fileExists(entity.path)) {
              throw DataException(
                  '''Pub does not support publishing packages with non-resolving symlink: `${entity.path}` => `$target`.''');
            }
          }
          final relative = p.relative(entity.path, from: this.dir);
          if (Platform.isWindows) {
            return p.posix.joinAll(p.split(relative));
          }
          return relative;
        });
      },
      ignoreForDir: (dir) {
        final pubIgnore = resolve('$dir/.pubignore');
        final gitIgnore = resolve('$dir/.gitignore');
        final ignoreFile = fileExists(pubIgnore)
            ? pubIgnore
            : (fileExists(gitIgnore) ? gitIgnore : null);

        final rules = [
          if (dir == '.') ..._basicIgnoreRules,
          if (ignoreFile != null) readTextFile(ignoreFile),
        ];
        return rules.isEmpty
            ? null
            : Ignore(
                rules,
                onInvalidPattern: (pattern, exception) {
                  log.warning(
                      '$ignoreFile had invalid pattern $pattern. ${exception.message}');
                },
              );
      },
      isDir: (dir) => dirExists(resolve(dir)),
    ).map(resolve).toList();
  }
}

/// The type of dependency from one package to another.
class DependencyType {
  /// A dependency declared in `dependencies`.
  static const direct = DependencyType._('direct');

  /// A dependency declared in `dev_dependencies`.
  static const dev = DependencyType._('dev');

  /// No dependency exists.
  static const none = DependencyType._('none');

  final String _name;

  const DependencyType._(this._name);

  @override
  String toString() => _name;
}
