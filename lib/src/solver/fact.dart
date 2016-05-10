import '../package.dart';

abstract class Cause {
  static const rootDependency = const _RootCause("root dependency");
  static const explicitDependency = const _RootCause("explicit dependency");
  static const packageNotFound = const _RootCause("package not found");
  static const badSdkVersion = const _RootCause("bad SDK version");
  static const unknownSource = const _RootCause("unknown dependency source");
}

class _RootCause implements Cause {
  final String _name;

  const _RootCause(this._name);

  String toString() => _name;
}

/// A context-independent truth about the package graph.
abstract class Fact implements Cause {
  List<Cause> get causes;
}

/// A package version covered by [allowed] is required.
class Required implements Fact {
  final List<Cause> causes;

  final PackageDep allowed;

  Required(this.allowed, [Iterable<Cause> causes])
      : causes = causes?.toList() ?? [Cause.rootDependency];
}

/// [package] can never be selected.
class Disallowed implements Fact {
  final List<Cause> causes;

  final PackageId package;

  Disallowed(this.package, Iterable<Cause> causes)
      : causes = causes.toList();
}

/// [depender] a package version covered by [allowed].
class Dependency implements Fact {
  final List<Cause> causes;

  final PackageId depender;

  final PackageDep allowed;

  Dependency(this.depender, this.allowed, [Iterable<Cause> causes])
      : causes = causes?.toList() ?? [Cause.explicitDependency];
}

/// No versions covered by [package1] may be selected along with any versions
/// covered by [package2].
class Incompatibility implements Fact {
  final List<Cause> causes;

  final PackageDep package1;
  final PackageDep package2;

  Incompatible(this.package1, this.package2, Iterable<Cause> causes)
      : causes = causes.toList() {
    assert(package1.name != package2.name);
  }
}
