// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:barback/barback.dart';

import 'scratch_space.dart';

final defaultAnalysisOptionsId =
    new AssetId('_internal_', 'lib/analysis_options.yaml');

final defaultAnalysisOptions =
    new Asset.fromString(defaultAnalysisOptionsId, '');

String defaultAnalysisOptionsArg(ScratchSpace scratchSpace) =>
    '--options=${scratchSpace.fileFor(defaultAnalysisOptionsId).path}';
