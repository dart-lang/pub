// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:source_span/source_span.dart';

import '../ignore.dart';
import '../validator.dart';

/// [Utf8Codec] which allows malformed strings.
const _utf8AllowMalformed = Utf8Codec(allowMalformed: true);

/// Link to the documentation for the `false_secrets` key in `pubspec.yaml`.
const _falseSecretsDocumentationLink = 'https://dart.dev/go/false-secrets';

/// A validator that validates attempts to find secrets that are about to be
/// accidentally leaked.
@sealed
class LeakDetectionValidator extends Validator {
  @override
  Future<void> validate() async {
    // Load `false_secrets` from `pubspec.yaml`.
    final falseSecrets = Ignore(
      entrypoint.root.pubspec.falseSecrets,
      ignoreCase: Platform.isWindows || Platform.isMacOS,
    );

    final pool = Pool(20); // don't read more than 20 files concurrently!
    final leaks = await Future.wait(files.map((f) async {
      final relPath = entrypoint.root.relative(f);

      // Skip files matching patterns in `false_secrets`
      final nixPath = p.posix.joinAll(p.split(relPath));
      if (falseSecrets.ignores(nixPath)) {
        return <LeakMatch>[];
      }

      String text;
      try {
        // On Windows, we can't open some files without normalizing them
        final file = File(p.normalize(p.absolute(f)));
        text = await pool.withResource(
          () async => await file.readAsString(encoding: _utf8AllowMalformed),
        );
      } on IOException {
        // Pass, ignore files we can't read, let something else error later!
        return <LeakMatch>[];
      }

      return leakPatterns
          .map((p) => p.findPossibleLeaks(relPath, text))
          .expand((i) => i);
    })).then((lists) => lists.expand((i) => i).toList());

    // Convert detected leaks to errors, if we have more than 3 then we return
    // the first 2 leaks, followed by a general summary of leaks.
    //
    // This way we never return more than 3 errors, and we always show a 2-3
    // samples leaks that very concretely demonstrates the strings we're
    // worried about leaking.
    if (leaks.length > 3) {
      errors.addAll(leaks.take(2).map((leak) => leak.toString()));

      final files = leaks
          .map((leak) => leak.span.sourceUrl!.toFilePath(windows: false))
          .toSet()
          .toList(growable: false)
        ..sort();
      final s = files.length > 1 ? 's' : '';

      errors.add([
        '${leaks.length} potential leaks detected in ${files.length} file$s:',
        ...files.take(10).map((f) => '- /$f'),
        if (files.length > 10) '...',
        '',
        'Add git-ignore style patterns to `false_secrets` in `pubspec.yaml`',
        'to ignore this. See $_falseSecretsDocumentationLink'
      ].join('\n'));
    } else if (leaks.isNotEmpty) {
      // If we have 3 leaks we return all leaks, but only include the message
      // about how ignore them in the last warning.
      final lastLeak = leaks.removeLast();
      errors.addAll([
        ...leaks.take(2).map((leak) => leak.toString()),
        [
          lastLeak.toString(),
          'Add a git-ignore style pattern to `false_secrets` in `pubspec.yaml`',
          'to ignore this. See $_falseSecretsDocumentationLink',
        ].join('\n'),
      ]);
    }
  }
}

/// Instance of a match against a [LeakPattern].
@sealed
class LeakMatch {
  final LeakPattern pattern;
  final SourceSpan span;

  LeakMatch(this.pattern, this.span);

  @override
  String toString() =>
      span.message('Potential leak of ${pattern.kind} detected.');
}

/// Definition of a pattern for detecting accidentally leaked secrets.
@visibleForTesting
@sealed
class LeakPattern {
  /// Human readable name for the kind of secret this pattern matches.
  final String kind;

  /// Pattern that matches a secret of given [kind].
  final RegExp _pattern;

  /// List of allow-listed patterns that are always known to be false-positives.
  ///
  /// Examples include dummy values commonly used for in documentation for
  /// illustrative purposes.
  final List<Pattern> _allowed;

  /// Entropy threshold for matched groups in [_pattern].
  ///
  /// This is a map from _group identifier_ to entropy threshold. This is
  /// inspired by [1] where researches ignore detected secrets that have entropy
  /// less than 3 standard deviations from the mean of secrets of this [kind].
  ///
  /// To compute the mean entropy of a specific [kind] of secret 10 instances
  /// of the secret is generated (and immediately revoked).
  ///
  /// [1]: https://www.ndss-symposium.org/wp-content/uploads/2019/02/ndss2019_04B-3_Meli_paper.pdf
  final Map<int, double> _entropyThresholds;

  /// Test vectors that will have a match in [findPossibleLeaks].
  @visibleForTesting
  final List<String> testsWithLeaks;

  /// Test vectors that will not have a match in [findPossibleLeaks].
  @visibleForTesting
  final List<String> testsWithNoLeaks;

