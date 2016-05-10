class Deducer {
  final SourceRegistry _sources;

  final _allIds = <PackageRef, List<PackageId>>{};

  final _required = <String, Required>{};

  final _disallowed = <PackageRef, Set<Disallowed>>{};

  final _dependenciesByDepender = <PackageRef, Set<Dependency>>{};

  final _dependenciesByAllowed = <PackageRef, Set<Dependency>>{};

  final _incompatibilities = <PackageId, Set<Incompatibility>>{};

  final _toProcess = new Queue<Fact>();

  void setAllIds(List<PackageId> ids) {
    var ref = ids.first.toRef();
    assert(ids.every((id) => id.toRef() == ref));
    _allIds[ref] = ids;
  }

  void add(Fact initial) {
    _toProcess.add(initial);

    while (!_toProcess.isEmpty) {
      var fact = _toProcess.removeFirst();
      if (fact is Required) {
        fact = _intersectRequired(fact);
        if (fact == null) continue;

        if (!_checkDisallowed(fact)) continue;

        _trimDependencies(fact);
        _trimIncompatibilities(fact);
      } else if (fact is Disallowed) {
        if (!_mergeDisallowed(fact)) continue;

        _trimRequired(fact);
      }
    }
  }

  // Merge [fact] with an existing requirement for the same package, if
  // one exists.
  //
  // Returns the (potentially modified) fact, or `null` if no new information
  // was added.
  Required _intersectRequired(Required fact) {
    var existing = _required[fact.name];
    if (existing == null) {
      _required[fact.name] = fact;
      return fact;
    }

    var intersection = _intersectDeps(existing.dep, fact.dep);
    if (intersection == null) {
      throw "Incompatible constraints!";
    }

    if (intersection.constraint == existing.dep.constraint) return null;

    _required[fact.name] = new Required(intersection, [existing, fact]);
    return _required[fact.name];
  }

  // Returns whether [fact] should continue to be processed as-is.
  bool _checkDisallowed(Required fact) {
    var disallowed = _disallowed[fact.dep.toRef()];
    if (disallowed == null) return true;

    var newDep = _depMinus(fact.dep, disallowed);
    if (newDep == null) throw "Incompatible constriants!";

    if (newDep.constraint == fact.dep.constraint) return true;

    _toProcess.add(new Required(newDep, [fact, disallowed]));
    return false;
  }

  void _trimDependencies(Required fact) {
    var factRef = fact.dep.toRef();
    for (var dependency in _dependenciesByDepender[factRef].toList()) {
      // Remove any dependencies from versions incompatible with [fact.dep],
      // since they'll never be relevant anyway.
      if (!_depAllows(fact.dep, dependency.depender)) {
        // TODO: should we keep some sort of first-class representation of the
        // cause draft so that removing a dependency removes all its
        // consequences?
        _removeDependency(dependency);
      }
    }

    for (var dependency in _dependenciesByAllowed[factRef].toList()) {
      // Remove any dependencies whose allowed versions are completely
      // incompatible with [fact.dep], since they'll never be relevant
      // anyway.
      var intersection = _intersectDeps(dependency.allowed, fact.dep);
      if (intersection == null) {
        _removeDependency(dependency);
        _toProcess.add(new Disallowed(dependency.depender, [dependency, fact]));
        continue;
      }

      _toProcess.add(new Dependency(
          dependency.depender, dependency.allowed.withConstraint(intersection),
          [dependency, fact]);
    }
  }

  void _trimIncompatibilities(Required fact) {
    // Remove any incompatibilities that are no longer relevant.
    for (var incompatibility in _incompatibilities[fact.dep.toRef()].toList()) {
      PackageDep same;
      PackageDep different;
      if (incompatibility.dep1.name == fact.dep.name) {
        same = incompatibility.dep1;
        different = incompatibility.dep2;
      } else {
        assert(incompatibility.dep2.name == fact.dep.name);
        same = incompatibility.dep2;
        different = incompatibility.dep1;
      }

      // The versions of [fact.dep] that are compatible with [different].
      var compatible = fact.dep.constraint.difference(same.constraint);
      _removeIncompatibility(incompatibility);

      if (compatible.isEmpty) {
        // If [fact] only allows versions in [same], then [different] is totally
        // disallowed.

        // TODO: make [Disallowed] take a PackageDep?
        for (var id in _idsForDep(same.withConstraint(compatible))) {
          _toProcess.add(new Disallowed(id, [incompatibility, fact]));
        }
      } else if (!fact.dep.allowsAll(compatible)) {
        // If [fact] allows versions outside of [same], then we can reframe this
        // incompatibility as a dependency from [different]. This is safe
        // because [fact.dep] needs to be selected anyway.
        //
        // There's no need to do this if *all* the versions allowed by [fact]
        // are outside of [same], since one of those versions is already
        // required.

        // TODO: make [Dependency] take a PackageDep?
        var newAllowed = same.withConstraint(compatible);
        for (var id in _idsForDep(newAllowed)) {
          _toProcess.add(
              new Dependency(id, newAllowed, [incompatibility, fact]));
        }
      }
    }
  }

  bool _mergeDisallowed(Disallowed fact) {
    var set = _disallowed.putIfAbsent(fact.asRef(), () => new Set());
    return set.add(fact);
  }

  /// Returns [dep] without matching of [ids], or `null` if this would produce
  /// an empty constraint.
  ///
  /// This should use [_allIds] to carve out slices where possible. Algorithm
  /// TBD.
  PackageDep _depMinus(PackageDep dep, Iterable<PackageId> ids);

  /// Intersect two deps, return `null` if they aren't compatible (diff name, diff
  /// source, diff desc, or non-overlapping).
  PackageDep _intersectDeps(PackageDep dep1, PackageDep dep2);

  /// Returns whether [dep] allows [id] (name, source, description, constraint).
  bool _depAllowed(PackageDep dep, PackageId id);
}
