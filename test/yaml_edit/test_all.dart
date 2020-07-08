// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'append_test.dart' as append;
import 'editor_test.dart' as editor;
import 'golden_test.dart' as golden;
import 'insert_test.dart' as insert;
import 'parse_test.dart' as parse;
import 'prepend_test.dart' as prepend;
import 'preservation_test.dart' as preservation;
import 'remove_test.dart' as remove;
import 'source_edit_test.dart' as source;
import 'special_test.dart' as special;
import 'splice_test.dart' as splice;
import 'update_test.dart' as update;
import 'utils_test.dart' as utils;
import 'wrap_test.dart' as wrap;

Future<void> main() async {
  await golden.main();
  group('append', append.main);
  group('editor', editor.main);
  group('insert', insert.main);
  group('parse', parse.main);
  group('prepend', prepend.main);
  group('preservation', preservation.main);
  group('remove', remove.main);
  group('sourceEdit', source.main);
  group('special cases', special.main);
  group('splice', splice.main);
  group('update', update.main);
  group('utils', utils.main);
  group('wrap', wrap.main);
}
