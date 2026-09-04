// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart' hide mapMap;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'exceptions.dart';
import 'io.dart';
import 'language_version.dart';
import 'package.dart';
import 'package_name.dart';
import 'path.dart';
import 'pubspec_parse.dart';
import 'sdk.dart';
import 'source.dart';
import 'source/root.dart';
import 'system_cache.dart';

export 'pubspec_parse.dart' hide PubspecBase;

/// The default SDK upper bound constraint for packages that don't declare one.
///
/// This provides a sane default for packages that don't have an upper bound.
final VersionRange _defaultUpperBoundSdkConstraint =
    VersionConstraint.parse('<2.0.0') as VersionRange;

/// The parsed contents of a pubspec file.
///
/// The fields of a pubspec are, for the most part, validated when they're first
/// accessed. This allows a partially-invalid pubspec to be used if only the
/// valid portions are relevant. To get a list of all errors in the pubspec, use
/// [allErrors].
class Pubspec extends PubspecBase {
  // If a new lazily-initialized field is added to this class and the
  // initialization can throw a [PubspecException], that error should also be
  // exposed through [allErrors].

  /// The fields of [pubspecOverridesFilename]. `null` if no such file exists or
  /// has to be considered.
  final YamlMap? _overridesFileFields;

  String? get _packageName => fields['name'] != null ? name : null;

  final bool dependencyOverridesFromOverridesFile;

  /// The name of the manifest file.
  static const pubspecYamlFilename = 'pubspec.yaml';

  /// The filename of the pubspec overrides file.
  ///
  /// This file can contain dependency_overrides that override those in
  /// pubspec.yaml.
  static const pubspecOverridesFilename = 'pubspec_overrides.yaml';

  /// The registry of sources to use when parsing [dependencies] and
  /// [devDependencies].
  final SourceRegistry sources;

  /// It is used to resolve relative paths. And to resolve path-descriptions
  /// from a git dependency as git-descriptions.
  final ResolvedDescription _containingDescription;

  /// Directories of packages that should resolve together with this package.
  late List<String> workspace = () {
    final result = <String>[];
    final workspaceNode =
        _overridesFileFields?.nodes['workspace'] ?? fields.nodes['workspace'];
    if (workspaceNode != null && !languageVersion.supportsWorkspaces) {
      _error(
        '`workspace` and `resolution` requires at least language version '
        '${LanguageVersion.firstVersionWithWorkspaces}',
        workspaceNode.span,
        hint: '''
Consider updating the SDK constraint to:

environment:
  sdk: '^${sdk.version}'
''',
      );
    }
    if (workspaceNode == null || workspaceNode.value == null) return <String>[];

    if (workspaceNode is! YamlList) {
      _error('"workspace" must be a list of strings', workspaceNode.span);
    }
    for (final t in workspaceNode.nodes) {
      final value = t.value;
      if (value is! String) {
        _error('"workspace" must be a list of strings', t.span);
      }
      if (!p.isRelative(value)) {
        _error('"workspace" members must be relative paths', t.span);
      }
      if (p.equals(value, '.') || !p.isWithin('.', value)) {
        _error('"workspace" members must be subdirectories', t.span);
      }
      result.add(value);
    }
    return result;
  }();

  /// The resolution mode.
  late Resolution resolution = () {
    final resolutionNode =
        _overridesFileFields?.nodes['resolution'] ?? fields.nodes['resolution'];

    if (resolutionNode != null && !languageVersion.supportsWorkspaces) {
      _error(
        '`workspace` and `resolution` requires at least language version '
        '${LanguageVersion.firstVersionWithWorkspaces}',
        resolutionNode.span,
        hint: '''
Consider updating the SDK constraint to:

environment:
  sdk: '^${sdk.version}'
''',
      );
    }
    return switch (resolutionNode?.value) {
      null => Resolution.none,
      'local' => Resolution.local,
      'workspace' => Resolution.workspace,
      'external' => Resolution.external,
      _ => _error(
        '"resolution" must be one of `workspace`, `local`, `external`',
        resolutionNode!.span,
      ),
    };
  }();

  /// The workspace [Policies] configured in this pubspec, or `null` if none
  /// are defined.
  ///
  /// Parsed lazily on first access.
  Policies? get policies => _policies ??= _parsePolicies();
  Policies? _policies;

