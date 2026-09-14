// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

/// Elliptic curve parameters for short Weierstrass curves: y^2 = x^3 + a*x + b (mod p).
final class EcCurve {
  /// The curve name (e.g. `secp256r1` or `secp384r1`).
  final String name;

  /// The prime field modulus p.
  final BigInt p;

  /// Curve coefficient a (typically -3 mod p).
  final BigInt a;

  /// Curve coefficient b.
  final BigInt b;

  /// Generator base point X coordinate.
  final BigInt gx;

  /// Generator base point Y coordinate.
  final BigInt gy;

  /// The prime order n of the base point.
  final BigInt n;

  /// The bit length of order n.
  final int bitSize;

  const EcCurve({
    required this.name,
    required this.p,
    required this.a,
    required this.b,
    required this.gx,
    required this.gy,
    required this.n,
    required this.bitSize,
  });

  /// NIST P-256 (secp256r1 / prime256v1 / OID 1.2.840.10045.3.1.7).
  static final EcCurve p256 = EcCurve(
    name: 'secp256r1',
    p: BigInt.parse(
      'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF',
      radix: 16,
    ),
    a: BigInt.parse(
      'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC',
      radix: 16,
    ),
    b: BigInt.parse(
      '5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B',
      radix: 16,
    ),
    gx: BigInt.parse(
      '6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296',
      radix: 16,
    ),
    gy: BigInt.parse(
      '4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5',
      radix: 16,
    ),
    n: BigInt.parse(
      'FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551',
      radix: 16,
    ),
    bitSize: 256,
  );

  /// NIST P-384 (secp384r1 / OID 1.3.132.0.34).
  static final EcCurve p384 = EcCurve(
    name: 'secp384r1',
    p: BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFF0000000000000000FFFFFFFF',
      radix: 16,
    ),
    a: BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFF0000000000000000FFFFFFFC',
      radix: 16,
    ),
    b: BigInt.parse(
      'B3312FA7E23EE7E4988E056BE3F82D19181D9C6EFE8141120314088F5013875AC656398D8A2ED19D2A85C8EDD3EC2AEF',
      radix: 16,
    ),
    gx: BigInt.parse(
      'AA87CA22BE8B05378EB1C71EF320AD746E1D3B628BA79B9859F741E082542A385502F25DBF55296C3A545E3872760AB7',
      radix: 16,
    ),
    gy: BigInt.parse(
      '3617DE4A96262C6F5D9E98BF9292DC29F8F41DBD289A147CE9DA3113B5F0B8C00A60B1CE1D7E819D7A431D7C90EA0E5F',
      radix: 16,
    ),
    n: BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC7634D81F4372DDF581A0DB248B0A77AECEC196ACCC52973',
      radix: 16,
    ),
    bitSize: 384,
  );

  /// Finds an [EcCurve] by standard name or OID.
  ///
  /// Throws a [FormatException] if [identifier] is not a supported curve.
  static EcCurve fromNameOrOid(String identifier) {
    switch (identifier) {
      case 'secp256r1':
      case 'prime256v1':
      case '1.2.840.10045.3.1.7':
        return p256;
      case 'secp384r1':
      case '1.3.132.0.34':
        return p384;
      default:
        throw FormatException('Unsupported elliptic curve: $identifier');
    }
  }

  /// Evaluates (val mod p) normalizing negative results into [0, p-1].
  BigInt modP(BigInt val) {
    final r = val % p;
    return r.isNegative ? r + p : r;
  }

  /// Evaluates (val mod n) normalizing negative results into [0, n-1].
  BigInt modN(BigInt val) {
    final r = val % n;
    return r.isNegative ? r + n : r;
  }
}

/// An affine elliptic curve point (x, y).
final class EcAffinePoint {
  final BigInt x;
  final BigInt y;

  const EcAffinePoint(this.x, this.y);

