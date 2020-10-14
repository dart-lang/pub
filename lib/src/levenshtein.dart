import 'dart:math';

/// Calculates Levenshtein distance between [s] and [t].
///
/// The Levenshtein distance is defined as the minimum number of edit operations
/// required to convert [s] to [t]. An edit operation can either be:
///
/// 1. Inserting a character
/// 2. Deleting a character
/// 3. Substituting a character.
///
/// This implementation is case-sensitive.
int levenshteinDistance(String s, String t) {
  ArgumentError.checkNotNull(s, 's');
  ArgumentError.checkNotNull(t, 't');

  /// Swap the strings if necessary so we can reduce the space requirement.
  final a = s.length > t.length ? s : t;
  final b = s.length > t.length ? t : s;

  /// Levenshtein Distance can be computed by creating a matrix such that
  /// `distances[i][j]` holds the edit distance to convert from the first i
  /// letters of [s] to the first j letters of [t], and dynamically computing
  /// upwards. We reduce the space requirement by repeatedly updating just
  /// one row.
  final distances = List.filled(b.length + 1, 0);

  /// Initialize the first row.
  for (var j = 0; j < distances.length; j++) {
    distances[j] = j;
  }

  for (var i = 1; i <= a.length; i++) {
    distances[0] = i;

    /// Holds the value of `distances[i-1][j-1]` if we had been using a mtraix.
    var holder = i - 1;
    for (var j = 1; j <= b.length; j++) {
      final newDistance = _min3(
          1 + distances[j], //  Deletion
          1 + distances[j - 1], // Insertion

          // Substitution
          holder + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1));
      holder = distances[j];
      distances[j] = newDistance;
    }
  }

  return distances[b.length];
}

/// Utility function to calculate the minimum of [a], [b], and [c].
T _min3<T extends num>(T a, T b, T c) {
  return min(min(a, b), c);
}