  Policies? _parsePolicies() {
    final policiesNode = fields.nodes['policies'];
    if (policiesNode == null || policiesNode.value == null) return null;

    if (!languageVersion.supportsCooldown) {
      _error(
        'The "policies" field requires at least language version '
        '${LanguageVersion.firstVersionWithCooldown}, '
        'current is $languageVersion.',
        policiesNode.span,
      );
    }

    if (policiesNode is! YamlMap) {
      _error('"policies" must be a map', policiesNode.span);
    }

    const knownPolicies = {'cooldown'};
    for (final keyNode in policiesNode.nodes.keys) {
      if (keyNode case YamlNode(value: final String value)) {
        if (!knownPolicies.contains(value)) {
          _error(
            'Invalid policies field "$value". '
            'Only ${knownPolicies.map((e) => '"$e"').join(', ')} is supported.',
            keyNode.span,
          );
        }
      }
    }

    final cooldownNode = policiesNode.nodes['cooldown'];
    final cooldown =
        cooldownNode == null || cooldownNode.value == null
            ? null
            : _parseCooldownPolicy(cooldownNode);

    return Policies(cooldown: cooldown, span: policiesNode.span);
  }

  CooldownPolicy _parseCooldownPolicy(YamlNode cooldownNode) {
    if (cooldownNode is! YamlMap) {
      _error('"cooldown" must be a map', cooldownNode.span);
    }

    final minAgeNode = cooldownNode.nodes['min_age'];
    final beforeNode = cooldownNode.nodes['before'];

    if (minAgeNode != null && beforeNode != null) {
      _error(
        'Only one of "min_age" and "before" can be specified.',
        cooldownNode.span,
      );
    }
    if (minAgeNode == null && beforeNode == null) {
      _error(
        'One of "min_age" or "before" must be specified.',
        cooldownNode.span,
      );
    }

    final excludeNode = cooldownNode.nodes['exclude'];
    final exclude =
        excludeNode != null
            ? _parseExclude(excludeNode)
            : const <String, VersionConstraint>{};

    final stabilityNode = cooldownNode.nodes['stability'];
    if (stabilityNode != null && beforeNode != null) {
      _error(
        '"stability" is only supported when "min_age" is specified.',
        stabilityNode.span,
      );
    }
    final stability =
        stabilityNode != null ? _parseStability(stabilityNode) : false;

    if (minAgeNode != null) {
      return CooldownPolicy.minAge(
        minAge: _parseMinAge(minAgeNode),
        exclude: exclude,
        stability: stability,
      );
    } else {
      return CooldownPolicy.before(
        before: _parseBefore(beforeNode!),
        exclude: exclude,
      );
    }
  }

  Duration _parseMinAge(YamlNode node) {
    if (node case YamlScalar(value: final String value)) {
      try {
        return _parseDuration(value);
      } on FormatException catch (e) {
        _error('Invalid "min_age": ${e.message}', node.span);
      }
    }
    _error('"min_age" must be a string', node.span);
  }

  DateTime _parseBefore(YamlNode node) {
    if (node case YamlScalar(value: final String value)) {
      if (!_utcIso8601RegExp.hasMatch(value)) {
        _error(
          '"before" must be a UTC timestamp in ISO 8601 format '
          '(e.g. "2026-05-28T09:09:29Z")',
          node.span,
        );
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null || !parsed.isUtc) {
        _error(
          '"before" must be a valid UTC timestamp in ISO 8601 format',
          node.span,
        );
      }
      return parsed;
    }
    _error('"before" must be a string', node.span);
  }

  Map<String, VersionConstraint> _parseExclude(YamlNode node) {
    if (node is! YamlMap) {
      _error('"exclude" must be a map', node.span);
    }
    final exclude = <String, VersionConstraint>{};
    for (final MapEntry(:key, :value) in node.nodes.entries) {
      final keyNode = key as YamlNode;
      final packageName = keyNode.value;
      if (packageName is! String) {
        _error('Exclude keys must be package names (strings).', keyNode.span);
      }
      if (!packageNameRegExp.hasMatch(packageName)) {
        _error('Not a valid package name.', keyNode.span);
      }
      exclude[packageName] = _parseVersionConstraint(
        value as YamlNode?,
        _packageName,
        _FileType.pubspec,
      );
    }
    return exclude;
  }

  bool _parseStability(YamlNode node) {
    if (node case YamlScalar(value: final bool value)) {
      return value;
    }
    _error('"stability" must be a boolean', node.span);
  }

  Duration _parseDuration(String s) {
    final match = _durationRegExp.firstMatch(s);
    if (match == null) {
      throw const FormatException(
        'Invalid duration format. Expected e.g. "7d" or "2w"',
      );
    }
    final value = int.parse(match.group(1)!);
    final unit = match.group(2)!;
    if (unit == 'd') {
      return Duration(days: value);
    } else if (unit == 'w') {
      return Duration(days: value * 7);
    }
    throw const FormatException('Invalid duration unit');
  }

