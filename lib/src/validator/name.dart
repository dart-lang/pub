// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as path;

import '../entrypoint.dart';
import '../utils.dart';
import '../validator.dart';

/// A validator that the name of a package is legal and matches the library name
/// in the case of a single library.
class NameValidator extends Validator {
  NameValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future validate() {
    return Future.sync(() {
      _checkName(entrypoint.root.name);

      var libraries = _libraries;

      if (libraries.length == 1) {
        var libName = path.basenameWithoutExtension(libraries[0]);
        if (libName == entrypoint.root.name) return;
        warnings.add('The name of "${libraries[0]}", "$libName", should match '
            'the name of the package, "${entrypoint.root.name}".\n'
            'This helps users know what library to import.');
      }
    });
  }

  /// Returns a list of all libraries in the current package as paths relative
  /// to the package's root directory.
  List<String> get _libraries {
    var libDir = entrypoint.root.path('lib');
    return entrypoint.root
        .listFiles(beneath: 'lib')
        .map((file) => path.relative(file, from: path.dirname(libDir)))
        .where((file) =>
            !path.split(file).contains('src') &&
            path.extension(file) == '.dart')
        .toList();
  }

  void _checkName(String name) {
    final description = 'Package name "$name"';
    if (name == '') {
      errors.add('$description may not be empty.');
    } else if (!RegExp(r'^[a-zA-Z0-9_]*$').hasMatch(name)) {
      errors.add('$description may only contain letters, numbers, and '
          'underscores.\n'
          'Using a valid Dart identifier makes the name usable in Dart code.');
    } else if (!RegExp(r'^[a-zA-Z_]').hasMatch(name)) {
      errors.add('$description must begin with a letter or underscore.\n'
          'Using a valid Dart identifier makes the name usable in Dart code.');
    } else if (reservedWords.contains(name.toLowerCase())) {
      errors.add('$description may not be a reserved word in Dart.\n'
          'Using a valid Dart identifier makes the name usable in Dart code.');
    } else if (RegExp(r'[A-Z]').hasMatch(name)) {
      warnings.add('$description should be lower-case. Maybe use '
          '"${_unCamelCase(name)}"?');
    }
  }

  String _unCamelCase(String source) {
    var builder = StringBuffer();
    var lastMatchEnd = 0;
    for (var match in RegExp(r'[a-z]([A-Z])').allMatches(source)) {
      builder
        ..write(source.substring(lastMatchEnd, match.start + 1))
        ..write('_')
        ..write(match.group(1).toLowerCase());
      lastMatchEnd = match.end;
    }
    builder.write(source.substring(lastMatchEnd));
    return builder.toString().toLowerCase();
  }
}
