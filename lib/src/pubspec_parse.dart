// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'exceptions.dart' show ApplicationException;
import 'log.dart' show warning, yellow;
import 'sdk.dart' show sdk;
import 'utils.dart'
    show equalsIgnoringPreRelease, identifierRegExp, reservedWords;

/// The default SDK upper bound constraint for packages that don't declare one.
///
/// This provides a sane default for packages that don't have an upper bound.
final _defaultUpperBoundSdkConstraint = VersionConstraint.parse('<2.0.0');

/// Whether or not to allow the pre-release SDK for packages that have an
/// upper bound Dart SDK constraint of <2.0.0.
///
/// If enabled then a Dart SDK upper bound of <2.0.0 is always converted to
/// <2.0.0-dev.infinity.
///
/// This has a default value of `true` but can be overridden with the
/// PUB_ALLOW_PRERELEASE_SDK system environment variable.
bool get _allowPreReleaseSdk => _allowPreReleaseSdkValue != 'false';

/// The value of the PUB_ALLOW_PRERELEASE_SDK environment variable, defaulted
/// to `true`.
final String _allowPreReleaseSdkValue = () {
  var value =
      Platform.environment['PUB_ALLOW_PRERELEASE_SDK']?.toLowerCase() ?? 'true';
  if (!['true', 'quiet', 'false'].contains(value)) {
    warning(yellow('''
The environment variable PUB_ALLOW_PRERELEASE_SDK is set as `$value`.
The expected value is either `true`, `quiet` (true but no logging), or `false`.
Using a default value of `true`.
'''));
    value = 'true';
  }
  return value;
}();

