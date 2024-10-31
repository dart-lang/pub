// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'descriptor.dart' as d;

/// Describes a symlink.
class LinkDescriptor extends d.Descriptor {
  /// On windows symlinks to directories are distinct from symlinks to files.
  final bool forceDirectory;
  final String target;
  LinkDescriptor(super.name, this.target, {this.forceDirectory = false});

  @override
  Future<void> create([String? parent]) async {
    final path = p.join(parent ?? d.sandbox, name);
    if (forceDirectory) {
      if (Platform.isWindows) {
        Process.runSync('cmd', ['/c', 'mklink', '/D', path, target]);
      } else {
        Link(path).createSync(target);
      }
    } else {
      Link(path).createSync(target);
    }
  }

  @override
  String describe() {
    return 'symlink at $name targeting $target';
  }

  @override
  Future<void> validate([String? parent]) async {
    final link = Link(p.join(parent ?? d.sandbox, name));
    try {
      final actualTarget = link.targetSync();
      expect(
        actualTarget,
        target,
        reason: 'Link doesn\'t point where expected.',
      );
    } on FileSystemException catch (e) {
      fail('Could not read link at $name $e');
    }
  }
}

d.Descriptor link(String name, String target, {bool forceDirectory = false}) {
  return LinkDescriptor(name, target, forceDirectory: forceDirectory);
}
