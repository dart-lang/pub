// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

const sigstoreTufCdn =
    'https://raw.githubusercontent.com/sigstore/root-signing/main/targets/trusted_root.json';

/// Fetches the latest trusted root JSON from Sigstore's TUF CDN repository.
Future<String> fetchLatestTrustedRootJson({
  String cdnUrl = sigstoreTufCdn,
  HttpClient? customHttpClient,
}) async {
  final uri = Uri.parse(cdnUrl);
  final client = customHttpClient ?? HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return await utf8.decoder.bind(response).join();
    }
    throw HttpException(
      'Failed to fetch Sigstore trusted root from $uri '
      '(status: ${response.statusCode})',
      uri: uri,
    );
  } finally {
    if (customHttpClient == null) {
      client.close();
    }
  }
}

/// Updates the cached trusted_root.json at [cachePath] with the latest from
/// [cdnUrl].
Future<void> updateTrustedRootCache({
  required String cachePath,
  String cdnUrl = sigstoreTufCdn,
  HttpClient? customHttpClient,
}) async {
  final content = await fetchLatestTrustedRootJson(
    cdnUrl: cdnUrl,
    customHttpClient: customHttpClient,
  );
  jsonDecode(content);
  final file = File(cachePath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
