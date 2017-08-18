import 'package:barback/barback.dart';

import 'scratch_space.dart';

final defaultAnalysisOptionsId =
    new AssetId('_internal_', 'lib/analysis_options.yaml');

final defaultAnalysisOptions =
    new Asset.fromString(defaultAnalysisOptionsId, '''
analyzer:
  strong-mode: true
''');

String defaultAnalysisOptionsArg(ScratchSpace scratchSpace) =>
    '--options=${scratchSpace.fileFor(defaultAnalysisOptionsId).path}';
