import '../log.dart' as log;
import '../package_name.dart';

/// Compatibility options describing to which degree pub should check and
/// enforce signatures for hosted dependencies.
///
/// The default is [softIfPresent].
enum SignatureVerificationMode {
  /// Don't verify package signatures at all.
  ignore,

  /// If a hosted package contains a signature, attempt to verify it. If this
  /// verification fails, a warning is printed.
  /// No warning is emitted for packages without a signature.
  softIfPresent,

  /// Attempt to verify signatures, print a warning for packages without a
  /// signature or with an invalid signature.
  soft,

  /// Require signatures for all hosted dependencies.
  ///
  /// In this mode, pub refuses to download dependencies that either don't have
  /// a signature or have an invalid signature.
  strict;

  void handleAbsentSignature(PackageId package) {
    if (this == strict) {
      throw PackageSignatureException.missingSignature(package);
    } else if (this == soft) {
      log.warning('Version ${package.version} of package ${package.name} does '
          'not have a signature.');
    }
  }

  void handleGpgNotAvailable(PackageId package) {
    if (this == strict) {
      throw PackageSignatureException.gpgNotAvailable(package);
    } else {
      log.warning('Version ${package.version} of package ${package.name} has '
          'a signature, but it could not be verified because GPG is not '
          'available.');
    }
  }

  void handleResults(
      PackageId package, List<PackageSignatureResult> foundSignatures) {
    void fail(String message) {
      if (this == strict) {
        throw PackageSignatureException(package, message);
      } else {
        log.warning('${package.name} version ${package.version}: $message');
      }
    }

    if (foundSignatures.length != 1) {
      // We don't currently support packages with multiple signatures.
      fail('Was signed multiple times which is not currently supported.');
      return;
    }

    final checkedSignature = foundSignatures.single;
    if (checkedSignature.isValid) {
      log.message(
          log.green('Package ${package.name}:${package.version} verified - '
              'signed with ${checkedSignature.fingerprint}'));
    } else {
      fail('Invalid signature ${checkedSignature.status}');
    }
  }
}

/// The result of verifying a package's signature.
class PackageSignatureResult {
  /// Whether this signature is fully valid, meaning that:
  ///
  /// - the key with the given [fingerprint] is available in the local key
  ///   chain.
  /// - the signature matches the actual contents of the checked file.
  final bool isValid;

  /// The PGP fingerprint of the key used to sign the contents of this package.
  final String fingerprint;

  /// A human-readable description of this signature's status.
  ///
  /// For valid signatures, this may simply be "Success". For invalid
  /// signatures, this contains a failure description like "expired key".
  ///
  /// Pub will show this status as an explanation if [isValid] is `false`.
  final String status;

  PackageSignatureResult(this.isValid, this.fingerprint, this.status);

  @override
  String toString() {
    return 'PackageSignatureResult(isValid = $isValid, '
        'fingerprint = $fingerprint, status = $status)';
  }
}

class PackageSignatureException implements Exception {
  final PackageId package;
  final String message;

  PackageSignatureException(this.package, this.message);

  PackageSignatureException.missingSignature(this.package)
      : message = 'Does not contain a signature';

  PackageSignatureException.gpgNotAvailable(this.package)
      : message =
            'Pub could not verify this signature because GPG is not available';

  @override
  String toString() {
    return 'Could not verify signature for ${package.name}:${package.version}: '
        '$message';
  }
}
