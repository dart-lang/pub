// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:yamlicious/yamlicious.dart';

import 'log.dart' as log;

class ConfigHelper {
  // PUBLIC API

  List<String> availableSettings;
  String standardConfig;
  String location;

  String get content => File(location).readAsStringSync();

  ConfigHelper(var settings, this.standardConfig, [String basename]) {
    availableSettings = List.from(settings);
    location = _getFileLocation(basename);
    _read();
  }

  ConfigHelper.simple(var args, [String basename]) {
    availableSettings = List.from(args[0]);
    standardConfig = args[1];
    location = _getFileLocation(basename);
    _read();
  }

  ConfigHelper.test(var settings, this.standardConfig, [String basename]) {
    availableSettings = List.from(settings);
    location = _getFileLocation(basename, isTest: true);
    _read();
  }

  ConfigHelper.simpleTest(var args, {String basename, String dir}) {
    availableSettings = List.from(args[0]);
    standardConfig = args[1];
    location = _getFileLocation(basename, isTest: true, dir: dir);
    _read();
  }

  bool get exists => File(location).existsSync();

  Future<bool> get existsAsync => File(location).exists();

  void write() => File(location).writeAsStringSync(toYamlString(_parsedYAML));

  void delete() {
    if (exists) File(location).deleteSync();
  }

  Future<void> deleteAsync() async {
    if (await existsAsync) await File(location).delete();
  }

  /// Set/create value: `set('something', 1337);`
  /// Set/create a value in an array: `set('something', 445, index: 2);`
  /// Nested item: `set('something.something2', 1337);`
  /// Array: `set('something', [1,2,'someString']);`
  /// All together: `set('something.something2.lol', [1,2,3]);`
  /// and           `set('something.something2.lol', 0, index: 2);`
  void set(String key, var value, {int index}) {
    _initializeYAML();
    final nestedFields = key.split('.');
    if (!availableSettings.contains(key)) {
      log.error('Error: Invalid key - ' + key);
      return;
    }

    if (nestedFields.length == 1) {
      if (_parsedYAML[key] is List && index != null) {
        var valueList = _parsedYAML[key];
        valueList[index] = value;
        _parsedYAML[key] = valueList;
      } else {
        _parsedYAML[key] = value;
      }
    } else {
      _handleNestedFields(nestedFields, value, index);
    }
  }

  /// Get a value from the config
  T get<T>(String key, [int index]) {
    _initializeYAML();
    // nested search
    final nestedFields = key.split('.');
    var pivot = _parsedYAML;

    for (var i = 0; i < nestedFields.length; i++) {
      if (availableSettings.contains(nestedFields[i])) {
        pivot = pivot[nestedFields[i]];
      }
    }
    if (pivot is List && index != null) {
      return pivot[index];
    } else {
      return pivot;
    }
  }

  /// operators cannot be generic so the value gets converted to String
  String operator [](var key) => get(key).toString();

  // END OF PUBLIC API

  dynamic _parsedYAML;

  String _getFileLocation(String basename, {bool isTest = false, String dir}) {
    final actualBasename = basename ?? 'pub_config.yaml';
    String ret;

    if (isTest) {
      if (dir == null) {
        final cleanPath =
            path.dirname(Platform.script.path).split('file://')[1];
        final splitCleanPath = cleanPath.split('/test');
        ret = path.join(splitCleanPath[0], 'bin', actualBasename);
      } else {
        ret = path.join(dir, 'bin', actualBasename);
      }
    } else {
      ret = path.join(path.dirname(Platform.script.path), actualBasename);
    }
    return Platform.isWindows ? (ret[0] == '/' ? ret.substring(1) : ret) : ret;
  }

  dynamic _getPivot(fields, insertionIndex) {
    var pivot = _parsedYAML;
    for (var i = 0; i < insertionIndex; i++) {
      pivot = pivot[fields[i]];
    }
    return pivot;
  }

  void _create() {
    // only create config file if it does not exist yet
    if (!exists) {
      var config = File(location);
      config.writeAsStringSync(standardConfig);
      _parsedYAML = _parseYAML();
    }
  }

  void _transformAvailableSettings() {
    var nestedKeys = ['']; //empty string to denote nestedKeys as List<String>
    nestedKeys.removeLast();
    for (var i = 0; i < availableSettings.length; i++) {
      var splitSettings = availableSettings[i].split('.');
      if (splitSettings.length > 1) nestedKeys.add(availableSettings[i]);
      availableSettings.removeAt(i);
      availableSettings.insertAll(i, splitSettings);
    }
    availableSettings.addAll(nestedKeys);
  }

  dynamic _parseYAML() {
    try {
      return json.decode(json.encode(loadYaml(content)));
    } catch (e) {
      log.error('Could not parse configuration file: ${e.toString()}');
      exit(1);
    }
  }

  List _findInsertionField(List<String> fields) {
    var datMap = Map.from(_parsedYAML);

    for (var i = 0; i < fields.length; i++) {
      if (datMap.containsKey(fields[i]) && datMap[fields[i]] is Map) {
        datMap = datMap[fields[i]];
      } else {
        if (i > 0) {
          return [i - 1, fields[i - 1]];
        } else {
          return [null, null];
        }
      }
    }
    return [fields.length - 1, fields[fields.length - 1]];
  }

  dynamic _handleNestedFields(List<String> fields, value, index) {
    final fieldLength = fields.length;
    if (fieldLength < 2) return _parsedYAML;

    final searchResult = _findInsertionField(fields);

    final insertionIndex = searchResult[0] ?? 0;
    final insertionElement = searchResult[1] ?? fields[0];

    var pivot = _getPivot(fields, insertionIndex);

    dynamic actualValue;
    try {
      actualValue = pivot[insertionElement][fields[fieldLength - 1]];
    } catch (e) {
      actualValue = null;
    }

    Map nestedMap;
    if (actualValue is! List) {
      nestedMap = {fields[fieldLength - 1]: value};
    } else if (index != null) {
      actualValue[index] = value;
      nestedMap = {fields[fieldLength - 1]: actualValue};
    }

    //create nested map object
    for (var j = fieldLength - 2; j >= insertionIndex + 1; j--) {
      nestedMap = {fields[j]: nestedMap};
    }

    if (pivot[insertionElement] is! LinkedHashMap) {
      pivot[insertionElement] = nestedMap;
    } else {
      var tmp = Map.from(pivot[insertionElement]);
      tmp.addAll(nestedMap);
      pivot[insertionElement] = tmp;
    }

    return _parsedYAML;
  }

  void _initializeYAML() {
    if (_parsedYAML == null) {
      delete();
      _create();
      _parsedYAML = _parseYAML();
    }
  }

  void _read() {
    _create();
    _transformAvailableSettings();
    _parsedYAML = _parseYAML();
  }

  // TESTING

  void createEmptyConfigFile() {
    var file = File(location);
    file.writeAsStringSync('');
  }

  void makeInvalid() {
    var file = File(location);
    file.writeAsStringSync('\ninvalid yaml content', mode: FileMode.append);
    _parsedYAML = _parseYAML();
  }

  void rawWrite(String content) {
    var file = File(location);
    file.writeAsStringSync(content);
  }
}
