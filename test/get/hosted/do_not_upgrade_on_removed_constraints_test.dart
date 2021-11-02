// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../descriptor.dart' as d;
import '../../test_pub.dart';

void main() {
  test(
      "doesn't upgrade dependencies whose constraints have been "
      'removed', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.0.0', deps: {'shared_dep': 'any'});
      builder.serve('bar', '1.0.0', deps: {'shared_dep': '<2.0.0'});
      builder.serve('shared_dep', '1.0.0');
      builder.serve('shared_dep', '2.0.0');
    });

    await d.appDir({'foo': 'any', 'bar': 'any'}).create();

    await pubGet();

    await d.appPackagesFile(
        {'foo': '1.0.0', 'bar': '1.0.0', 'shared_dep': '1.0.0'}).validate();

    await d.appDir({'foo': 'any'}).create();

    await pubGet();

    await d.appPackagesFile({'foo': '1.0.0', 'shared_dep': '1.0.0'}).validate();
  });
}
