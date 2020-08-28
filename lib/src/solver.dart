// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'lock_file.dart';
import 'package.dart';
import 'solver/failure.dart';
import 'solver/result.dart';
import 'solver/type.dart';
import 'solver/version_solver.dart';
import 'system_cache.dart';

export 'solver/failure.dart';
export 'solver/result.dart';
export 'solver/type.dart';

/// Attempts to select the best concrete versions for all of the transitive
/// dependencies of [root] taking into account all of the [VersionConstraint]s
/// that those dependencies place on each other and the requirements imposed by
/// [lockFile].
///
/// Packages referenced in [solveFirst], if any, will be given priority in the
/// solving process.
///
/// If [solveFirst] is given and [type] is [SolveType.UPGRADE], then the
/// referenced packages will be additionally unlocked. Otherwise, if [type] is
/// [SolveType.UPGRADE] and [solveFirst] is not given, all the packages will
/// be unlocked.
Future<SolveResult> resolveVersions(
    SolveType type, SystemCache cache, Package root,
    {LockFile lockFile, Iterable<String> solveFirst}) {
  return VersionSolver(
    type,
    cache,
    root,
    lockFile ?? LockFile.empty(),
    solveFirst ?? const [],
  ).solve();
}

/// Attempts to select the best concrete versions for all of the transitive
/// dependencies of [root] taking into account all of the [VersionConstraint]s
/// that those dependencies place on each other and the requirements imposed by
/// [lockFile].
///
/// Like [resolveVersions] except that this function returns `null` where a
/// similar call to [resolveVersions] would throw a [SolveFailure].
///
/// Packages referenced in [solveFirst], if any, will be given priority in the
/// solving process.
///
/// If [solveFirst] is given and [type] is [SolveType.UPGRADE], then the
/// referenced packages will be additionally unlocked. Otherwise, if [type] is
/// [SolveType.UPGRADE] and [solveFirst] is not given, all the packages will
/// be unlocked.
Future<SolveResult> tryResolveVersions(
    SolveType type, SystemCache cache, Package root,
    {LockFile lockFile, Iterable<String> solveFirst}) async {
  try {
    return await resolveVersions(type, cache, root,
        lockFile: lockFile, solveFirst: solveFirst);
  } on SolveFailure {
    return null;
  }
}