  /// Matches a UTC timestamp in ISO 8601 format ending with 'Z'
  /// (e.g. "2026-05-28T09:09:29Z" or "2026-05-28Z").
  static final _utcIso8601RegExp = RegExp(
    r'^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?)?Z$',
  );

  /// Matches a duration string of digits followed by 'd' (days) or 'w' (weeks),
  /// such as "7d" or "2w".
  static final _durationRegExp = RegExp(r'^(\d+)([dw])$');

  /// The additional packages this package depends on.
  Map<String, PackageRange> get dependencies =>
      _dependencies ??= _parseDependencies(
        'dependencies',
        fields.nodes['dependencies'],
        sources,
        languageVersion,
        _packageName,
        _containingDescription,
      );

  Map<String, PackageRange>? _dependencies;

  /// The packages this package depends on when it is the root package.
  Map<String, PackageRange> get devDependencies =>
      _devDependencies ??= _parseDependencies(
        'dev_dependencies',
        fields.nodes['dev_dependencies'],
        sources,
        languageVersion,
        _packageName,
        _containingDescription,
      );

  Map<String, PackageRange>? _devDependencies;

  /// The dependency constraints that this package overrides when it is the root
  /// package.
  ///
  /// Dependencies here will replace any dependency on a package with the same
  /// name anywhere in the dependency graph.
  ///
  /// These can occur both in the pubspec.yaml file and the
  /// [pubspecOverridesFilename].
  Map<String, PackageRange> get dependencyOverrides {
    if (_dependencyOverrides != null) return _dependencyOverrides!;
    final pubspecOverridesFields = _overridesFileFields;
    if (pubspecOverridesFields != null) {
      if (pubspecOverridesFields.containsKey('dependency_overrides')) {
        _dependencyOverrides = _parseDependencies(
          'dependency_overrides',
          pubspecOverridesFields.nodes['dependency_overrides'],
          sources,
          languageVersion,
          _packageName,
          _containingDescription,
          fileType: _FileType.pubspecOverrides,
        );
      }
    }
    return _dependencyOverrides ??= _parseDependencies(
      'dependency_overrides',
      fields.nodes['dependency_overrides'],
      sources,
      languageVersion,
      _packageName,
      _containingDescription,
    );
  }

  Map<String, PackageRange>? _dependencyOverrides;

  SdkConstraint get dartSdkConstraint => sdkConstraints['dart']!;

  /// A map from SDK identifiers to constraints on those SDK versions.
  late final Map<String, SdkConstraint> sdkConstraints =
      _givenSdkConstraints ?? UnmodifiableMapView(_parseEnvironment(fields));

  final Map<String, SdkConstraint>? _givenSdkConstraints;

  /// Whether or not to apply the [_defaultUpperBoundSdkConstraint] to this
  /// pubspec.
  final bool _includeDefaultSdkConstraint;

  /// Parses the "environment" field in [parent] and returns a map from SDK
  /// identifiers to constraints on those SDKs.
  Map<String, SdkConstraint> _parseEnvironment(YamlMap parent) {
    final yaml = parent['environment'];
    final VersionConstraint originalDartSdkConstraint;
    if (yaml == null) {
      originalDartSdkConstraint = VersionConstraint.any;
    } else if (yaml is! YamlMap) {
      _error(
        '"environment" field must be a map.',
        parent.nodes['environment']!.span,
      );
    } else {
      originalDartSdkConstraint = _parseVersionConstraint(
        yaml.nodes['sdk'],
        _packageName,
        _FileType.pubspec,
      );
    }
    final dartConstraint = SdkConstraint.interpretDartSdkConstraint(
      originalDartSdkConstraint,
      defaultUpperBoundConstraint:
          _includeDefaultSdkConstraint ? _defaultUpperBoundSdkConstraint : null,
    );
    final constraints = {'dart': dartConstraint};

    if (yaml is YamlMap) {
      yaml.nodes.forEach((nameNode, constraintNode) {
        if (nameNode is! YamlNode) throw AssertionError('Bad state');
        final name = nameNode.value;
        if (name is! String) {
          _error('SDK names must be strings.', nameNode.span);
        } else if (name == 'dart') {
          _error('Use "sdk" to for Dart SDK constraints.', nameNode.span);
        }
        if (name == 'sdk') return;

        final constraint = _parseVersionConstraint(
          constraintNode,
          _packageName,
          _FileType.pubspec,
        );
        constraints[name] =
            name == 'flutter'
                ? SdkConstraint.interpretFlutterSdkConstraint(
                  constraint,
                  isRoot: _containingDescription is ResolvedRootDescription,
                  languageVersion: dartConstraint.languageVersion,
                )
                : SdkConstraint(constraint);
      });
    }
    return constraints;
  }

