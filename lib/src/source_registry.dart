// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'source.dart';
import 'source/git.dart';
import 'source/hosted.dart';
import 'source/path.dart';
import 'source/sdk.dart';
import 'source/unknown.dart';

/// A class that keeps track of [Source]s used for getting packages.
class SourceRegistry {
  /// The registered sources.
  ///
  /// This is initialized with the three built-in sources.
  final _sources = {
    'git': GitSource(),
    'hosted': HostedSource(),
    'path': PathSource(),
    'sdk': SdkSource()
  };

  /// The default source, which is used when no source is specified.
  ///
  /// This defaults to [hosted].
  Source get defaultSource => _default;
  Source _default;

  /// The registered sources, in name order.
  List<Source> get all {
    var sources = _sources.values.toList();
    sources.sort((a, b) => a.name.compareTo(b.name));
    return sources;
  }

  /// The built-in [GitSource].
  GitSource get git => _sources['git'] as GitSource;

  /// The built-in [HostedSource].
  HostedSource get hosted => _sources['hosted'] as HostedSource;

  /// The built-in [PathSource].
  PathSource get path => _sources['path'] as PathSource;

  /// The built-in [SdkSource].
  SdkSource get sdk => _sources['sdk'] as SdkSource;

  SourceRegistry() {
    _default = hosted;
  }

  /// Sets the default source.
  ///
  /// This takes a string, which must be the name of a registered source.
  void setDefault(String name) {
    if (!_sources.containsKey(name)) {
      throw StateError('Default source $name is not in the registry');
    }

    _default = _sources[name];
  }

  /// Registers a new source.
  ///
  /// This source may not have the same name as a source that's already been
  /// registered.
  void register(Source source) {
    if (_sources.containsKey(source.name)) {
      throw StateError('Source registry already has a source named '
          '${source.name}');
    }

    _sources[source.name] = source;
  }

  /// Returns the source named [name].
  ///
  /// Returns an [UnknownSource] if no source with that name has been
  /// registered. If [name] is null, returns the default source.
  Source operator [](String name) {
    if (name == null) return _default;
    if (_sources.containsKey(name)) return _sources[name];
    return UnknownSource(name);
  }
}
