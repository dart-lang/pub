// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub/src/utils.dart';
import 'package:test/test.dart';

void main() {
  group('yamlToString()', () {
    test('null', () {
      expect(yamlToString(null), equals('null'));
    });

    test('numbers', () {
      expect(yamlToString(123), equals('123'));
      expect(yamlToString(12.34), equals('12.34'));
    });

    test('does not quote strings that do not need it', () {
      expect(yamlToString('a'), equals('a'));
      expect(yamlToString('some-string'), equals('some-string'));
      expect(yamlToString('hey123CAPS'), equals('hey123CAPS'));
      expect(yamlToString('_under_score'), equals('_under_score'));
    });

    test('quotes other strings', () {
      expect(yamlToString(''), equals('""'));
      expect(yamlToString('123'), equals('"123"'));
      expect(yamlToString('white space'), equals('"white space"'));
      expect(yamlToString('"quote"'), equals(r'"\"quote\""'));
      expect(yamlToString("apostrophe'"), equals('"apostrophe\'"'));
      expect(yamlToString('new\nline'), equals(r'"new\nline"'));
      expect(yamlToString('?unctu@t!on'), equals(r'"?unctu@t!on"'));
    });

    test('lists use JSON style', () {
      expect(yamlToString([1, 2, 3]), equals('[1,2,3]'));
    });

    test('uses indentation for maps', () {
      expect(
          yamlToString({
            'a': {'b': 1, 'c': 2},
            'd': 3
          }),
          equals('''
a:
  b: 1
  c: 2
d: 3'''));
    });

    test('sorts map keys', () {
      expect(yamlToString({'a': 1, 'c': 2, 'b': 3, 'd': 4}), equals('''
a: 1
b: 3
c: 2
d: 4'''));
    });

    test('quotes map keys as needed', () {
      expect(yamlToString({'no': 1, 'yes!': 2, '123': 3}), equals('''
"123": 3
no: 1
"yes!": 2'''));
    });

    test('handles non-string map keys', () {
      var map = {};
      map[null] = 'null';
      map[123] = 'num';
      map[true] = 'bool';

      expect(yamlToString(map), equals('''
123: num
null: null
true: bool'''));
    });

    test('handles empty maps', () {
      expect(yamlToString({}), equals('{}'));
      expect(yamlToString({'a': {}, 'b': {}}), equals('''
a: {}
b: {}'''));
    });
  });

  group('niceDuration()', () {
    test('formats duration longer than a minute correctly', () {
      expect(niceDuration(Duration(minutes: 3, seconds: 1, milliseconds: 337)),
          equals('3:01.3s'));
    });

    test('does not display extra zero when duration is less than a minute', () {
      expect(niceDuration(Duration(minutes: 0, seconds: 0, milliseconds: 400)),
          equals('0.4s'));
    });

    test('has reasonable output on minute boundary', () {
      expect(niceDuration(Duration(minutes: 1)), equals('1:00.0s'));
    });
  });

  group('uuid', () {
    var uuidRegexp = RegExp('^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-'
        r'[8-9A-B][0-9A-F]{3}-[0-9A-F]{12}$');

    test('min value is valid', () {
      var uuid = createUuid(List<int>.filled(16, 0));
      expect(uuid, matches(uuidRegexp));
      expect(uuid, '00000000-0000-4000-8000-000000000000');
    });
    test('max value is valid', () {
      var uuid = createUuid(List<int>.filled(16, 255));
      expect(uuid, matches(uuidRegexp));
      expect(uuid, 'FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF');
    });
    test('random values are valid', () {
      for (var i = 0; i < 100; i++) {
        var uuid = createUuid();
        expect(uuid, matches(uuidRegexp));
      }
    });
  });

  group('minByAsync', () {
    test('is stable', () async {
      {
        final completers = <String, Completer>{};
        Completer completer(k) => completers.putIfAbsent(k, () => Completer());
        Future<int> lengthWhenComplete(String s) async {
          await completer(s).future;
          return s.length;
        }

        final w = expectLater(
            minByAsync(['aa', 'a', 'b', 'ccc'], lengthWhenComplete),
            completion('a'));
        completer('aa').complete();
        completer('b').complete();
        completer('a').complete();
        completer('ccc').complete();
        await w;
      }
      {
        final completers = <String, Completer>{};
        Completer completer(k) => completers.putIfAbsent(k, () => Completer());
        Future<int> lengthWhenComplete(String s) async {
          await completer(s).future;
          return s.length;
        }

        final w = expectLater(
            minByAsync(['aa', 'a', 'b', 'ccc'], lengthWhenComplete),
            completion('a'));
        completer('ccc').complete();
        completer('a').complete();
        completer('b').complete();
        completer('aa').complete();
        await w;
      }
    });
  });
}
