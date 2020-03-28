// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'package:yamlicious/yamlicious.dart';

import 'log.dart' as log;

class ConfigHelper {
  var _parsedYAML;

  // PUBLIC API

  List<String> availableSettings;
  String standardConfig;
  String location;

  ConfigHelper(var settings, this.standardConfig, [String basename]) {
    availableSettings = List.from(settings);
    basename = basename ?? 'pub_config.yaml';
    location = path.join(path.dirname(Platform.script.path), basename);
    _read();
  }

  ConfigHelper.simple(var args, [String basename]) {
    basename = basename ?? 'pub_config.yaml';
    location = path.join(path.dirname(Platform.script.path), basename);
    availableSettings = List.from(args[0]);
    standardConfig = args[1];
    _read();
  }

  ConfigHelper.test(var settings, this.standardConfig, [String basename]) {
    availableSettings = List.from(settings);
    basename = basename ?? 'pub_config.yaml';
    String cleanPath = path.dirname(Platform.script.path).split('file://')[1];
    final splitCleanPath = cleanPath.split('/test');
    location = path.join(splitCleanPath[0], 'bin', basename);
    _read();
  }

  ConfigHelper.simpleTest(var args, [String basename]) {
    availableSettings = List.from(args[0]);
    standardConfig = args[1];
    basename = basename ?? 'pub_config.yaml';
    String cleanPath = path.dirname(Platform.script.path).split('file://')[1];
    final splitCleanPath = cleanPath.split('/test');
    location = path.join(splitCleanPath[0], 'bin', basename);
    _read();
  }

  bool get exists => new File(location).existsSync();

  get existsAsync => new File(location).exists();

  void write() =>
      new File(location).writeAsStringSync(toYamlString(_parsedYAML));

  void delete() {
    if (exists) File(location).deleteSync();
  }

  void deleteAsync() async {
    if (await exists) await File(location).delete();
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
      } else
        _parsedYAML[key] = value;
    } else
      _handleNestedFields(nestedFields, value, index);
  }

  /// Get a value from the config
  T get<T>(String key, [int index]) {
    _initializeYAML();
    // nested search
    final nestedFields = key.split('.');
    var pivot = _parsedYAML;

    for (int i = 0; i < nestedFields.length; i++) {
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

  void createEmptyConfigFile() {
    var file = File(location);
    file.writeAsStringSync("");
  }

  // END OF PUBLIC API

  String get _content => new File(location).readAsStringSync();

  _getPivot(fields, insertionIndex) {
    var pivot = _parsedYAML;
    for (int i = 0; i < insertionIndex; i++) {
      pivot = pivot[fields[i]];
    }
    return pivot;
  }

  void _create() {
    // only create config file if it does not exist yet
    if (!exists) {
      var config = new File(location);
      config.writeAsStringSync(standardConfig);
      _parsedYAML = _parseYAML();
    }
  }

  void _transformAvailableSettings() {
    List<String> nestedKeys = [];
    for (int i = 0; i < availableSettings.length; i++) {
      var splitSettings = availableSettings[i].split('.');
      if (splitSettings.length > 1) nestedKeys.add(availableSettings[i]);
      availableSettings.removeAt(i);
      availableSettings.insertAll(i, splitSettings);
    }
    availableSettings.addAll(nestedKeys);
  }

  _parseYAML() {
    try {
      return json.decode(json.encode(loadYaml(_content)));
    } catch (e) {
      log.error('Could not parse configuration file: ${e.toString()}');
      exit(1);
    }
  }

  List _findInsertionField(List<String> fields) {
    var datMap = Map.from(_parsedYAML);

    for (int i = 0; i < fields.length; i++) {
      if (datMap.containsKey(fields[i]) && datMap[fields[i]] is Map) {
        datMap = datMap[fields[i]];
      } else {
        if (i > 0) {
          return [i - 1, fields[i - 1]];
        } else
          return [null, null];
      }
    }
    return [fields.length - 1, fields[fields.length - 1]];
  }

  _handleNestedFields(List<String> fields, value, index) {
    final fieldLength = fields.length;
    if (fieldLength < 2) return _parsedYAML;

    List searchResult = _findInsertionField(fields);

    final insertionIndex = searchResult[0] ?? 0;
    final insertionElement = searchResult[1] ?? fields[0];

    var pivot = _getPivot(fields, insertionIndex);

    var actualValue = null;
    try {
      actualValue = pivot[insertionElement][fields[fieldLength - 1]];
    } catch (e) {
      actualValue = null;
    }

    Map nestedMap = null;
    if (actualValue is! List)
      nestedMap = {fields[fieldLength - 1]: value};
    else if (index != null) {
      actualValue[index] = value;
      nestedMap = {fields[fieldLength - 1]: actualValue};
    }

    //create nested map object
    for (int j = fieldLength - 2; j >= insertionIndex + 1; j--) {
      nestedMap = {fields[j]: nestedMap};
    }

    if (pivot[insertionElement] is! LinkedHashMap)
      pivot[insertionElement] = nestedMap;
    else {
      Map tmp = Map.from(pivot[insertionElement]);
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
}
