// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../exceptions.dart';
import '../path.dart';
import '../platform_info.dart';
import 'credential.dart';

typedef PublishFile = ({int length, String sha256});

typedef HelperContext =
    ({
      String package,
      String? version,
      PublishFile? archive,
      PublishFile? attestations,
    });

class _Grant {
  final String token;
  final DateTime expires;
  final bool requiresProof;

  _Grant(this.token, this.expires, this.requiresProof);
}

/// An explicitly registered executable. Grants live only in this process.
class AuthHelper {
  final List<String> command;
  final _pending = <HelperContext, Future<_Grant>>{};
  final _grants = <HelperContext, _Grant>{};

  // Each helper instance belongs to exactly one registered repository.
  String? resourceNonce;

  AuthHelper(this.command);

  static String? executableError(String executable) {
    if (executable.isEmpty) return '--auth-helper needs an executable path.';
    if (!p.isAbsolute(executable)) {
      return '--auth-helper needs an absolute path.';
    }
    if (platform.isWindows && !executable.toLowerCase().endsWith('.exe')) {
      return 'On Windows, --auth-helper needs an .exe file.';
    }
    return null;
  }

  Future<Map<String, String>> headers(
    Uri repository,
    HelperContext context,
    String method,
    Uri target,
  ) async {
    final cached = _grants[context];
    final grant =
        cached != null && cached.expires.isAfter(DateTime.now())
            ? cached
            : await _pending.putIfAbsent(
              context,
              () => _acquire(repository, context),
            );
    if (!grant.requiresProof) return {'authorization': 'Bearer ${grant.token}'};
    final response = await _invoke(repository, {
      'action': 'prove',
      if (resourceNonce != null) 'nonce': resourceNonce,
      'token': grant.token,
      'method': method,
      'uri': target.toString().split(RegExp('[?#]')).first,
    });
    final proof = response['proof'];
    if (proof is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
        ).hasMatch(proof)) {
      throw DataException('Invalid auth helper proof for $repository.');
    }
    return {'authorization': 'DPoP ${grant.token}', 'dpop': proof};
  }

  Future<_Grant> _acquire(Uri repository, HelperContext context) async {
    try {
      final json = await _invoke(repository, {
        'action': 'acquire',
        'operation': context.archive == null ? 'read' : 'publish',
        'package': context.package,
        if (context.version != null) 'version': context.version,
        if (context.archive case final file?)
          'archive': {'length': file.length, 'sha256': file.sha256},
        if (context.attestations case final file?)
          'attestations': {'length': file.length, 'sha256': file.sha256},
      });
      final token = json['token'];
      final expiry = json['expiresAt'];
      final expires =
          expiry is String && expiry.endsWith('Z')
              ? DateTime.tryParse(expiry)
              : null;
      final type = json['tokenType'] ?? 'Bearer';
      if (token is! String ||
          !Credential.isValidBearerToken(token) ||
          expires == null ||
          !expires.isAfter(DateTime.now()) ||
          (type != 'Bearer' && type != 'DPoP')) {
        throw DataException('Invalid auth helper credential for $repository.');
      }
      return _grants[context] = _Grant(token, expires, type == 'DPoP');
    } finally {
      final _ = _pending.remove(context);
    }
  }

  void invalidate(HelperContext context) => _grants.remove(context);

  Future<Map<String, dynamic>> _invoke(
    Uri repository,
    Map<String, Object?> input,
  ) async {
    Process? child;
    try {
      child = await Process.start(
        command.first,
        command.sublist(1),
        workingDirectory: p.dirname(command.first),
      );
      final process = child;
      final bytes = <int>[];
      await Future.wait<void>([
        process.stdout.forEach((chunk) {
          if (bytes.length + chunk.length > 64 * 1024) {
            throw const FormatException();
          }
          bytes.addAll(chunk);
        }),
        process.stderr.drain<void>(),
        () async {
          process.stdin.add(
            utf8.encode(
              jsonEncode({
                'protocolVersion': 1,
                'repository': repository.toString(),
                'interactive': false,
                ...input,
              }),
            ),
          );
          await process.stdin.close();
        }(),
        process.exitCode.then((code) {
          if (code != 0) throw const FormatException();
        }),
      ], eagerError: true).timeout(const Duration(seconds: 30));
      final response = jsonDecode(utf8.decode(bytes));
      if (response is Map<String, dynamic>) return response;
      throw const FormatException();
    } on Exception {
      child?.kill(ProcessSignal.sigkill);
      throw DataException(
        'Auth helper failed for $repository. '
        'Check the helper installation and sign-in.',
      );
    }
  }
}
