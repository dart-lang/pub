// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';
import 'package:sigstore/provenance.dart';

import '../exceptions.dart';

/// Exception thrown when package integrity or provenance policies fail.
class PackageProvenanceException extends DataException {
  PackageProvenanceException(super.message);
}

/// Compact provenance summary stored in memory or lockfile.
class ProvenanceInfo {
  final String repository;
  final String? ref;
  final String? commitSha;
  final String? workflowPath;

  ProvenanceInfo({
    required this.repository,
    this.ref,
    this.commitSha,
    this.workflowPath,
  });

  Map<String, dynamic> toJson() => {
    'repository': repository,
    if (ref != null) 'ref': ref,
    if (commitSha != null) 'commitSha': commitSha,
    if (workflowPath != null) 'workflowPath': workflowPath,
  };

  factory ProvenanceInfo.fromJson(Map<String, dynamic> json) {
    return ProvenanceInfo(
      repository: json['repository'] as String? ?? '',
      ref: json['ref'] as String?,
      commitSha: json['commitSha'] as String?,
      workflowPath: json['workflowPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProvenanceInfo &&
      repository == other.repository &&
      ref == other.ref &&
      commitSha == other.commitSha &&
      workflowPath == other.workflowPath;

  @override
  int get hashCode => Object.hash(repository, ref, commitSha, workflowPath);
}

/// Why an attestation is expected for a version of a package, and from which
/// repository the package is expected to have been built.
///
/// The package repository says which versions are attested (`slsa_level` in
/// the version listing), but must not be the only one to say so: a compromised
/// repository could simply stop reporting it. These are the two signals the
/// client has of its own.
sealed class AttestationExpectation {
  /// The repository the package is expected to have been built from.
  String get repository;

  /// Where the expectation comes from, as a sentence for a message about
  /// [package] [version].
  String describe(String package, Version version);

  /// What to do if [package] is not attested on purpose, as a sentence.
  String howToDrop(String package);
}

/// `pubspec.lock` records that this version was verified as built from
/// [repository] when it was last resolved.
///
/// This is the signal that travels with the project: a machine that has never
/// downloaded the package (say, a fresh CI runner) expects the attestation that
/// the machine that resolved the lockfile verified, and dropping it is a change
/// to the lockfile that shows up in code review.
final class LockedProvenance extends AttestationExpectation {
  @override
  final String repository;

  LockedProvenance(this.repository);

  @override
  String describe(String package, Version version) =>
      'pubspec.lock records that $package $version was verified as built from '
      '$repository when it was last resolved.';

  @override
  String howToDrop(String package) =>
      'If $package is no longer attested on purpose, remove the `provenance` '
      'entry of $package from pubspec.lock to accept it unverified.';
}

/// An attestation was verified for a version of this package on this machine,
/// which is recorded in the pub cache (`HostedSource.packageProvenancePath`).
///
/// Versions from [since], the lowest attested version seen, on are expected to
/// be attested. Earlier versions are not: they may predate the first attested
/// version of the package, and must stay installable, for `dart pub downgrade`
/// or an older pin in another project on the same machine.
final class PreviouslyAttested extends AttestationExpectation {
  @override
  final String repository;

  /// The lowest version an attestation was verified for.
  final Version since;

  /// The file in the pub cache recording this, so the message can name it.
  final String path;

  PreviouslyAttested({
    required this.repository,
    required this.since,
    required this.path,
  });

  @override
  String describe(String package, Version version) =>
      'an attestation from $repository was verified for $package $since on '
      'this machine, so versions from $since on are expected to be attested.';

  @override
  String howToDrop(String package) =>
      'If $package is no longer attested on purpose, delete `$path` to stop '
      'expecting attestations for it on this machine.';
}

/// The client-side policy for the provenance of downloaded packages.
///
/// What a verified attestation proves is that the archive was built by a
/// trusted publishing workflow from the GitHub repository the archive's own
/// pubspec names. Whether that repository is the one authorized to publish the
/// package is established by the package repository at publish time, not here:
/// the client can only check that an attestation is there when one is expected,
/// and notice when the repository changes.
class ProvenancePolicy {
  /// Checks [verified], the provenance established by verifying the attestation
  /// of [package] [version] (`null` if it was not attested), against
  /// [expectation] (`null` if no attestation was expected).
  ///
  /// Throws a [PackageProvenanceException] if an attestation was expected and
  /// there is none, naming [repositoryUrl], the package repository, and what to
  /// do about it. Reports a package built from another repository than
  /// expected to [onRepositoryChange], or throws if [fatalOnRepositoryChange].
  static void check({
    required String package,
    required Version version,
    required ProvenanceInfo? verified,
    required AttestationExpectation? expectation,
    required String repositoryUrl,
    bool fatalOnRepositoryChange = false,
    void Function(String message)? onRepositoryChange,
  }) {
    if (expectation == null) return;

    if (verified == null) {
      throw PackageProvenanceException('''
Package $package $version is not attested, but an attestation is expected:
${expectation.describe(package, version)}

The package repository `$repositoryUrl` served no attestation for it.
${expectation.howToDrop(package)}
''');
    }

    if (!repositoriesMatch(expectation.repository, verified.repository)) {
      final message =
          'Package $package $version is attested as built from '
          '${verified.repository}, but '
          '${expectation.describe(package, version)}';
      if (fatalOnRepositoryChange) {
        throw PackageProvenanceException(message);
      }
      onRepositoryChange?.call(message);
    }
  }

  /// Whether [a] and [b] name the same repository.
  ///
  /// GitHub repositories compare by owner and name, case-insensitively and
  /// regardless of the URL form (see [GitHubRepository.tryParse]); anything
  /// else compares as a string.
  static bool repositoriesMatch(String a, String b) {
    final repoA = GitHubRepository.tryParse(a);
    final repoB = GitHubRepository.tryParse(b);
    if (repoA != null && repoB != null) return repoA == repoB;
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }
}
