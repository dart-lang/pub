// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Parsing of the SLSA build provenance carried in a Sigstore bundle.
///
/// `package:sigstore` verifies the cryptographic material of a bundle, and
/// exposes the signer identity from the Fulcio certificate. It does not expose
/// the signed payload, so we parse the DSSE envelope of the bundle ourselves.
///
/// This is safe as long as the exact same bundle JSON is handed to
/// `package:sigstore` for signature verification and to
/// [BuildProvenance.parseBundle] - the payload we inspect here is then
/// guaranteed to be the payload the signature was verified over. To make it
/// hard to get this wrong, `PubAttestationVerifier.verify` takes the bundle as
/// JSON and does both.
library;

import 'dart:convert';

/// The OIDC issuer of tokens minted by GitHub Actions.
const githubActionsOidcIssuer = 'https://token.actions.githubusercontent.com';

const _inTotoStatementType = 'https://in-toto.io/Statement/v1';
const _inTotoPayloadType = 'application/vnd.in-toto+json';
const _slsaProvenancePredicateType = 'https://slsa.dev/provenance/v1';

/// A GitHub repository, identified by its [owner] and [name].
///
/// GitHub treats owner and repository names case-insensitively, and so does
/// [operator ==].
class GitHubRepository {
  final String owner;
  final String name;

  GitHubRepository(this.owner, this.name);

  /// Parses a reference to a GitHub repository, or returns `null` if [source]
  /// does not denote one.
  ///
  /// Accepts the forms used in `pubspec.yaml`'s `repository:` field and in
  /// SLSA provenance statements:
  ///
  /// * `https://github.com/<owner>/<repo>`
  /// * `https://github.com/<owner>/<repo>.git`
  /// * `git+https://github.com/<owner>/<repo>@<ref>`
  /// * `https://github.com/<owner>/<repo>/tree/<ref>/<dir>` (monorepos)
  ///
  /// Everything after `<repo>` is ignored: a package living in a subdirectory
  /// of a monorepo is published from the repository as a whole, so the
  /// subdirectory carries no information for verification.
  static GitHubRepository? tryParse(String source) {
    var s = source.trim();
    if (s.isEmpty) return null;
    // Provenance uses SPDX-style download locations such as
    // `git+https://github.com/dart-lang/pub@refs/tags/v1.0.0`.
    if (s.startsWith('git+')) {
      s = s.substring('git+'.length);
      final at = s.lastIndexOf('@');
      if (at > 0) s = s.substring(0, at);
    }
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // Compare the full host: `endsWith('github.com')` would also accept
    // `github.com.example.com`.
    final host = uri.host.toLowerCase();
    if (host != 'github.com' && host != 'www.github.com') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final owner = segments[0];
    var name = segments[1];
    if (name.endsWith('.git')) {
      name = name.substring(0, name.length - '.git'.length);
    }
    if (owner.isEmpty || name.isEmpty) return null;
    return GitHubRepository(owner, name);
  }

  /// `<owner>/<name>`, as used by the GitHub API and in OIDC claims.
  String get slug => '$owner/$name';

  /// The canonical url of this repository.
  String get url => 'https://github.com/$owner/$name';

  @override
  bool operator ==(Object other) =>
      other is GitHubRepository &&
      owner.toLowerCase() == other.owner.toLowerCase() &&
      name.toLowerCase() == other.name.toLowerCase();

  @override
  int get hashCode => Object.hash(owner.toLowerCase(), name.toLowerCase());

  @override
  String toString() => url;
}

/// The identity of the workflow that signed an attestation.
///
/// This is the `job_workflow_ref` claim of the GitHub Actions OIDC token,
/// which Fulcio puts in the subject alternative name of the signing
/// certificate. For a reusable workflow it identifies the *reusable* workflow
/// - the trusted builder - and not the repository that called it.
class GitHubWorkflowIdentity {
  final GitHubRepository repository;

  /// The path of the workflow file within [repository], e.g.
  /// `.github/workflows/publish.yml`.
  final String path;

  /// The git ref the workflow ran at, e.g. `refs/tags/v2`.
  final String ref;

  GitHubWorkflowIdentity({
    required this.repository,
    required this.path,
    required this.ref,
  });

  /// Parses an identity of the form
  /// `https://github.com/<owner>/<repo>/<path>@<ref>`.
  static GitHubWorkflowIdentity? tryParse(String identity) {
    final at = identity.lastIndexOf('@');
    if (at <= 0) return null;
    final url = identity.substring(0, at);
    final ref = identity.substring(at + 1);
    if (ref.isEmpty) return null;
    final repository = GitHubRepository.tryParse(url);
    if (repository == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 3) return null;
    return GitHubWorkflowIdentity(
      repository: repository,
      path: segments.sublist(2).join('/'),
      ref: ref,
    );
  }

  /// `<owner>/<repo>/<path>` - the workflow without the ref it ran at.
  String get workflow => '${repository.slug}/$path';

  @override
  String toString() => '${repository.url}/$path@$ref';
}

/// An entry of the `subject` list of an in-toto statement.
class ProvenanceSubject {
  final String name;

  /// The lowercase hex-encoded sha256 digest, or `null` if the subject is not
  /// identified by a sha256.
  final String? sha256;

  ProvenanceSubject(this.name, this.sha256);
}

/// The SLSA build provenance of an artifact, as carried in the DSSE envelope
/// of a Sigstore bundle.
class BuildProvenance {
  /// The repository the build ran for.
  ///
  /// This is `github.repository` of the workflow run - for a reusable
  /// workflow, the repository that *called* the trusted builder. It is filled
  /// in by GitHub from the run context and cannot be set by the caller.
  final GitHubRepository sourceRepository;