  /// The language version implied by the sdk constraint.
  LanguageVersion get languageVersion {
    return LanguageVersion.fromSdkConstraint(
      dartSdkConstraint.originalConstraint,
    );
  }

  /// Loads the pubspec for a package located in [packageDir].
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw a [SourceSpanApplicationException].
  ///
  /// If [allowOverridesFile] is `true` [pubspecOverridesFilename] is loaded and
  /// is allowed to override dependency_overrides from `pubspec.yaml`.
  factory Pubspec.load(
    String packageDir,
    SourceRegistry sources, {
    String? expectedName,
    bool allowOverridesFile = false,
    required ResolvedDescription containingDescription,
  }) {
    final pubspecPath = p.join(packageDir, pubspecYamlFilename);
    final overridesPath = p.join(packageDir, pubspecOverridesFilename);
    if (!fileExists(pubspecPath)) {
      throw FileException(
        // Make the package dir absolute because for the entrypoint it'll just
        // be ".", which may be confusing.
        'Could not find a file named "pubspec.yaml" in '
        '"${canonicalize(packageDir)}".',
        pubspecPath,
      );
    }
    final overridesFileContents =
        allowOverridesFile && fileExists(overridesPath)
            ? readTextFile(overridesPath)
            : null;

    return Pubspec.parse(
      readTextFile(pubspecPath),
      sources,
      expectedName: expectedName,
      location: p.toUri(pubspecPath),
      overridesFileContents: overridesFileContents,
      overridesLocation: p.toUri(overridesPath),
      containingDescription: containingDescription,
    );
  }

  /// Convenience helper to pass to [Package.load].
  static Pubspec Function(
    String dir, {
    String? expectedName,
    required bool withPubspecOverrides,
  })
  loadRootWithSources(SourceRegistry sources) {
    return (
      String dir, {
      String? expectedName,
      required bool withPubspecOverrides,
    }) => Pubspec.load(
      dir,
      sources,
      expectedName: expectedName,
      allowOverridesFile: withPubspecOverrides,
      containingDescription: ResolvedRootDescription.fromDir(dir),
    );
  }

  Pubspec(
    String name, {
    super.version,
    Iterable<PackageRange>? dependencies,
    Iterable<PackageRange>? devDependencies,
    Iterable<PackageRange>? dependencyOverrides,
    Map? fields,
    SourceRegistry? sources,
    Map<String, SdkConstraint>? sdkConstraints,
    this.workspace = const <String>[],
    this.dependencyOverridesFromOverridesFile = false,
    this.resolution = Resolution.none,
    Policies? policies,
  }) : _policies = policies,
       _dependencies =
           dependencies == null
               ? null
               : {for (final d in dependencies) d.name: d},
       _devDependencies =
           devDependencies == null
               ? null
               : {for (final d in devDependencies) d.name: d},
       _dependencyOverrides =
           dependencyOverrides == null
               ? null
               : {for (final d in dependencyOverrides) d.name: d},
       _givenSdkConstraints =
           sdkConstraints ??
           UnmodifiableMapView({'dart': SdkConstraint(VersionConstraint.any)}),
       _includeDefaultSdkConstraint = false,
       sources =
           sources ??
           ((String? name) => throw StateError('No source registry given')),
       _overridesFileFields = null,
       // This is a dummy value. Dependencies should already be resolved, so we
       // never need to do relative resolutions.
       _containingDescription = ResolvedRootDescription.fromDir('.'),
       super(fields == null ? YamlMap() : YamlMap.wrap(fields), name: name);

  /// Returns a Pubspec object for an already-parsed map representing its
  /// contents.
  ///
  /// If [expectedName] is passed and the pubspec doesn't have a matching name
  /// field, this will throw an [ApplicationException].
  ///
  /// [location] is the location from which this pubspec was loaded.
  Pubspec.fromMap(
    Map fields,
    this.sources, {
    YamlMap? overridesFields,
    String? expectedName,
    Uri? location,
    required ResolvedDescription containingDescription,
  }) : _overridesFileFields = overridesFields,
       _includeDefaultSdkConstraint = true,
       _givenSdkConstraints = null,
       dependencyOverridesFromOverridesFile =
           overridesFields != null &&
           overridesFields.containsKey('dependency_overrides'),
       _containingDescription = containingDescription,
       super(
         fields is YamlMap ? fields : YamlMap.wrap(fields, sourceUrl: location),
       ) {
    if (overridesFields != null) {
      overridesFields.nodes.forEach((key, _) {
        final keyNode = key as YamlNode;
        if (!const {
          'dependency_overrides',
          'resolution',
          'workspace',
        }.contains(keyNode.value)) {
          throw SourceSpanApplicationException(
            'pubspec_overrides.yaml only supports the '
            '`dependency_overrides`, `resolution` and `workspace` fields.',
            keyNode.span,
          );
        }
      });
    }
    // If [expectedName] is passed, ensure that the actual 'name' field exists
    // and matches the expectation.
    if (expectedName == null) return;
    if (name == expectedName) return;

    throw SourceSpanApplicationException(
      '"name" field doesn\'t match expected name '
      '"$expectedName".',
      this.fields.nodes['name']!.span,
    );
  }

