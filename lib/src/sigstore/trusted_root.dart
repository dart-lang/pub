// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import '../exceptions.dart';
import '../io.dart';
import '../path.dart';
import '../platform_info.dart';
import '../sdk/dart.dart';

/// Loads the Sigstore `trusted_root.json` root of trust.
///
/// Looks in the following order:
/// 1. An explicit override path passed in [overridePath].
/// 2. The `PUB_SIGSTORE_TRUST_ROOT` environment variable.
/// 3. The built SDK directory at `lib/_internal/sigstore/trusted_root.json`.
/// 4. The Dart repository checkout at `third_party/sigstore/trusted_root.json`.
String loadTrustedRootJson({String? overridePath}) {
  if (overridePath != null) {
    if (!fileExists(overridePath)) {
      throw DataException(
        'Could not find Sigstore trusted root file at "$overridePath".',
      );
    }
    return readTextFile(overridePath);
  }

  if (platform.environment['PUB_SIGSTORE_TRUST_ROOT'] case final envPath?) {
    if (!fileExists(envPath)) {
      throw DataException(
        'Could not find Sigstore trusted root file at "$envPath" '
        'specified by PUB_SIGSTORE_TRUST_ROOT.',
      );
    }
    return readTextFile(envPath);
  }

  // 1. Check in the built SDK layout:
  final sdkPath = p.join(
    DartSdk().rootDirectory,
    'lib',
    '_internal',
    'sigstore',
    'trusted_root.json',
  );
  if (fileExists(sdkPath)) {
    return readTextFile(sdkPath);
  }

  // 2. Check in the repository checkout layout (when running in repo/tests):
  final repoPath = p.join(
    p.dirname(DartSdk().rootDirectory),
    'third_party',
    'sigstore',
    'trusted_root.json',
  );
  if (fileExists(repoPath)) {
    return readTextFile(repoPath);
  }

  throw ApplicationException(
    'Could not locate Sigstore trusted_root.json in the Dart SDK.',
  );
}

/// Parses and returns the decoded JSON map of the Sigstore trusted root.
Map<String, dynamic> loadTrustedRoot({String? overridePath}) {
  final text = loadTrustedRootJson(overridePath: overridePath);
  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw DataException('Failed to parse Sigstore trusted_root.json: $e');
  }
}
