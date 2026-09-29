// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

/// An experiment as described by an SDK's experiments file.
///
/// For the Dart SDK that file is `lib/_internal/sdk_experiments.json`, which
/// is generated from `tools/experimental_features.yaml` in the SDK repository.
final class Experiment {
  /// The name used to enable the experiment, for example `this-promotion`.
  final String name;

  /// A short human readable description of the experiment.
  final String description;

  /// Where to read more about the experiment, if known.
  final String? docUrl;

  /// The SDK version in which the experiment was enabled by default.
  ///
  /// `null` if the experiment is not (yet) enabled by default.
  final Version? enabledIn;

  /// Whether the experiment flag has been retired.
  ///
  /// An expired experiment is either shipped ([enabledIn] is not `null`) or
  /// abandoned.
  final bool expired;

  /// The SDK release channels on which the experiment can be enabled.
  ///
  /// `null` means that the experiment can be enabled on all channels.
  final List<String>? channels;

  /// The first language version for which enabling the experiment has an
  /// effect.
  ///
  /// Libraries with an older language version are not affected by enabling
  /// the experiment.
  final Version? experimentalReleaseVersion;

  Experiment(
    this.name,
    this.description, {
    this.docUrl,
    this.enabledIn,
    this.expired = false,
    List<String>? channels,
    this.experimentalReleaseVersion,
  }) : channels = channels == null ? null : List.unmodifiable(channels);

  /// Parses one entry of the `experiments` list of an SDK experiments file.
  ///
  /// Throws a [FormatException] if [json] is malformed.
  factory Experiment.fromJson(Object? json) {
    if (json case {
      'name': final String name,
      'description': final String description,
    }) {
      Version? parseVersion(String key) => switch (json[key]) {
        null => null,
        final String version => Version.parse(version),
        _ =>
          throw FormatException('"$key" of experiment $name must be a string'),
      };
      final channels = switch (json['channels']) {
        null => null,
        final List<Object?> channels => [
          for (final channel in channels)
            channel is String
                ? channel
                : throw FormatException(
                  '"channels" of experiment $name must be a list of strings',
                ),
        ],
        _ =>
          throw FormatException(
            '"channels" of experiment $name must be a list of strings',
          ),
      };
      return Experiment(
        name,
        description,
        docUrl: switch (json['docUrl']) {
          null => null,
          final String url => url,
          _ =>
            throw FormatException(
              '"docUrl" of experiment $name must be a string',
            ),
        },
        enabledIn: parseVersion('enabledIn'),
        expired: json['expired'] == true,
        channels: channels,
        experimentalReleaseVersion: parseVersion('experimentalReleaseVersion'),
      );
    }
    throw const FormatException(
      'Each experiment must have a "name" and a "description"',
    );
  }

  /// Whether the experiment is enabled without being listed in `experiments`.
  bool get isEnabledByDefault => enabledIn != null;

  /// Whether listing the experiment in `experiments` has any effect.
  ///
  /// Experiments that are enabled by default or expired are not passed on to
  /// the tools, and any package may list them.
  bool get requiresOptIn => !isEnabledByDefault && !expired;

  /// Whether the experiment can be enabled on the SDK release [channel].
  ///
  /// If [channel] is `null` (unknown) the experiment is assumed available.
  bool isAvailableOnChannel(String? channel) =>
      channel == null || channels == null || channels!.contains(channel);

  /// A one-line description suitable for listing the experiment in messages.
  String get summary =>
      '`$name`: $description${docUrl == null ? '' : ' ($docUrl)'}';
}