  LeakPattern._({
    required this.kind,
    required String pattern,
    Iterable<Pattern> allowed = const <Pattern>[],
    Map<int, double> entropyThresholds = const <int, double>{},
    Iterable<String> testsWithLeaks = const <String>[],
    Iterable<String> testsWithNoLeaks = const <String>[],
  })  : _pattern = RegExp(pattern),
        _allowed = List.unmodifiable(allowed),
        _entropyThresholds = Map.unmodifiable(entropyThresholds),
        testsWithLeaks = List.unmodifiable(testsWithLeaks),
        testsWithNoLeaks = List.unmodifiable(testsWithNoLeaks);

  /// Find possible leaks using this [LeakPattern].
  ///
  /// A possible [LeakMatch] is found when:
  ///  * [_pattern] is matched,
  ///  * no pattern in [_allowed] is matched,
  ///  * Captured group have a entropy higher than [_entropyThresholds] requires
  ///    for the given _group identifier_, and,
  Iterable<LeakMatch> findPossibleLeaks(String file, String content) sync* {
    final source = SourceFile.fromString(content, url: file);
    for (final m in _pattern.allMatches(content)) {
      if (_allowed.any((s) => m.group(0)!.contains(s))) {
        continue;
      }
      if (_entropyThresholds.entries
          .any((entry) => _entropy(m.group(entry.key)!) < entry.value)) {
        continue;
      }

      yield LeakMatch(
        this,
        source.span(m.start, m.start + m.group(0)!.length),
      );
    }
  }
}

/// Compute Shannon entropy [1] of [s].
///
/// [1]: https://en.wikipedia.org/w/index.php?title=Entropy_(information_theory)&oldid=1033726547
double _entropy(String s) {
  final length = s.length.toDouble();
  final frequencies = <int, int>{};
  for (final rune in s.runes) {
    frequencies[rune] = (frequencies[rune] ?? 0) + 1;
  }
  var sum = 0.0;
  for (final frequency in frequencies.values) {
    sum -= frequency / length * (log(frequency / length) / log(2));
  }
  return sum;
}

