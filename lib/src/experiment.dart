// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An experiment as described by an sdk_experiments file
class Experiment {
  final String name;

  /// A description of the experiment
  final String description;

  /// Where you can read more about the experiment
  final String docUrl;

  Experiment(this.name, this.description, this.docUrl);
}
