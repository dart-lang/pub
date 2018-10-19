// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:link_checker/link_checker.dart';
import 'package:test/test.dart';

void main() => test('project for dead links', () async {
      var badLinks = <BadLink>[];
      await for (BadLink badLink
          in getBadLinksInDirectory(blacklistedLinksRegexes: [
        RegExp(r'http:\/\/localhost.*'),
        RegExp(r'http:\/\/example\.com.*'),
        RegExp(r'http:\/\/pub\.invalid.*'),
        RegExp(r'http:\/\/bad\.url.*'),
        RegExp(r'https:\/\/accounts\.google\.com.*')
      ])) {
        badLinks.add(badLink);
      }
      expect(badLinks, isEmpty,
          reason: "There shouldn't be dead links in the project");
    }, timeout: Timeout.none);
