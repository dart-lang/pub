// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
library;

import 'package:pub/src/sigstore/provenance.dart';
import 'package:pub/src/sigstore/verifier.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

const _trustedSigner =
    'https://github.com/dart-lang/setup-dart/.github/workflows/'
    'publish.yml@refs/tags/v2';

const _archiveSha256 =
    '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

/// Runs the policy for `helpful 1.0.0`, published from `dieter/helpful`.
List<String> check({
  String packageName = 'helpful',
  String version = '1.0.0',
  String archiveSha256 = _archiveSha256,
  String subjectName = 'helpful-1.0.0.tar.gz',
  String subjectSha256 = _archiveSha256,
  String repository = 'https://github.com/dieter/helpful',
  String? builderId = _trustedSigner,
  String signerIdentity = _trustedSigner,
  String? oidcIssuer = githubActionsOidcIssuer,
  String? expectedRepository = 'https://github.com/dieter/helpful',
  bool requireRepository = true,
  bool requireTaggedSignerRef = true,
}) {
  return checkProvenancePolicy(
    packageName: packageName,
    packageVersion: Version.parse(version),
    archiveSha256: archiveSha256,
    provenance: BuildProvenance.parseBundle(
      buildProvenanceBundleJson(
        subjectName: subjectName,
        subjectSha256: subjectSha256,
        repository: repository,
        builderId: builderId,
      ),
    ),
    signer: GitHubWorkflowIdentity.tryParse(signerIdentity)!,
    oidcIssuer: oidcIssuer,
    expectedRepository: expectedRepository,
    requireRepository: requireRepository,
    requireTaggedSignerRef: requireTaggedSignerRef,
  );
}

void main() {
  test(
    'accepts a package built by the trusted workflow from its repository',
    () {
      expect(check(), isEmpty);
    },
  );

  group('signer', () {
    test('rejects a signature from an untrusted workflow', () {
      // This is the case the client used to accept: a cryptographically valid
      // bundle from any GitHub Actions workflow in any repository.
      final errors = check(
        signerIdentity:
            'https://github.com/evil/evil/.github/workflows/sign.yml@'
            'refs/tags/v1',
        builderId:
            'https://github.com/evil/evil/.github/workflows/sign.yml@'
            'refs/tags/v1',
      );
      expect(errors, hasLength(1));
      expect(errors.single, contains('not a workflow trusted to publish'));
    });

    test('rejects the trusted workflow at a mutable ref', () {
      final errors = check(
        signerIdentity:
            'https://github.com/dart-lang/setup-dart/.github/workflows/'
            'publish.yml@refs/heads/main',
        builderId:
            'https://github.com/dart-lang/setup-dart/.github/workflows/'
            'publish.yml@refs/heads/main',
      );
      expect(errors.single, contains('only tagged releases'));
    });

    test('rejects a builder that disagrees with the signer', () {
      final errors = check(
        builderId:
            'https://github.com/evil/evil/.github/workflows/sign.yml@'
            'refs/tags/v1',
      );
      expect(errors.single, contains('but was signed by'));
    });

    test('rejects a non-GitHub issuer', () {
      final errors = check(oidcIssuer: 'https://accounts.google.com');
      expect(errors.single, contains('was issued by'));
    });
  });

  group('subject', () {
    test('rejects an attestation for another package', () {
      // All packages are signed by the same workflow, so without this check a
      // compromised repository could serve the archive and attestation of one
      // package under the name of another.
      final errors = check(subjectName: 'evil-1.0.0.tar.gz');
      expect(errors.single, contains('not for "helpful-1.0.0.tar.gz"'));
    });

    test('rejects an attestation for another version', () {
      final errors = check(subjectName: 'helpful-1.0.1.tar.gz');
      expect(errors.single, contains('not for "helpful-1.0.0.tar.gz"'));
    });

    test('rejects an attestation for other bytes', () {
      final errors = check(subjectSha256: 'a' * 64);
      expect(errors.single, contains('but the downloaded archive has sha256'));
    });
  });

  group('repository', () {
    test('rejects a build from another repository', () {
      final errors = check(repository: 'https://github.com/evil/helpful');
      expect(errors.single, contains('was built from'));
    });

    test('rejects a repository that only matches by suffix', () {
      final errors = check(
        repository: 'https://github.com/evil-dieter/helpful',
      );
      expect(errors.single, contains('was built from'));
    });

    test('accepts a monorepo subdirectory url', () {
      expect(
        check(
          repository: 'https://github.com/dart-lang/tools',
          expectedRepository:
              'https://github.com/dart-lang/tools/tree/main/pkgs/helpful',
        ),
        isEmpty,
      );
    });

    test('accepts a differently spelled url for the same repository', () {
      expect(
        check(expectedRepository: 'https://github.com/Dieter/helpful.git'),
        isEmpty,
      );
    });

    test('rejects a package that does not declare a repository', () {
      // Without a repository in the pubspec the attestation is unbound: it
      // only says that some trusted workflow built these bytes.
      final errors = check(expectedRepository: null);
      expect(errors.single, contains('does not have a `repository` field'));
      expect(check(expectedRepository: '  '), hasLength(1));
    });

    test('rejects a non-GitHub repository in the pubspec', () {
      final errors = check(
        expectedRepository: 'https://gitlab.com/dieter/helpful',
      );
      expect(errors.single, contains('only supported for GitHub'));
    });
  });
}
