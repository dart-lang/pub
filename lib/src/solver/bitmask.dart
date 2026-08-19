// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

int _popcount32(int x) {
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F;
  x = x + (x >> 8);
  x = x + (x >> 16);
  return x & 0x3F;
}

/// A fixed-size discrete bitmask of length [length] backed by [Uint32List]
/// words.
class Bitmask {
  final Uint32List _words;
  final int length;

  Bitmask._(this._words, this.length);

  /// Creates an empty mask of [length] bits.
  factory Bitmask.empty(int length) {
    final wordCount = (length + 31) ~/ 32;
    return Bitmask._(Uint32List(wordCount), length);
  }

  /// Creates a mask with all [length] bits set.
  factory Bitmask.all(int length) {
    final wordCount = (length + 31) ~/ 32;
    final words = Uint32List(wordCount);
    for (var i = 0; i < wordCount; i++) {
      words[i] = 0xFFFFFFFF;
    }
    _maskTopWord(words, length);
    return Bitmask._(words, length);
  }

  /// Creates a mask with a single bit at [index] set.
  factory Bitmask.single(int length, int index) {
    final mask = Bitmask.empty(length);
    if (index >= 0 && index < length) {
      mask._words[index ~/ 32] |= 1 << (index % 32);
    }
    return mask;
  }

  /// Creates a mask with bits in range `[startIndex, endIndex)` set.
  factory Bitmask.range(int length, int startIndex, int endIndex) {
    final mask = Bitmask.empty(length);
    final clampedStart = startIndex < 0 ? 0 : startIndex;
    final clampedEnd = endIndex > length ? length : endIndex;
    for (var i = clampedStart; i < clampedEnd; i++) {
      mask._words[i ~/ 32] |= 1 << (i % 32);
    }
    return mask;
  }

  /// Creates a mask from a predicate testing each index.
  factory Bitmask.fromPredicate(int length, bool Function(int) test) {
    final mask = Bitmask.empty(length);
    for (var i = 0; i < length; i++) {
      if (test(i)) {
        mask._words[i ~/ 32] |= 1 << (i % 32);
      }
    }
    return mask;
  }

  static void _maskTopWord(Uint32List words, int length) {
    final remainder = length % 32;
    if (remainder != 0 && words.isNotEmpty) {
      words[words.length - 1] &= (1 << remainder) - 1;
    }
  }

  bool get isEmpty {
    for (var i = 0; i < _words.length; i++) {
      if (_words[i] != 0) return false;
    }
    return true;
  }

  bool get isNotEmpty => !isEmpty;

  /// The number of set bits in this mask.
  int count() {
    var total = 0;
    for (var i = 0; i < _words.length; i++) {
      total += _popcount32(_words[i]);
    }
    return total;
  }

  /// The highest index set in this mask, or `-1` if empty.
  int highestIndex() {
    for (var w = _words.length - 1; w >= 0; w--) {
      final word = _words[w];
      if (word != 0) {
        return w * 32 + word.bitLength - 1;
      }
    }
    return -1;
  }

  /// The lowest index set in this mask, or `-1` if empty.
  int lowestIndex() {
    for (var w = 0; w < _words.length; w++) {
      final word = _words[w];
      if (word != 0) {
        final lowestBit = word & -word;
        return w * 32 + lowestBit.bitLength - 1;
      }
    }
    return -1;
  }

  /// Whether bit at [index] is set.
  bool allows(int index) {
    if (index < 0 || index >= length) return false;
    return (_words[index ~/ 32] & (1 << (index % 32))) != 0;
  }

  /// Intersection of `this` and [other].
  Bitmask operator &(Bitmask other) {
    if (other.length != length) {
      throw ArgumentError('Mismatched Bitmask lengths');
    }
    final result = Uint32List(_words.length);
    for (var i = 0; i < _words.length; i++) {
      result[i] = _words[i] & other._words[i];
    }
    return Bitmask._(result, length);
  }

  /// Union of `this` and [other].
  Bitmask operator |(Bitmask other) {
    if (other.length != length) {
      throw ArgumentError('Mismatched Bitmask lengths');
    }
    final result = Uint32List(_words.length);
    for (var i = 0; i < _words.length; i++) {
      result[i] = _words[i] | other._words[i];
    }
    return Bitmask._(result, length);
  }

  /// Set difference of `this \ other` (`this & ~other`).
  Bitmask difference(Bitmask other) {
    if (other.length != length) {
      throw ArgumentError('Mismatched Bitmask lengths');
    }
    final result = Uint32List(_words.length);
    for (var i = 0; i < _words.length; i++) {
      result[i] = _words[i] & ~other._words[i];
    }
    return Bitmask._(result, length);
  }

  /// Whether `this` is a superset of [other] (i.e. `other ⊆ this`).
  bool allowsAll(Bitmask other) {
    if (other.length != length) return false;
    for (var i = 0; i < _words.length; i++) {
      if ((_words[i] & other._words[i]) != other._words[i]) {
        return false;
      }
    }
    return true;
  }

  /// Whether `this` and [other] share at least one set bit.
  bool allowsAny(Bitmask other) {
    if (other.length != length) return false;
    for (var i = 0; i < _words.length; i++) {
      if ((_words[i] & other._words[i]) != 0) {
        return true;
      }
    }
    return false;
  }

  // Uint32List inherits reference equality from Object.
  // See https://github.com/dart-lang/sdk/issues/64095 for a proposed native
  // memory range comparison API.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Bitmask || length != other.length) return false;
    for (var i = 0; i < _words.length; i++) {
      if (_words[i] != other._words[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(length, Object.hashAll(_words));
}
