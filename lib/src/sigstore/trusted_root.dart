// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import '../exceptions.dart';
import '../io.dart';
import '../platform_info.dart';
import '../system_cache.dart';

/// Loads the Sigstore `trusted_root.json` root of trust.
///
/// Looks in the following order:
/// 1. An explicit override path passed in [overridePath].
/// 2. The `PUB_SIGSTORE_TRUST_ROOT` environment variable.
/// 3. The cached trusted root in the pub cache (`$PUB_CACHE/sigstore/trusted_root.json`).
///
/// Returns `null` if no custom or cached root is found, in which case
/// `package:sigstore` falls back to its built-in production trusted root.
String? loadTrustedRootJson({SystemCache? cache, String? overridePath}) {
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

  final cachePath = cache?.sigstoreTrustedRootPath;
  if (cachePath != null && fileExists(cachePath)) {
    return readTextFile(cachePath);
  }

  return null;
}

/// Parses and returns the decoded JSON map of the Sigstore trusted root,
/// or `null` if no custom or cached root is found.
Map<String, dynamic>? loadTrustedRoot({
  SystemCache? cache,
  String? overridePath,
}) {
  final text = loadTrustedRootJson(cache: cache, overridePath: overridePath);
  if (text == null) return null;
  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw DataException('Failed to parse Sigstore trusted_root.json: $e');
  }
}