  /// Parses the pubspec stored at [location] whose text is [contents].
  ///
  /// If the pubspec doesn't define a version for itself, it defaults to
  /// [Version.none].
  factory Pubspec.parse(
    String contents,
    SourceRegistry sources, {
    String? expectedName,
    Uri? location,
    String? overridesFileContents,
    Uri? overridesLocation,
    required ResolvedDescription containingDescription,
  }) {
    final YamlMap pubspecMap;
    YamlMap? overridesFileMap;
    try {
      pubspecMap = _ensureMap(loadYamlNode(contents, sourceUrl: location));
      if (overridesFileContents != null) {
        overridesFileMap = _ensureMap(
          loadYamlNode(overridesFileContents, sourceUrl: overridesLocation),
        );
      }
    } on YamlException catch (error) {
      throw SourceSpanApplicationException(error.message, error.span);
    }

    return Pubspec.fromMap(
      pubspecMap,
      sources,
      overridesFields: overridesFileMap,
      expectedName: expectedName,
      location: location,
      containingDescription: containingDescription,
    );
  }

  Pubspec copyWith({
    String? name,
    Version? version,
    Iterable<PackageRange>? dependencies,
    Iterable<PackageRange>? devDependencies,
    Iterable<PackageRange>? dependencyOverrides,
    Map? fields,
    Map<String, SdkConstraint>? sdkConstraints,
    List<String>? workspace,
    //this.dependencyOverridesFromOverridesFile = false,
    Resolution? resolution,
    Policies? policies,
  }) {
    return Pubspec(
      name ?? this.name,
      version: version ?? this.version,
      dependencies: dependencies ?? this.dependencies.values,
      devDependencies: devDependencies ?? this.devDependencies.values,
      dependencyOverrides:
          dependencyOverrides ?? this.dependencyOverrides.values,
      sdkConstraints: sdkConstraints ?? this.sdkConstraints,
      workspace: workspace ?? this.workspace,
      resolution: resolution ?? this.resolution,
      policies: policies ?? this.policies,
    );
  }

  /// Ensures that [node] is a mapping.
  ///
  /// If [node] is already a map it is returned.
  /// If [node] is yaml-null an empty map is returned.
  /// Otherwise an exception is thrown.
  static YamlMap _ensureMap(YamlNode node) {
    if (node is YamlScalar && node.value == null) {
      return YamlMap(sourceUrl: node.span.sourceUrl);
    } else if (node is YamlMap) {
      return node;
    } else {
      throw SourceSpanApplicationException(
        'The pubspec must be a YAML mapping.',
        node.span,
      );
    }
  }

  List<SourceSpanApplicationException> _collectErrorsFor(
    List<dynamic Function()> toCheck,
  ) {
    final errors = <SourceSpanApplicationException>[];
    void collectError(void Function() fn) {
      try {
        fn();
      } on SourceSpanApplicationException catch (e) {
        errors.add(e);
      }
    }

    for (final fn in toCheck) {
      collectError(fn);
    }
    return errors;
  }

  /// Returns a list of errors relevant to consuming this pubspec as a
  /// dependency
  ///
  /// This will return at most one error for each field.
  List<SourceSpanApplicationException> get dependencyErrors =>
      _collectErrorsFor([
        () => name,
        () => version,
        () => dependencies,
        () => executables,
        () => ignoredAdvisories,
      ]);

  /// Returns a list of most errors in this pubspec.
  ///
  /// This will return at most one error for each field.
  List<SourceSpanApplicationException> get allErrors => _collectErrorsFor([
    () => name,
    () => version,
    () => dependencies,
    () => devDependencies,
    () => publishTo,
    () => executables,
    () => falseSecrets,
    () => sdkConstraints,
    () => ignoredAdvisories,
  ]);

