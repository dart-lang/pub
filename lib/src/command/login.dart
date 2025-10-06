// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import '../command.dart';
import '../command_runner.dart';
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
    final credentials = oauth2.loadCredentials();
    final userInfo = await _retrieveUserInfo();

    if (credentials == null) {
      if (userInfo == null) {
        log.warning(
          'Could not retrieve your user details.\n'
          'Run `$topLevelProgram pub logout` to delete credentials and try '
          'again.',
        );
      } else {
        log.message('You are now logged in as $userInfo');
      }
    } else {
      if (userInfo == null) {
        log.warning(
          'Your credentials seem to be broken.\n'
          'Run `$topLevelProgram pub logout` to delete credentials and try '
          'again.',
        );
      } else {
        log.message('You are already logged in as $userInfo');
      }
    }
  }

  Future<_UserInfo?> _retrieveUserInfo() async {
    return await oauth2.withClient((client) async {
      final discovery = await oauth2.fetchOidcDiscoveryDocument();
      final userInfoEndpoint = discovery['userinfo_endpoint'];

      if (userInfoEndpoint is! String) {
        log.fine(
          'Invalid discovery document: userinfo_endpoint is not a String',
        );
        return null;
      }

      final response = await client.get(Uri.parse(userInfoEndpoint));
      if (response.statusCode != 200) {
        log.fine('Failed to fetch user info: HTTP ${response.statusCode}');
        return null;
      }

      try {
        final decoded = json.decode(response.body);
        if (decoded case {
          'name': final String? name,
          'email': final String email,
        }) {
          return _UserInfo(name, email);
        } else {
          log.fine('Unexpected user info format: ${response.body}');
          return null;
        }
      } on FormatException catch (e) {
        log.fine('Failed to decode user info: $e\nResponse: ${response.body}');
        return null;
      }
    });
  }
}

class _UserInfo {
  final String? name;
  final String email;
  _UserInfo({required this.name, required this.email});
  @override
  String toString() => ['<$email>', name ?? ''].join(' ');
}
