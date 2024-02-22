// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../language_version.dart';
import '../source.dart';
import 'unknown.dart';

/// Represents a bad dependency description.
///
/// Allows for postponing the error until the dependency is actually read.
class ErrorDescription extends Description {
  final Exception exception;

  ErrorDescription(this.exception);

  @override
  String format() {
    throw UnimplementedError();
  }

  @override
  bool operator ==(Object other) {
    return identical(other, this);
  }

  @override
  int get hashCode => identityHashCode(this);

  @override
  Object? serializeForPubspec({
    required String? containingDir,
    required LanguageVersion languageVersion,
  }) {
    throw UnimplementedError();
  }

  @override
  Source get source => UnknownSource('Error');
}
