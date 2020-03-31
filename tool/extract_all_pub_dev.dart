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

Stream<String> allPackageNames() async* {
  var nextUrl = 'https://pub.dev/api/packages';
  do {
    final result = json.decode(await httpClient.read(nextUrl));
    for (final package in result['packages']) {
      yield package['name'];
    }
    nextUrl = result['next_url'];
  } while (nextUrl != null);
}

Future<List<String>> versionArchiveUrls(String packageName) async {
  final url = 'https://pub.dev/api/packages/$packageName';
  final result = json.decode(await httpClient.read(url));
  return List<String>.from(result['versions'].map((v) => v['archive_url']));
}

Future<void> main() async {
  var alreadyDonePackages = <String>{};
  var failures = <String>[];
  if (fileExists(statusFilename)) {
    final json = jsonDecode(readTextFile(statusFilename));
    for (final packageName in json['packages'] ?? []) {
      alreadyDonePackages.add(packageName);
    }
    for (final packageName in json['failures'] ?? []) {
      failures.add(packageName);
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
  }

  ProcessSignal.sigint.watch().listen((_) {
    writeStatus();
    exit(1);
  });

  final pool = Pool(10); // Process 10 packages at a time.

  try {
    await for (final packageName in allPackageNames()) {
      if (alreadyDonePackages.contains(packageName)) {
        print('Skipping $packageName - already done');
        continue;
      } else {
        print('Processing all versions of $packageName '
            '[+${alreadyDonePackages.length}, - ${failures.length}]');
      }
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
                print('Failed to get and extract $archiveUrl');
                failures.add(archiveUrl);
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
  }
}
