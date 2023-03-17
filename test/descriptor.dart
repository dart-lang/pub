// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Pub-specific test descriptors.
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:pub/src/language_version.dart';
import 'package:pub/src/package_config.dart';
import 'package:pub/src/third_party/oauth2/lib/oauth2.dart' as oauth2;
import 'package:test_descriptor/test_descriptor.dart';

import 'descriptor/git.dart';
import 'descriptor/package_config.dart';
import 'descriptor/tar.dart';
import 'descriptor/yaml.dart';
import 'test_pub.dart';

export 'package:test_descriptor/test_descriptor.dart';

export 'descriptor/git.dart';
export 'descriptor/package_config.dart';
export 'descriptor/tar.dart';

/// Creates a new [GitRepoDescriptor] with [name] and [contents].
GitRepoDescriptor git(String name, [List<Descriptor>? contents]) =>
    GitRepoDescriptor(name, contents ?? <Descriptor>[]);

/// Creates a new [TarFileDescriptor] with [name] and [contents].
TarFileDescriptor tar(String name, [List<Descriptor>? contents]) =>
    TarFileDescriptor(name, contents ?? <Descriptor>[]);

FileDescriptor validPubspec({Map<String, Object?>? extras}) =>
    libPubspec('test_pkg', '1.0.0', sdk: '>=3.1.2 <=3.2.0', extras: extras);

/// Describes a package that passes all validation.
DirectoryDescriptor validPackage({String version = '1.0.0'}) => dir(appPath, [
      validPubspec(extras: {'version': version}),
      file('LICENSE', 'Eh, do what you want.'),
      file('README.md', "This package isn't real."),
      file('CHANGELOG.md', '# $version\nFirst version\n'),
      dir('lib', [file('test_pkg.dart', 'int i = 1;')])
    ]);

/// Returns a descriptor of a snapshot that can't be run by the current VM.
///
/// This snapshot was generated using version 2.0.0-dev.58.0 of the VM.
FileDescriptor outOfDateSnapshot(String name) => file(
      name,
      base64.decode(
        'kKvN7wAAAAYBAAEAAQAAAAAAAAABBgMBBh8AAQEAAAABA'
        'wofAAAAAAAAAFwBShABHhAGAQABJwIAAAAAEwAAAAAAAA'
        'AVAAAAOQAAAAEAAAACAAAAJWZpbGU6Ly8vVXNlcnMvcm5'
        '5c3Ryb20vdGVtcC90ZW1wLmRhcnQgdm9pZCBtYWluKCkg'
        'PT4gcHJpbnQoJ2hlbGxvIScpOwoDACABAAAAUQAAAFQGA'
        'AMBBAIBAAUEBAUGAAAAAAcABAovN0BFbWFpbmhlbGxvIW'
        'ZpbGU6Ly8vVXNlcnMvcm55c3Ryb20vdGVtcC90ZW1wLmR'
        'hcnRAbWV0aG9kc2RhcnQ6Y29yZXByaW50AAAAAE0AAACn'
        'AAAAtAAAALQAAAC4AAABBQAAAAMAAAAJAAAATQAAAAEAA'
        'AEy',
      ),
    );

/// Describes a file named `pubspec.yaml` with the given YAML-serialized
/// [contents], which should be a serializable object.
///
/// [contents] may contain [Future]s that resolve to serializable objects,
/// which may in turn contain [Future]s recursively.
FileDescriptor pubspec(Map<String, Object?> contents) => YamlDescriptor(
      'pubspec.yaml',
      yaml({
        ...contents,
        // TODO: Copy-pasting this into all call-sites, or use d.libPubspec
        'environment': {
          'sdk': defaultSdkConstraint,
          ...(contents['environment'] ?? {}) as Map,
        },
      }),
    );

Descriptor rawPubspec(Map<String, Object> contents) =>
    YamlDescriptor('pubspec.yaml', yaml(contents));

/// Describes a file named `pubspec.yaml` for an application package with the
/// given [dependencies].
Descriptor appPubspec({Map? dependencies, Map<String, Object>? extras}) {
  var map = <String, Object>{
    'name': 'myapp',
    ...?extras,
  };
  if (dependencies != null) map['dependencies'] = dependencies;
  return pubspec(map);
}

