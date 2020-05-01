import 'dart:convert';
import 'dart:io';

import '../command.dart';
import '../http.dart';
import '../log.dart' as log;
import '../pubspec.dart';
import '../solver.dart';
import '../source_registry.dart';

class AddCommand extends PubCommand {
  @override
  String get name => 'add';
  @override
  String get description =>
      'Retrieve a specific package and add it to pubspec.yaml';
  @override
  String get invocation => 'pub add <package> [--location=<URL>]';

  AddCommand() {
    argParser.addOption('location',
        abbr: 'l',
        help:
            'Specify the location from where the package will be downloaded from.');
  }

  @override
  Future run() async {
    if (argResults.rest.isEmpty) {
      printUsage();
      return;
    }
    final name = argResults.rest[0];
    final requestUrl =
        '${_hasExternalUrl() ? _getExternalUrl() : 'https://pub.dartlang.org'}/api/packages/$name';
    String latestVersion;

    if (!argResults.wasParsed('location')) {
      latestVersion = await _getLatestVersion(requestUrl);
      if (latestVersion == null) return;
    }

    var pubspecPath = Directory.current.path;
    if (Platform.isWindows) {
      pubspecPath = pubspecPath.substring(
          1,
          pubspecPath.indexOf('\:') > 0
              ? pubspecPath.indexOf('\:')
              : pubspecPath.length - 1);
    }
    final pubspec = Pubspec.load(pubspecPath, SourceRegistry());
    log.message('Found $name $latestVersion');
    if (pubspec.addDependency(name, latestVersion,
        url: argResults['location'])) {
      // url can be null
      await entrypoint.acquireDependencies(SolveType.GET);
    }
  }

  String _getExternalUrl() {
    if (argResults.wasParsed('location')) {
      return argResults['location'];
    } else if (Platform.environment.containsKey('PUB_HOSTED_URL')) {
      return Platform.environment['PUB_HOSTED_URL'];
    }
    return null;
  }

  Future<String> _getLatestVersion(String url) async {
    String latestVersion;
    try {
      latestVersion =
          json.decode((await httpClient.get(url)).body)['latest']['version'];
    } catch (e) {
      log.error(e.toString());
      log.error(
          'Could not find package ${url.split('/')[url.split('/').length - 1]} at $url');
      return null;
    }
    return latestVersion;
  }

  bool _hasExternalUrl() =>
      Platform.environment.containsKey('PUB_HOSTED_URL') ||
      argResults.wasParsed('location');
}
