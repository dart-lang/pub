// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

/// A proxy for [Platform] from `dart:io` which can be overridden.
PlatformInfo get platform =>
    Zone.current[_platformInfoKey] as PlatformInfo? ??
    PlatformInfo.nativePlatform();

/// The key for the [platform] in the current [Zone].
final _platformInfoKey = Object();

/// Runs [callback] in a [Zone] where `platform` is overridden by [platform].
Future<T> withPlatform<T>(
  FutureOr<T> Function() callback, {
  required PlatformInfo platform,
}) {
  return runZoned(() async {
    return await callback();
  }, zoneValues: {_platformInfoKey: platform});
}

abstract final class PlatformInfo {
  const PlatformInfo._();

  factory PlatformInfo.nativePlatform() = _NativePlatformInfo;

  factory PlatformInfo.override({
    required Map<String, String> environment,
    required String executable,
    required bool isAndroid,
    required bool isFuchsia,
    required bool isIOS,
    required bool isLinux,
    required bool isMacOS,
    required bool isWindows,
    required String lineTerminator,
    required String operatingSystem,
    required String pathSeparator,
    required String resolvedExecutable,
    required String version,
    required int numberOfProcessors,
    required Uri script,
  }) = _PlatformInfoOverride;

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
