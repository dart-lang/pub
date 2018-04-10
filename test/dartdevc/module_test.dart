// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:test/test.dart';

import 'package:pub/src/dartdevc/module.dart';

import 'util.dart';

void main() {
  group('ModuleId', () {
    test('can go to and from json', () {
      var id = makeModuleId();
      var newId = new ModuleId.fromJson(json.decode(json.encode(id)));
      expect(newId, equals(id));
      expect(newId.hashCode, equals(id.hashCode));
    });
  });

  group('Module', () {
    test('can go to and from json', () {
      var module = makeModule();
      var newModule = new Module.fromJson(json.decode(json.encode(module)));
      expect(module, equalsModule(newModule));
    });

    test('can be serialized in a list', () {
      var modules = makeModules();
      var serialized = json.encode(modules);
      var newModules =
          json.decode(serialized).map((s) => new Module.fromJson(s)).toList();
      expect(modules.length, equals(newModules.length));
      for (int i = 0; i < modules.length; i++) {
        expect(modules[i], equalsModule(newModules[i]));
      }
    });
  });
}
