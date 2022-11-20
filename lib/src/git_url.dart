// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

String parseGitUrl(String url) {
  if (url.startsWith('git@')) {
    return _parseGitUrl(url);
  }
  return Uri.parse(url).toString();
}

String _parseGitUrl(String url) {
  if (!url.endsWith('.git')) {
    throw GitUrlException('This is not git format.');
  }
  int colonIndex = url.indexOf(':');
  if (colonIndex == -1) {
    throw GitUrlException('Need to contain a domain.');
  }
  final domain = url.substring(4, colonIndex);
  if (domain.isEmpty || Uri.tryParse(domain) == null) {
    throw GitUrlException('Need to contain a valid domain.');
  }
  return url;
}

class GitUrlException implements Exception {
  final String message;

  GitUrlException(this.message);

  @override
  String toString() {
    return message;
  }
}
