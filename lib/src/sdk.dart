// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'experiment.dart';
import 'io.dart';
import 'log.dart';
import 'sdk/dart.dart';
import 'sdk/flutter.dart';
import 'sdk/fuchsia.dart';
import 'utils.dart';

/// An SDK that can provide packages and on which pubspecs can express version
/// constraints.
abstract class Sdk {
  /// Is this the Dart sdk?
  bool get isDartSdk => identifier == 'dart';

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
  Version? get version;

  /// A message to indicate to the user how to make this SDK available.
  ///
  /// This is printed after a version solve where the SDK wasn't found. It may
  /// be `null`, indicating that no such message should be printed.
  String? get installMessage;

  /// Whether or not non-SDK dependencies are allowed in the regular
  /// dependencies section for packages vendored by this SDK.
  bool get allowsNonSdkDepsInSdkPackages;

  /// Returns the path to the package [name] within this SDK.
  ///
  /// Returns `null` if the SDK isn't available or if it doesn't contain a
  /// package with the given name.
  String? packagePath(String name);

  String get experimentsPath;

  late final Map<String, Experiment> experiments = _loadExperiments();

  Map<String, Experiment> _loadExperiments() {
    if (!isAvailable) return {};
    final Object? json;
    try {
      json = jsonDecode(readTextFile(experimentsPath));
    } on IOException catch (e) {
      fine('Could not load $experimentsPath $e');
      // Most likely the file doesn't exist, return empty map.
      return {};
    } on FormatException catch (e) {
      fail('Failed to parse $experimentsPath. $e');
    }
    final result = <String, Experiment>{};
    if (json case {'experiments': final List<Object?> experiments}) {
      for (final experiment in experiments) {
        if (experiment case {
          'name': final String name,
          'description': final String description,
          'docUrl': final String url,
        }) {
          result[name] = Experiment(name, description, url);
        } else {
          fail('Malformed experiments file $experimentsPath');
        }
      }
    } else {
      fail('Malformed experiments file $experimentsPath');
    }
    return result;
  }

  @override
  String toString() => name;
}

/// A map from SDK identifiers that appear in pubspecs to the implementations of
/// those SDKs.
final sdks = UnmodifiableMapView<String, Sdk>({
  'dart': sdk,
  'flutter': FlutterSdk(),
  'fuchsia': FuchsiaSdk(),
});

/// The experiments available
final Map<String, Experiment> availableExperiments = {
  for (final sdk in sdks.values.where((sdk) => sdk.isAvailable))
    ...sdk.experiments,
};

/// The core Dart SDK.
final sdk = DartSdk();

extension AsCompatibleWithIfPossible on VersionConstraint {
  // Returns `this` expressed as [VersionConstraint.compatibleWith] if possible.
  VersionConstraint asCompatibleWithIfPossible() {
    final range = this;
    if (range is! VersionRange) return this;
    final min = range.min;
    if (min == null) return this;
    final asCompatibleWith = VersionConstraint.compatibleWith(min);
    if (asCompatibleWith == this) return asCompatibleWith;
    return this;
  }
}
