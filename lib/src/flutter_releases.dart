// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:pub_semver/pub_semver.dart';

import 'http.dart';
import 'log.dart';

String get flutterReleasesUrl =>
    Platform.environment['_PUB_TEST_FLUTTER_RELEASES_URL'] ??
    'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json';

// Retrieves all released versions of Flutter.
Future<List<FlutterRelease>> _flutterReleases = () async {
  final response = await retryForHttp(
    'fetching available Flutter releases',
    () => globalHttpClient.fetch(Request('GET', Uri.parse(flutterReleasesUrl))),
  );
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) throw FormatException('Bad response - should be a Map');
  final releases = decoded['releases'];
  if (releases is! List) {
    throw FormatException('Bad response - releases should be a list.');
  }
  final result = <FlutterRelease>[];
  for (final release in releases) {
    final channel = {
      'beta': Channel.beta,
      'stable': Channel.stable,
      'dev': Channel.dev
    }[release['channel']];
    if (channel == null) throw FormatException('Release with bad channel');
    final dartVersion = release['dart_sdk_version'];
    // Some releases don't have an associated dart version, ignore.
    if (dartVersion is! String) continue;
    final flutterVersion = release['version'];
    if (flutterVersion is! String) throw FormatException('Not a string');
    result.add(
      FlutterRelease(
        flutterVersion: Version.parse(flutterVersion),
        dartVersion: Version.parse(dartVersion.split(' ').first),
        channel: channel,
      ),
    );
  }
  return result
      // Sort releases by channel and version.
      .sorted((a, b) {
        final compareChannels = b.channel.index - a.channel.index;
        if (compareChannels != 0) return compareChannels;
        return a.flutterVersion.compareTo(b.flutterVersion);
      })
      // Newest first.
      .reversed
      .toList();
}();

/// The "best" Flutter release for a given set of constraints is the first one
/// in [_flutterReleases] that matches both the flutter and dart constraint.
///
/// Returns if no such release could be found.
Future<FlutterRelease?> inferBestFlutterRelease(
  Map<String, VersionConstraint> sdkConstraints,
) async {
  final List<FlutterRelease> flutterReleases;
  try {
    flutterReleases = await _flutterReleases;
  } on Exception catch (e) {
    fine('Failed retrieving the list of flutter-releases: $e');
    return null;
  }
  return flutterReleases.firstWhereOrNull(
    (release) =>
        (sdkConstraints['flutter'] ?? VersionConstraint.any)
            .allows(release.flutterVersion) &&
        (sdkConstraints['dart'] ?? VersionConstraint.any)
            .allows(release.dartVersion),
  );
}

enum Channel {
  stable,
  beta,
  dev,
}

/// A version of the Flutter SDK and its related Dart SDK.
class FlutterRelease {
  final Version flutterVersion;
  final Version dartVersion;
  final Channel channel;
  FlutterRelease({
    required this.flutterVersion,
    required this.dartVersion,
    required this.channel,
  });
  @override
  toString() =>
      'FlutterRelease(flutter=$flutterVersion, dart=$dartVersion, channel=$channel)';
}
