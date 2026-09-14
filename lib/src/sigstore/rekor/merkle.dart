import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../crypto/der.dart';

/// Implements RFC 6962 Merkle tree audit path inclusion verification.
final class MerkleVerifier {
  MerkleVerifier._();

  /// Computes the RFC 6962 leaf hash for [leafData]: `SHA-256(0x00 || leafData)`.
  ///
  /// Performance is O(n) where n is [leafData.length].
  static Uint8List computeLeafHash(List<int> leafData) {
    return Uint8List.fromList(crypto.sha256.convert([0x00, ...leafData]).bytes);
  }

  /// Computes the RFC 6962 interior node hash for [left] and [right]:
  /// `SHA-256(0x01 || left || right)`.
  static Uint8List computeInteriorHash(List<int> left, List<int> right) {
    return Uint8List.fromList(
      crypto.sha256.convert([0x01, ...left, ...right]).bytes,
    );
  }

  /// Verifies an RFC 6962 Merkle tree audit path inclusion proof.
  ///
  /// Evaluates whether the leaf at [logIndex] in a tree of size [treeSize] with leaf
  /// hash [leafHash] and audit path [proofHashes] computes the expected [rootHash].
  ///
  /// Returns `true` if and only if the inclusion proof is valid.
  ///
  /// It is an error if [logIndex] is negative, or if [logIndex] >= [treeSize].
  ///
  /// Performance is O(m) hash evaluations where m is [proofHashes.length] (typically O(log treeSize)).
  static bool verifyInclusion({
    required int logIndex,
    required int treeSize,
    required Uint8List leafHash,
    required List<Uint8List> proofHashes,
    required Uint8List rootHash,
  }) {
    if (logIndex < 0 || logIndex >= treeSize) {
      throw ArgumentError.value(
        logIndex,
        'logIndex',
        'Must be between 0 and treeSize - 1 ($treeSize).',
      );
    }
    if (treeSize <= 0) {
      throw ArgumentError.value(treeSize, 'treeSize', 'Must be positive.');
    }

    var fn = logIndex;
    var sn = treeSize - 1;
    var r = leafHash;

    for (final p in proofHashes) {
      if (sn == 0) return false;
      if (fn.isOdd || fn == sn) {
        r = computeInteriorHash(p, r);
        while (fn.isEven && fn != 0) {
          fn >>= 1;
          sn >>= 1;
        }
      } else {
        r = computeInteriorHash(r, p);
      }
      fn >>= 1;
      sn >>= 1;
    }

    return sn == 0 && DerUtils.bytesEqual(r, rootHash);
  }
}