/// Whether or not to warn about pre-release SDK overrides.
bool get warnAboutPreReleaseSdkOverrides => _allowPreReleaseSdkValue != 'quiet';

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

  /// Whether or not to apply the [_defaultUpperBoundsSdkConstraint] to this
  /// pubspec.
  final bool _includeDefaultSdkConstraint;

  PubspecBase(
    this.fields, {
    String? name,
    Version? version,
    bool includeDefaultSdkConstraint = false,
    Map<String, VersionConstraint>? sdkConstraints,
  })  : _name = name,
        _version = version,
        _includeDefaultSdkConstraint = includeDefaultSdkConstraint,
        _sdkConstraints = sdkConstraints;

  /// The package's name.
  String get name {
    if (_name != null) return _name!;

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

    _name = name;
    return _name!;
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

  /// A map from SDK identifiers to constraints on those SDK versions.
  Map<String, VersionConstraint> get sdkConstraints {
    ensureEnvironment();
    return _sdkConstraints!;
  }

  Map<String, VersionConstraint>? _sdkConstraints;

  /// Whether or not the SDK version was overridden from <2.0.0 to
  /// <2.0.0-dev.infinity.
  bool get dartSdkWasOverridden => _dartSdkWasOverridden;
  bool _dartSdkWasOverridden = false;

  /// The original Dart SDK constraint as written in the pubspec.
  ///
  /// If [dartSdkWasOverridden] is `false`, this will be identical to
  /// `sdkConstraints["dart"]`.
  VersionConstraint? get originalDartSdkConstraint {
    ensureEnvironment();
    return _originalDartSdkConstraint ?? sdkConstraints['dart'];
  }

  VersionConstraint? _originalDartSdkConstraint;

  /// Ensures that the top-level "environment" field has been parsed and
  /// [_sdkConstraints] is set accordingly.
  @protected
  void ensureEnvironment() {
    if (_sdkConstraints != null) return;

    var sdkConstraints = parseEnvironment(fields);
    var parsedDartSdkConstraint = sdkConstraints['dart'];

    if (parsedDartSdkConstraint is VersionRange &&
        _shouldEnableCurrentSdk(parsedDartSdkConstraint)) {
      _originalDartSdkConstraint = parsedDartSdkConstraint;
      _dartSdkWasOverridden = true;
      sdkConstraints['dart'] = VersionRange(
          min: parsedDartSdkConstraint.min,
          includeMin: parsedDartSdkConstraint.includeMin,
          max: sdk.version,
          includeMax: true);
    }

    _sdkConstraints = UnmodifiableMapView(sdkConstraints);
  }

  /// Whether or not we should override [sdkConstraint] to be <= the user's
  /// current SDK version.
  ///
  /// This is true if the following conditions are met:
  ///
  ///   - [_allowPreReleaseSdk] is `true`
  ///   - The user's current SDK is a pre-release version.
  ///   - The original [sdkConstraint] max version is exclusive (`includeMax`
  ///     is `false`).
  ///   - The original [sdkConstraint] is not a pre-release version.
  ///   - The original [sdkConstraint] matches the exact same major, minor, and
  ///     patch versions as the user's current SDK.
  bool _shouldEnableCurrentSdk(VersionRange sdkConstraint) {
    if (!_allowPreReleaseSdk) return false;
    if (!sdk.version.isPreRelease) return false;
    if (sdkConstraint.includeMax) return false;
    if (sdkConstraint.min != null &&
        sdkConstraint.min!.isPreRelease &&
        equalsIgnoringPreRelease(sdkConstraint.min!, sdk.version)) {
      return false;
    }
    if (sdkConstraint.max == null) return false;
    if (sdkConstraint.max!.isPreRelease &&
        !sdkConstraint.max!.isFirstPreRelease) {
      return false;
    }
    return equalsIgnoringPreRelease(sdkConstraint.max!, sdk.version);
  }

  /// Parses the "environment" field in [parent] and returns a map from SDK
  /// identifiers to constraints on those SDKs.
  @protected
  Map<String, VersionConstraint> parseEnvironment(YamlMap parent) {
    var yaml = parent['environment'];
    if (yaml == null) {
      return {
        'dart': _includeDefaultSdkConstraint
            ? _defaultUpperBoundSdkConstraint
            : VersionConstraint.any
      };
    }

    if (yaml is! Map) {
      _error('"environment" field must be a map.',
          parent.nodes['environment']?.span);
    }

    var constraints = {
      'dart': parseVersionConstraint(yaml.nodes['sdk'],
          defaultUpperBoundConstraint: _includeDefaultSdkConstraint
              ? _defaultUpperBoundSdkConstraint
              : null)
    };
    yaml.nodes.forEach((name, constraint) {
      if (name.value is! String) {
        _error('SDK names must be strings.', name.span);
      } else if (name.value == 'dart') {
        _error('Use "sdk" to for Dart SDK constraints.', name.span);
      }
      if (name.value == 'sdk') return;

      constraints[name.value as String] = parseVersionConstraint(constraint,
          // Flutter constraints get special treatment, as Flutter won't be
          // using semantic versioning to mark breaking releases.
          ignoreUpperBound: name.value == 'flutter');
    });

    return constraints;
  }

  /// Parses [node] to a [VersionConstraint].
  ///
  /// If or [defaultUpperBoundConstraint] is specified then it will be set as
  /// the max constraint if the original constraint doesn't have an upper
  /// bound and it is compatible with [defaultUpperBoundConstraint].
  ///
  /// If [ignoreUpperBound] the max constraint is ignored.
  @protected
  VersionConstraint parseVersionConstraint(YamlNode? node,
      {VersionConstraint? defaultUpperBoundConstraint,
      bool ignoreUpperBound = false}) {
    if (node?.value == null) {
      return defaultUpperBoundConstraint ?? VersionConstraint.any;
    }
    if (node!.value is! String) {
      _error('A version constraint must be a string.', node.span);
    }

    return _wrapFormatException('version constraint', node.span, () {
      var constraint = VersionConstraint.parse(node.value);
      if (defaultUpperBoundConstraint != null &&
          constraint is VersionRange &&
          constraint.max == null &&
          defaultUpperBoundConstraint.allowsAny(constraint)) {
        constraint = VersionConstraint.intersection(
            [constraint, defaultUpperBoundConstraint]);
      }
      if (ignoreUpperBound && constraint is VersionRange) {
        return VersionRange(
            min: constraint.min, includeMin: constraint.includeMin);
      }
      return constraint;
    });
  }

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