  /// Decodes an uncompressed SEC 1 point byte sequence (0x04 || X || Y).
  ///
  /// Throws a [FormatException] if [bytes] is not a valid uncompressed point for [curve].
  factory EcAffinePoint.fromUncompressedBytes(Uint8List bytes, EcCurve curve) {
    final expectedLen = 1 + (curve.bitSize ~/ 8) * 2;
    if (bytes.length != expectedLen) {
      throw FormatException(
        'Invalid uncompressed EC point length: expected $expectedLen bytes for ${curve.name}, got ${bytes.length}.',
      );
    }
    if (bytes[0] != 0x04) {
      throw FormatException(
        'Expected uncompressed point prefix 0x04, got 0x${bytes[0].toRadixString(16)}.',
      );
    }
    final coordLen = curve.bitSize ~/ 8;
    var x = BigInt.zero;
    for (var i = 1; i <= coordLen; i++) {
      x = (x << 8) | BigInt.from(bytes[i]);
    }
    var y = BigInt.zero;
    for (var i = 1 + coordLen; i < expectedLen; i++) {
      y = (y << 8) | BigInt.from(bytes[i]);
    }

    // Validate point on curve: y^2 = x^3 + a*x + b (mod p)
    final lhs = (y * y) % curve.p;
    final rhs = (x * x * x + curve.a * x + curve.b) % curve.p;
    if (lhs != rhs) {
      throw const FormatException(
        'Decoded public key point does not lie on the elliptic curve.',
      );
    }

    return EcAffinePoint(x, y);
  }
}

/// An elliptic curve point represented in Jacobian coordinates: (X, Y, Z)
/// where affine x = X / Z^2 and affine y = Y / Z^3.
final class EcJacobianPoint {
  final BigInt x;
  final BigInt y;
  final BigInt z;

  const EcJacobianPoint(this.x, this.y, this.z);

  static final EcJacobianPoint infinity = EcJacobianPoint(
    BigInt.one,
    BigInt.one,
    BigInt.zero,
  );

  bool get isInfinity => z == BigInt.zero;

  factory EcJacobianPoint.fromAffine(EcAffinePoint affine) {
    return EcJacobianPoint(affine.x, affine.y, BigInt.one);
  }

  /// Converts this Jacobian point back to affine coordinates (x, y).
  ///
  /// Returns `null` if this point is at infinity.
  EcAffinePoint? toAffine(EcCurve curve) {
    if (isInfinity) return null;
    final zInv = z.modInverse(curve.p);
    final zInv2 = curve.modP(zInv * zInv);
    final zInv3 = curve.modP(zInv2 * zInv);
    final ax = curve.modP(x * zInv2);
    final ay = curve.modP(y * zInv3);
    return EcAffinePoint(ax, ay);
  }

  /// Point doubling in Jacobian coordinates on curve with a = -3 (mod p).
  EcJacobianPoint doublePoint(EcCurve curve) {
    if (isInfinity || y == BigInt.zero) {
      return infinity;
    }

    final big2 = BigInt.two;
    final big3 = BigInt.from(3);
    final big8 = BigInt.from(8);

    final a = curve.modP(x * x);
    final b = curve.modP(y * y);
    final c = curve.modP(b * b);
    final d = curve.modP(big2 * (curve.modP((x + b) * (x + b)) - a - c));
    final z2 = curve.modP(z * z);
    final e = curve.modP(big3 * (x - z2) * (x + z2));
    final x3 = curve.modP(e * e - big2 * d);
    final y3 = curve.modP(e * (d - x3) - big8 * c);
    final z3 = curve.modP(big2 * y * z);

    return EcJacobianPoint(x3, y3, z3);
  }

