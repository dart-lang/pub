// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;

import '../entrypoint.dart';
import '../null_safety_analysis.dart';
import '../package_name.dart';
import '../validator.dart';

/// Gives a warning when publishing a new version, if this package opts into
/// null safety, but any of the dependencies do not.
class NullSafetyMixedModeValidator extends Validator {
  NullSafetyMixedModeValidator(Entrypoint entrypoint) : super(entrypoint);

  @override
  Future<void> validate() async {
    final pubspec = entrypoint.root.pubspec;
    final declaredLanguageVersion = pubspec.languageVersion;
    if (!declaredLanguageVersion.supportsNullSafety) {
      return;
    }
    final analysisResult = await NullSafetyAnalysis(entrypoint.cache)
        .nullSafetyCompliance(PackageId(
            entrypoint.root.name,
            entrypoint.cache.sources.path,
            entrypoint.root.version,
            {'relative': false, 'path': p.absolute(entrypoint.root.dir)}));

    if (analysisResult.compliance == NullSafetyCompliance.mixed) {
      warnings.add('''
This package is opting into null-safety, but a dependency or file is not.

${analysisResult.reason}

Note that by publishing with non-migrated dependencies your package may be
broken at any time if one of your dependencies migrates without a breaking 
change release. 

We highly recommend that you wait until all of your dependencies have been 
migrated before publishing.

Run `pub outdated --mode=null-safety` for more information about the state of
dependencies.

See ${NullSafetyAnalysis.guideUrl}
for more information about migrating.
''');
    }
  }
}
