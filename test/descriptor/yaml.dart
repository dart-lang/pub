// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async' show Future;
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart';
import 'package:yaml/yaml.dart';

import '../descriptor.dart';

class YamlDescriptor extends FileDescriptor {
  final String _contents;

  YamlDescriptor(super.name, this._contents) : super.protected();

  @override
  Future<String> read() async => _contents;

  @override
  Stream<List<int>> readAsBytes() =>
      Stream.fromIterable([utf8.encode(_contents)]);

  @override
  Future validate([String? parent]) async {
    final fullPath = p.join(parent ?? sandbox, name);
    if (!await File(fullPath).exists()) {
      fail("File not found: '$fullPath'.");
    }

    final bytes = await File(fullPath).readAsBytes();

    final actualContentsText = utf8.decode(bytes);
    final actual = loadYaml(actualContentsText);
    final expected = loadYaml(_contents);

    if (!const DeepCollectionEquality().equals(expected, actual)) {
      fail('Expected $expected, found: $actual');
    }
  }
}