  /// Returns the type of dependency from this package onto [name].
  DependencyType dependencyType(String? name) {
    if (dependencies.containsKey(name)) {
      return DependencyType.direct;
    } else if (devDependencies.containsKey(name)) {
      return DependencyType.dev;
    } else {
      return DependencyType.none;
    }
  }
}

/// The type of dependency from one package to another.
enum DependencyType { direct, dev, none }

/// Parses the dependency field named [field], and returns the corresponding
/// map of dependency names to dependencies.
Map<String, PackageRange> _parseDependencies(
  String field,
  YamlNode? node,
  SourceRegistry sources,
  LanguageVersion languageVersion,
  String? packageName,
  ResolvedDescription containingDescription, {
  _FileType fileType = _FileType.pubspec,
}) {
  final dependencies = <String, PackageRange>{};

  // Allow an empty dependencies key.
  if (node == null || node.value == null) return dependencies;

  if (node is! YamlMap) {
    _error('"$field" field must be a map.', node.span);
  }

  final nonStringNode = node.nodes.keys.firstWhereOrNull(
    (e) => e is YamlScalar && e.value is! String,
  );
  if (nonStringNode != null) {
    _error(
      'A dependency name must be a string.',
      (nonStringNode as YamlNode).span,
    );
  }

  node.nodes.forEach((nameNode, specNode) {
    final name = (nameNode as YamlNode).value;
    if (name is! String) {
      _error('A dependency name must be a string.', nameNode.span);
    }
    if (!packageNameRegExp.hasMatch(name)) {
      _error('Not a valid package name.', nameNode.span);
    }
    final spec = specNode.value;
    if (packageName != null && name == packageName) {
      _error('A package may not list itself as a dependency.', nameNode.span);
    }

    final String? sourceName;
    VersionConstraint versionConstraint = VersionRange();
    YamlNode? descriptionNode;
    if (spec == null) {
      sourceName = null;
    } else if (spec is String) {
      sourceName = null;
      versionConstraint = _parseVersionConstraint(
        specNode,
        packageName,
        fileType,
      );
    } else if (specNode is YamlMap) {
      // Don't write to the immutable YAML map.
      final versionNode = specNode.nodes['version'];
      versionConstraint = _parseVersionConstraint(
        versionNode,
        packageName,
        fileType,
      );
      final otherEntries =
          specNode.nodes.entries
              .where((entry) => (entry.key as YamlNode).value != 'version')
              .toList();
      if (otherEntries.length > 1) {
        _error('A dependency may only have one source.', specNode.span);
      } else if (otherEntries.isEmpty) {
        // Default to a hosted dependency if no source is specified.
        sourceName = 'hosted';
      } else {
        switch (otherEntries.single) {
          case MapEntry(key: YamlScalar(value: final String s), value: final d):
            sourceName = s;
            descriptionNode = d;
          case MapEntry(key: final k, value: _):
            _error('A source name must be a string.', (k as YamlNode).span);
        }
      }
    } else {
      _error(
        'A dependency specification must be a string or a mapping.',
        specNode.span,
      );
    }

    // Let the source validate the description.
    final ref = _wrapFormatException(
      'description',
      descriptionNode?.span,
      () {
        return sources(sourceName).parseRef(
          name,
          descriptionNode?.value,
          containingDescription: containingDescription,
          languageVersion: languageVersion,
        );
      },
      packageName,
      fileType,
      targetPackage: name,
    );

    dependencies[name] = ref.withConstraint(versionConstraint);
  });

  return dependencies;
}

/// Parses [node] to a [VersionConstraint].
///
/// `null` is interpreted as [VersionConstraint.any].
///
/// A String is parsed with [VersionConstraint.parse].
VersionConstraint _parseVersionConstraint(
  YamlNode? node,
  String? packageName,
  _FileType fileType,
) {
  if (node?.value == null) {
    return VersionConstraint.any;
  }
  final value = node!.value;
  if (value is! String) {
    _error('A version constraint must be a string.', node.span);
  }

  return _wrapFormatException(
    'version constraint',
    node.span,
    () {
      final constraint = VersionConstraint.parse(value);
      return constraint;
    },
    packageName,
    fileType,
  );
}

/// Runs [fn] and wraps any [FormatException] it throws in a
/// [SourceSpanApplicationException].
///
/// [description] should be a noun phrase that describes whatever's being
/// parsed or processed by [fn]. [span] should be the location of whatever's
/// being processed within the pubspec.
///
/// If [targetPackage] is provided, the value is used to describe the
/// dependency that caused the problem.
T _wrapFormatException<T>(
  String description,
  SourceSpan? span,
  T Function() fn,
  String? packageName,
  _FileType fileType, {
  String? targetPackage,
}) {
  try {
    return fn();
  } on FormatException catch (e) {
    // If we already have a pub exception with a span, re-use that
    if (e is SourceSpanApplicationException) rethrow;

    var msg = 'Invalid $description';
    final typeName = _fileTypeName(fileType);
    if (targetPackage != null) {
      msg =
          '$msg in the "$packageName" $typeName on the "$targetPackage" '
          'dependency';
    }
    msg = '$msg: ${e.message}';
    _error(msg, span);
  }
}

