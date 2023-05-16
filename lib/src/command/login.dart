// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import '../command.dart';
import '../command_runner.dart';
import '../log.dart' as log;
import '../oauth2.dart' as oauth2;
import '../utils.dart';

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
    final credentials = oauth2.loadCredentials();
    if (credentials == null) {
      final userInfo = await _retrieveUserInfo();
      if (userInfo == null) {
        log.warning('Could not retrieve your user-details.\n'
            'You might have to run `$topLevelProgram pub logout` to delete your credentials and try again.');
      } else {
        log.message('You are now logged in as $userInfo');
      }
    } else {
      final userInfo = await _retrieveUserInfo();
      if (userInfo == null) {
        log.warning('Your credentials seems broken.\n'
            'Run `$topLevelProgram pub logout` to delete your credentials and try again.');
      }
      log.warning('You are already logged in as $userInfo\n'
          'Run `$topLevelProgram pub logout` to log out and try again.');
    }
  }

  Future<_UserInfo?> _retrieveUserInfo() async {
    return await oauth2.withClient((client) async {
      final discovery = await oauth2.fetchOidcDiscoveryDocument();
      final userInfoEndpoint = asString(discovery['userinfo_endpoint']);
      final userInfoRequest = await client.get(Uri.parse(userInfoEndpoint));
      if (userInfoRequest.statusCode != 200) return null;
      try {
        final userInfo = json.decode(userInfoRequest.body);
        final name = userInfo['name'] as String?;
        final email = userInfo['email'];
        if (email is String) {
          return _UserInfo(name, email);
        } else {
          log.fine(
            'Bad response from $userInfoEndpoint: ${userInfoRequest.body}',
          );
          return null;
        }
      } on FormatException catch (e) {
        log.fine(
          'Bad response from $userInfoEndpoint ($e): ${userInfoRequest.body}',
        );
        return null;
      }
    });
  }
}

class _UserInfo {
  final String? name;
  final String email;
  _UserInfo(this.name, this.email);
  @override
  String toString() => ['<$email>', name ?? ''].join(' ');
}
