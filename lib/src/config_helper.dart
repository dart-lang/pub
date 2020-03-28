// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
<<<<<<< HEAD
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
=======
import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:convert';
>>>>>>> Add new command pub config
import 'package:yaml/yaml.dart';
import 'package:yamlicious/yamlicious.dart';

import 'log.dart' as log;

class ConfigHelper {
<<<<<<< HEAD
=======
  var _parsedYAML;

>>>>>>> Add new command pub config
  // PUBLIC API

  List<String> availableSettings;
  String standardConfig;
  String location;

<<<<<<< HEAD
  String get content => File(location).readAsStringSync();

  ConfigHelper(var settings, this.standardConfig, [String basename]) {
    availableSettings = List.from(settings);
    location = _getFileLocation(basename);
=======
  ConfigHelper(var settings, this.standardConfig, [String basename]) {
    availableSettings = List.from(settings);
    basename = basename ?? 'pub_config.yaml';
    location = path.join(path.dirname(Platform.script.path), basename);
>>>>>>> Add new command pub config
    _read();
  }

  ConfigHelper.simple(var args, [String basename]) {
<<<<<<< HEAD
    availableSettings = List.from(args[0]);
    standardConfig = args[1];
    location = _getFileLocation(basename);
=======
    basename = basename ?? 'pub_config.yaml';
    location = path.join(path.dirname(Platform.script.path), basename);
    availableSettings = List.from(args[0]);
    standardConfig = args[1];
>>>>>>> Add new command pub config
    _read();
  }

  ConfigHelper.test(var settings, this.standardConfig, [String basename]) {
    availableSettings = List.from(settings);
<<<<<<< HEAD
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
=======
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
>>>>>>> Add new command pub config

  void delete() {
    if (exists) File(location).deleteSync();
  }

<<<<<<< HEAD
  Future<void> deleteAsync() async {
    if (await existsAsync) await File(location).delete();
=======
  void deleteAsync() async {
    if (await exists) await File(location).delete();
>>>>>>> Add new command pub config
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
<<<<<<< HEAD
      } else {
        _parsedYAML[key] = value;
      }
    } else {
      _handleNestedFields(nestedFields, value, index);
    }
=======
      } else
        _parsedYAML[key] = value;
    } else
      _handleNestedFields(nestedFields, value, index);
>>>>>>> Add new command pub config
  }

  /// Get a value from the config
  T get<T>(String key, [int index]) {
    _initializeYAML();
    // nested search
    final nestedFields = key.split('.');
    var pivot = _parsedYAML;

<<<<<<< HEAD
    for (var i = 0; i < nestedFields.length; i++) {
=======
    for (int i = 0; i < nestedFields.length; i++) {
>>>>>>> Add new command pub config
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

<<<<<<< HEAD
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
=======
  void createEmptyConfigFile() {
    var file = File(location);
    file.writeAsStringSync("");
  }

  // END OF PUBLIC API

  bool _isInvalidState = false;
  String get _content => new File(location).readAsStringSync();

  _getPivot(fields, insertionIndex) {
    var pivot = _parsedYAML;
    for (int i = 0; i < insertionIndex; i++) {
>>>>>>> Add new command pub config
      pivot = pivot[fields[i]];
    }
    return pivot;
  }

  void _create() {
    // only create config file if it does not exist yet
    if (!exists) {
<<<<<<< HEAD
      var config = File(location);
=======
      var config = new File(location);
>>>>>>> Add new command pub config
      config.writeAsStringSync(standardConfig);
      _parsedYAML = _parseYAML();
    }
  }

  void _transformAvailableSettings() {
<<<<<<< HEAD
    var nestedKeys = ['']; //empty string to denote nestedKeys as List<String>
    nestedKeys.removeLast();
    for (var i = 0; i < availableSettings.length; i++) {
=======
    List<String> nestedKeys = [];
    for (int i = 0; i < availableSettings.length; i++) {
>>>>>>> Add new command pub config
      var splitSettings = availableSettings[i].split('.');
      if (splitSettings.length > 1) nestedKeys.add(availableSettings[i]);
      availableSettings.removeAt(i);
      availableSettings.insertAll(i, splitSettings);
    }
    availableSettings.addAll(nestedKeys);
  }

<<<<<<< HEAD
  dynamic _parseYAML() {
    try {
      return json.decode(json.encode(loadYaml(content)));
    } catch (e) {
      log.error('Could not parse configuration file: ${e.toString()}');
      File(location).writeAsStringSync(previousContent);
=======
  _parseYAML() {
    try {
      return json.decode(json.encode(loadYaml(_content)));
    } catch (e) {
      log.error('Could not parse configuration file: ${e.toString()}');
>>>>>>> Add new command pub config
      exit(1);
    }
  }

  List _findInsertionField(List<String> fields) {
    var datMap = Map.from(_parsedYAML);

<<<<<<< HEAD
    for (var i = 0; i < fields.length; i++) {
=======
    for (int i = 0; i < fields.length; i++) {
>>>>>>> Add new command pub config
      if (datMap.containsKey(fields[i]) && datMap[fields[i]] is Map) {
        datMap = datMap[fields[i]];
      } else {
        if (i > 0) {
          return [i - 1, fields[i - 1]];
<<<<<<< HEAD
        } else {
          return [null, null];
        }
=======
        } else
          return [null, null];
>>>>>>> Add new command pub config
      }
    }
    return [fields.length - 1, fields[fields.length - 1]];
  }

<<<<<<< HEAD
  dynamic _handleNestedFields(List<String> fields, value, index) {
    final fieldLength = fields.length;
    if (fieldLength < 2) return _parsedYAML;

    final searchResult = _findInsertionField(fields);
=======
  _handleNestedFields(List<String> fields, value, index) {
    final fieldLength = fields.length;
    if (fieldLength < 2) return _parsedYAML;

    List searchResult = _findInsertionField(fields);
>>>>>>> Add new command pub config

    final insertionIndex = searchResult[0] ?? 0;
    final insertionElement = searchResult[1] ?? fields[0];

    var pivot = _getPivot(fields, insertionIndex);

<<<<<<< HEAD
    dynamic actualValue;
=======
    var actualValue = null;
>>>>>>> Add new command pub config
    try {
      actualValue = pivot[insertionElement][fields[fieldLength - 1]];
    } catch (e) {
      actualValue = null;
    }

<<<<<<< HEAD
    Map nestedMap;
    if (actualValue is! List) {
      nestedMap = {fields[fieldLength - 1]: value};
    } else if (index != null) {
=======
    Map nestedMap = null;
    if (actualValue is! List)
      nestedMap = {fields[fieldLength - 1]: value};
    else if (index != null) {
>>>>>>> Add new command pub config
      actualValue[index] = value;
      nestedMap = {fields[fieldLength - 1]: actualValue};
    }

    //create nested map object
<<<<<<< HEAD
    for (var j = fieldLength - 2; j >= insertionIndex + 1; j--) {
      nestedMap = {fields[j]: nestedMap};
    }

    if (pivot[insertionElement] is! LinkedHashMap) {
      pivot[insertionElement] = nestedMap;
    } else {
      var tmp = Map.from(pivot[insertionElement]);
=======
    for (int j = fieldLength - 2; j >= insertionIndex + 1; j--) {
      nestedMap = {fields[j]: nestedMap};
    }

    if (pivot[insertionElement] is! LinkedHashMap)
      pivot[insertionElement] = nestedMap;
    else {
      Map tmp = Map.from(pivot[insertionElement]);
>>>>>>> Add new command pub config
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
<<<<<<< HEAD

  // TESTING

  void createEmptyConfigFile() {
    var file = File(location);
    file.writeAsStringSync('');
  }

  String previousContent = '';

  void makeInvalid() {
    previousContent = content;
    var file = File(location);
    file.writeAsStringSync('\ninvalid yaml content', mode: FileMode.append);
    _parsedYAML = _parseYAML();
  }
=======
>>>>>>> Add new command pub config
}
