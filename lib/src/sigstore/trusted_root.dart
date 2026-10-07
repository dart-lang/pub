// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sigstore/sigstore.dart';

import '../exceptions.dart';
import '../io.dart';
import '../log.dart' as log;
import '../platform_info.dart';
import '../system_cache.dart';

const sigstoreTufMirror = 'https://tuf-repo-cdn.sigstore.dev';

/// Callback signature for refreshing the Sigstore TUF repository and returning
/// the verified `trusted_root.json` content.
typedef TrustedRootRefresher =
    String Function(String mirrorUrl, String cacheDir);

/// Override refresher used in unit tests to simulate TUF refreshes without
/// hitting the production CDN.
@visibleForTesting
TrustedRootRefresher? debugTrustedRootRefresher;

final _versionedRootFileRegExp = RegExp(r'^(\d+)\.root\.json$');

/// Returns the highest TUF root metadata version cached in [cacheDir], or
/// `null` if no TUF root metadata is present on disk.
///
/// Inspects both `root.json` and versioned `<N>.root.json` files in [cacheDir].
int? readMaxTufRootVersion(String cacheDir) {
  final dir = Directory(cacheDir);
  if (!dir.existsSync()) return null;

  int? maxVersion;
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    int? fileVersion;
    final match = _versionedRootFileRegExp.firstMatch(name);
    if (match != null) {
      fileVersion = int.tryParse(match.group(1)!);
    } else if (name != 'root.json') {
      continue;
    }

    try {
      final decoded = jsonDecode(entity.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        final signed = decoded['signed'];
        if (signed is Map<String, dynamic>) {
          final v = signed['version'];
          if (v is int && v > 0) {
            if (fileVersion == null || v > fileVersion) {
              fileVersion = v;
            }
          }
        }
      }
    } catch (_) {
      // Ignore unreadable or non-JSON files when scanning version numbers;
      // filename version (if any) is still considered below.
    }

    if (fileVersion != null &&
        (maxVersion == null || fileVersion > maxVersion)) {
      maxVersion = fileVersion;
    }
  }
  return maxVersion;
}

/// Returns `true` if the Sigstore TUF cache in [cacheDir] (or the cached
/// `trusted_root.json` at [cachePath]) is missing or expired as of [now].
bool isTrustedRootCacheExpired({
  required String cacheDir,
  String? cachePath,
  DateTime? now,
}) {
  if (cachePath != null && !fileExists(cachePath)) {
    return true;
  }
  final dir = Directory(cacheDir);
  if (!dir.existsSync()) {
    return true;
  }

  final currentTime = (now ?? DateTime.now()).toUtc();
  final maxRootVersion = readMaxTufRootVersion(cacheDir);
  if (maxRootVersion == null) {
    return true;
  }

  // Check TUF metadata expiration timestamps (`signed.expires`).
  // Require at least one fresh top-level metadata file (`timestamp.json`,
  // `targets.json`, `root.json`, or `<maxRootVersion>.root.json`) and fail
  // (report expired) if any present role metadata has expired.
  final roleFiles = <String>[
    'timestamp.json',
    'snapshot.json',
    'targets.json',
    'root.json',
    '$maxRootVersion.root.json',
  ];

  var foundValidExpiry = false;
  for (final roleFile in roleFiles) {
    final file = File(p.join(cacheDir, roleFile));
    if (!file.existsSync()) continue;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return true;
      final signed = decoded['signed'];
      if (signed is! Map<String, dynamic>) return true;
      final expiresRaw = signed['expires'];
      if (expiresRaw is! String) return true;
      final expires = DateTime.tryParse(expiresRaw)?.toUtc();
      if (expires == null) return true;
      if (!expires.isAfter(currentTime)) {
        return true;
      }
      foundValidExpiry = true;
    } catch (_) {
      return true;
    }
  }

  return !foundValidExpiry;
}