/// Describes a file named `pubspec.yaml` for a library package with the given
/// [name], [version], and [deps]. If "sdk" is given, then it adds an SDK
/// constraint on that version, otherwise it adds an SDK constraint allowing
/// the current SDK version.
///
/// [extras] is additional fields of the pubspec.
FileDescriptor libPubspec(
  String name,
  String version, {
  Map? deps,
  Map? devDeps,
  String? sdk,
  Map<String, Object?>? extras,
}) {
  var map = packageMap(name, version, deps, devDeps);
  if (sdk != null) {
    map['environment'] = {'sdk': sdk};
  }
  return pubspec({...map, ...extras ?? {}});
}

/// Describes a file named `pubspec_overrides.yaml` by default, with the given
/// YAML-serialized [contents], which should be a serializable object.
///
/// [contents] may contain [Future]s that resolve to serializable objects,
/// which may in turn contain [Future]s recursively.
Descriptor pubspecOverrides(Map<String, Object> contents) => YamlDescriptor(
      'pubspec_overrides.yaml',
      yaml(contents),
    );

/// Describes a directory named `lib` containing a single dart file named
/// `<name>.dart` that contains a line of Dart code.
Descriptor libDir(String name, [String? code]) {
  // Default to printing the name if no other code was given.
  code ??= name;
  return dir('lib', [file('$name.dart', 'main() => "$code";')]);
}

/// Describes a directory whose name ends with a hyphen followed by an
/// alphanumeric hash.
Descriptor hashDir(String name, Iterable<Descriptor> contents) => pattern(
      RegExp("$name${r'-[a-f0-9]+'}"),
      (dirName) => dir(dirName, contents),
    );

/// Describes a directory for a Git repo with a dart package.
/// This directory is of the form found in the revision cache of the global
/// package cache.
///
/// If [repoName] is not given it is assumed to be equal to [packageName].
Descriptor gitPackageRevisionCacheDir(
  String packageName, {
  int? modifier,
  String? repoName,
}) {
  repoName = repoName ?? packageName;
  var value = packageName;
  if (modifier != null) value = '$packageName $modifier';
  return hashDir(repoName, [libDir(packageName, value)]);
}

/// Describes a directory for a Git package. This directory is of the form
/// found in the repo cache of the global package cache.
Descriptor gitPackageRepoCacheDir(String name) =>
    hashDir(name, [dir('objects'), dir('refs')]);

/// Describes the global package cache directory containing all the given
/// [packages], which should be name/version pairs. The packages will be
/// validated against the format produced by the mock package server.
///
/// A package's value may also be a list of versions, in which case all
/// versions are expected to be downloaded.
///
/// If [port] is passed, it's used as the port number of the local hosted server
/// that this cache represents. It defaults to [globalServer.port].
///
/// If [includePubspecs] is `true`, then pubspecs will be created for each
/// package. Defaults to `false` so that the contents of pubspecs are not
/// validated since they will often lack the dependencies section that the
/// real pubspec being compared against has. You usually only need to pass
/// `true` for this if you plan to call [create] on the resulting descriptor.
Descriptor cacheDir(Map packages, {int? port, bool includePubspecs = false}) {
  var contents = <Descriptor>[];
  packages.forEach((name, versions) {
    if (versions is! List) versions = [versions];
    for (var version in versions) {
      var packageContents = [libDir(name, '$name $version')];
      if (includePubspecs) {
        packageContents.add(libPubspec(name, version));
      }
      contents.add(dir('$name-$version', packageContents));
    }
  });

  return hostedCache(contents, port: port);
}

/// Describes the main cache directory containing cached hosted packages
/// downloaded from the mock package server.
///
/// If [port] is passed, it's used as the port number of the local hosted server
/// that this cache represents. It defaults to [globalServer.port].
Descriptor hostedCache(Iterable<Descriptor> contents, {int? port}) {
  return dir(hostedCachePath(port: port), contents);
}

