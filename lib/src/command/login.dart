// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.10

import 'dart:async';
import 'dart:convert';

import '../authentication/token.dart';
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

  String get server => argResults['server'];
  bool get list => argResults['list'];

  LoginCommand() {
    argParser.addOption('server',
        help: 'The package server to which needs to be authenticated.');

    argParser.addFlag('list',
        help: 'Displays list of currently logged in hosted pub servers',
        defaultsTo: false);
  }

  @override
  Future<void> runProtected() async {
    if (list) {
      await _listCredentials();
    } else if (server == null) {
      await _loginToPubDev();
    } else {
      if (Uri.tryParse(server) == null) {
        usageException('Invalid or malformed server URL provided.');
      }
      await _loginToServer(server);
    }
  }

  Future<void> _listCredentials() async {
    log.message('Found ${cache.tokenStore.tokens.length} entries.');
    for (final scheme in cache.tokenStore.tokens) {
      log.message(scheme.url);
    }
  }

  Future<void> _loginToServer(String server) async {
    // TODO(themisir): Replace this line with validateAndNormalizeHostedUrl from
    // source/hosted.dart when dart-lang/pub#3030 is merged.
    if (Uri.tryParse(server) == null ||
        !server.startsWith(RegExp(r'https?:\/\/'))) {
      usageException('Invalid or malformed server URL provided.');
    }

    try {
      final token = await readLine('Please enter bearer token')
          .timeout(const Duration(minutes: 5));
      if (token.isEmpty) {
        usageException('Token is not provided.');
      }

      tokenStore.addToken(Token.bearer(server, token));
      log.message('You are now logged in to $server using bearer token.');
    } on TimeoutException catch (error, stackTrace) {
      log.error(
          'Timeout error. Token is not provided within '
          '${error.duration.inSeconds} seconds.',
          error,
          stackTrace);
    }
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