/// Common patterns for detecting accidentally leaked secrets.
///
/// These patterns are adopted from [1] and [2] with lots of tweaks around:
///  * Boundary detection,
///  * Common allow-listed patterns,
///  * Special file patterns to ignore,
///  * entropy threshold for matched groups,
///  * Examples for correctness testing.
///
/// [1]: https://www.ndss-symposium.org/wp-content/uploads/2019/02/ndss2019_04B-3_Meli_paper.pdf
/// [2]: https://github.com/awslabs/git-secrets
@visibleForTesting
final leakPatterns = List<LeakPattern>.unmodifiable([
  LeakPattern._(
    kind: 'AWS Access Key',
    // Unique identifiers are documented here:
    // https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_identifiers.html#identifiers-unique-ids
    //
    // Maximum length of a access key is specified as 128 here:
    // https://docs.aws.amazon.com/IAM/latest/APIReference/API_AccessKey.html#API_AccessKey_Contents
    pattern:
        r'[^A-Z0-9]((?:A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{12,128})[^A-Z0-9]',
    allowed: [
      // Commonly used in AWS documentation and code samples as an example key.
      'AKIAIOSFODNN7EXAMPLE',
      // Test credentials for play.min.io, see:
      // https://docs.min.io/docs/how-to-use-paperclip-with-minio-server.html
      'Q3AM3UQ867SPQQA43P2F',
    ],
    entropyThresholds: {
      // Add entropy requirement for the first group
      //
      // Entropy from the 10 example keys below:
      //      Mean:     3.756
      //      Std.dev.:	0.145
      //
      // Assuming a normal distribution we get 99.7% within 3 std.dev. from mean
      // so using this as a lower bound seems reasonable:
      //      Mean - 3 * std.dev. = 3.322
      1: 3.32,
    },
    // Added a requirement that start/end is different from [^A-Z0-9]
    // This minimizes false positives in large base64 blobs
    testsWithLeaks: [
      // Generated with AWS Console and immediately deactivated and deleted!
      'final accessKey = "AKIAVBOGPFGGW6HQOSMY";',
      'final accessKey = "AKIAVBOGPFGG77LJO6ZC";',
      'final accessKey = "AKIAVBOGPFGG3Y4MQ6LI";',
      'final accessKey = "AKIAVBOGPFGG3FLAFH4W";',
      'final accessKey = "AKIAVBOGPFGGQDCE4MVN";',
      'final accessKey = "AKIAVBOGPFGGVHHAE7EL";',
      'final accessKey = "AKIAVBOGPFGG23S677TL";',
      'final accessKey = "AKIAVBOGPFGG2GISUKVC";',
      'final accessKey = "AKIAVBOGPFGGQCCVD5NH";',
      'final accessKey = "AKIAVBOGPFGG6R2WWNYY";',
    ],
  ),
  LeakPattern._(
    kind: 'AWS Secret Key',
    pattern:
        r'''(?:"|')?(?:AWS|aws|Aws)?_?(?:SECRET|secret|Secret)?_?(?:ACCESS|access|Access)?_?(?:KEY|key|Key)(?:"|')?\s*(?::|=>|=)\s*(?:"|')?([A-Za-z0-9/\+=]{40})(?:"|')''',
    allowed: [
      // Commonly used in AWS documentation and code samples as an example key
      'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      // Test credentials for play.min.io, see:
      // https://docs.min.io/docs/how-to-use-paperclip-with-minio-server.html
      'zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG',
      // If the 40 characters contains are just hexadecimal, there isn't enough
      // entropy for it to be a key, and we must have matched something else.
      RegExp(
        r'''(:|=>|=)\s*("|')?[A-Fa-f0-9][A-Fa-f0-9x][A-Fa-f0-9]{38}("|')?''',
      ),
    ],
    entropyThresholds: {
      // Add entropy requirement for the first group
      //
      // Entropy from the 10 example keys below:
      //      Mean:     4.759
      //      Std.dev.:	0.072
      //
      // Assuming a normal distribution we get 99.7% within 3 std.dev. from mean
      // so using this as a lower bound seems reasonable:
      //      Mean - 3 * std.dev. = 4.54
      1: 4.54,
    },
    testsWithLeaks: [
      // Generated with AWS Console and immediately deactivated and deleted!
      'final secretKey = "zuIzgn8PknWrldyGk5N9GcdQaOWGh57VC54qo7Sy";',
      'final secretKey = "xsg5EujrI960RFuOR6Y0IROqtK47zlSwAgzFWMbS";',
      'final secretKey = "e5lBcRfsby+Du1B/QTbwZ4aLdmsSVytsGvMZC1R3";',
      'final secretKey = "UKUx4bN0ZiGlnM/bTtq3lpXTlawxgSX+Ya3KpD0E";',
      'final secretKey = "FvcpSaMTo04BiNEeT20cbvkYtnmE0qYrzhKPcLL3";',
      'final secretKey = "W8Peo59t66CM8vws1z9HvobIrIFjP47GAM85yBeS";',
      'final secretKey = "epC4pMsSFDtl9zFB70UBtI4mknTG2zKGA5pVxgYp";',
      'final secretKey = "fVtx9YuRYtrVIVRUnhi6lzMjKlUa4txw0YvYJ18W";',
      'final secretKey = "D/GZyi2nQ+dUoJUflYTHI8d+giIMEY9isjsDPE2D";',
      'final secretKey = "RcyVZxn9WKV/QaAJdO+s77IQyMaFKJM1CYQkXQ9u";',
    ],
  ),
  LeakPattern._(
    kind: 'Google API Key',
    pattern: r'''[^0-9A-Za-z\-_](AIza[0-9A-Za-z\-_]{35})[^0-9A-Za-z\-_]''',
    // Added a requirement that start/end is differnet from [^0-9A-Za-z\-_]
    // This minimize false positives in large base64 blobs.
    entropyThresholds: {
      // Add entropy requirement for the first group
      //
      // Entropy from the 10 example keys below:
      //      Mean:     4.702
      //      Std.dev.:	0.150
      //
      // Assuming a normal distribution we get 99.7% within 3 std.dev. from mean
      // so using this as a lower bound seems reasonable:
      //      Mean - 3 * std.dev. = 4.25
      1: 4.25,
    },
    testsWithLeaks: [
      // Generated with GCP Console and immediately deleted!
      'final apiKey = "AIzaSyDG0yD6347wy0i1U4ThqQoEZ0y37ZvFKPM";',
      'final apiKey = "AIzaSyCBSJpVO1A2yHOKP627dSmarIrdgvBygjw";',
      'final apiKey = "AIzaSyCB1pW0i5c5Wr42jykePxjrYOXwM4V4Kxk";',
      'final apiKey = "AIzaSyBg0xThpU0mAbbVgzm-BZ_4r3ByKwq8HQU";',
      'final apiKey = "AIzaSyDWpBgA7US5vfQnooBk1WsKa9U0ogKzuaI";',
      'final apiKey = "AIzaSyD95YyR7Xv1F7hdp503G6Tr2vi3CGDC27U";',
      'final apiKey = "AIzaSyCIKRF0KxSDxMkTAM7npQKQcASzRMItakw";',
      'final apiKey = "AIzaSyAH6KPIIZ5eXLrOX3l90su4YwYpaQ8X7cs";',
      'final apiKey = "AIzaSyCS78MPRLsd-Qkhc-t31OiaglmwstaU-nI";',
      'final apiKey = "AIzaSyAazCCPl4tWkSuDt9XBWRTpHxroViYhSxg";',
    ],
    testsWithNoLeaks: [
      // Insufficient entropy
      'final apiKey = "AIzaXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";',
    ],
  ),
  LeakPattern._(
    kind: 'Google OAuth ID',
    pattern: r'[0-9]+-([0-9A-Za-z_]{32})\.apps\.googleusercontent\.com',
    entropyThresholds: {
      // Add entropy requirement for the first group, only the random part of
      // the string!
      // We ignore the project number and the '.apps.googleusercontent.com'
      // suffix for the entropy computation.
      //
      // Entropy from the 10 example keys below:
      //      Mean:     4.107
      //      Std.dev.:	0.186
      //
      // Assuming a normal distribution we get 99.7% within 3 std.dev. from mean
      // so using this as a lower bound seems reasonable:
      //      Mean - 3 * std.dev. = 3.54
      1: 3.54,
    },
    testsWithLeaks: [
      'final id = "204799038523-t6juuc8cvsvn7bdq0chhihkejuru0bkj.apps.googleusercontent.com";',
      'final id = "204799038523-lskk842vjvcn1lqjela2ased27sh4s5m.apps.googleusercontent.com";',
      'final id = "204799038523-3cer31sm4566gjeccnms5qo6snn4gn82.apps.googleusercontent.com";',
      'final id = "204799038523-ojt14ml172su917bdd2er0t433ke2hh0.apps.googleusercontent.com";',
      'final id = "204799038523-5hofn8sghib442c9a6clfe4rag0g3123.apps.googleusercontent.com";',
      'final id = "204799038523-gbgohctu6a9hcbmhthkmcahnofocb7ue.apps.googleusercontent.com";',
      'final id = "204799038523-gbnpjdjvgeijcpft6ak3rcd5ligqbveh.apps.googleusercontent.com";',
      'final id = "204799038523-1toc9p0g13rsj02u695u1hqu7pcq9art.apps.googleusercontent.com";',
      'final id = "204799038523-brnom9obdhic04q4e7pvcgdopg6lb1ah.apps.googleusercontent.com";',
      'final id = "204799038523-4bjsvv3bmqklm92mlaps2nbi9cjbi94i.apps.googleusercontent.com";',
      '''
      // Not enough entropy:
      final id = "191919191919-onesonesonesonesonesonesonesones.apps.googleusercontent.com";
      // This will count as being leaked
      final superSecret = '204799038523-t6juuc8cvsvn7bdq0chhihkejuru0bkj.apps.googleusercontent.com';
      '''
    ],
    testsWithNoLeaks: [
      // Not enough entropy:
      'final id = "191919191919-onesonesonesonesonesonesonesones.apps.googleusercontent.com";',
    ],
  ),
  LeakPattern._(
    kind: 'Google OAuth Refresh Token',
    pattern: r'[^0-9A-Za-z_\-/+&](1//?[0-9A-Za-z_-]{28,255})[^0-9A-Za-z_\-/+=]',
    // We don't know length of the format, probably there isn't a formal one.
    // But shorter than 28 or longer than 255 seems unlikely. Maybe it could be
    // longer in the future, but restricting it to 255 reduces risk of matching
    // a large base64 blob.
    //
    // Added a requirement that start is differnet from [^0-9A-Za-z_-/+&]
    // and end is differnet from [^0-9A-Za-z_-/+=].
    // This minimize false positives in large base64 blobs
    entropyThresholds: {
      // Add entropy requirement for the first group.
      //
      // Entropy from the 10 example keys below:
      //      Mean:     5.499
      //      Std.dev.:	0.088
      //
      // Assuming a normal distribution we get 99.7% within 3 std.dev. from mean
      // so using this as a lower bound seems reasonable:
      //      Mean - 3 * std.dev. = 5.23
      // As std.dev. of 0.06 feels a bit low and we're unlikely to find false
      // positives with a threshold lower than 5.5, we'll just use 5
      1: 5,
    },
    testsWithLeaks: [
      // Created with [OAuth Playground][1] and revoked with [MyAccount][2].
      //
      // [1]: https://developers.google.com/oauthplayground/
      // [2]: https://myaccount.google.com/permissions
      'final refreshToken = "1//042ys8uoFwZrkCgYIARAAGAQSNwF-L9IrXmFYE-sfKefSpoCnyqEcsHX97Y90KY-p8TPYPPnY2IPgRXdy0QeVw7URuF5u9oUeIF0";',
      'final refreshToken = "1//04FB0GjFdOAxACgYIARAAGAQSNwF-L9Ir7WcX-BM2PSxVZegTE1ZCzA9nd4dE9o6bPrmqPJsKgRCjuez1LuR5cvTTsLqfHxBgnpk";',
      'final refreshToken = "1//04feFjBQvPS3HCgYIARAAGAQSNwF-L9IrIZC-acykL2UV_jEBwgP-6FSZjw91szK8XrejWFhfaP2j5MTi4osihlwI2lkWl6Q8pcc";',
      'final refreshToken = "1//04uP_vMZZBdKRCgYIARAAGAQSNwF-L9IreezpHKQJHni026lWYQuNR7yLRTVKE9qBAV9u9msrEXe1Q3rfgoqoPZJje6lZDMH-o9U";',
      'final refreshToken = "1//04bNFb5JQTtMHCgYIARAAGAQSNwF-L9IrSZHCDb94QYeOn1fZZobMVb5pNYhqJ1IpVA406nJziljDXRP6YZ84JxxT1ACeX5Ednt4";',
      'final refreshToken = "1//04tpLkWJyOUNXCgYIARAAGAQSNwF-L9IrdN_J4xhzUIwFy4W7cHNl8qGTeEjV6_7rRC564Jm9Vgf_vB-k-fYRaNY3uF7cw5LLmvo";',
      'final refreshToken = "1//0427tFuPZKd6PCgYIARAAGAQSNwF-L9IrcFbzaHINAVa0GftO8q5-BYsijx-jKpw5MhSu7Kg1hVNR9k61vprm0m5fbYisYF5LdzI";',
      'final refreshToken = "1//04j6Awy3hlyQMCgYIARAAGAQSNwF-L9Ir_XPyo9RSakFqTp_mtEqs8CdjzZwcRWE41CaRqIxn7YMyQqXwZLYMbWq766pEX68Q1kI";',
      'final refreshToken = "1//04l0n920gild0CgYIARAAGAQSNwF-L9Ir7kdqjs95T0J-yU9PUg30EIBTlvvzPVR8DHTHxK3I_lqgOG-_ma2pM0Q5-gMcgNMQujQ";',
      'final refreshToken = "1//04Mzc8Fsyx4PgCgYIARAAGAQSNwF-L9Ir28S7ZydKT1GnUcju5WgBsb6qFCaZQHgtusdTnPgHGlny5vhq1O0M0K1OtDFK-sFKP_k";',
    ],
  ),
  LeakPattern._(
    kind: 'Google OAuth Access Token',
    pattern: r'[^0-9A-Za-z._-]ya29\.([0-9A-Za-z_-]{30,255})[^0-9A-Za-z._-]',
    // Added minimum size of 30 to minimize false positives
    entropyThresholds: {
      // Add entropy requirement for the first group, only the random part of
      // the string!
      //
      // Entropy from the 10 example keys below:
      //      Mean:     5.691
      //      Std.dev.:	0.060
      //
      // Assuming a normal distribution we get 99.7% within 3 std.dev. from mean
      // so using this as a lower bound seems reasonable:
      //      Mean - 3 * std.dev. = 5.5
      // As std.dev. of 0.06 feels a bit low and we're unlikely to find false
      // positives with a threshold lower than 5.5, we'll just use 5
      1: 5,
    },
    testsWithLeaks: [
      'final accessToken = "ya29.a0AfH6SMDItdQQ9J7j3FVgJubZUgztl0FThTEkBs4pA4-9tFREyf2cfcL-_YE5Urg1O0NWwQKie4Ce42n9dOKlxohWgcAl8cg9DTxRx-TFZN-S1VYPLVtQLGYyNTfGp054Ad3ej73-FIHz3RZY43lcKSorbZEY4BI";',
      'final accessToken = "ya29.a0AfH6SMAPytspCjQX5SEB87E3-jmwTVoNtXsNT7nPyakT26g6zwKaJ5vxxiZj7OB9Z1IYSoi_09WUHKV_xhxnds2p597tlzZ13qXUm8Sdhgo7n7lyoXQlF34_PT9Y5ttGtsZUWKjflYXOQduN-1kJ1iGixDZdsMk";',
      'final accessToken = "ya29.a0AfH6SMCBliVvyA43bb4nYZuk050qrAXztBZ0bNQseXAkz0U1s4M7YjZjHShpGPNQUXfHsd1BCs2v5-dEDiZpQB3_fYKrLQpCeduv5Xm-CyBKc1gEzz0beoJs3i9zBjGVdaAJ7a9kikbaZ-J0Yz50S2dSEqlKsz8";',
      'final accessToken = "ya29.a0AfH6SMBJBEUIPqM5zTk9qIr7giESOiXRfqx_xteG8BB4FaBlknw4nE_YqGJef9ZW-J_5LBY-AmTAs2t-x8yCSPQcEVRS2pKL0NQtmh-HoQtNEY11afZl43HC5v3u2S--QVBuUVCqj6EHC1g0JGcPNi4IT2f5Sr0";',
      'final accessToken = "ya29.a0AfH6SMD6df9ZUsFdb-mkNU0ua_WHbln6cYWpLJHiH1hLJ-XcM8bI-AMjWGu5ZZ6N05BOBzAKFCBHptDjZhRGP1qpAu5UX2MHN_Zgt4hPqcndcUjSMewtXEckynNsq2wCzl7tSo_QnYAyof2TlHbEDF_pFnOAfu0";',
      'final accessToken = "ya29.a0AfH6SMCxD4A3TDkDl2ge_X58b2i8a_y4--_rFfmMw69w-K-8hv7gowN6_shU5-GPyGKkPTdyTbTuvKfPH_zdlKp4_SRasNRJ7HoBEB2H3yhsiFZ8v0gDOSH9GbNREjNuOScwVwwKqhCTFqNHEmULrSJHWm4K8Cs";',
      'final accessToken = "ya29.a0AfH6SMDEZPbs0TzUWKZXKrL94Y0LHt0OgZn5efSx6I0Z-P9LQelXVFngaMwR9IFeoeCKRduRLGJJSLAThIE5PmBSyw4o75pZzKF_l4KSVIQCPOCZJtWQWM2eOskN6tEst9DMyIT94g8Rl-WMW9U3IZxmcPsglCc";',
      'final accessToken = "ya29.a0AfH6SMDB-jjdR-Q48jiUCuUur2NhVFusLqv-l0JBYELjqmJpsmkZy8kscIOrWq21Z-qzcOvPwSeSShCypxsiK2MHRYrF74JK6eCKJjqPayVP5fVBaOdOQxmzi6jCA0aNF9sZjKL9dsCemPnwhuZUs5AeuWD40Vw";',
      'final accessToken = "ya29.a0AfH6SMDrJu5ATPtdPfhPfT2kWECrdVYRJbyQKbrY24T8ONN6AcikbacLzm7DIHh9BU-2EiNUu9B4M1o4ITng-hptqsFugMgJwanHDdC3B-NvqfYgT3x_5eo37reGyT2ZpinBcPFukezRX6kLomdsoyopXru054M";',
      'final accessToken = "ya29.a0AfH6SMDzpLKMe0726VNxiT7RYf21w7_Rdl1HjYvth-1Ief20N8nEmSzqQ9RAepiQXgn15-MrkPh0VVRypGu9Yxc3ty9N88ADmOaV9xJO4LkTWENyEW4zF_KMtwgxt0-Cb1DtQ84fEtfRdMp3OZJI3kjZQjwXrbc";',
    ],
  ),
  LeakPattern._(
    kind: 'Private Key',
    pattern: _pemKeyFormat('PRIVATE KEY'),
    testsWithLeaks: [
      // Normal text file
      '''
-----BEGIN PRIVATE KEY-----
H0M6xpM2q+53wmsN/eYLdgtjgBd3DBmHtPilCkiFICXyaA8z9LkJ
-----END PRIVATE KEY-----
''',
      // Text file without normal line breaks at the end
      '''-----BEGIN PRIVATE KEY-----
H0M6xpM2q+53wmsN/eYLdgtjgBd3DBmHtPilCkiFICXyaA8z9LkJ
-----END PRIVATE KEY-----''',
      // Normal encoding when embedding in source as multiline string
      '''
        final privateKey = \'\'\'
          -----BEGIN PRIVATE KEY-----
          MIGEAgEAMBAGByqGSM49AgEGBSuBBAAKBG0wawIBAQQgVcB/UNPxalR9zDYAjQIf
          jojUDiQuGnSJrFEEzZPT/92hRANCAASc7UJtgnF/abqWM60T3XNJEzBv5ez9TdwK
          H0M6xpM2q+53wmsN/eYLdgtjgBd3DBmHtPilCkiFICXyaA8z9LkJ
          -----END PRIVATE KEY-----
        \'\'\';
      ''',
      // Allows some arbitrary whitespace
      // LAX mode from: https://tools.ietf.org/html/rfc7468
      '''
        -----BEGIN PRIVATE KEY-----
        
        M IGE
        AgEAMBAGByqGSM49AgEGBSuBBAAKBG0wawI
        BAQQgVcB/UNPxalR9zDYAjQIf
        jojUDiQuGnSJrFEEzZPT/92hRANCAASc7UJtgnF/abqWM60T3XNJEzBv5ez9T
        dwK
        H0M6xp
        M2q+53wmsN/eYLdgtjgBd3DBmHtPilCkiFICXyaA8z9LkJ
        -----END PRIVATE KEY-----
      ''',
      // Allows 1 padding character
      '''
        -----BEGIN PRIVATE KEY-----
        H0M6xpM2q+53wmsN/eYLdgtjgBd3DBmHtPilCkiFICXyaA8z9Lk=
        -----END PRIVATE KEY-----
      ''',
      // Allows 2 padding character
      '''
        -----BEGIN PRIVATE KEY-----
        H0M6xpM2q+53wmsN/eYLdgtjgBd3DBmHtPilCkiFICXyaA8z9L==
        -----END PRIVATE KEY-----
      ''',
      // Encoding in exported service-account credentials
      r'''
        {
          "type": "service_account",
          "project_id": "api-project-999797222222",
          "private_key_id": "1f6070c2f200bcdfdcc03be6555d1fefa0715c5a",
          "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCq60Njgtb74U/7\nkin5YKmY4hVDCb+nskL22TfckskfgFJz6n4dgwkNX2una8LOFimsNqajxHUFiAOy\n8uCBVhLDkMp35lZyprir1wnOwSU/pN3sJh2c22RfS+Q1nAc9/LRyaNxdIxAxaChq\nr48JpfGpACV3siXtp8m2aJd+cyqXUBz3sGMyA43KgPkdeGfL9Rk05Bc457PtH7CX\nGHArJJ2cpDhNRdJ1QBZL6Tb5ZmbQCM0lhpCe5XToVCZMSI5hnce++0vImZxwLhQW\noFyLYceggONmX0ZmNu97gEo9T6koxDXDACVRk4dnTMyktIWiOtTJxF0moALHvNfZ\nCPIlMu/rAgMBAAECggEABxzh9w2GM4E9j4iWT+x34lw2P6NI4zUF7bk9xo4ilI8F\n32Zjd92beNT/E+k7eCbFS9y9CT+vEbCGsYxt+glCSqUx59TMGtquq2gNiRnR764a\nwNhtObk073T8ZZwSqRUP0AW7y0ce8LoW7ymoguGcXEjHRmNBiicGEUiVAAwm5O5n\nugwTwjr5njBw1vZ8kGrHR58o78Fpiqo30unweUL4qjrRYTXsDSOq29JOXy5a8bVP\ntMZM3Y1g5RDNdJaCJO580qpIIcB+1MqGE008+aHTHK/Jx2MjlRh4zF5jTnNk8jcE\nxAX0OM7d9tSsud6/SSgFSSH0JMwFkNSLbyL7GWxU8QKBgQDoSCFi8VvASfOnHfQ9\ntspERdyaUf3meDYrVtG1Zhmuc44lf7gYaWnGvdWpu4KMQQWDC9uL/zlRqLzRp0db\nalNvyuO9Z9GDki28uCR289q6DHeRaGHVKYkx5cfbaOJhTPEiWMoq4vtHsk4jo5eI\n47gxa6BoQO7r/qhGvtMnxu0ehQKBgQC8XxqQhlv5cld4edqQb3bT9R7WzQlYLmlB\nb+tM5eKESt0KWjpxu8QJ5JKgUCgc4jcoXQ/sy8QP/upiF9Xz4QQ37mtFaSup/HlY\nYv3HiT9lUy9yvALLo0yBvtjQvuW7+X0xCnbIzMuNNHcpTCESR44cWERgZUT8TFrw\nv7+PwkK3rwKBgQC8DXmKIyFHAhgS2jtco1oKAA1jmrHWHsisObO6CpkMFV2lmksu\n6FjMn/AVZEuCxTlzKOxr4QtEwzlq+uTYa7J1NWs/coe632PL/8D11OLl8SX0QO/D\npcb+8KrnRXjRkXs/dWbnZbBOEVsVm2IZX1NGH35UKQ3FXfxami9VasWaCQKBgC7U\nogEONi10vMRJ3wmLfIpDZVBXlxwiJa7MCT6L5F2pUvyw49jEqn8fIUjTxLUxlC7n\nu/7NxceIQ3LxpBJGfcr97hNKiz1udCiCK7+Aoo8pOCGZFkTUK0ASV0rGOs0ZwIMB\nq/hN2ckYIwvUTmCCA5WOaCli49ypiu5RbWlrDTUnAoGBAKi2ci9kXlMVTLpbadGE\nzBMl1uB+3HXhgtXsaofA1JmquGuxlRXrq1O/XXGQYBISTKAf87ULKMnMXnh1klmU\nZ84gQQkywISfmMY6tIqqOlWkXXk7OVDDErHdnBj+3UfMkTEZChbiMkQAkSc+Hwd9\n6xhidr9WqPzl7r3PXBPA2Zdx\n-----END PRIVATE KEY-----\n",
          "client_email": "test@api-project-999797222222.iam.gserviceaccount.com",
          "client_id": "111119132165292222222",
          "auth_uri": "https://accounts.google.com/o/oauth2/auth",
          "token_uri": "https://oauth2.googleapis.com/token",
          "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
          "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/test%40api-project-999797222222.iam.gserviceaccount.com"
        }
      ''',
    ],
    testsWithNoLeaks: [
      // 3 base padding characters is never valid!
      '''
        -----BEGIN PRIVATE KEY-----
        H0M6xpM2q+53wmsN/eYLdgtjgBd3DBmHtPilCkiFICXyaA8z9===
        -----END PRIVATE KEY-----
      ''',
    ],
  ),
  LeakPattern._(
    kind: 'RSA Private Key',
    pattern: _pemKeyFormat('RSA PRIVATE KEY'),
  ),
  LeakPattern._(
    kind: 'EC Private Key',
    pattern: _pemKeyFormat('EC PRIVATE KEY'),
  ),
  LeakPattern._(
    kind: 'PGP Private Key',
    pattern: [
      _pemBegin('PGP PRIVATE KEY BLOCK'),
      // Allow "Armor Headers" from:
      // https://www.rfc-editor.org/rfc/rfc4880.html#section-6.2
      '(?:\\w+: [^\\n]{1,1024}$_pemRequireLineBreak$_pemWSP)*',
      _pemBase64Block(),
      // Require a line break, and a 24-bit base64 encoded checksum prefixed '='
      // https://www.rfc-editor.org/rfc/rfc4880.html#section-6
      '$_pemRequireLineBreak$_pemWSP',
      '=(?:(?:[a-zA-Z0-9+/]$_pemWSP){4})',
      _pemEnd('PGP PRIVATE KEY BLOCK'),
    ].join(),
    testsWithLeaks: [
      '''
-----BEGIN PGP PRIVATE KEY BLOCK-----
Version: Keybase OpenPGP v1.0.0
Comment: https://keybase.io/crypto
xcASBGCFQ7MTBSuBBAAiAwMEvlAADGgIHDMkO5UqDbFaVfARFUzvMJyo355r8LuE
NWW3XWHb+r39waMhqXmQZxes4YuXT2o/68wTzzus14gOtrLWQrrTZgp99duOfiS7
gv2NX7uF0kx2DG5YlD+VMkDl/gkDCOcy7lmIlJawYDrgCBSEfnrXh0m96xhN9RNZ
u7AkuvD+MnhUkC6r/zlKNBERP2QKYhsxQRQDwlCQL3B3Pj07os7DboMpEMGbAGss
PMtqYDExOwfQ6H6+FqDcc7E0VWNSzSF0ZXN0ICh0ZXN0KSA8ZXhhbXBsZUBleGFt
cGxlLmNvbT7CjwQTEwoAFwUCYIVDswIbLwMLCQcDFQoIAh4BAheAAAoJEP1+dYog
Dm+yhCUBgKeyXrKZvzi5OVrFJC6KSbRQB/YaxxIk9g01GupyLLgnti0oea5eSqGS
8YVxT/A16wF9Gqq31sE2yOVC9xAuyohANfV+bMdhgivG8TIUMIFkQ9EOE1WSBuY0
mzXSrS+4KMbDx6UEYIVDsxMIKoZIzj0DAQcCAwT9dBwQahYj+vxBX3Aha4Ti9vaZ
PFdTIN+OfFniiPCaHqHHdZ/I28kAMMEdDwPexYNiR0Fk6iz/Yx86V8jnQH2X/gkD
CG5njLK6ZHWmYNeqMwjEHN8nA7M2bY8BxbHTeJv49FfSr/Zh5O2vNE1uYg/B3gNJ
yGN4fxLBzKYGCDOkiJEYaWJGOBuPWKGd+quyjIuAzjbCwCcEGBMKAA8FAmCFQ7MF
CQ8JnAACGy4AagkQ/X51iiAOb7JfIAQZEwoABgUCYIVDswAKCRBIawKSRH1lh9RY
AQDmPgwHtLjq4Bezi5ouTDFp77ThbJ9CnCcXwrQd7TtSaQD/SXfPpAe1HToSdJoe
Hcbo1elrxh6Rtc+JWd+/XJ/IpLeCEwGA5a9yqbMegLetpj1F2jwxO8O5raamTR4w
/V0Q+Msb73PuNPUikImFZDv+ChI1+cffAX9Jqd7+Eh7WafuoC475izLBZJbJKTW5
BodQdUXsO5WmcVUOivkylktJFwpft3LZWPPHpQRghUOzEwgqhkjOPQMBBwIDBGzY
1lmmmDIJZZwQjeDqac8JMrX0/6VuUw9NBF5r+k8Vkvvx2iaz79IjvJMCN9u50O2w
4bDlmBvZ55koL4PX49z+CQMIk87UpR3v5ktgkx0t1+QkY7byJ59f5tpDTTgez2fT
LhTbfOdHyD5Al/zjU6p5XNF0If4GsjhfVMxoJUbKkLMtPM5xlLmuqnozvJF4PKhH
kcLAJwQYEwoADwUCYIVDswUJDwmcAAIbLgBqCRD9fnWKIA5vsl8gBBkTCgAGBQJg
hUOzAAoJENYMoCRtY0P6rWMBAJgOpN3f6FwSDop+MRCImahF6le6b6GK/vKkCL3V
pjhmAQDMYovIDX7YH831pdv9ggrthZEBTVD/Rtpw8BdLTAsggecSAX9p5otJE+cg
/fQssS2nWDcpSQ4mqjJu5wQLB8u/EWUzDpMDnd6/b4BiaL/CUf33gGIBgPo2WTAM
RmkFFVpJpULM46oNqjI0Ps58ClfR7PH73mJ5T+6CFUAAIm3zBVDlpLE8pA==
=3iPB
-----END PGP PRIVATE KEY BLOCK-----
      ''',
    ],
  ),
]);