  /// Point addition in Jacobian coordinates: this + other.
  EcJacobianPoint add(EcJacobianPoint other, EcCurve curve) {
    if (isInfinity) return other;
    if (other.isInfinity) return this;

    final big2 = BigInt.two;

    final z1z1 = curve.modP(z * z);
    final z2z2 = curve.modP(other.z * other.z);

    final u1 = curve.modP(x * z2z2);
    final u2 = curve.modP(other.x * z1z1);

    final s1 = curve.modP(y * other.z * z2z2);
    final s2 = curve.modP(other.y * z * z1z1);

    if (u1 == u2) {
      if (s1 == s2) {
        return doublePoint(curve);
      }
      return infinity;
    }

    final h = curve.modP(u2 - u1);
    final i = curve.modP((big2 * h) * (big2 * h));
    final j = curve.modP(h * i);
    final r = curve.modP(big2 * (s2 - s1));
    final v = curve.modP(u1 * i);

    final x3 = curve.modP(r * r - j - big2 * v);
    final y3 = curve.modP(r * (v - x3) - big2 * s1 * j);
    final z3 = curve.modP(
      curve.modP((z + other.z) * (z + other.z) - z1z1 - z2z2) * h,
    );

    return EcJacobianPoint(x3, y3, z3);
  }

  /// Scalar multiplication: k * this using double-and-add.
  EcJacobianPoint multiply(BigInt k, EcCurve curve) {
    if (k == BigInt.zero || isInfinity) return infinity;
    var scalar = k % curve.n;
    var result = infinity;
    var addend = this;

    while (scalar > BigInt.zero) {
      if (scalar.isOdd) {
        result = result.add(addend, curve);
      }
      addend = addend.doublePoint(curve);
      scalar >>= 1;
    }
    return result;
  }
}

/// An ECDSA signature comprising (r, s).
final class EcSignature {
  final BigInt r;
  final BigInt s;

  const EcSignature(this.r, this.s);
}

/// An EC public key holding an affine curve point and curve parameters.
final class EcPublicKey {
  final EcAffinePoint point;
  final EcCurve curve;

  const EcPublicKey(this.point, this.curve);
}

/// Self-contained ECDSA signature verifier in pure Dart without external dependencies.
final class PureEcdsaVerifier {
  PureEcdsaVerifier._();

  /// Verifies an ECDSA signature [signature] against a message [digest] using [publicKey].
  ///
  /// The [digest] is the raw output of SHA-256 or SHA-384.
  ///
  /// Returns `true` if and only if the signature is mathematically valid.
  ///
  /// It is an error if [digest] is empty.
  ///
  /// Performance is O(log n) group operations dominated by elliptic curve point multiplication.
  static bool verify({
    required Uint8List digest,
    required EcSignature signature,
    required EcPublicKey publicKey,
  }) {
    ArgumentError.checkNotNull(digest, 'digest');
    ArgumentError.checkNotNull(signature, 'signature');
    ArgumentError.checkNotNull(publicKey, 'publicKey');

    if (digest.isEmpty) {
      throw ArgumentError.value(digest, 'digest', 'Digest must not be empty.');
    }

    final curve = publicKey.curve;
    final r = signature.r;
    final s = signature.s;
    final n = curve.n;

    // 1. Verify that r and s are in [1, n-1]
    if (r < BigInt.one || r >= n || s < BigInt.one || s >= n) {
      return false;
    }

    // 2. Truncate hash if bit length exceeds curve order bit length
    var e = BigInt.zero;
    for (final b in digest) {
      e = (e << 8) | BigInt.from(b);
    }
    final digestBits = digest.length * 8;
    if (digestBits > curve.bitSize) {
      e >>= digestBits - curve.bitSize;
    }

    // 3. Compute w = s^-1 mod n
    final w = s.modInverse(n);

    // 4. Compute u1 = e * w mod n and u2 = r * w mod n
    final u1 = (e * w) % n;
    final u2 = (r * w) % n;

    // 5. Compute R = u1 * G + u2 * Q
    final gJacobian = EcJacobianPoint(curve.gx, curve.gy, BigInt.one);
    final qJacobian = EcJacobianPoint.fromAffine(publicKey.point);

    final u1G = gJacobian.multiply(u1, curve);
    final u2Q = qJacobian.multiply(u2, curve);
    final pointR = u1G.add(u2Q, curve);

    if (pointR.isInfinity) {
      return false;
    }

    final affineR = pointR.toAffine(curve);
    if (affineR == null) return false;

    // 6. Signature is valid if and only if (R.x mod n) == r
    final v = affineR.x % n;
    return v == r;
  }
}