/// Describes the hosted-hashes cache directory containing hashes of the hosted
/// packages downloaded from the mock package server.
///
/// If [port] is passed, it's used as the port number of the local hosted server
/// that this cache represents. It defaults to [globalServer.port].
Descriptor hostedHashesCache(Iterable<Descriptor> contents, {int? port}) {
  return dir(cachePath, [
    dir(
      'hosted-hashes',
      [dir('localhost%58${port ?? globalServer.port}', contents)],
    )
  ]);
}

String hostedCachePath({int? port}) =>
    p.join(cachePath, 'hosted', 'localhost%58${port ?? globalServer.port}');

/// Describes the file that contains the client's OAuth2
/// credentials. The URL "/token" on [server] will be used as the token
/// endpoint for refreshing the access token.
Descriptor credentialsFile(
  PackageServer server,
  String accessToken, {
  String? refreshToken,
  DateTime? expiration,
}) {
  return configDir(
    [
      file(
        'pub-credentials.json',
        _credentialsFileContent(
          server,
          accessToken,
          refreshToken: refreshToken,
          expiration: expiration,
        ),
      ),
    ],
  );
}

Descriptor legacyCredentialsFile(
  PackageServer server,
  String accessToken, {
  String? refreshToken,
  DateTime? expiration,
}) {
  return dir(
    cachePath,
    [
      file(
        'credentials.json',
        _credentialsFileContent(
          server,
          accessToken,
          refreshToken: refreshToken,
          expiration: expiration,
        ),
      ),
    ],
  );
}

String _credentialsFileContent(
  PackageServer server,
  String accessToken, {
  String? refreshToken,
  DateTime? expiration,
}) =>
    oauth2.Credentials(
      accessToken,
      refreshToken: refreshToken,
      tokenEndpoint: Uri.parse(server.url).resolve('/token'),
      scopes: [
        'openid',
        'https://www.googleapis.com/auth/userinfo.email',
      ],
      expiration: expiration,
    ).toJson();

/// Describes the file in the system cache that contains credentials for
/// third party hosted pub servers.
Descriptor tokensFile([Map<String, dynamic> contents = const {}]) {
  return configDir([file('pub-tokens.json', jsonEncode(contents))]);
}

/// Describes the application directory, containing only a pubspec specifying
/// the given [dependencies].
DirectoryDescriptor appDir({Map? dependencies, Map<String, Object>? pubspec}) =>
    dir(appPath, [appPubspec(dependencies: dependencies, extras: pubspec)]);

/// Describes a `.dart_tools/package_config.json` file.
///
/// [dependencies] is a list of packages included in the file.
///
/// Validation checks that the `.dart_tools/package_config.json` file exists,
/// has the expected entries (one per key in [dependencies]), each with a path
/// that matches the `rootUri` of that package.
Descriptor packageConfigFile(
  List<PackageConfigEntry> packages, {
  String generatorVersion = '3.1.2+3',
}) =>
    PackageConfigFileDescriptor(packages, generatorVersion);

Descriptor appPackageConfigFile(
  List<PackageConfigEntry> packages, {
  String generatorVersion = '3.1.2+3',
}) =>
    dir(
      appPath,
      [
        packageConfigFile(
          [
            packageConfigEntry(name: 'myapp', path: '.'),
            ...packages,
          ],
          generatorVersion: generatorVersion,
        ),
      ],
    );

/// Create a [PackageConfigEntry] which assumes package with [name] is either
/// a cached package with given [version] or a path dependency at given [path].
PackageConfigEntry packageConfigEntry({
  required String name,
  String? version,
  String? path,
  String? languageVersion,
  PackageServer? server,
}) {
  if (version != null && path != null) {
    throw ArgumentError.value(
      path,
      'path',
      'Only one of "version" and "path" can be provided',
    );
  }
  if (version == null && path == null) {
    throw ArgumentError.value(
      version,
      'version',
      'Either "version" or "path" must be given',
    );
  }
  Uri rootUri;
  if (version != null) {
    rootUri = p.toUri((server ?? globalServer).pathInCache(name, version));
  } else {
    rootUri = p.toUri(p.join('..', path));
  }
  return PackageConfigEntry(
    name: name,
    rootUri: rootUri,
    packageUri: Uri(path: 'lib/'),
    languageVersion:
        languageVersion != null ? LanguageVersion.parse(languageVersion) : null,
  );
}
