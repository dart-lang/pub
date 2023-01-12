// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This is a manual test that can be run to test the .tar.gz decoding.
/// It will save progress in [statusFileName] such that it doesn't have to be
/// finished in a single run.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';
import 'package:pub/src/http.dart';
import 'package:pub/src/io.dart';
import 'package:pub/src/log.dart' as log;

const statusFilename = 'extract_all_pub_status.json';

Future<List<String>> allPackageNames() async {
  var nextUrl = Uri.https('pub.dev', 'api/packages?compact=1');
  final request = http.Request('GET', nextUrl);
  request.attachMetadataHeaders();
  final response = await globalHttpClient.fetch(request);
  final result = json.decode(response.body);
  return List<String>.from(result['packages']);
}

Future<List<String>> versionArchiveUrls(String packageName) async {
  final url = Uri.https('pub.dev', 'api/packages/$packageName');
  final request = http.Request('GET', url);
  request.attachMetadataHeaders();
  final response = await globalHttpClient.fetch(request);
  final result = json.decode(response.body);
  return List<String>.from(result['versions'].map((v) => v['archive_url']));
}

Future<void> main() async {
  var alreadyDonePackages = <String>{};
  var failures = <Map<String, dynamic>?>[];
  if (fileExists(statusFilename)) {
    final json = jsonDecode(readTextFile(statusFilename));
    for (final packageName in json['packages'] ?? []) {
      alreadyDonePackages.add(packageName);
    }
    for (final failure in json['failures'] ?? []) {
      failures.add(failure);
    }
  }
  log.message('Already processed ${alreadyDonePackages.length} packages');
  log.message('Already found ${alreadyDonePackages.length}');

  void writeStatus() {
    writeTextFile(
      statusFilename,
      JsonEncoder.withIndent('  ').convert({
        'packages': [...alreadyDonePackages],
        'failures': [...failures],
      }),
    );
    log.message('Wrote status to $statusFilename');
  }

  ProcessSignal.sigint.watch().listen((_) {
    writeStatus();
    exit(1);
  });

  final pool = Pool(10); // Process 10 packages at a time.

  try {
    for (final packageName in await allPackageNames()) {
      if (alreadyDonePackages.contains(packageName)) {
        log.message('Skipping $packageName - already done');
        continue;
      }
      log.message('Processing all versions of $packageName '
          '[+${alreadyDonePackages.length}, - ${failures.length}]');
      final resource = await pool.request();
      scheduleMicrotask(() async {
        try {
          final versions = await versionArchiveUrls(packageName);
          var allVersionsGood = true;
          await Future.wait(
            versions.map((archiveUrl) async {
              await withTempDir((tempDir) async {
                log.message('downloading $archiveUrl');
                http.StreamedResponse response;
                try {
                  final archiveUri = Uri.parse(archiveUrl);
                  final request = http.Request('GET', archiveUri);
                  request.attachMetadataHeaders();
                  response = await globalHttpClient.fetchAsStream(request);
                  await extractTarGz(response.stream, tempDir);
                  log.message('Extracted $archiveUrl');
                } catch (e) {
                  log.message('Failed to get and extract $archiveUrl $e');
                  failures.add({'archive': archiveUrl, 'error': e.toString()});
                  allVersionsGood = false;
                  return;
                }
              });
            }),
          );
          if (allVersionsGood) alreadyDonePackages.add(packageName);
        } finally {
          resource.release();
        }
      });
    }
  } finally {
    writeStatus();
    exit(failures.isEmpty ? 0 : 1);
  }
}
