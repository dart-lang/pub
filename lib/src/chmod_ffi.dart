// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';

@AbiSpecificIntegerMapping({
  Abi.macosArm64: Uint16(),
  Abi.macosX64: Uint16(),
  Abi.linuxArm: Uint32(),
  Abi.linuxArm64: Uint32(),
  Abi.linuxIA32: Uint32(),
  Abi.linuxRiscv32: Uint32(),
  Abi.linuxRiscv64: Uint32(),
  Abi.linuxX64: Uint32(),
})
final class _ModeT extends AbiSpecificInteger {
  const _ModeT();
}

@Native<Int Function(Pointer<Uint8>, _ModeT)>(symbol: 'chmod')
external int _posixChmod(Pointer<Uint8> path, int mode);

@Native<Pointer<Uint8> Function(Size)>(symbol: 'malloc', isLeaf: true)
external Pointer<Uint8> _malloc(int size);

@Native<Void Function(Pointer<Uint8>)>(symbol: 'free', isLeaf: true)
external void _free(Pointer<Uint8> pointer);

/// Calls POSIX `chmod(2)` on [path] with [mode].
///
/// Returns `0` on success, or `-1` on error.
int chmod(int mode, String path) {
  final bytes = utf8.encode(path);
  if (bytes.contains(0)) {
    return -1;
  }
  final ptr = _malloc(bytes.length + 1);
  if (ptr == nullptr) {
    throw const OutOfMemoryError();
  }
  try {
    ptr.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    return _posixChmod(ptr, mode);
  } finally {
    _free(ptr);
  }
}
