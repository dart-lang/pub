// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An enum of possible relationships between two sets.
enum SetRelation {
  /// The second set contains all elements of the first, as well as possibly
  /// more.
  subset('subset'),

  /// Neither set contains any elements of the other.
  disjoint('disjoint'),

  /// The sets have elements in common, but the first is not a superset of the
  /// second.
  ///
  /// This is also used when the first set is a superset of the first, but in
  /// practice we don't need to distinguish that from overlapping sets.
  overlapping('overlapping');

  final String _name;

  const SetRelation(this._name);

  @override
  String toString() => _name;
}
