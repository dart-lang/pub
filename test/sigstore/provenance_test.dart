// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/sigstore/provenance.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  group('GitHubRepository.tryParse', () {
    void expectRepo(String source, String? slug) {
      expect(
        GitHubRepository.tryParse(source)?.slug,
        slug,
        reason: 'parsing "$source"',
      );
    }

    test('accepts the forms found in pubspecs and provenance', () {
      expectRepo('https://github.com/dieter/helpful', 'dieter/helpful');
      expectRepo('https://github.com/dieter/helpful/', 'dieter/helpful');
      expectRepo('https://github.com/dieter/helpful.git', 'dieter/helpful');
      expectRepo('http://github.com/dieter/helpful', 'dieter/helpful');
      expectRepo('https://www.github.com/dieter/helpful', 'dieter/helpful');
      expectRepo('  https://github.com/dieter/helpful  ', 'dieter/helpful');
      expectRepo(
        'git+https://github.com/dieter/helpful@refs/tags/v1.0.0',
        'dieter/helpful',
      );
    });

    test('ignores the subdirectory of a monorepo package', () {
      expectRepo(
        'https://github.com/dart-lang/tools/tree/main/pkgs/graphs',
        'dart-lang/tools',
      );
    });

    test('rejects everything that is not a GitHub repository', () {
      expectRepo('https://gitlab.com/dieter/helpful', null);
      expectRepo('https://example.com/dieter/helpful', null);
      // A suffix check on the host would accept this one.
      expectRepo('https://github.com.evil.example/dieter/helpful', null);
      expectRepo('https://notgithub.com/dieter/helpful', null);
      expectRepo('https://github.com/dieter', null);
      expectRepo('https://github.com/', null);
      expectRepo('ftp://github.com/dieter/helpful', null);
      expectRepo('dieter/helpful', null);
      expectRepo('', null);
    });

    test('compares case-insensitively but does not match by suffix', () {
      final helpful = GitHubRepository.tryParse(
        'https://github.com/dieter/helpful',
      );
      expect(
        helpful,
        GitHubRepository.tryParse('https://github.com/Dieter/Helpful.git'),
      );
      // `endsWith`-style matching would consider these equal.
      expect(
        helpful,
        isNot(
          GitHubRepository.tryParse('https://github.com/evil-dieter/helpful'),
        ),
      );
      expect(
        helpful,
        isNot(GitHubRepository.tryParse('https://github.com/evil/helpful')),
      );
    });
  });

  group('GitHubWorkflowIdentity.tryParse', () {
    test('splits repository, path and ref', () {
      final identity =
          GitHubWorkflowIdentity.tryParse(
            'https://github.com/dart-lang/setup-dart/.github/workflows/'
            'publish.yml@refs/tags/v2',
          )!;
      expect(identity.repository.slug, 'dart-lang/setup-dart');
      expect(identity.path, '.github/workflows/publish.yml');
      expect(identity.ref, 'refs/tags/v2');
      expect(
        identity.workflow,
        'dart-lang/setup-dart/.github/workflows/publish.yml',
      );
    });

    test('rejects identities without a workflow path or ref', () {
      expect(
        GitHubWorkflowIdentity.tryParse(
          'https://github.com/dart-lang/setup-dart@refs/tags/v2',
        ),
        isNull,
      );
      expect(
        GitHubWorkflowIdentity.tryParse(
          'https://github.com/dart-lang/setup-dart/.github/workflows/p.yml',
        ),
        isNull,
      );
      expect(
        GitHubWorkflowIdentity.tryParse('mailto:someone@example.com'),
        isNull,
      );
    });
  });

  group('BuildProvenance.parseBundle', () {
    test('extracts the repository, ref, commit and subjects', () {
      final provenance = BuildProvenance.parseBundle(
        buildProvenanceBundleJson(
          subjectName: 'helpful-0.1.2.tar.gz',
          subjectSha256: 'abc123',
          repository: 'https://github.com/dieter/helpful',
          ref: 'refs/tags/v0.1.2',
          commitSha: 'deadbeef',
        ),
      );
      expect(provenance.sourceRepository.slug, 'dieter/helpful');
      expect(provenance.sourceRef, 'refs/tags/v0.1.2');
      expect(provenance.commitSha, 'deadbeef');
      expect(provenance.subjects.single.name, 'helpful-0.1.2.tar.gz');
      expect(provenance.subjects.single.sha256, 'abc123');
      expect(
        provenance.builder!.workflow,
        'dart-lang/setup-dart/.github/workflows/publish.yml',
      );
    });

    test('rejects a bundle without a DSSE envelope', () {
      // The bundle of a plain artifact signature carries no statement at all -
      // there is nothing to bind it to a package.
      expect(
        () => BuildProvenance.parseBundle(sampleBundleJson),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('carries no build provenance'),
          ),
        ),
      );
    });

    test('rejects a statement that is not SLSA build provenance', () {
      expect(
        () => BuildProvenance.parseBundle(
          buildProvenanceBundleJson(
            predicateType: 'https://slsa.dev/verification_summary/v1',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BuildProvenance.parseBundle(
          buildProvenanceBundleJson(payloadType: 'application/json'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a build from a non-GitHub repository', () {
      expect(
        () => BuildProvenance.parseBundle(
          buildProvenanceBundleJson(
            repository: 'https://gitlab.com/dieter/helpful',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not a GitHub repository'),
          ),
        ),
      );
    });

    test('rejects malformed input', () {
      expect(
        () => BuildProvenance.parseBundle('not json'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => BuildProvenance.parseBundle('{"dsseEnvelope": 42}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
