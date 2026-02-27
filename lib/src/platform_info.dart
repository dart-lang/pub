// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

/// A proxy for [Platform] from `dart:io` which can be overridden.
PlatformInfo get platform =>
    Zone.current[_platformInfoKey] as PlatformInfo? ??
    PlatformInfo.defaultPlatform();

/// The key for the [platform] in the current [Zone].
final _platformInfoKey = Object();

/// Runs [callback] in a [Zone] where `platform` is overridden by [platform].
R withPlatform<R>(R Function() callback, {required PlatformInfo platform}) =>
    runZoned(callback, zoneValues: {_platformInfoKey: platform});

abstract final class PlatformInfo {
  const PlatformInfo._();

  factory PlatformInfo.defaultPlatform() =>
      const bool.fromEnvironment('dart.library.io')
          ? const _NativePlatformInfo()
          : const _BrowserPlatformInfo();

  factory PlatformInfo.override({
    Map<String, String>? environment,
    String? executable,
    bool? isAndroid,
    bool? isFuchsia,
    bool? isIOS,
    bool? isLinux,
    bool? isMacOS,
    bool? isWindows,
    String? lineTerminator,
    String? operatingSystem,
    String? pathSeparator,
    String? resolvedExecutable,
    String? version,
    int? numberOfProcessors,
    Uri? script,
  }) => _PlatformInfoOverride(
    environment: environment ?? platform.environment,
    executable: executable ?? platform.executable,
    isAndroid: isAndroid ?? platform.isAndroid,
    isFuchsia: isFuchsia ?? platform.isFuchsia,
    isIOS: isIOS ?? platform.isIOS,
    isLinux: isLinux ?? platform.isLinux,
    isMacOS: isMacOS ?? platform.isMacOS,
    isWindows: isWindows ?? platform.isWindows,
    lineTerminator: lineTerminator ?? platform.lineTerminator,
    operatingSystem: operatingSystem ?? platform.operatingSystem,
    pathSeparator: pathSeparator ?? platform.pathSeparator,
    resolvedExecutable: resolvedExecutable ?? platform.resolvedExecutable,
    version: version ?? platform.version,
    numberOfProcessors: numberOfProcessors ?? platform.numberOfProcessors,
    script: script ?? platform.script,
  );

  /// Returns [Platform.environment].
  Map<String, String> get environment;

  /// Returns [Platform.executable].
  String get executable;

  /// Returns [Platform.isAndroid].
  bool get isAndroid;

  /// Returns [Platform.isFuchsia].
  bool get isFuchsia;

  /// Returns [Platform.isIOS].
  bool get isIOS;

  /// Returns [Platform.isLinux].
  bool get isLinux;

  /// Returns [Platform.isMacOS].
  bool get isMacOS;

  /// Returns [Platform.isWindows].
  bool get isWindows;

  /// Returns [Platform.lineTerminator].
  String get lineTerminator;

  /// Returns [Platform.operatingSystem].
  String get operatingSystem;

  /// Returns [Platform.pathSeparator].
  String get pathSeparator;

  /// Returns [Platform.resolvedExecutable].
  String get resolvedExecutable;

  /// Returns [Platform.numberOfProcessors].
  int get numberOfProcessors;

  /// Returns [Platform.script].
  Uri get script;

  /// Returns [Platform.version] from 'dart:io'.
  String get version;
}

final class _NativePlatformInfo extends PlatformInfo {
  const _NativePlatformInfo() : super._();

  @override
  Map<String, String> get environment => Platform.environment;

  @override
  String get executable => Platform.executable;

  @override
  bool get isAndroid => Platform.isAndroid;

  @override
  bool get isFuchsia => Platform.isFuchsia;

  @override
  bool get isIOS => Platform.isIOS;

  @override
  bool get isLinux => Platform.isLinux;

  @override
  bool get isMacOS => Platform.isMacOS;

  @override
  bool get isWindows => Platform.isWindows;

  @override
  String get lineTerminator => Platform.lineTerminator;

  @override
  String get operatingSystem => Platform.operatingSystem;

  @override
  String get pathSeparator => Platform.pathSeparator;

  @override
  String get resolvedExecutable => Platform.resolvedExecutable;

  @override
  String get version => Platform.version;

  @override
  int get numberOfProcessors => Platform.numberOfProcessors;

  @override
  Uri get script => Platform.script;
}

final class _BrowserPlatformInfo extends PlatformInfo {
  const _BrowserPlatformInfo() : super._();

  @override
  Map<String, String> get environment => const {};

  @override
  String get executable => '';

  @override
  bool get isAndroid => false;

  @override
  bool get isFuchsia => false;

  @override
  bool get isIOS => false;

  @override
  bool get isLinux => false;

  @override
  bool get isMacOS => false;

  @override
  bool get isWindows => false;

  @override
  String get lineTerminator => '\n';

  @override
  String get operatingSystem => '';

  @override
  String get pathSeparator => '/';

  @override
  String get resolvedExecutable => '';

  @override
  String get version => '';

  @override
  int get numberOfProcessors => 1;

  @override
  Uri get script => Uri();
}

final class _PlatformInfoOverride extends PlatformInfo {
  const _PlatformInfoOverride({
    required this.environment,
    required this.executable,
    required this.isAndroid,
    required this.isFuchsia,
    required this.isIOS,
    required this.isLinux,
    required this.isMacOS,
    required this.isWindows,
    required this.lineTerminator,
    required this.operatingSystem,
    required this.pathSeparator,
    required this.resolvedExecutable,
    required this.version,
    required this.numberOfProcessors,
    required this.script,
  }) : super._();

  @override
  final Map<String, String> environment;

  @override
  final String executable;

  @override
  final bool isAndroid;

  @override
  final bool isFuchsia;

  @override
  final bool isIOS;

  @override
  final bool isLinux;

  @override
  final bool isMacOS;

  @override
  final bool isWindows;

  @override
  final String lineTerminator;

  @override
  final String operatingSystem;

  @override
  final String pathSeparator;

  @override
  final String resolvedExecutable;

  @override
  final String version;

  @override
  final int numberOfProcessors;

  @override
  final Uri script;
}
