// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'exceptions.dart' show ApplicationException;
import 'utils.dart' show identifierRegExp, reservedWords;

/// A regular expression matching allowed package names.
///
/// This allows dot-separated valid Dart identifiers. The dots are there for
/// compatibility with Google's internal Dart packages, but they may not be used
/// when publishing a package to pub.dartlang.org.
final packageNameRegExp =
    RegExp('^${identifierRegExp.pattern}(\\.${identifierRegExp.pattern})*\$');

/// Helper class for pubspec parsing to:
/// - extract the fields and methods that are reusable outside of `pub` client, and
/// - help null-safety migration a bit.
///
/// This class should be eventually extracted to a separate library, or re-merged with `Pubspec`.
abstract class PubspecBase {
  /// All pubspec fields.
  ///
  /// This includes the fields from which other properties are derived.
  final YamlMap fields;

  PubspecBase(
    this.fields, {
    String? name,
    Version? version,
  })  : _name = name,
        _version = version;

  /// The package's name.
  String get name => _name ??= _lookupName();

  String _lookupName() {
    final name = fields['name'];
    if (name == null) {
      throw PubspecException('Missing the required "name" field.', fields.span);
    } else if (name is! String) {
      throw PubspecException(
          '"name" field must be a string.', fields.nodes['name']?.span);
    } else if (!packageNameRegExp.hasMatch(name)) {
      throw PubspecException('"name" field must be a valid Dart identifier.',
          fields.nodes['name']?.span);
    } else if (reservedWords.contains(name)) {
      throw PubspecException('"name" field may not be a Dart reserved word.',
          fields.nodes['name']?.span);
    }

    return name;
  }

  String? _name;

  /// The package's version.
  Version get version {
    if (_version != null) return _version!;

    final version = fields['version'];
    if (version == null) {
      _version = Version.none;
      return _version!;
    }

    final span = fields.nodes['version']?.span;
    if (version is num) {
      var fixed = '$version.0';
      if (version is int) {
        fixed = '$fixed.0';
      }
      _error(
          '"version" field must have three numeric components: major, '
          'minor, and patch. Instead of "$version", consider "$fixed".',
          span);
    }
    if (version is! String) {
      _error('"version" field must be a string.', span);
    }

    _version = _wrapFormatException(
        'version number', span, () => Version.parse(version));
    return _version!;
  }

  Version? _version;

  /// The URL of the server that the package should default to being published
  /// to, "none" if the package should not be published, or `null` if it should
  /// be published to the default server.
  ///
  /// If this does return a URL string, it will be a valid parseable URL.
  String? get publishTo {
    if (_parsedPublishTo) return _publishTo;

    final publishTo = fields['publish_to'];
    if (publishTo != null) {
      final span = fields.nodes['publish_to']?.span;

      if (publishTo is! String) {
        _error('"publish_to" field must be a string.', span);
      }

      // It must be "none" or a valid URL.
      if (publishTo != 'none') {
        _wrapFormatException('"publish_to" field', span, () {
          final url = Uri.parse(publishTo);
          if (url.scheme.isEmpty) {
            throw FormatException('must be an absolute URL.');
          }
        });
      }
    }

    _parsedPublishTo = true;
    _publishTo = publishTo;
    return _publishTo;
  }

  bool _parsedPublishTo = false;
  String? _publishTo;

  /// The list of patterns covering _false-positive secrets_ in the package.
  ///
  /// This is a list of git-ignore style patterns for files that should be
  /// ignored when trying to detect possible leaks of secrets during
  /// package publication.
  List<String> get falseSecrets {
    if (_falseSecrets == null) {
      final falseSecrets = <String>[];

      // Throws a [PubspecException]
      void _falseSecretsError(SourceSpan span) => _error(
            '"false_secrets" field must be a list of git-ignore style patterns',
            span,
          );

      final falseSecretsNode = fields.nodes['false_secrets'];
      if (falseSecretsNode != null) {
        if (falseSecretsNode is YamlList) {
          for (final node in falseSecretsNode.nodes) {
            final value = node.value;
            if (value is! String) {
              _falseSecretsError(node.span);
            }
            falseSecrets.add(value);
          }
        } else {
          _falseSecretsError(falseSecretsNode.span);
        }
      }

      _falseSecrets = List.unmodifiable(falseSecrets);
    }
    return _falseSecrets!;
  }

  List<String>? _falseSecrets;

  /// The executables that should be placed on the user's PATH when this
  /// package is globally activated.
  ///
  /// It is a map of strings to string. Each key is the name of the command
  /// that will be placed on the user's PATH. The value is the name of the
  /// .dart script (without extension) in the package's `bin` directory that
  /// should be run for that command. Both key and value must be "simple"
  /// strings: alphanumerics, underscores and hypens only. If a value is
  /// omitted, it is inferred to use the same name as the key.
  Map<String, String> get executables {
    if (_executables != null) return _executables!;

    _executables = {};
    var yaml = fields['executables'];
    if (yaml == null) return _executables!;

    if (yaml is! Map) {
      _error('"executables" field must be a map.',
          fields.nodes['executables']?.span);
    }

    yaml.nodes.forEach((key, value) {
      if (key.value is! String) {
        _error('"executables" keys must be strings.', key.span);
      }

      final keyPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
      if (!keyPattern.hasMatch(key.value)) {
        _error(
            '"executables" keys may only contain letters, '
            'numbers, hyphens and underscores.',
            key.span);
      }

      if (value.value == null) {
        value = key;
      } else if (value.value is! String) {
        _error('"executables" values must be strings or null.', value.span);
      }

      final valuePattern = RegExp(r'[/\\]');
      if (valuePattern.hasMatch(value.value)) {
        _error('"executables" values may not contain path separators.',
            value.span);
      }

      _executables![key.value] = value.value;
    });

    return _executables!;
  }

  Map<String, String>? _executables;

  /// Whether the package is private and cannot be published.
  ///
  /// This is specified in the pubspec by setting "publish_to" to "none".
  bool get isPrivate => publishTo == 'none';

  /// Runs [fn] and wraps any [FormatException] it throws in a
  /// [PubspecException].
  ///
  /// [description] should be a noun phrase that describes whatever's being
  /// parsed or processed by [fn]. [span] should be the location of whatever's
  /// being processed within the pubspec.
  ///
  /// If [targetPackage] is provided, the value is used to describe the
  /// dependency that caused the problem.
  T _wrapFormatException<T>(
      String description, SourceSpan? span, T Function() fn,
      {String? targetPackage}) {
    try {
      return fn();
    } on FormatException catch (e) {
      var msg = 'Invalid $description';
      if (targetPackage != null) {
        msg = '$msg in the "$name" pubspec on the "$targetPackage" dependency';
      }
      msg = '$msg: ${e.message}';
      throw PubspecException(msg, span);
    }
  }

  /// Throws a [PubspecException] with the given message.
  @alwaysThrows
  void _error(String message, SourceSpan? span) {
    throw PubspecException(message, span);
  }
}

/// An exception thrown when parsing a pubspec.
///
/// These exceptions are often thrown lazily while accessing pubspec properties.
class PubspecException extends SourceSpanFormatException
    implements ApplicationException {
  PubspecException(String message, SourceSpan? span) : super(message, span);
}
