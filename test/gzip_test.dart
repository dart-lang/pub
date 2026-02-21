// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub/src/gzip/gzip.dart';
import 'package:test/test.dart';

void main() {
  test('gzipDecoder can decode a gzipped string', () async {
    // "Hello, world!" gzipped
    final List<int> gzipped = base64.decode(
      'H4sIAAAAAAAAA/NIzcnJ11Eozy/KSVEEAObG5usNAAAA',
    );
    final decoded = await Stream.value(gzipped).transform(gzipDecoder).toList();
    expect(utf8.decode(decoded.expand((e) => e).toList()), 'Hello, world!');
  });
}
