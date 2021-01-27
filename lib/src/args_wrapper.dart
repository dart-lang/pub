import 'package:args/args.dart';
import 'package:meta/meta.dart';

abstract class Arg<T> {
  String name;

  final String help;
  final String abbr;
  final bool hide;

  String valueHelp;

  Arg._(
    this.name, {
    @required this.abbr,
    @required this.help,
    @required this.hide,
  });
}

class Flag extends Arg<bool> {
  final bool negatable;
  final bool defaultsTo;

  Flag(
    String name, {
    this.negatable,
    String abbr,
    String help,
    bool hide,
    this.defaultsTo,
  }) : super._(name, abbr: abbr, help: help, hide: hide);
}

class MultiOption extends Arg<List<String>> {
  final bool splitCommas;
  List<String> allowed;
  Map<String, String> allowedHelp;
  final List<String> defaultsTo;
  MultiOption(String name,
      {this.splitCommas,
      bool hide = false,
      String help,
      String abbr,
      this.allowed,
      this.allowedHelp,
      this.defaultsTo})
      : super._(name, abbr: abbr, help: help, hide: hide);
}

class Option extends Arg<String> {
  final List<String> allowed;
  final Map<String, String> allowedHelp;
  final String defaultsTo;
  Option(String name,
      {String abbr,
      String help,
      this.allowed,
      this.allowedHelp,
      this.defaultsTo,
      bool hide})
      : super._(name, abbr: abbr, help: help, hide: hide);
}

extension ArgResultExt on ArgResults {
  T get<T>(Arg<T> arg) => this[arg.name] as T;
  bool argWasParsed(Arg arg) => wasParsed(arg.name);
}

extension ArgParserExt on ArgParser {
  void add<T>(Arg<T> arg) {
    if (arg is Flag) {
      final flag = arg as Flag;
      addFlag(
        flag.name,
        abbr: flag.abbr,
        hide: flag.hide,
        defaultsTo: flag.defaultsTo,
        negatable: flag.negatable,
      );
    } else if (arg is MultiOption) {
      final multi = arg as MultiOption;
      addMultiOption(
        multi.name,
        abbr: multi.abbr,
        help: multi.help,
        allowed: multi.allowed,
        hide: multi.hide,
        defaultsTo: multi.defaultsTo,
        allowedHelp: multi.allowedHelp,
        valueHelp: multi.valueHelp,
        splitCommas: multi.splitCommas,
      );
    } else {
      final option = arg as Option;
      addOption(
        option.name,
        abbr: option.abbr,
        help: option.help,
        allowed: option.allowed,
        hide: option.hide,
        defaultsTo: option.defaultsTo,
        allowedHelp: option.allowedHelp,
        valueHelp: option.valueHelp,
      );
    }
  }
}
