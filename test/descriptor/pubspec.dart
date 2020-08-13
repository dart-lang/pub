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
import 'package:yaml_edit/yaml_edit.dart';

import '../descriptor.dart';

class PubspecDescriptor extends FileDescriptor {
  final String _contents;

  PubspecDescriptor(String name, this._contents) : super.protected(name);

  @override
  Future<String> read() async => _contents;

  @override
  Stream<List<int>> readAsBytes() =>
      Stream.fromIterable([utf8.encode(_contents)]);

  @override
  Future validate([String parent]) async {
    var fullPath = p.join(parent ?? sandbox, name);
    if (!await File(fullPath).exists()) {
      fail("File not found: '$fullPath'.");
    }

    var bytes = await File(fullPath).readAsBytes();

    final actualContentsText = utf8.decode(bytes);
    final actualYaml = YamlEditor(actualContentsText);
    final expectedYaml = YamlEditor(_contents);

    final actual = actualYaml.parseAt([]);
    final expected = expectedYaml.parseAt([]);

    if (!MapEquality().equals(expected.value, actual.value)) {
      fail('Expected $expected, found: $actual');
    }
  }
}
