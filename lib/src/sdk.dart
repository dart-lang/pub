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
export 'utils.dart' show AsCompatibleWithIfPossible;

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

  /// The path of the file describing the experiments this SDK supports.
  String get experimentsPath;

  /// The experiments known to this SDK, keyed by name.
  ///
  /// Empty if the SDK isn't available or has no experiments file.
  late final Map<String, Experiment> experiments = _loadExperiments();

  Map<String, Experiment> _loadExperiments() {
    // SDKs predating experiments in pubspecs have no experiments file.
    if (!isAvailable || !fileExists(experimentsPath)) return {};
    final Object? json;
    try {
      json = jsonDecode(readTextFile(experimentsPath));
    } on IOException catch (e) {
      fine('Could not load $experimentsPath $e');
      return {};
    } on FormatException catch (e) {
      fail('Failed to parse $experimentsPath. $e');
    }
    if (json is! Map<String, Object?>) {
      fail('Malformed experiments file $experimentsPath');
    }
    // Files written before the format was versioned have no `version`.
    final version = json['version'] ?? 1;
    if (version != _experimentsFileVersion) {
      fail(
        'The experiments file $experimentsPath has version $version. '
        'This version of pub only understands version '
        '$_experimentsFileVersion.',
      );
    }
    final result = <String, Experiment>{};
    if (json case {'experiments': final List<Object?> experiments}) {
      for (final entry in experiments) {
        try {
          final experiment = Experiment.fromJson(entry);
          result[experiment.name] = experiment;
        } on FormatException catch (e) {
          fail('Malformed experiments file $experimentsPath: ${e.message}');
        }
      }
    } else {
      fail('Malformed experiments file $experimentsPath');
    }
    return result;
  }

  /// The version of the experiments file format that pub understands.
  static const _experimentsFileVersion = 1;

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

/// The experiments known to the available SDKs, keyed by name.
final Map<String, Experiment> availableExperiments = {
  for (final sdk in sdks.values.where((sdk) => sdk.isAvailable))
    ...sdk.experiments,
};

/// The experiment entries that don't require workspace opt-in, because they
/// are enabled by default, expired, or opt-outs (`no-<name>`).
///
/// Listing such an entry in a dependency's `experiments` does not opt in to an
/// unshipped feature, so the solver always allows them.
Set<String> get experimentsNotRequiringOptIn => {
  for (final experiment in availableExperiments.values) ...[
    if (!experiment.requiresOptIn) experiment.name,
    'no-${experiment.name}',
  ],
};

/// Whether [flag] (an `<experiment>` or `no-<experiment>` entry from
/// `experiments`) has an effect and should be passed on to tools.
bool isEffectiveExperimentFlag(
  String flag, {
  Map<String, Experiment>? experiments,
}) {
  final knownExperiments = experiments ?? availableExperiments;
  if (flag.startsWith('no-')) {
    final experiment = knownExperiments[flag.substring(3)];
    return experiment == null || experiment.canBeDisabled;
  }
  final experiment = knownExperiments[flag];
  return experiment == null || experiment.requiresOptIn;
}

/// The core Dart SDK.
final sdk = DartSdk();
