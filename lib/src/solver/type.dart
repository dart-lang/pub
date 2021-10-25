// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An enum for types of version resolution.
class SolveType {
  /// As few changes to the lockfile as possible to be consistent with the
  /// pubspec.
  static const GET = SolveType._('get');

  /// Upgrade all packages or specific packages to the highest versions
  /// possible, regardless of the lockfile.
  static const UPGRADE = SolveType._('upgrade');

  /// Downgrade all packages or specific packages to the lowest versions
  /// possible, regardless of the lockfile.
  static const DOWNGRADE = SolveType._('downgrade');

  final String _name;

  const SolveType._(this._name);

  @override
  String toString() => _name;
}
