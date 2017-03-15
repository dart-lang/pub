// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:pub/src/io.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

main() {
  integration("doesn't re-fetch a repository if nothing changes", () {
    ensureGit();

    var repo =
        d.git('foo.git', [d.libDir('foo'), d.libPubspec('foo', '1.0.0')]);
    repo.create();

    d.appDir({
      "foo": {
        "git": {"url": "../foo.git"}
      }
    }).create();

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubGet(args: ["--packages-dir"]);

    d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo";')])
    ]).validate();

    // Delete the repo. This will cause "pub get" to fail if it tries to
    // re-fetch.
    schedule(() => deleteEntry(p.join(sandboxDir, 'foo.git')));

    // TODO(rnystrom): Remove "--packages-dir" and validate using the
    // ".packages" file instead of looking in the "packages" directory.
    pubGet(args: ["--packages-dir"]);

    d.dir(packagesPath, [
      d.dir('foo', [d.file('foo.dart', 'main() => "foo";')])
    ]).validate();
  });
}