/// Throws a [SourceSpanApplicationException] with the given message.
Never _error(String message, SourceSpan? span, {String? hint}) {
  throw SourceSpanApplicationException(message, span, hint: hint);
}

enum _FileType { pubspec, pubspecOverrides }

String _fileTypeName(_FileType type) {
  switch (type) {
    case _FileType.pubspec:
      return 'pubspec';
    case _FileType.pubspecOverrides:
      return 'pubspec override';
  }
}

/// There are special rules or interpreting SDK constraints, we take care to
/// save the original constraint as found in pubspec.yaml.
class SdkConstraint {
  /// The constraint as written in the pubspec.yaml.
  final VersionConstraint originalConstraint;

  /// The constraint as interpreted by pub.
  final VersionConstraint effectiveConstraint;

  SdkConstraint(
    this.effectiveConstraint, {
    VersionConstraint? originalConstraint,
  }) : originalConstraint = originalConstraint ?? effectiveConstraint;

  /// Implement support for down to 2.12 in the dart 3 series. Note that this
  /// function has to be be idempotent, because we apply it both when we write
  /// and read lock-file constraints, so applying this function a second time
  /// should have no further effect.
  factory SdkConstraint.interpretDartSdkConstraint(
    VersionConstraint originalConstraint, {
    required VersionConstraint? defaultUpperBoundConstraint,
  }) {
    var constraint = originalConstraint;
    if (defaultUpperBoundConstraint != null &&
        constraint is VersionRange &&
        constraint.max == null &&
        defaultUpperBoundConstraint.allowsAny(constraint)) {
      constraint = VersionConstraint.intersection([
        constraint,
        defaultUpperBoundConstraint,
      ]);
    }
    // If a package is null safe it should also be compatible with dart 3.
    // Therefore we rewrite a null-safety enabled constraint with the upper
    // bound <3.0.0 to be have upper bound <4.0.0
    //
    // Only do this rewrite after dart 3.
    if (sdk.version.major >= 3 &&
        constraint is VersionRange &&
        LanguageVersion.fromSdkConstraint(constraint) >=
            LanguageVersion.firstVersionWithNullSafety &&
        // <3.0.0 is parsed into a max of 3.0.0-0, so that is what we look for
        // here.
        constraint.max == Version(3, 0, 0).firstPreRelease &&
        constraint.includeMax == false) {
      constraint = VersionRange(
        min: constraint.min,
        includeMin: constraint.includeMin,
        // We don't have to use .firstPreRelease as the constructor will do that
        // if needed.
        max: Version(4, 0, 0),
      );
    }
    return SdkConstraint(constraint, originalConstraint: originalConstraint);
  }

  /// Flutter constraints get special treatment, as Flutter won't be using
  /// semantic versioning to mark breaking releases. We simply ignore upper
  /// bounds for dependencies.
  ///
  /// After language version
  /// [LanguageVersion.firstVersionRespectingFlutterBoundInRoots] for root
  /// packages we use the upper bound, allowing app developers to constrain the
  /// Flutter version.
  factory SdkConstraint.interpretFlutterSdkConstraint(
    VersionConstraint constraint, {
    required bool isRoot,
    required LanguageVersion languageVersion,
  }) {
    if (constraint is VersionRange) {
      if (!(isRoot && languageVersion.respectsFlutterBoundInRoots)) {
        return SdkConstraint(
          VersionRange(min: constraint.min, includeMin: constraint.includeMin),
          originalConstraint: constraint,
        );
      }
    }
    return SdkConstraint(constraint);
  }

  /// The language version of a constraint is determined from how it is written.
  LanguageVersion get languageVersion =>
      LanguageVersion.fromSdkConstraint(originalConstraint);

