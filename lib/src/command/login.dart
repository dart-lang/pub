// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import '../command.dart';
import '../http.dart';
import '../log.dart' as log;
import '../oauth2.dart' as oauth2;

/// Handles the `login` pub command.
class LoginCommand extends PubCommand {
  @override
  String get name => 'login';
  @override
  String get description => 'Log into pub.dev.';
  @override
  String get invocation => 'pub login';

  LoginCommand();

  @override
  Future<void> runProtected() async {
    final credentials = oauth2.loadCredentials(cache);
    if (credentials == null) {
      final userInfo = await retrieveUserInfo();
      log.message('You are now logged in as $userInfo');
    } else {
      final userInfo = await retrieveUserInfo();
      if (userInfo == null) {
        log.warning('Your credentials seems broken.\n'
            'Run `pub logout` to delete your credentials  and try again.');
      }
      log.warning('You are already logged in as $userInfo\n'
          'Run `pub logout` to log out and try again.');
    }
  }

  Future<_UserInfo> retrieveUserInfo() async {
    return await oauth2.withClient(cache, (client) async {
      final discovery = await httpClient
          .get('https://accounts.google.com/.well-known/openid-configuration');
      final userInfoEndpoint = json.decode(discovery.body)['userinfo_endpoint'];
      final userInfoRequest = await client.get(userInfoEndpoint);
      if (userInfoRequest.statusCode != 200) return null;
      try {
        final userInfo = json.decode(userInfoRequest.body);
        return _UserInfo(userInfo['name'], userInfo['email']);
      } on FormatException {
        return null;
      }
    });
  }
}

class _UserInfo {
  final String name;
  final String email;
  _UserInfo(this.name, this.email);
  @override
  String toString() => '<$email> "$name"';
}
