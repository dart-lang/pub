// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  test(
      'doesn\'t require the repository name to match the name in the '
      'pubspec', () async {
    await ensureGit();

    await d.git('foo.git',
        [d.libDir('weirdname'), d.libPubspec('weirdname', '1.0.0')]).create();

    await d.dir(appPath, [
      d.appPubspec({
        "weirdname": {"git": "../foo.git"}
      })
    ]).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    await pubGet(args: ["--packages-dir"]);

    await d.dir(packagesPath, [
      d.dir('weirdname', [d.file('weirdname.dart', 'main() => "weirdname";')])
    ]).validate();
  });
}