  // We currently don't call this anywhere - so this is only for debugging
  // purposes.
  @override
  String toString() {
    if (effectiveConstraint != originalConstraint) {
      return '$originalConstraint (interpreted as $effectiveConstraint)';
    }
    return effectiveConstraint.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is SdkConstraint &&
      other.effectiveConstraint == effectiveConstraint &&
      other.originalConstraint == originalConstraint;

  @override
  int get hashCode => Object.hash(effectiveConstraint, originalConstraint);
}

enum Resolution {
  // Still unused.
  external,
  // This package is a member of a workspace, and should be resolved with a
  // pubspec.yaml located higher.
  workspace,
  // Still unused.
  local,
  // This package is at the root of a workspace.
  none,
}

/// Represents workspace policies specified under the `policies` key in
/// `pubspec.yaml`.
///
/// For example:
/// ```yaml
/// policies:
///   cooldown:
///     min_age: 7d
///     stability: true
///     exclude:
///       foo: ^1.0.0
/// ```
final class Policies {
  /// The cooldown policy configuration, if defined.
  final CooldownPolicy? cooldown;

  /// The source span where the policy was declared in `pubspec.yaml`.
  final SourceSpan span;

  Policies({this.cooldown, required this.span});
}

/// A policy that restricts dependency versions based on publication age or an
/// absolute cutoff timestamp.
///
/// Cooldown policies mitigate supply-chain risks by delaying the adoption of
/// newly published versions, giving repositories and ecosystem tooling time to
/// detect and yank compromised or broken releases.
///
/// A [CooldownPolicy] is configured either with a relative minimum age via
/// [CooldownPolicy.minAge] or an absolute UTC cutoff date via
/// [CooldownPolicy.before].
final class CooldownPolicy {
  /// The minimum age a package release must have before it can be resolved.
  ///
  /// Exactly one of [minAge] and [before] is non-null.
  final Duration? minAge;

  /// The cutoff UTC timestamp after which package releases cannot be resolved.
  ///
  /// Exactly one of [minAge] and [before] is non-null.
  final DateTime? before;

  /// A map from package names to version constraints that are exempt from the
  /// cooldown policy.
  final Map<String, VersionConstraint> exclude;

  /// Whether to block releases that were followed by another release within the
  /// cooldown window (indicating an unstable release).
  final bool stability;

  /// Creates a cooldown policy requiring package releases to be at least
  /// [minAge] old.
  ///
  /// Packages matching [exclude] constraints are exempt from this policy.
  /// If [stability] is `true`, versions that were quickly superseded by newer
  /// releases within [minAge] will also be blocked.
  CooldownPolicy.minAge({
    required Duration this.minAge,
    required this.exclude,
    this.stability = false,
  }) : before = null;

  /// Creates a cooldown policy blocking package releases published after
  /// [before].
  ///
  /// Packages matching [exclude] constraints are exempt from this policy.
  CooldownPolicy.before({required DateTime this.before, required this.exclude})
    : minAge = null,
      stability = false;

  /// Returns `true` if the given package [version] is blocked by this policy.
  ///
  /// [packageName] is the name of the package.
  /// [version] is the version being evaluated.
  /// [published] is the publication date of the version, or `null` if unknown.
  /// [statusMap] contains status information (including publication dates) for
  /// all known versions of the package, used for evaluating stability rules.
  ///
  /// Packages exempt under [exclude] for the given [version] are never blocked.
  /// Versions without a [published] date are considered blocked unless
  /// excluded.
  bool isBlocked(
    String packageName,
    Version version,
    DateTime? published, [
    Map<Version, PackageStatus> statusMap = const {},
  ]) {
    final constraint = exclude[packageName];
    if (constraint != null && constraint.allows(version)) return false;
    if (published == null) return true;

    if (minAge case final minAge?) {
      final age = DateTime.now().difference(published);
      if (age < minAge) return true;

      if (stability) {
        for (final entry in statusMap.entries) {
          final v = entry.key;
          final pubDate = entry.value.published;
          if (v > version) {
            if (pubDate != null) {
              final diff = pubDate.difference(published);
              // We only care if the newer version was published *after* this
              // version (i.e., diff >= Duration.zero).
              //
              // If the newer version was published *before* this version,
              // diff is negative (which is always less than minAge). This can
              // happen if we publish a backported patch version for an older
              // release line long after a newer major version was already
              // released.
              //
              // For example, if 2.0.0 was published 30 days ago, and we publish
              // a backport 1.0.1 today (0 days ago), then:
              //   pubDate(2.0.0) - published(1.0.1) = -30 days.
              // Since -30 days < 7 days (minAge), 1.0.1 would be incorrectly
              // blocked by stability without the diff >= 0 check.
              if (diff >= Duration.zero && diff < minAge) {
                return true; // Blocked by stability!
              }
            } else {
              // If a newer version has no published date, it is considered
              // "too new" and thus breaks stability of older versions.
              return true;
            }
          }
        }
      }
    } else if (before case final before?) {
      if (published.isAfter(before)) return true;
    }

    return false;
  }
}
