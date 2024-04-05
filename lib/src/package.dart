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
import 'source/root.dart';
import 'system_cache.dart';
import 'utils.dart';

/// A Package is a [Pubspec] and a directory where it belongs that can be used
/// for version solving or as a node in a package graph.
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
  String get name => pubspec.name;

  /// The package's version.
  Version get version => pubspec.version;

  /// The parsed pubspec associated with this package.
  final Pubspec pubspec;

  /// The path to the entrypoint package's pubspec.
  String get pubspecPath => p.normalize(p.join(dir, 'pubspec.yaml'));

  /// The path to the entrypoint package's pubspec overrides file.
  String get pubspecOverridesPath =>
      p.normalize(p.join(dir, 'pubspec_overrides.yaml'));

  /// The (non-transitive) workspace packages.
  final List<Package> workspaceChildren;

  /// The transitive closure of [workspaceChildren] rooted at this package.
  ///
  /// Includes this package.
  Iterable<Package> get transitiveWorkspace sync* {
    final stack = [this];

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      yield current;
      stack.addAll(current.workspaceChildren);
    }
  }

  /// The immediate dependencies this package specifies in its pubspec.
  Map<String, PackageRange> get dependencies => pubspec.dependencies;

  /// The immediate dev dependencies this package specifies in its pubspec.
  Map<String, PackageRange> get devDependencies => pubspec.devDependencies;

  /// The dependency overrides this package specifies in its pubspec or pubspec
  /// overrides.
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

  /// Returns a list of paths to all Dart executables in this package's bin
  /// directory.
  List<String> get executablePaths {
    final binDir = p.join(dir, 'bin');
    if (!dirExists(binDir)) return <String>[];
    return ordered(listDir(p.join(dir, 'bin'), includeDirs: false))
        .where((executable) => p.extension(executable) == '.dart')
        .map((executable) => p.relative(executable, from: dir))
        .toList();
  }

  List<String> get executableNames =>
      executablePaths.map(p.basenameWithoutExtension).toList();

  /// Returns whether or not this package is in a Git repo.
  late final bool inGitRepo = computeInGitRepoCache();

  bool computeInGitRepoCache() {
    if (!git.isInstalled) {
      return false;
    } else {
      // If the entire package directory is ignored, don't consider it part of a
      // git repo. `git check-ignore` will return a status code of 0 for
      // ignored, 1 for not ignored, and 128 for not a Git repo.
      var result = runProcessSync(
        git.command!,
        ['check-ignore', '--quiet', '.'],
        workingDir: dir,
      );
      return result.exitCode == 1;
    }
  }

  /// Loads the package whose root directory is [packageDir].
  ///
  /// Will also load the workspace sub-packages of this package (recursively).
  ///
  /// [name] is the expected name of that package (e.g. the name given in the
  /// dependency), or `null` if the package being loaded is the entrypoint
  /// package.
  ///
  /// `pubspec_overrides.yaml` is only loaded if [withPubspecOverrides] is
  /// `true`.
  ///
  /// [loadPubspec] if given will be used to obtain a pubspec from a path. Also
  /// for the workspace children.
  ///
  /// This mechanism can be used to avoid loading pubspecs twice. It can also be
  /// used to override a pubspec in memory for trying out an alternative
  /// resolution.
  factory Package.load(
    String dir,
    SourceRegistry sources, {
    bool withPubspecOverrides = false,
    String? expectedName,
    Pubspec Function(
      String path, {
      String? expectedName,
      required bool withPubspecOverrides,
    })? loadPubspec,
  }) {
    loadPubspec ??=
        (path, {expectedName, required withPubspecOverrides}) => Pubspec.load(
              path,
              sources,
              containingDescription: RootDescription(path),
            );
    final pubspec = loadPubspec(
      dir,
      withPubspecOverrides: withPubspecOverrides,
      expectedName: expectedName,
    );
    final workspacePackages = pubspec.workspace
        .map(
          (e) => Package.load(
            p.join(dir, e),
            sources,
            loadPubspec: loadPubspec,
            withPubspecOverrides: withPubspecOverrides,
          ),
        )
        .toList();
    for (final package in workspacePackages) {
      if (package.pubspec.resolution != Resolution.workspace) {
        fail('''
${package.pubspecPath} is inluded in the workspace from ${p.join(dir, 'pubspec.yaml')}, but does not have `resolution: workspace`.

See $workspacesDocUrl for more information.
''');
      }
    }
    return Package(pubspec, dir, workspacePackages);
  }

  /// Creates a package with [pubspec] associated with [dir].
  ///
  /// For temporary resolution attempts [pubspec] does not have to correspond
  /// to the one at disk.
  Package(this.pubspec, this.dir, this.workspaceChildren);

  /// Given a relative path within this package, returns its absolute path.
  ///
  /// This is similar to `p.join(dir, part1, ...)`, except that subclasses may
  /// override it to report that certain paths exist elsewhere than within
  /// [dir].
  String path(
    String? part1, [
    String? part2,
    String? part3,
    String? part4,
    String? part5,
    String? part6,
    String? part7,
  ]) {
    return p.join(dir, part1, part2, part3, part4, part5, part6, part7);
  }

  /// Given an absolute path within this package (such as that returned by
  /// [path] or [listFiles]), returns it relative to the package root.
  String relative(String path) {
    return p.relative(path, from: dir);
  }

  static final _basicIgnoreRules = [
    '.*', // Don't include dot-files.
    '!.htaccess', // Include .htaccess anyways.
    'pubspec.lock',
    '!pubspec.lock/', // We allow a directory called pubspec lock.
    '/pubspec_overrides.yaml',
  ];

  /// Returns a list of files that are considered to be part of this package.
  ///
  /// If [beneath] is passed, this will only return files beneath that path,
  /// which is expected to be relative to the package's root directory. If
  /// [recursive] is true, this will return all files beneath that path;
  /// otherwise, it will only return files one level beneath it.
  ///
  /// This will take .pubignore and .gitignore files into account.
  ///
  /// If [dir] is inside a git repository, all ignore files from the repo root
  /// are considered.
  ///
  /// For each directory a .pubignore takes precedence over a .gitignore.
  ///
  /// Note that the returned paths will be always be below [dir], and will
  /// always start with [dir] (thus always be relative to the current working
  /// directory) or absolute id [dir] is absolute.
  ///
  /// To convert them to paths relative to the package root, use [p.relative].
  List<String> listFiles({String? beneath, bool recursive = true}) {
    var packageDir = dir;
    var root = git.repoRoot(packageDir) ?? packageDir;
    beneath = p
        .toUri(
          p.normalize(
            p.relative(p.join(packageDir, beneath ?? '.'), from: root),
          ),
        )
        .path;
    if (beneath == './') beneath = '.';
    String resolve(String path) {
      if (Platform.isWindows) {
        return p.joinAll([root, ...p.posix.split(path)]);
      }
      return p.join(root, path);
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
                '''Pub does not support publishing packages with directory symlinks: `${entity.path}`.''',
              );
            }
            if (!fileExists(entity.path)) {
              throw DataException(
                '''Pub does not support publishing packages with non-resolving symlink: `${entity.path}` => `$target`.''',
              );
            }
          }
          final relative = p.relative(entity.path, from: root);
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
          if (dir == beneath) ..._basicIgnoreRules,
          if (ignoreFile != null) readTextFile(ignoreFile),
        ];
        return rules.isEmpty
            ? null
            : Ignore(
                rules,
                onInvalidPattern: (pattern, exception) {
                  log.warning(
                    '$ignoreFile had invalid pattern $pattern. ${exception.message}',
                  );
                },
                // Ignore case on macOS and Windows, because `git clone` and
                // `git init` will set `core.ignoreCase = true` in the local
                // local `.git/config` file for the repository.
                //
                // So on Windows and macOS most users will have case-insensitive
                // behavior with `.gitignore`, hence, it seems reasonable to do
                // the same when we interpret `.gitignore` and `.pubignore`.
                //
                // There are cases where a user may have case-sensitive behavior
                // with `.gitignore` on Windows and macOS:
                //
                //  (A) The user has manually overwritten the repository
                //      configuration setting `core.ignoreCase = false`.
                //
                //  (B) The git-clone or git-init command that create the
                //      repository did not deem `core.ignoreCase = true` to be
                //      appropriate. Documentation for [git-config]][1] implies
                //      this might depend on whether or not the filesystem is
                //      case sensitive:
                //      > If true, this option enables various workarounds to
                //      > enable Git to work better on filesystems that are not
                //      > case sensitive, like FAT.
                //      > ...
                //      > The default is false, except git-clone[1] or
                //      > git-init[1] will probe and set core.ignoreCase true
                //      > if appropriate when the repository is created.
                //
                // In either case, it seems likely that users on Windows and
                // macOS will prefer case-insensitive matching. We specifically
                // know that some tooling will generate `.PDB` files instead of
                // `.pdb`, see: [#3003][2]
                //
                // [1]: https://git-scm.com/docs/git-config/2.14.6#Documentation/git-config.txt-coreignoreCase
                // [2]: https://github.com/dart-lang/pub/issues/3003
                ignoreCase: Platform.isMacOS || Platform.isWindows,
              );
      },
      isDir: (dir) => dirExists(resolve(dir)),
    ).map(resolve).toList();
  }
}

/// Reports an error if the graph of the workspace rooted at [root] is not a
/// tree.
void validateWorkspaceGraph(Package root) {
  final includedFrom = <String, String>{};
  final stack = [root];

  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    for (final child in current.workspaceChildren) {
      final previous = includedFrom[child.dir];
      if (previous != null) {
        fail('''
Packages can only be included in the workspace once.

`${p.join(child.dir, 'pubspec.yaml')}` is included in the workspace, both from:
* `${p.join(current.dir, 'pubspec.yaml')}` and
* ${p.join(previous, 'pubspec.yaml')}.''');
      }
      includedFrom[child.dir] = current.dir;
    }
    stack.addAll(current.workspaceChildren);
  }
}
