import "../package.dart";
import "deduction.dart";
import "version_solver.dart";

class DeductionBuilder {
  final _ids = <PackageId>[];
  final _failures = <SolveFailure>[];

  DeductionBuilder(PackageId id, SolveFailure failure) {
    _ids.add(id);
    _failures.add(failure);
  }

  bool add(PackageId id, SolveFailure failure) {
    assert(id.toRef() == _ids.first.toRef());
    if (failure.runtimeType != _failures.first.runtimeType) return false;
    if (failure.package != _failures.first.package) return false;

    _failures.add(failure);
  }

  List<Deduction> build() {
    if (_failures.first is BadSdkVersionException) {
      return [new Required(_excludesIds, [Cause.badSdkVersion])];
    }

    if (_failures.first is UnknownSourceException) {
      // TODO: we should include information about what package was depended on.
      return [new Required(_excludesIds, [Cause.unknownSource])];
    }

    if (_failures.first is DisjointConstraintException ||
        _failures.first is SourceMismatchException ||
        _failures.first is DescriptionMismatchException) {
      return [new Dependency(_includesIds, _allowed)];
    }

    // TODO: what to do about NoVersionExceptions?
    return [];
  }

  PackageDep get _excludesIds {
    
  }

  PackageDep get _includesIds {
    
  }

  PackageDep get _allowed {
    var dependencies = _failures.map((failure) {
      return failure.dependencies
          .firstWhere((dep) => dep.depender.name == _ids.first.name);
    }).toList();

    var constraint = dependencies.reduce(
        (dep1, dep2) => dep1.dep.constraint.union(dep2.dep.constraint));

    return new dependencies.first.dep.withConstraint(constraint);
  }
}
