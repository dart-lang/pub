// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

/// Calculates the [Sørensen–Dice coefficient][1] for two strings.
///
/// This is done by converting the strings into bigrams (e.g. 'dart' becomes
/// {'da', 'ar', 'rt}), and calculates the coefficient based on twice the
/// number of common elements over the total number of elements.
///
/// In this implementation, identical bigrams that appear more than once in the
/// string will be calculated accordingly (e.g. 'aaaa' is split into {'aa', 'aa'
/// , 'aa'}), and each them a match is made, we strike off one of the bigrams.
/// The effect of doing so increases the meaingfulness of the coefficient
/// produced.
///
/// Our implementation also works with empty strings and one-character strigns.
///
/// **Example**
/// ```dart
/// diceCoefficient('', '')                                 /// 1.0
/// diceCoefficient('', 'a')                                /// 0.0
/// diceCoefficient('a', 'a')                               /// 1.0
/// diceCoefficient('a', 'b')                               /// 0.0
/// diceCoefficient('aa', 'aaa')                            /// 0.6666667
/// diceCoefficient('aaaa', 'aaaaa')                        /// 0.857142
/// diceCoefficient('night', 'nacht')                       /// 0.25
/// diceCoefficient('dev_dependencies', 'dev-dependencies') /// 0.8666666
/// diceCoefficient('dependency', 'dependencies')           /// 0.8
/// ```
///
/// [1]: https://www.aclweb.org/anthology/N03-2016.pdf
double diceCoefficient(String string1, String string2) {
  if (string1.isEmpty && string2.isEmpty) return 1.0;

  final bigrams1 = _createBigrams(string1);
  final bigrams2 = _createBigrams(string2);

  final diceNumerator = 2 * _countMatches(bigrams1, bigrams2);
  var diceDenominator = 0;
  diceDenominator += string1.length > 1 ? string1.length - 1 : string1.length;
  diceDenominator += string2.length > 1 ? string2.length - 1 : string2.length;

  return diceNumerator / diceDenominator;
}

/// Parses [string] to form a map of bigrams, where the key is the bigram, and
/// the value is the number of time it appears in [string] irrespective of
/// position.
///
/// If [string] has only one character, the resulting map will only have one
/// entry: ([string]: 1)
///
/// If [string] is empty, the resulting map will likewise be empty.
HashMap<String, int> _createBigrams(String string) {
  final result = HashMap<String, int>();

  for (var i = 0; i < string.length - 1; i++) {
    final substring = string.substring(i, i + 2);
    if (result[substring] == null) {
      result[substring] = 1;
    } else {
      result[substring]++;
    }
  }

  // Deal with one character strings
  if (string.length == 1) {
    result[string] = 1;
  }

  return result;
}

/// Counts the number of elements that are common to both [bigrams1] and
/// [bigrams2].
int _countMatches(
    HashMap<String, int> bigrams1, HashMap<String, int> bigrams2) {
  var matchCount = 0;

  for (final entry in bigrams1.entries) {
    final key = entry.key;

    for (var i = 0; i < entry.value; i++) {
      if (bigrams2[key] == null) break;

      matchCount++;
      if (bigrams2[key] == 1) {
        bigrams2.remove(key);
      } else {
        bigrams2[key]--;
      }
    }
  }

  return matchCount;
}