  /// The ref of [sourceRepository] the build ran at, e.g. `refs/tags/v1.0.0`.
  final String? sourceRef;

  /// The path of the caller's workflow file.
  final String? workflowPath;

  /// The commit the build ran at, if recorded.
  final String? commitSha;

  /// The builder as self-reported in the statement.
  ///
  /// Note that the authoritative statement about who signed is the certificate
  /// identity, not this field.
  final GitHubWorkflowIdentity? builder;

  final List<ProvenanceSubject> subjects;

  BuildProvenance({
    required this.sourceRepository,
    required this.sourceRef,
    required this.workflowPath,
    required this.commitSha,
    required this.builder,
    required this.subjects,
  });

  /// Extracts the build provenance from the DSSE envelope of the Sigstore
  /// bundle in [bundleJson].
  ///
  /// Throws a [FormatException] if [bundleJson] is not a bundle carrying a
  /// SLSA build provenance statement.
  ///
  /// This does not validate any signature. Only use the result if
  /// `package:sigstore` has verified the very same [bundleJson].
  factory BuildProvenance.parseBundle(String bundleJson) {
    final Object? decoded;
    try {
      decoded = json.decode(bundleJson);
    } on FormatException catch (e) {
      throw FormatException('Attestation is not valid JSON: ${e.message}');
    }
    final bundle = _expectMap(decoded, 'bundle');
    final envelope = bundle['dsseEnvelope'];
    if (envelope == null) {
      throw const FormatException(
        'Attestation does not contain a `dsseEnvelope`, so it carries no '
        'build provenance.',
      );
    }
    final dsse = _expectMap(envelope, 'dsseEnvelope');
    final payloadType = dsse['payloadType'];
    if (payloadType != _inTotoPayloadType) {
      throw FormatException(
        'Attestation payload has type `$payloadType`, '
        'expected `$_inTotoPayloadType`.',
      );
    }
    final encodedPayload = dsse['payload'];
    if (encodedPayload is! String) {
      throw const FormatException('Attestation has no `payload`.');
    }
    final Object? decodedStatement;
    try {
      decodedStatement = json.decode(
        utf8.decode(base64.decode(encodedPayload)),
      );
    } on FormatException catch (e) {
      throw FormatException(
        'Attestation payload is not valid base64-encoded JSON: ${e.message}',
      );
    }
    final statement = _expectMap(decodedStatement, 'statement');

    final type = statement['_type'];
    if (type != _inTotoStatementType) {
      throw FormatException(
        'Attestation statement has type `$type`, '
        'expected `$_inTotoStatementType`.',
      );
    }
    final predicateType = statement['predicateType'];
    if (predicateType != _slsaProvenancePredicateType) {
      throw FormatException(
        'Attestation has predicate type `$predicateType`, '
        'expected `$_slsaProvenancePredicateType`.',
      );
    }

    final subjects = <ProvenanceSubject>[];
    final subjectList = statement['subject'];
    if (subjectList is! List || subjectList.isEmpty) {
      throw const FormatException('Attestation statement has no `subject`.');
    }
    for (final subject in subjectList) {
      final s = _expectMap(subject, 'subject');
      final name = s['name'];
      if (name is! String) {
        throw const FormatException('Attestation subject has no `name`.');
      }
      final digest = s['digest'];
      final sha256 = digest is Map ? digest['sha256'] : null;
      subjects.add(
        ProvenanceSubject(name, sha256 is String ? sha256.toLowerCase() : null),
      );
    }

    final predicate = _expectMap(statement['predicate'], 'predicate');
    final buildDefinition = _expectMap(
      predicate['buildDefinition'],
      'buildDefinition',
    );
    final externalParameters = _expectMap(
      buildDefinition['externalParameters'],
      'externalParameters',
    );
    final workflow = _expectMap(externalParameters['workflow'], 'workflow');

    final repositoryField = workflow['repository'];
    if (repositoryField is! String) {
      throw const FormatException(
        'Attestation does not state the repository it was built from.',
      );
    }
    final sourceRepository = GitHubRepository.tryParse(repositoryField);
    if (sourceRepository == null) {
      throw FormatException(
        'Attestation was built from `$repositoryField`, which is not a GitHub '
        'repository. Only GitHub is supported for now.',
      );
    }

    String? commitSha;
    final resolvedDependencies = buildDefinition['resolvedDependencies'];
    if (resolvedDependencies is List) {
      for (final dependency in resolvedDependencies) {
        if (dependency is! Map) continue;
        final uri = dependency['uri'];
        if (uri is! String) continue;
        if (GitHubRepository.tryParse(uri) != sourceRepository) continue;
        final digest = dependency['digest'];
        final gitCommit = digest is Map ? digest['gitCommit'] : null;
        if (gitCommit is String) {
          commitSha = gitCommit;
          break;
        }
      }
    }

    GitHubWorkflowIdentity? builder;
    final runDetails = predicate['runDetails'];
    if (runDetails is Map) {
      final builderField = runDetails['builder'];
      final id = builderField is Map ? builderField['id'] : null;
      if (id is String) builder = GitHubWorkflowIdentity.tryParse(id);
    }

    final ref = workflow['ref'];
    final path = workflow['path'];
    return BuildProvenance(
      sourceRepository: sourceRepository,
      sourceRef: ref is String ? ref : null,
      workflowPath: path is String ? path : null,
      commitSha: commitSha,
      builder: builder,
      subjects: subjects,
    );
  }
}

Map<String, dynamic> _expectMap(Object? value, String what) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Attestation `$what` is not a JSON object.');
  }
  return value;
}
