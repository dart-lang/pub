// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:pub_semver/pub_semver.dart';

import 'sdk/dart.dart';
import 'sdk/flutter.dart';
import 'sdk/fuchsia.dart';

/// An SDK that can provide packages and on which pubspecs can express version
/// constraints.
abstract class Sdk {
  /// This SDK's human-readable name.
  String get name;

  /// The identifier used in pubspecs to refer to this SDK.
  ///
  /// This should match the key used in [sdks].
  String get identifier => name.toLowerCase();

  /// Whether the user has this SDK installed and configured so that it's
  /// accessible to pub.
  bool get isAvailable;

  /// The SDK's version number, or `null` if the SDK is unavailable.
  Version get version;

  /// The version of pub that added support for this SDK.
  Version get firstPubVersion;

  /// A message to indicate to the user how to make this SDK available.
  ///
  /// This is printed after a version solve where the SDK wasn't found. It may
  /// be `null`, indicating that no such message should be printed.
  String get installMessage;

  /// Returns the path to the package [name] within this SDK.
  ///
  /// Returns `null` if the SDK isn't available or if it doesn't contain a
  /// package with the given name.
  String packagePath(String name);

  @override
  String toString() => name;
}

/// A map from SDK identifiers that appear in pubspecs to the implementations of
/// those SDKs.
final sdks = UnmodifiableMapView<String, Sdk>(
    {'dart': sdk, 'flutter': FlutterSdk(), 'fuchsia': FuchsiaSdk()});

/// The core Dart SDK.
final sdk = DartSdk();
