import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Stores timestamps of the absolute paths to Dart scripts
/// specified in packages' "after_install" fields, and the
/// last times they were run.
class AfterInstallCache {
  final Map<String, int> _cache;

  const AfterInstallCache._(this._cache);

  /// Returns the name of the file that would hold an "after_install" cache in the [rootDir].
  static String resolveCacheFilePath(String rootDir) {
    return p.join(rootDir, "after_install_cache.json");
  }

  /// Loads from a given [rootDir].
  static Future<AfterInstallCache> load(String rootDir) async {
    var filename = resolveCacheFilePath(rootDir);
    var cacheFile = new File(filename);

    // If the file does not exist, return the default.
    if (!await cacheFile.exists()) return new AfterInstallCache._({});

    var map = json.decode(await cacheFile.readAsString());
    var isValidMap = map is Map &&
        map.keys.every((k) => k is String) &&
        map.values.every((k) => k is int);

    // If the file is formatted improperly, return the default.
    //
    // Whatever corrupted data was stored in the cache file, will
    // ultimately be overwritten.
    if (!isValidMap) return new AfterInstallCache._({});

    // If everything went well, return the parsed cache.
    return new AfterInstallCache._(map.cast<String, int>());
  }

  /// Determines if the script at [path] should be re-run.
  ///
  /// This is `true` if any of the following is true:
  ///   * The cache contains no entry for the [path].
  ///   * The file at [path] was modified after the timestamp in the cache.
  Future<bool> isOutdated(String path) async {
    if (!_cache.containsKey(path)) return true;
    var stat = await FileStat.stat(path);
    return _cache[path] < stat.modified.millisecondsSinceEpoch;
  }

  /// Saves the contents of the cache to a file in the given [rootDir].
  Future save(String rootDir) async {
    if (_cache.isNotEmpty) {
      var file = new File(resolveCacheFilePath(rootDir));
      await file.create(recursive: true);
      await file.writeAsString(json.encode(_cache));
    }
  }

  /// Updates the cached timestamp for [path].
  void update(String path) =>
      _cache[path] = new DateTime.now().millisecondsSinceEpoch;

  /// Returns a combined cache containing the contents of both `this` and [other].
  ///
  /// Where there are conflicts, values in [other] are prioritized.
  ///
  /// Does not modify the caches of either `this` or [other].
  AfterInstallCache merge(AfterInstallCache other) {
    return new AfterInstallCache._(
        <String, int>{}..addAll(_cache)..addAll(other._cache));
  }

  Map<String, int> toMap() => new Map<String, int>.from(_cache);
}
