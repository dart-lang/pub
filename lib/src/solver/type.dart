// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An enum for types of version resolution.
enum SolveType {
  /// As few changes to the lockfile as possible to be consistent with the
  /// pubspec.
  get('get'),

  /// Upgrade all packages or specific packages to the highest versions
  /// possible, regardless of the lockfile.
  upgrade('upgrade'),

  /// Downgrade all packages or specific packages to the lowest versions
  /// possible, regardless of the lockfile.
  downgrade('downgrade');

  final String _name;

  const SolveType(this._name);

  @override
  String toString() => _name;
}
