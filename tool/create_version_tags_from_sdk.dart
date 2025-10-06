// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a

/// Tool for finding all tagged versions of the dart sdk, and in turn tag this
/// repository with `SDK-$version` for each of these.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

Future<void> main(List<String> args) async {
  final argParser =
      ArgParser()
        ..addFlag(
          'create',
          help: 'Create the missing tags, otherwise only list them',
          negatable: false,
        )
        ..addFlag(
          'push',
          help: 'Push missing sdk tags to remote',
          negatable: false,
        )
        ..addOption('sdk-dir');
  final ArgResults argResults;
  try {
    argResults = argParser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${argParser.usage}');
    stderr.writeln('''
Will find all tagged sdk versions, and tag the corresponding revision in this 
repository with `--create`.
And can push these tags to the remote with `--push`.

Usage: create_version_tags_from_sdk [--create] [--push] [--sdk-dir <path>]
''');
    exit(-1);
  }
  final create = argResults.flag('create');
  final push = argResults.flag('push');

  Directory? tempDir;
  String sdkDir;
  try {
    if (argResults.option('sdk-dir') == null) {
      tempDir = Directory.systemTemp.createTempSync();
      final cloneResult = Process.runSync('git', [
        'clone',
        // Using a treeless clone is faster up-front, but slower for
        // showing a specific revision.
        // We assume we only miss a few tags.
        '--filter=tree:0',
        '-n',
        'https://github.com/dart-lang/sdk',
      ], workingDirectory: tempDir.path);
      if (cloneResult.exitCode != 0) {
        throw Exception(
          'Failed to clone sdk ${cloneResult.stderr} ${cloneResult.stdout}',
        );
      }
      sdkDir = p.join(tempDir.path, 'sdk');
    } else {
      sdkDir = argResults.option('sdk-dir')!;
    }

    final sdkTags =
        (Process.runSync('git', [
                  'ls-remote',
                  '--tags',
                  '--refs',
                  'origin',
                ], workingDirectory: sdkDir).stdout
                as String)
            .split('\n')
            .where((line) => line.isNotEmpty)
            .map((line) => line.split('\t')[1])
            .map((x) => x.substring('refs/tags/'.length))
            .where((x) {
              try {
                Version.parse(x);
              } on FormatException {
                return false;
              }
              return true;
            })
            .toSet();
    final alreadyTagged =
        (Process.runSync('git', [
                  'ls-remote',
                  '--tags',
                  '--refs',
                  'origin',
                ], workingDirectory: Directory.current.path).stdout
                as String)
            .split('\n')
            .where((line) => line.isNotEmpty)
            .map((line) => line.split('\t')[1])
            .map((x) => x.substring('refs/tags/'.length))
            .where((x) => x.startsWith('SDK-'))
            .map((x) => x.substring('SDK-'.length))
            .toSet();
    final missing = sdkTags.difference(alreadyTagged);
    var createdTagCount = 0;
    var pushedTagCount = 0;

    if (missing.isNotEmpty) {
      for (final sdkTag in missing) {
        final version = Version.parse(sdkTag);
        if (
        // Old versions of the sdk had no pub or no DEPS file.
        version <= (Version.parse('1.11.3')) ||
            // These version seems to have a broken DEPS file.
            version == Version.parse('1.12.0-dev.5.6') ||
            version == Version.parse('1.12.0-dev.5.7')) {
          continue;
        }
        final depsResult = Process.runSync('git', [
          'show',
          '$sdkTag:DEPS',
        ], workingDirectory: sdkDir);
        if (depsResult.exitCode != 0) {
          stderr.writeln(
            'Failed to get deps for $sdkTag ${depsResult.stderr} '
            '${depsResult.stdout}',
          );
          continue;
        }

        // Could use `gclient getdep -r sdk/third_party/pkg/pub` instead of a
        // regexp. But for some versions that seems to not work well.
        // The regexp
        var pubRev = RegExp(
          '"pub_rev": "([^"]*)"',
        ).firstMatch(depsResult.stdout as String)?.group(1);
        if (pubRev == null || pubRev.isEmpty) {
          stderr.writeln('Failed to get pub rev for $sdkTag ');
          continue;
        }
        if (pubRev.startsWith('@')) {
          pubRev = pubRev.substring(1);
        }

        stdout.writeln('$sdkTag uses pub: $pubRev');
        if (create) {
          final tagResult = Process.runSync('git', [
            '-c', 'user.email=support@pub.dev', //
            '-c', 'user.name=Pub tagging bot', //
            'tag',
            'SDK-$sdkTag',
            pubRev,
            '--annotate',
            '--force',
            '--message', 'SDK $sdkTag', //
          ], workingDirectory: Directory.current.path);
          if (tagResult.exitCode != 0) {
            stderr.writeln(
              'Failed to tag sdk ${tagResult.stderr} ${tagResult.stdout}',
            );
            continue;
          }
          createdTagCount++;
        }
        if (push) {
          final pushResult = Process.runSync('git', [
            'push',
            'origin',
            // Don't run any hooks before pushing.
            '--no-verify',
            'tag',
            'SDK-$sdkTag',
          ], workingDirectory: Directory.current.path);
          if (pushResult.exitCode != 0) {
            stderr.writeln(
              'Failed to push sdk ${pushResult.stderr} ${pushResult.stdout}',
            );
            continue;
          }
          pushedTagCount++;
        }
      }
    }
    if (!create) {
      stdout.writeln('Would have created $createdTagCount tags');
    } else {
      stdout.writeln('Created $createdTagCount tags');
    }
    if (push) {
      stdout.writeln('Pushed $pushedTagCount tags');
    }
  } finally {
    tempDir?.deleteSync(recursive: true);
  }
}