// Allow arbitrary whitespace and escaped line breaks
String _pemWSP = r'(?:\\r|\\n|\\t|\s)*';

// Require \n, \r, \\r, or \\n, backslash escaping is allowed if the key
// is in a JSON string. We just require something to indicate line break.
String _pemRequireLineBreak = r'\s*(?:\\r|\\n|\r|\n)\s*';

String _pemBegin(String label) => [
      // Require a boundary
      '-----BEGIN $label-----',
      // Require \n, \r, \\r, or \\n, backslash escaping is allowed if the key
      // is in a JSON string. We just require something to indicate line break.
      _pemRequireLineBreak,
      // Allow arbitrary whitespace and escaped line breaks
      _pemWSP,
    ].join();

String _pemBase64Block() => [
      // Require base64 character in blocks of 4, allow arbirary whitespace
      // and escaped line breaks in between.
      '(?:(?:[a-zA-Z0-9+/]$_pemWSP){4})+',
      // We have 3 options for encoding the ending:
      // (A) 1 padding character,
      // (B) 2 padding characters,
      // (C) No padding characters (neither A or B)
      '(?:(',
      [
        // Option (A): 3 base64 characters followed by one base64 padding
        // character, allow arbirary whitespace and escaped line breaks
        // in between.
        '(?:[a-zA-Z0-9+/]$_pemWSP){3}=$_pemWSP',
        // Either (A) or (B):
        ')|(?:',
        // Option (B): 2 base64 characters followed by 2 base64 padding
        // character, allow arbirary whitespace and escaped line breaks
        // in between.
        '(?:[a-zA-Z0-9+/]$_pemWSP){2}(?:=$_pemWSP){2}',
      ].join(),
      // End blocks
      '))?',
    ].join();

String _pemEnd(String label) => [
      // Require \n, \r, \\r, or \\n, backslash escaping is allowed if the key
      // is in a JSON string. We just require something to indicate line break.
      _pemRequireLineBreak,
      // Allow arbitrary whitespace and escaped line breaks
      _pemWSP,
      '-----END $label-----',
    ].join();

String _pemKeyFormat(String label) => [
      _pemBegin(label),
      _pemBase64Block(),
      _pemEnd(label),
    ].join();
