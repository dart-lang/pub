// At times we are able to transform one type of fact into another. We do this
// in a consistent direction to avoid circularity. The order of preferred types
// is generally in order of strength of claim:
//
// 1. [Required]
// 2. [Disallowed]
// 3. [Dependency]
// 4. [Incompatibility]
//
// Note that we use [mathematical interval notation][] to write about version
// ranges. These have similar properties, but interval notation is much more
// concise. An interval like [1, 3) should be read as >=1.0.0 <3.0.0.
//
// [mathematical interval notation]: https://en.wikipedia.org/wiki/Interval_(mathematics)#Notations_for_intervals
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

  /// Facts derived from the current fact being processed in [add].
  ///
  /// These may or may not be added to [_toProcess], depending on whether the
  /// current fact ends up being determined to be redundant.
  final _fromCurrent = <Fact>[];

  void setAllIds(List<PackageId> ids) {
    var ref = ids.first.toRef();
    assert(ids.every((id) => id.toRef() == ref));
    _allIds[ref] = ids;
  }

  void add(Fact initial) {
    _toProcess.add(initial);

    while (!_toProcess.isEmpty) {
      _fromCurrent.clear();

      var fact = _toProcess.removeFirst();
      if (fact is Required) {
        fact = _requiredIntoRequired(fact);
        if (fact == null) continue;

        fact = _requiredIntoDisallowed(fact);
        if (fact == null) continue;

        _requiredIntoDependencies(fact);
        _requiredIntoIncompatibilities(fact);

        _required[fact.name] = fact;
      } else if (fact is Disallowed) {
        fact = _disallowedIntoDisallowed(fact);
        if (fact == null) continue;

        if (!_disallowedIntoRequired(fact)) continue;
        _disallowedIntoDependencies(fact);
        _disallowedIntoIncompatibilities(fact);

        _disallowed[fact.dep.toRef()] = fact;
      } else if (fact is Dependency) {
        fact = _dependencyIntoDependency(fact);
        if (fact == null) continue;

        fact = _dependencyIntoReqired(fact);
        if (fact == null) continue;

        fact = _dependencyIntoDisallowed(fact);
        if (fact == null) continue;

        _dependenciesByDepender
            .putIfAbsent(fact.depender.toRef(), () => new Set())
            .add(fact);
        _dependenciesByAllowed
            .putIfAbsent(fact.allowed.toRef(), () => new Set())
            .add(fact);
      }

      _toProcess.addAll(_fromCurrent);
    }
  }

  // Merge [fact] with an existing requirement for the same package, if
  // one exists.
  //
  // Returns the (potentially modified) fact, or `null` if no new information
  // was added.
  Required _requiredIntoRequired(Required fact) {
    var existing = _required[fact.name];
    if (existing == null) return fact;

    // If there are two requirements on the same package, intersect them. For
    // example, if
    //
    // * a [0, 2) is required (fact)
    // * a [1, 3) is required (existing)
    //
    // we can remove both [fact] and [existing] and add
    //
    // * a [1, 2) is required
    var intersection = _intersectDeps(existing.dep, fact.dep);
    if (intersection == null) {
      throw "Incompatible constraints!";
    }

    if (intersection.constraint == existing.dep.constraint) return null;
    _required.remove(fact.name);
    return new Required(intersection, [existing, fact]);
  }

  // Returns whether [fact] should continue to be processed as-is.
  Required _requiredIntoDisallowed(Required fact) {
    var ref = fact.dep.toRef();
    var disallowed = _disallowed[ref];
    if (disallowed == null) return fact;

    // Remove [disallowed] since it's redundant with [fact]. We'll update [fact]
    // to encode the relevant information.
    _disallowed.remove(ref);

    // TODO: delete Disalloweds with the same name but different source/desc

    return _requiredAndDisallowed(fact, disallowed);
  }

  void _requiredIntoDependencies(Required fact) {
    // TODO: remove dependencies from/onto packages with the same name but
    // non-matching sources.

    // Dependencies whose depender is exactly [fact.dep], grouped by the names
    // of packages they depend on.
    var matchingByAllowed = <String, Set<Dependency>>{};

    // Fill [matchingByAllowed] and trim any irrelevant dependencies while we're
    // at it.
    var ref = fact.dep.toRef();
    for (var dependency in _dependenciesByDepender[ref].toList()) {
      var intersection = fact.dep.constraint
          .intersect(dependency.depender.constraint);

      if (intersection.isEmpty) {
        // If no versions in [fact] have this dependency, then it's irrelevant.
        // For example, if
        //
        // * a [0, 1) is required (fact)
        // * a [1, 2) depends on b [0, 2) (dependency)
        //
        // we can throw away [dependency].
        _removeDependency(dependency);
      } else if (intersection != dependency.depender.constraint) {
        // If only some versions [dependency.depender] are in [fact], we can
        // trim the ones that aren't. For example, if
        //
        // * a [0, 2) is required (fact)
        // * a [1, 3) depends on b [0, 2) (dependency)
        //
        // we can remove [dependency] and add
        //
        // * a [1, 2) depends on b [0, 2) (newDependency)
        _removeDependency(dependency);
        var newDependency = new Dependency(
            dependency.depender.withConstraint(intersection),
            dependency.allowed,
            [dependency, fact]);
        _fromCurrent.add(newDependency);
        matchingByAllowed[newDependency.allowed.name] = newDependency;
      } else {
        matchingByAllowed[dependency.allowed.name] = dependency;
      }
    }

    // Go through the dependencies from [fact]'s package onto each other package
    // to see if we can create any new requirements from them. For example, if
    //
    // * a [0, 2) is required (fact)
    // * a [0, 1) depends on b [0, 1) (in matchingByAllowed)
    // * a [1, 2) depends on b [1, 2) (in matchingByAllowed)
    //
    // we can add
    //
    // * b [0, 2) is required
    for (var dependencies in matchingByAllowed.values) {
      var allowed = _transitiveAllowed(fact.dep, dependencies);
      if (allowed == null) continue;

      _fromCurrent.add(new Required(allowed, dependencies.toList()..add(fact)));

      // If [fact] was covered by a single dependency, that dependency is now
      // redundant and can be removed. For example, if
      //
      // * a [0, 2) is required (fact)
      // * a [0, 2) depends on b [0, 1) (in matchingByAllowed)
      //
      // we can remove the dependency and add
      //
      // * b [0, 1) is required
      if (dependencies.length == 1) _removeDependency(dependencies.single);
    }

    // Trim any dependencies whose allowed versions aren't covered by [fact].
    for (var dependency in _dependenciesByAllowed[ref].toList()) {
      var result = _requiredAndAllowed(fact, dependency);
      if (result == dependency) continue;

      _removeDependency(dependency);
      if (result != null) _fromCurrent.add(result);
    }
  }

  void _requiredIntoIncompatibilities(Required fact) {
    // Remove any incompatibilities that are no longer relevant.
    for (var incompatibility in _incompatibilities[fact.dep.toRef()].toList()) {
      var same = _matching(incompatibility, fact.dep);
      var different = _nonMatching(incompatibility, fact.dep);

      // The versions of [fact.dep] that aren't in [same], and thus that are
      // compatible with [different].
      var compatible = fact.dep.constraint.difference(same.constraint);
      _removeIncompatibility(incompatibility);

      if (compatible.isEmpty) {
        // If [fact] is incompatible with all versions of [different], then
        // [different] must be disallowed entirely. For example, if
        //
        // * a [0, 1) is required (fact)
        // * a [0, 1) is incompatible with b [0, 1) (incompatibility)
        //
        // we can remove [incompatibility] and add
        //
        // * b [0, 1) is disallowed
        _fromCurrent.add(new Disallowed(different, [incompatibility, fact]));
      } else if (compatible != fact.dep.constraint) {
        // If [fact] allows versions outside of [same], then we can reframe this
        // incompatibility as a dependency from [different] onto [fact.dep].
        // This is safe because [fact.dep] needs to be selected anyway. For
        // example, if
        //
        // * a [0, 2) is required (fact)
        // * a [0, 1) is incompatible with b [0, 1) (incompatibility)
        //
        // we can remove [incompatibility] and add
        //
        // * b [0, 1) depends on a [1, 2)
        _fromCurrent.add(new Dependency(
            different,
            same.withConstraint(compatible),
            [incompatibility, fact]));
      } else {
        // There's no need to do anything else if *all* the versions allowed by
        // [fact] are outside of [same], since one of those versions is already
        // required. For example, if
        //
        // * a [0, 1) is required (fact)
        // * a [1, 2) is incompatible with b [0, 1) (incompatibility)
        //
        // we can throw away [incompatibility].
      }
    }
  }

  Disallowed _disallowedIntoDisallowed(Disallowed fact) {
    var ref = fact.dep.asRef();
    var existing = _disallowed[ref];
    if (existing == null) return true;

    /// Merge two disalloweds on the same package. For example, if:
    ///
    /// * a [0, 1) is disallowed (fact)
    /// * a [1, 2) is disallowed (existing)
    ///
    /// we can remove both [fact] and [existing] and add
    ///
    /// * a [0, 2) is disallowed
    _disallowed.remove(ref);
    return new Disallowed(
        _mergeDeps([fact.dep, existing.dep]), [existing, fact]);
  }

  bool _disallowedIntoRequired(Disallowed fact) {
    var required = _required[fact.dep.name];
    if (required == null) return true;

    // If there's a [Required] matching [fact], delete [fact] and modify the
    // [Required] instead. We prefer [Required] because it's more specific. For
    // example, if
    //
    // * a [0, 1) is disallowed (fact)
    // * a [0, 2) is required (required)
    //
    // we can remove [fact] and [required] and add
    //
    // * a [1, 2) is required
    _required.remove(fact.dep.name);
    var trimmed = _requiredAndDisallowed(required, disallowed);

    // Add to [_toProcess] because [_fromCurrent] will get discarded when we
    // return `false`.
    if (trimmed != null) _toProcess.add(trimmed);
    return false;
  }

  void _disallowedIntoDependencies(Disallowed fact) {
    // Trim dependencies from [fact.dep].
    var ref = fact.dep.toRef();
    for (var dependency in _dependenciesByDepender[ref].toList()) {
      var result = _disallowedAndDepender(fact, dependency);
      if (result == dependency) continue;
      _removeDependency(dependency);
      if (result != null) _forCurrent.add(dependency);
    }

    // Trim dependencies onto [fact.dep].
    for (var dependency in _dependenciesByAllowed[ref].toList()) {
      var result = _disallowedAndAllowed(fact, dependency);
      if (result == dependency) continue;
      _removeDependency(dependency);
      _fromCurrent.add(result);
    }
  }

  void _disallowedIntoIncompatibilities(Disallowed fact) {
    // Remove any incompatibilities that are no longer relevant.
    for (var incompatibility in _incompatibilities[fact.dep.toRef()].toList()) {
      var same = _matching(incompatibility, fact.dep);
      var different = _nonMatching(incompatibility, fact.dep);

      var trimmed = same.constraint.difference(fact.dep.constraint);
      if (trimmed == same.constraint) continue;

      // If [fact] disallows some of the versions in [same], we create a new
      // incompatibility with narrower versions. For example, if
      //
      // * a [1, 2) is disallowed (fact)
      // * a [0, 2) is incompatible with b [0, 1) (incompatibility)
      //
      // we can remove [incompatibility] and add
      //
      // * a [0, 1) is incompatible with b [0, 1)
      //
      // If this would produce an empty constraint, we instead remove
      // [incompatibility] entirely.
      _removeIncompatibility(incompatibility);
      if (trimmed.isEmpty) continue;

      _fromCurrent.add(new Incompatibility(
          same.withConstraint(trimmed), different, [incompatibility, fact]));
    }
  }

  Dependency _dependencyIntoDependency(Dependency fact) {
    // Other dependencies from the same package onto the same target. This is
    // used later on to determine whether we can merge this with existing
    // dependencies.
    var siblings = <Dependency>[];

    // Check whether [fact] can be merged with other dependencies with the same
    // depender and allowed.
    for (var dependency in _dependenciesByDepender(fact.depender.toRef())) {
      if (dependency.allowed.toRef() != fact.allowed.toRef()) continue;

      if (dependency.allowed.constraint == fact.allowed.constraint) {
        // If [fact] has the same allowed constraint as [dependency], they can
        // be merged. For example, if
        //
        // * a [0, 1) depends on b [0, 1) (fact)
        // * a [1, 2) depends on b [0, 1) (dependency)
        //
        // we can remove both [fact] and [dependency] and add
        //
        // * a [0, 2) depends on b [0, 1).
        var merged = _mergeDeps([dependency.depender, fact.depender]);

        // If [fact] adds no new information to [dependency], it's redundant.
        if (merged.constraint == dependency.depender.constraint) return null;

        // If [fact] adds new information to [dependency], create a new
        // dependency for it.
        _removeDependency(dependency);
        fact = new Dependency(merged, fact.allowed, [dependency, fact]);
      } else if (
          dependency.depender.constraint.allowsAny(fact.depender.constraint)) {
        // If [fact] has a different allowed constraint than [dependency] but
        // their dependers overlap, remove the part that's overlapping. This
        // ensures that, for a given depender/allowed pair, there will be only
        // one dependency for each depender version.

        if (fact.allowed.constraint.allowsAll(dependency.allowed.constraint)) {
          // If [fact] allows strictly more versions than [dependency], remove
          // any overlap from [fact] because it's less specific. For example,
          // if
          //
          // * a [1, 3) depends on b [0, 2) (fact)
          // * a [2, 4) depends on b [1, 2) (dependency)
          //
          // we can remove [fact] and add
          //
          // * a [1, 2) depends on b [0, 2).
          var difference = _depMinus(fact.depender, dependency.depender);
          if (difference == null) return null;

          fact = new Dependency(difference, fact.allowed, [dependency, fact]);
        } else if (dependency.allowed.constraint
            .allowsAll(fact.allowed.constraint)) {
          _removeDependency(dependency);

          // If [dependency] allows strictly more versions than [fact], remove
          // any overlap from [dependency] because it's less specific. For
          // example, if
          //
          // * a [1, 3) depends on b [1, 2) (fact)
          // * a [2, 4) depends on b [0, 2) (dependency)
          //
          // we can remove [dependency] and add
          //
          // * a [3, 4) depends on b [0, 2).
          var difference = _depMinus(dependency.depender, fact.depender);
          if (difference == null) continue;

          _fromCurrent.add(new Dependency(
              difference, dependency.allowed, [dependency, fact]));
        } else {
          // If [fact] and [dependency]'s allowed targets overlap without one
          // being a subset of the other, we need to create a third dependency
          // that represents the intersection. For example, if
          //
          // * a [1, 3) depends on b [0, 2) (fact)
          // * a [2, 4) depends on b [1, 3) (dependency)
          //
          // we can remove both [fact] and [dependency] and add
          //
          // * a [1, 2) depends on b [0, 2)
          // * a [2, 3) depends on b [1, 2)
          // * a [3, 4) depends on b [1, 3)
          _removeDependency(dependency);

          var intersection = _intersectDeps(dependency.depender, fact.depender);
          _fromCurrent.add(new Dependency(
              intersection,
              _intersectDeps(dependency.allowed, fact.allowed),
              [dependency, fact]));

          var dependencyDifference = _depMinus(dependency, intersection);
          if (dependencyDifference != null) {
            // If [intersection] covers the entirety of [dependency], throw it
            // away; otherwise, trim it to exclude [intersection].
            _fromCurrent.add(new Dependency(
                dependencyDifference, dependency.allowed, [dependency, fact]));
          }

          var factDifference = _depMinus(fact, intersection);
          if (factDifference == null) return null;

          // If [intersection] covers the entirety of [fact], throw it away;
          // otherwise, trim it to exclude [intersection].
          fact = new Dependency(
              factDifference, fact.allowed, [dependency, fact]);
        }
      } else {
        siblings.add(dependency);
      }
    }

    // Merge [fact] with dependencies *from* [fact.allowed] to see if we can
    // deduce anything about transitive dependencies. For example, if
    //
    // * a [0, 1) depends on b [0, 2) (fact)
    // * b [0, 1) depends on c [0, 1) (in byAllowed)
    // * b [1, 2) depends on c [1, 2) (in byAllowed)
    //
    // we can add
    //
    // * a [0, 1) depends on c [0, 2)
    var byAllowed = groupBy(
        _dependenciesByDepender[fact.allowed.toRef()].where((dependency) =>
            fact.allowed.constraint.allowsAny(dependency.depender.constraint)),
        (dependency) => dependency.allowed.toRef());
    for (var dependencies in byAllowed.values) {
      var allowed = _transitiveAllowed(fact.allowed, dependencies);
      if (allowed == null) continue;

      _fromCurrent.add(new Dependency(
          fact.depender, allowed, dependencies.toList()..add(fact)));
    }

    for (var dependency in _dependenciesByAllowed[fact.depender.toRef()]) {
      if (!dependency.allowed.constraint.allowsAny(fact.depender.constraint)) {
        continue;
      }

      // Merge [fact] with dependencies *onto* [fact.depender]. For example, if
      //
      // * b [0, 1) depends on c [0, 1) (fact)
      // * b [1, 2) depends on c [1, 2) (in siblings)
      // * a [0, 1) depends on b [0, 2) (dependency)
      //
      // we can add
      //
      // * a [0, 1) depends on c [1, 2)
      var relevant = siblings
          .where((sibling) => dependency.allowed.constraint
              .allowsAny(sibling.depender.constraint))
          .toList()..add(fact);
      var allowed = _transitiveAllowed(fact.allowed, relevant);
      if (allowed == null) continue;

      _fromCurrent.add(new Dependency(
          dependency.depender, allowed, [dependency].addAll(relevant)));
    }

    return fact;
  }

  Dependency _dependencyIntoRequired(Dependency fact) {
    var required = _required[fact.depender.name];
    if (required != null) {
      if (required.toRef() != fact.depender.toRef()) return null;

      // Trim [fact] or throw it away if it's irrelevant. For example, if
      //
      // * a [0, 2) depends on b [0, 1) (fact)
      // * a [1, 3) is required (required)
      //
      // we can remove [fact] and add
      //
      // * a [1, 2) depends on b [0, 1)
      //
      // If this would produce an empty depender, we instead remove [dependency]
      // entirely.
      var intersection = required.dep.constraint
          .intersect(fact.depender.constraint);
      if (intersection.isEmpty) return null;
      if (intersection != fact.depender.constraint) {
        fact = new Dependency(
            fact.depender.withConstraint(intersection),
            fact.allowed,
            [required, fact]);
      }

      // If [fact]'s depender is required, see if we can come up with a merged
      // requirement based on all its dependers' dependencies. For example, if
      //
      // * a [0, 1) depends on b [0, 1) (fact)
      // * a [1, 2) depends on b [1, 2) (in siblings)
      // * a [0, 2) is required (required)
      //
      // we can add
      //
      // * b [0, 2) is required
      var allowedRef = fact.allowed.toRef();
      var siblings = _dependenciesByDepender[fact.depender.toRef()]
          .where((dependency) => dependency.allowed.toRef() == allowedRef)
          .toList()..add(fact);
      var allowed = _transitiveAllowed(fact.dep, sibilngs);
      if (allowed != null) {
        var newRequired = new Required(allowed, [required].addAll(siblings));

        // If [fact] entirely covered [required], [fact] is now redundant and
        // can be discarded. For example, if
        //
        // * a [0, 1) depends on b [0, 1) (fact)
        // * a [0, 1) is required (required)
        //
        // we can remove [fact] and add
        //
        // * b [0, 1) is required
        if (siblings.length == 1) {
          // Add to [_toProcess] because [_fromCurrent] will get discarded when
          // we return `null`.
          _toProcess.add(newRequired);
          return null;
        } else {
          _fromCurrent.add(newRequired);
        }
      }
    }

    /// Trim [fact]'s allowed version if it's not covered by a requirement.
    required = _required[fact.allowed.name];
    if (required == null) return fact;

    var result = _requiredAndAllowed(required, fact);
    if (result is! Disallowed) return result as Dependency;

    _toProcess.add(result);
    return null;
  }

  Dependency _dependencyIntoDisallowed(Dependency fact) {
    // Trim [fact] if some of its depender is disallowed.
    var disallowed = _disallowed[fact.depender.toRef()];
    if (disallowed != null) fact = _disallowedAndDepender(disallowed, fact);
    if (fact == null) return null;

    // Trim [fact] if some of its allowed versions are disallowed.
    disallowed = _disallowed[fact.allowed.toRef()];
    if (disallowed == null) return fact;
    var result = _disallowedAndAllowed(disallowed, fact);
    if (result is Dependency) return result;

    // Add to [_toProcess] because [_fromCurrent] will get discarded when we
    // return `null`.
    _toProcess.add(result);
    return null;
  }

  // Resolves [required] and [disallowed], which should refer to the same
  // package.
  //
  // Returns a trimmed copy of [required], or `null` if it had no overlap with
  // [disallowed].
  Required _requiredAndDisallowed(Required required, Disallowed disallowed) {
    assert(required.dep.toRef() == disallowed.dep.toRef());

    var difference = required.dep.constraint.difference(
        disallowed.dep.constraint);
    if (difference.isEmpty) throw "Incompatible constriants!";
    if (difference == required.dep.constraint) return null;

    return new Required(
        required.dep.withConstraint(difference), [required, disallowed]);
  }

  /// Resolves [required] and [dependency.allowed], which should refer to the
  /// same package.
  ///
  /// Returns a new fact to replace [dependency] (either a [Disallowed] or a
  /// [Dependency]), or `null` if the dependency is irrelevant.
  Fact _requiredAndAllowed(Required required, Dependency dependency) {
    assert(required.dep.name == dependency.allowed.name);

    var intersection = _intersectDeps(required.dep, dependency.allowed);
    if (intersection == null) {
      // If there are no versions covered by both [dependency.allowed] and
      // [required], then this dependency can never be satisfied and the
      // depender should be disallowed entirely. For example, if
      //
      // * a [0, 1) is required (required)
      // * b [0, 1) depends on a [1, 2) (dependency)
      //
      // we can remove [dependency] and add
      //
      // * b [0, 1) is disallowed
      return new Disallowed(dependency.depender, [dependency, required]);
    } else if (intersection.constraint == required.dep.constraint) {
      // If [intersection] is exactly [required.dep], then this dependency adds
      // no information in addition to [required], so it can be discarded
      // entirely. For example, if
      //
      // * a [0, 1) is required (required)
      // * b [0, 1) depends on a [0, 2) (dependency)
      //
      // we can throw away [dependency].
      return null;
    } else if (intersection.constraint == dependency.allowed.constraint) {
      // If [intersection] is exactly [dependency.allowed.constraint], then
      // [dependency] can be preserved as-is. For example, if
      //
      // * a [0, 2) is required (required)
      // * b [0, 1) depends on a [0, 1) (dependency)
      //
      // there are no changes to be made.
      return dependency;
    } else {
      // If some but not all packages covered by [dependency.allowed] are
      // covered by [required], replace [dependency] with one with a narrower
      // constraint. For example, if
      //
      // * a [0, 2) is required (required)
      // * b [0, 1) depends on a [1, 3) (dependency)
      //
      // we can remove [dependency] and add
      //
      // * b [0, 1) depends on a [1, 2)
      return new Dependency(
          dependency.depender, intersection, [dependency, required]);
    }
  }

  /// Resolves [disallowed] and [dependency.depender], which should refer to the
  /// same package.
  ///
  /// Returns a new [Dependency] to replace [dependency], or `null` if the
  /// dependency is irrelevant. This dependency may be identical to
  /// [dependency].
  Dependency _disallowedAndDepender(Disallowed disallowed,
      Dependency dependency) {
    assert(disallowed.dep.name == dependency.depender.name);

    var trimmed = _depMinus(dependency.depender, disallowed.dep);
    if (trimmed = null) {
      // If all versions in [dependency.depender] are covered by [disallowed],
      // the dependency is irrelevant and can be discarded. For example, if
      //
      // * a [0, 2) is disallowed (disallowed)
      // * a [0, 1) depends on b [0, 1) (depenency)
      //
      // we can throw away [dependency].
      return null;
    } else if (trimmed == depenendency.depender.constraint) {
      // If no versions in [dependency.depender] are covered by [disallowed],
      // the dependency is fine as-is. For example, if
      //
      // * a [0, 1) is disallowed (disallowed)
      // * a [1, 2) depends on b [0, 1) (depenency)
      //
      // there are no changes to be made.
      return dependency;
    } else {
      // If [disallowed] covers some but not all of [dependency.depender], trim
      // the dependency so that its depender doesn't include disallowed
      // versions. For example, if
      //
      // * a [0, 1) is disallowed (fact)
      // * a [0, 2) depends on b [0, 1) (dependency)
      //
      // we can remove [dependency] and add
      //
      // * a [1, 2) depends on b [0, 1)
      return new Dependency(
          trimmed, dependency.allowed, [dependency, disallowed]);
    }
  }

  /// Resolves [disallowed] and [dependency.allowed], which should refer to the
  /// same package.
  ///
  /// Returns a new fact to replace [dependency] (either a [Disallowed] or a
  /// [Dependency]).
  Fact _disallowedAndAllowed(Disallowed disallowed,
      Dependency dependency) {
    assert(disallowed.dep.name == dependency.allowed.name);

    var trimmed = _depMinus(dependency.allowed, disallowed.dep);
    if (trimmed = null) {
      // If all versions in [dependency.allowed] are covered by [disallowed],
      // then this dependency can never be satisfied and the depender should be
      // disallowed entirely. For example, if
      //
      // * a [0, 1) is disallowed (disallowed)
      // * b [0, 1) depends on a [0, 1) (depenency)
      //
      // we can throw away [dependency] and add
      //
      // * b [0, 1) is disallowed
      return new Disallowed(dependency.depender, [dependency, disallowed]);
    } else if (trimmed == depenendency.depender.constraint) {
      // If no versions in [dependency.allowed] are covered by [disallowed],
      // the dependency is fine as-is. For example, if
      //
      // * a [0, 1) is disallowed (disallowed)
      // * b [0, 1) depends on a [1, 2) (dependency)
      //
      // there are no changes to be made.
      return dependency;
    } else {
      // If [disallowed] covers some but not all of [dependency.allowed], trim
      // the dependency so that it doesn't allow disallowed versions. For
      // example, if
      //
      // * a [0, 1) is disallowed (fact)
      // * b [0, 1) depends on a [0, 2) (dependency)
      //
      // we can remove [dependency] and add
      //
      // * b [0, 1) depends on a [1, 2)
      return new Dependency(
          trimmed, dependency.allowed, [dependency, disallowed]);
    }
  }

  void _removeDependency(Dependency dependency);

  /// If [dependencies]' dependers cover all of [depender], returns the union of
  /// their allowed constraints.
  ///
  /// Returns `null` if the dependencies don't cover all of [depender] of the
  /// allowed constraints can't be merged.
  ///
  /// This assumes that [dependencies]' dependers are all on the same package as
  /// [depender].
  PackageDep _transitiveAllowed(PackageDep depender,
      Iterable<Dependency> dependencies) {
    // Union all the dependencies dependers. If we have dependency information
    // for all versions covered by [depender], we may be able to deduce a new
    // fact.
    var mergedDepender = _mergeDeps(dependencies.map((dependency) {
      assert(dependency.depender.toRef() == depender.toRef());
      return dependency.depender;
    }));
    if (!mergedDepender.constraint.allowsAll(depender.constraint)) return null;

    // If the dependencies cover all of [depender], try to union the allowed
    // versions to get the narrowest possible constraint that covers all
    // versions allowed by any selectable depender. There may be no such
    // constraint if different dependers use [allowed] from different sources
    // or with different descriptions.
    return _mergeDeps(dependencies.map((dependency) => dependency.allowed));
  }

  /// Returns the dependency in [incompatibility] whose name matches [dep].
  PackageDep _matching(Incompatibility incompatibility, PackageDep dep) =>
      incompatibility.dep1.name == dep.name
          ? incompatibility.dep1
          : incompatibility.dep2;

  /// Returns the dependency in [incompatibility] whose name doesn't match
  /// [dep].
  PackageDep _nonMatching(Incompatibility incompatibility, PackageDep dep) =>
      incompatibility.dep1.name == dep.name
          ? incompatibility.dep2
          : incompatibility.dep1;

  // Merge [deps], [_allIds]-aware to reduce gaps. `null` if the deps are
  // incompatible source/desc. Algorithm TBD.
  PackageDep _mergeDeps(Iterable<PackageDep> deps);

  // Intersect two deps, return `null` if they aren't compatible (diff name, diff
  // source, diff desc, or non-overlapping).
  //
  // Should this reduce gaps? Are gaps possible if the inputs are fully merged?
  PackageDep _intersectDeps(PackageDep dep1, PackageDep dep2);

  // Returns packages allowed by [minuend] but not also [subtrahend]. `null` if
  // the resulting constraint is empty.
  PackageDep _depMinus(PackageDep minuend, PackageDep subtrahend);

  /// Returns whether [dep] allows [id] (name, source, description, constraint).
  // bool _depAllows(PackageDep dep, PackageId id);

  /// Returns whether [dep] allows any packages covered by [dep2] (name, source,
  /// description, constraint).
  // bool _depAllowsAny(PackageDep dep1, PackageDep dep2);

  /// Returns whether [dep] allows all packages covered by [dep2] (name, source,
  /// description, constraint).
  // bool _depAllowsAll(PackageDep dep1, PackageDep dep2);
}
