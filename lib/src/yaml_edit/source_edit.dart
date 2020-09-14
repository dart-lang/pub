// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// A class representing a change on a [String], intended to be compatible with
/// `package:analysis_server`'s [SourceEdit].
///
/// For example, changing a string from
/// ```
/// foo: foobar
/// ```
/// to
/// ```
/// foo: barbar
/// ```
/// will be represented by `SourceEdit(offset: 4, length: 3, replacement: 'bar')`
@sealed
class SourceEdit {
  /// The offset from the start of the string where the modification begins.
  final int offset;

  /// The length of the substring to be replaced.
  final int length;

  /// The replacement string to be used.
  final String replacement;

  /// Creates a new [SourceEdit] instance. [offset], [length] and [replacement]
  /// must be non-null, and [offset] and [length] must be non-negative.
  factory SourceEdit(int offset, int length, String replacement) =>
      SourceEdit._(offset, length, replacement);

  SourceEdit._(this.offset, this.length, this.replacement) {
    ArgumentError.checkNotNull(offset, 'offset');
    ArgumentError.checkNotNull(length, 'length');
    ArgumentError.checkNotNull(replacement, 'replacement');
    RangeError.checkNotNegative(offset);
    RangeError.checkNotNegative(length);
  }

  @override
  bool operator ==(Object other) {
    if (other is SourceEdit) {
      return offset == other.offset &&
          length == other.length &&
          replacement == other.replacement;
    }

    return false;
  }

  @override
  int get hashCode => offset.hashCode ^ length.hashCode ^ replacement.hashCode;

  /// Constructs a SourceEdit from JSON.
  ///
  /// **Example:**
  /// ```dart
  /// final edit = {
  ///   'offset': 1,
  ///   'length': 2,
  ///   'replacement': 'replacement string'
  /// };
  ///
  /// final sourceEdit = SourceEdit.fromJson(edit);
  /// ```
  factory SourceEdit.fromJson(Map<String, dynamic> json) {
    ArgumentError.checkNotNull(json, 'json');

    if (json is Map) {
      final offset = json['offset'];
      final length = json['length'];
      final replacement = json['replacement'];

      if (offset is int && length is int && replacement is String) {
        return SourceEdit(offset, length, replacement);
      }
    }
    throw FormatException('Invalid JSON passed to SourceEdit');
  }

  /// Encodes this object as JSON-compatible structure.
  ///
  /// **Example:**
  /// ```dart
  /// import 'dart:convert' show jsonEncode;
  ///
  /// final edit = SourceEdit(offset, length, 'replacement string');
  /// final jsonString = jsonEncode(edit.toJson());
  /// print(jsonString);
  /// ```
  Map<String, dynamic> toJson() {
    return {'offset': offset, 'length': length, 'replacement': replacement};
  }

  @override
  String toString() => 'SourceEdit($offset, $length, "$replacement")';

  /// Applies a series of [SourceEdit]s to an original string, and return the
  /// final output.
  ///
  /// [edits] should be in order i.e. the first [SourceEdit] in [edits] should
  /// be the first edit applied to [original].
  ///
  /// **Example:**
  /// ```dart
  /// const original = 'YAML: YAML';
  /// final sourceEdits = [
  ///        SourceEdit(6, 4, "YAML Ain't Markup Language"),
  ///        SourceEdit(6, 4, "YAML Ain't Markup Language"),
  ///        SourceEdit(0, 4, "YAML Ain't Markup Language")
  ///      ];
  /// final result = SourceEdit.applyAll(original, sourceEdits);
  /// ```
  /// **Expected result:**
  /// ```dart
  /// "YAML Ain't Markup Language: YAML Ain't Markup Language Ain't Markup
  /// Language"
  /// ```
  static String applyAll(String original, Iterable<SourceEdit> edits) {
    ArgumentError.checkNotNull(original, 'original');
    ArgumentError.checkNotNull(edits, 'edits');

    return edits.fold(original, (current, edit) => edit.apply(current));
  }

  /// Applies one [SourceEdit]s to an original string, and return the final
  /// output.
  ///
  /// **Example:**
  /// ```dart
  /// final edit = SourceEdit(4, 3, 'bar');
  /// final originalString = 'foo: foobar';
  /// print(edit.apply(originalString)); // 'foo: barbar'
  /// ```
  String apply(String original) {
    ArgumentError.checkNotNull(original, 'original');

    return original.replaceRange(offset, offset + length, replacement);
  }
}
