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

const statusFilename = 'extract_all_pub_status.json';

Future<List<String>> allPackageNames() async {
  var nextUrl = 'https://pub.dev/api/packages?compact=1';
  final result = json.decode(await httpClient.read(nextUrl));
  return List<String>.from(result['packages']);
}

Future<List<String>> versionArchiveUrls(String packageName) async {
  final url = 'https://pub.dev/api/packages/$packageName';
  final result = json.decode(await httpClient.read(url));
  return List<String>.from(result['versions'].map((v) => v['archive_url']));
}

Future<void> main() async {
  var alreadyDonePackages = <String>{};
  var failures = <Map<String, dynamic>>[];
  if (fileExists(statusFilename)) {
    final json = jsonDecode(readTextFile(statusFilename));
    for (final packageName in json['packages'] ?? []) {
      alreadyDonePackages.add(packageName);
    }
    for (final failure in json['failures'] ?? []) {
      failures.add(failure);
    }
  }
  print('Already processed ${alreadyDonePackages.length} packages');
  print('Already found ${alreadyDonePackages.length}');

  void writeStatus() {
    writeTextFile(
      statusFilename,
      JsonEncoder.withIndent('  ').convert({
        'packages': [...alreadyDonePackages],
        'failures': [...failures],
      }),
    );
    print('Wrote status to $statusFilename');
  }

  ProcessSignal.sigint.watch().listen((_) {
    writeStatus();
    exit(1);
  });

  final pool = Pool(10); // Process 10 packages at a time.

  try {
    for (final packageName in await allPackageNames()) {
      if (alreadyDonePackages.contains(packageName)) {
        print('Skipping $packageName - already done');
        continue;
      }
      print('Processing all versions of $packageName '
          '[+${alreadyDonePackages.length}, - ${failures.length}]');
      final resource = await pool.request();
      scheduleMicrotask(() async {
        try {
          final versions = await versionArchiveUrls(packageName);
          var allVersionsGood = true;
          await Future.wait(versions.map((archiveUrl) async {
            await withTempDir((tempDir) async {
              print('downloading $archiveUrl');
              http.StreamedResponse response;
              try {
                response = await httpClient
                    .send(http.Request('GET', Uri.parse(archiveUrl)));
                await extractTarGz(response.stream, tempDir);
                print('Extracted $archiveUrl');
              } catch (e, _) {
                print('Failed to get and extract $archiveUrl $e');
                failures.add({'archive': archiveUrl, 'error': e.toString()});
                allVersionsGood = false;
                return;
              }
            });
          }));
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
