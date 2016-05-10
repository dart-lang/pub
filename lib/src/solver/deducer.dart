// At times we are able to transform one type of fact into another. We do this
// in a consistent direction to avoid circularity. The order of preferred types
// is generally in order of strength of claim:
//
// 1. [Required]
// 2. [Disallowed]
// 3. [Dependency]
// 4. [Incompatibility]
class Deducer {
  final SourceRegistry _sources;

  final _allIds = <PackageRef, List<PackageId>>{};

  final _required = <String, Required>{};

  // TODO: these maps should hash description as well, somehow
  final _disallowed = <PackageRef, Disallowed>{};

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
      // Note: every fact needs to check against its own type first and bail
      // early if it's redundant. This helps ensure that we don't get circular.
      var fact = _toProcess.removeFirst();
      if (fact is Required) {
        fact = _requiredIntoRequired(fact);
        if (fact == null) continue;

        if (!_requiredIntoDisallowed(fact)) continue;
        _requiredIntoDependencies(fact);
        _requiredIntoIncompatibilities(fact);
      } else if (fact is Disallowed) {
        if (!_disallowedIntoDisallowed(fact)) continue;
        if (!_disallowedIntoRequired(fact)) continue;
        _disallowedIntoDependencies(fact);
      }
    }
  }

  // Merge [fact] with an existing requirement for the same package, if
  // one exists.
  //
  // Returns the (potentially modified) fact, or `null` if no new information
  // was added.
  Required _requiredIntoRequired(Required fact) {
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
  bool _requiredIntoDisallowed(Required fact) {
    var disallowed = _disallowed[fact.dep.toRef()];
    if (disallowed == null) return true;

    // Remove [disallowed] since it's redundant with [fact]. We'll update [fact]
    // to encode the relevant information.
    _removeDisallowed(disallowed);

    // TODO: delete Disalloweds with the same name but different source/desc

    // If the required version was trimmed, stop processing, since we'll just
    // process the narrower version later on.
    return !_requiredAndDisallowed(fact, disallowed);
  }

  void _requiredIntoDependencies(Required fact) {
    var ref = fact.dep.toRef();
    for (var dependency in _dependenciesByDepender[ref].toList()) {
      if (!fact.dep.constraint.allowsAny(dependency.depender.constraint)) {
        // If [fact] doesn't allow any of the depender versions, the dependency
        // is irrelevant and we can remove it.
        _removeDependency(dependency);
      } else if (
          dependency.depender.constraint.allowsAll(fact.dep.constraint)) {
        // If all versions in [fact] have this dependency, then it can be
        // upgraded to a requirement.
        _removeDependency(dependency);
        _toProcess.add(new Requirement(dependency.allowed, [dependency, fact]));
      }
    }

    for (var dependency in _dependenciesByAllowed[ref].toList()) {
      var intersection = dependency.allowed.constraint.intersect(
          fact.dep.constraint);
      if (intersection == dependency.allowed.constraint) continue;

      _removeDependency(dependency);
      if (intersection.isEmpty) {
        // If there are no valid versions covered by both [dependency.allowed]
        // and [fact], then this dependency can never be satisfied and the
        // depender should be disallowed entirely.
        _toProcess.add(new Disallowed(dependency.depender, [dependency, fact]));
      } else if (intersection != fact.dep.constraint) {
        // If some but not all packages covered by [dependency.allowed] are
        // covered by [fact], replace [dependency] with one with a narrower
        // constraint.
        //
        // If [intersection] is exactly [fact.dep.constraint], then this
        // dependency adds no information in addition to [fact], so it can be
        // discarded entirely.
        _toProcess.add(new Dependency(
            dependency.depender,
            dependency.allowed.withConstraint(intersection),
            [dependency, fact]));
      }
    }
  }

  void _requiredIntoIncompatibilities(Required fact) {
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
        _toProcess.add(new Disallowed(
            fact.dep.withConstraint(compatible),
            [incompatibility, fact]));
      } else if (!fact.dep.allowsAll(compatible)) {
        // If [fact] allows versions outside of [same], then we can reframe this
        // incompatibility as a dependency from [different]. This is safe
        // because [fact.dep] needs to be selected anyway.
        //
        // There's no need to do this if *all* the versions allowed by [fact]
        // are outside of [same], since one of those versions is already
        // required.
        _toProcess.add(new Dependency(
            different,
            same.withConstraint(compatible),
            [incompatibility, fact]));
        }
      }
    }
  }

  bool _disallowedIntoDisallowed(Disallowed fact) {
    var ref = fact.dep.asRef();
    var existing = _disallowed[ref];
    if (existing == null) {
      _disallowed[ref] = fact;
      return true;
    }

    _disallowed[ref] = new Disallowed(
        _mergeDeps(fact.dep, existing.dep), [existing, fact]);
    return false;
  }

  bool _disallowedIntoRequired(Disallowed fact) {
    var required = _required[fact.dep.name];
    if (required == null) return true;

    // If there's a [Required] matching [fact], delete [fact] and modify the
    // [Required] instead. We prefer [Required] because it's more specific.
    _removeDisallowed(fact);
    _requiredAndDisallowed(required, disallowed);
    return false;
  }

  // Resolves [required] and [disallowed], which should refer to the same
  // package. Returns whether any required versions were trimmed.
  bool _requiredAndDisallowed(Required required, Disallowed disallowed) {
    assert(required.dep.toRef() == disallowed.dep.toRef());

    var difference = required.dep.constraint.difference(
        disallowed.dep.constraint);
    if (difference.isEmpty) throw "Incompatible constriants!";
    if (difference == required.dep.constraint) return false;

    _toProcess.add(new Required(
        required.dep.withConstraint(difference), [required, disallowed]));
    return true;
  }

  void _removeDependency(Dependency dependency);

  void _removeDisallowed(Disallowed disallowed);

  // Merge two deps, [_allIds] aware to reduce gaps. Algorithm TBD.
  PackageDep _mergeDeps(PackageDep dep1, PackageDep dep2);

  // Intersect two deps, return `null` if they aren't compatible (diff name, diff
  // source, diff desc, or non-overlapping).
  //
  // Should this reduce gaps? Are gaps possible if the inputs are fully merged?
  PackageDep _intersectDeps(PackageDep dep1, PackageDep dep2);

  // Returns packages allowed by [minuend] but not also [subtrahend].
  // PackageDep _depMinus(PackageDep minuend, PackageDep subtrahend);

  /// Returns whether [dep] allows [id] (name, source, description, constraint).
  // bool _depAllows(PackageDep dep, PackageId id);

  /// Returns whether [dep] allows any packages covered by [dep2] (name, source,
  /// description, constraint).
  // bool _depAllowsAny(PackageDep dep1, PackageDep dep2);

  /// Returns whether [dep] allows all packages covered by [dep2] (name, source,
  /// description, constraint).
  // bool _depAllowsAll(PackageDep dep1, PackageDep dep2);
}
