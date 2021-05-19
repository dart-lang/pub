// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:async';
import 'dart:convert';

import '../authentication/bearer.dart';
import '../command.dart';
import '../http.dart';
import '../io.dart';
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

  String get token => argResults['token'];
  bool get tokenStdin => argResults['token-stdin'];

  LoginCommand() {
    argParser.addOption('token', help: 'Authorization token for the server');

    argParser.addFlag('token-stdin',
        help: 'Read authorization token from stdin stream');
  }

  @override
  Future<void> runProtected() async {
    if (argResults.rest.isEmpty) {
      await _loginToPubDev();
    } else {
      if (token?.isNotEmpty != true && !tokenStdin) {
        usageException('Must specify a token.');
      }
      await _loginToServer(argResults.rest.first);
    }
  }

  Future<void> _loginToServer(String server) async {
    if (Uri.tryParse(server) == null) {
      usageException('Invalid or malformed server URL provided.');
    }

    final _token = tokenStdin ? await readLine() : token;
    credentialStore.addCredentials(server, BearerCredential(_token));
    log.message('You are now logged in to $server using bearer token');
  }

  Future<void> _loginToPubDev() async {
    final credentials = oauth2.loadCredentials(cache);
    if (credentials == null) {
      final userInfo = await _retrieveUserInfo();
      log.message('You are now logged in as $userInfo');
    } else {
      final userInfo = await _retrieveUserInfo();
      if (userInfo == null) {
        log.warning('Your credentials seems broken.\n'
            'Run `pub logout` to delete your credentials  and try again.');
      }
      log.warning('You are already logged in as $userInfo\n'
          'Run `pub logout` to log out and try again.');
    }
  }

  Future<_UserInfo> _retrieveUserInfo() async {
    return await oauth2.withClient(cache, (client) async {
      final discovery = await httpClient.get(Uri.https(
          'accounts.google.com', '/.well-known/openid-configuration'));
      final userInfoEndpoint = json.decode(discovery.body)['userinfo_endpoint'];
      final userInfoRequest = await client.get(Uri.parse(userInfoEndpoint));
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
  String toString() => ['<$email>', if (name != null) name].join(' ');
}