/// Loads the Sigstore `trusted_root.json` root of trust.
///
/// Looks in the following order:
/// 1. An explicit override path passed in [overridePath].
/// 2. The `PUB_SIGSTORE_TRUST_ROOT` environment variable.
/// 3. The cached trusted root in the pub cache (`$PUB_CACHE/sigstore/trusted_root.json`).
///
/// If TUF root metadata is already cached in `$PUB_CACHE/sigstore/tuf/`, this
/// function will never silently fall back to `null` (which would downgrade to
/// the older SDK/package-bundled trusted root).
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

  final tufDir = cache?.sigstoreTufCacheDir;
  if (tufDir != null) {
    final cachedRootVersion = readMaxTufRootVersion(tufDir);
    if (cachedRootVersion != null) {
      final tufTargetCandidates = [
        p.join(tufDir, 'targets', 'trusted_root.json'),
        p.join(tufDir, 'trusted_root.json'),
      ];
      for (final candidate in tufTargetCandidates) {
        if (fileExists(candidate)) {
          return readTextFile(candidate);
        }
      }
      throw DataException(
        'Sigstore TUF metadata (root v$cachedRootVersion) is present in '
        '"$tufDir", but "$cachePath" is missing. Refusing to fall back to the '
        'bundled trusted root to prevent a root rollback.',
      );
    }
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

/// Refreshes the Sigstore TUF trusted root using full TUF verification
/// (threshold signatures, anti-rollback, timestamp, snapshot, targets)
/// and writes verified metadata to [cacheDir].
///
/// Enforces that the TUF root version in [cacheDir] never downgrades below the
/// highest root version already cached on disk.
///
/// Also caches the verified `trusted_root.json` at [cachePath] if provided.
Future<String> refreshTrustedRoot({
  required String cacheDir,
  String? cachePath,
  String mirrorUrl = sigstoreTufMirror,
  TrustedRootRefresher? refresher,
}) async {
  final dir = Directory(cacheDir);
  final previousRootVersion = readMaxTufRootVersion(cacheDir);

  // Snapshot existing TUF metadata files so we can restore them if a downgrade
  // or invalid refresh is detected.
  final backupFiles = <String, List<int>>{};
  if (dir.existsSync()) {
    for (final entity in dir.listSync()) {
      if (entity is File) {
        backupFiles[p.basename(entity.path)] = entity.readAsBytesSync();
      }
    }
  } else {
    dir.createSync(recursive: true);
  }

  final effectiveRefresher =
      refresher ??
      debugTrustedRootRefresher ??
      ((url, targetDir) =>
          SigstoreClient.create().refreshTrustedRoot(url, targetDir));

  final trustedRootJson = effectiveRefresher(mirrorUrl, cacheDir);

  final newRootVersion = readMaxTufRootVersion(cacheDir);
  if (previousRootVersion != null &&
      newRootVersion != null &&
      newRootVersion < previousRootVersion) {
    _restoreTufBackup(dir, backupFiles);
    throw DataException(
      'Refusing to downgrade Sigstore TUF root version from '
      '$previousRootVersion to $newRootVersion.',
    );
  }
  if (previousRootVersion != null && newRootVersion == null) {
    _restoreTufBackup(dir, backupFiles);
    throw DataException(
      'Refusing to discard cached Sigstore TUF root version '
      '$previousRootVersion during refresh.',
    );
  }

  try {
    final decoded = jsonDecode(trustedRootJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Root is not a JSON object.');
    }
  } on FormatException catch (e) {
    _restoreTufBackup(dir, backupFiles);
    throw DataException(
      'Refreshed Sigstore trusted_root.json is invalid JSON: $e',
    );
  }

  if (cachePath != null) {
    final file = File(cachePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(trustedRootJson);
  }
  return trustedRootJson;
}

void _restoreTufBackup(Directory dir, Map<String, List<int>> backupFiles) {
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  for (final entity in dir.listSync()) {
    if (entity is File) {
      entity.deleteSync();
    }
  }
  for (final entry in backupFiles.entries) {
    File(p.join(dir.path, entry.key)).writeAsBytesSync(entry.value);
  }
}

/// Refreshes the Sigstore trusted root in [cache] if [force] is `true` or if
/// `$PUB_CACHE/sigstore/tuf/` / `$PUB_CACHE/sigstore/trusted_root.json` is
/// missing or expired.
Future<void> refreshTrustedRootIfNeeded({
  required SystemCache cache,
  bool force = false,
  String? mirrorUrl,
  TrustedRootRefresher? refresher,
}) async {
  if (cache.isOffline) return;
  final envMirror = platform.environment['PUB_SIGSTORE_TUF_MIRROR'];
  final effectiveMirrorUrl = mirrorUrl ?? envMirror;
  if (runningFromTest &&
      effectiveMirrorUrl == null &&
      refresher == null &&
      debugTrustedRootRefresher == null) {
    return;
  }

  final cacheDir = cache.sigstoreTufCacheDir;
  final cachePath = cache.sigstoreTrustedRootPath;
  if (!force &&
      !isTrustedRootCacheExpired(cacheDir: cacheDir, cachePath: cachePath)) {
    return;
  }

  try {
    await refreshTrustedRoot(
      cacheDir: cacheDir,
      cachePath: cachePath,
      mirrorUrl: effectiveMirrorUrl ?? sigstoreTufMirror,
      refresher: refresher,
    );
    log.fine('Refreshed Sigstore trusted root from TUF repository.');
  } on DataException {
    rethrow;
  } catch (e) {
    log.fine('Could not refresh Sigstore trusted root from TUF mirror: $e');
  }
}
