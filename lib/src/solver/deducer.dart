// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

  final _maximizers = <PackageRef, ConstraintMaximizer>{};

  final _required = <String, Required>{};

  // TODO: these maps should hash description as well, somehow
  final _disallowed = <PackageRef, Disallowed>{};

  final _dependenciesByDepender = <PackageRef, Set<Dependency>>{};

  final _dependenciesByAllowed = <PackageRef, Set<Dependency>>{};

  final _incompatibilities = <PackageRef, Set<Incompatibility>>{};

  final _toProcess = new Queue<Fact>();

  /// Facts derived from the current fact being processed in [add].
  ///
  /// These may or may not be added to [_toProcess], depending on whether the
  /// current fact ends up being determined to be redundant.
  final _fromCurrent = <Fact>[];

  void setAllIds(Iterable<PackageId> ids) {
    var ref = ids.first.toRef();
    assert(ids.every((id) => id.toRef() == ref));
    _allIds[ref] = new ConstraintMaximizer(ids.map((id) => id.version));
  }

  void add(Fact initial) {
    _toProcess.add(initial);

    while (!_toProcess.isEmpty) {
      _fromCurrent.clear();

      var fact = _toProcess.removeFirst();
      if (fact is Required) {
        if (!_requiredIntoRequired(fact)) continue;
        if (!_requiredIntoDisallowed(fact)) continue;
        _requiredIntoDependencies(fact);
        _requiredIntoIncompatibilities(fact);

        _required[fact.name] = fact;
      } else if (fact is Disallowed) {
        if (!_disallowedIntoDisallowed(fact)) continue;
        if (!_disallowedIntoRequired(fact)) continue;
        _disallowedIntoDependencies(fact);
        _disallowedIntoIncompatibilities(fact);

        _disallowed[fact.dep.toRef()] = fact;
      } else if (fact is Dependency) {
        if (!_dependencyIntoDependency(fact)) continue;
        if (!_dependencyIntoReqired(fact)) continue;
        if (!_dependencyIntoDisallowed(fact)) continue;
        _dependencyIntoIncompatibilities(fact);

        _dependenciesByDepender
            .putIfAbsent(fact.depender.toRef(), () => new Set())
            .add(fact);
        _dependenciesByAllowed
            .putIfAbsent(fact.allowed.toRef(), () => new Set())
            .add(fact);
      } else if (fact is Incompatibility) {
        if (!_incompatibilityIntoIncompatibilities(fact)) continue;
        if (!_incompatibilityIntoDisallowed(fact)) continue;
        if (!_incompatibilityIntoRequired(fact)) continue;
        if (!_incompatibilityIntoDependencies(fact)) continue;

        _incompatibilities
            .putIfAbsent(fact.dep1.toRef(), () => new Set())
            .add(fact);
        _incompatibilities
            .putIfAbsent(fact.dep2.toRef(), () => new Set())
            .add(fact);
      }

      _toProcess.addAll(_fromCurrent);
    }
  }

  bool _requiredIntoRequired(Required fact) {
    var existing = _required[fact.name];
    if (existing == null) return true;

    var intersection = _intersectDeps(existing.dep, fact.dep);
    if (intersection == null) {
      throw "Incompatible constraints!";
    } else if (intersection == existing.dep) {
      // If [existing] is a subset of [fact], then [fact] is redundant. For
      // example, if
      //
      // * a [0, 2) is required (fact)
      // * a [0, 1) is required (existing)
      //
      // we can throw away [fact].
      return false;
    } else if (intersection == existing.dep) {
      // If [fact] is a subset of [existing], then [existing] is redundant. For
      // example, if
      //
      // * a [0, 1) is required (fact)
      // * a [0, 2) is required (existing)
      //
      // we can throw away [existing].
      _required.remove(fact.name);
      return true;
    } else {
      // Otherwise, create a new requirement from the intersection. For example,
      // if
      //
      // * a [0, 2) is required (fact)
      // * a [1, 3) is required (existing)
      //
      // we can remove both [fact] and [existing] and add
      //
      // * a [1, 2) is required
      _required.remove(fact.name);
      _replaceCurrent(new Required(intersection, [existing, fact]));
      return false;
    }
  }

  // Returns whether [fact] should continue to be processed as-is.
  bool _requiredIntoDisallowed(Required fact) {
    var ref = fact.dep.toRef();
    var disallowed = _disallowed[ref];
    if (disallowed == null) return true;

    // Remove [disallowed] since it's redundant with [fact]. We'll update [fact]
    // to encode the relevant information.
    _disallowed.remove(ref);

    var trimmed = _requiredAndDisallowed(fact, disallowed);
    if (trimmed != null) _replaceCurrent(trimmed);
    return false;
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
      _removeIncompatibility(incompatibility);
      var result = _requiredAndIncompatibility(required, incompatibility);
      if (result != null) _fromCurrent.add(result);
    }
  }

  bool _disallowedIntoDisallowed(Disallowed fact) {
    var ref = fact.dep.asRef();
    var existing = _disallowed[ref];
    if (existing == null) return true;

    var merged = _mergeDeps([fact.dep, existing.dep]);
    if (merged == existing.dep) {
      // If [existing] is a superset of [fact], then [fact] is redundant. For
      // example, if
      //
      // * a [0, 1) is disallowed (fact)
      // * a [0, 2) is disallowed (existing)
      //
      // we can throw away [fact].
      return false;
    } else if (merged == fact.dep) {
      // If [fact] is a superset of [existing], then [existing] is redundant.
      // For example, if
      //
      // * a [0, 2) is disallowed (fact)
      // * a [0, 1) is disallowed (existing)
      //
      // we can throw away [existing].
      _disallowed.remove(ref);
      return true;
    } else {
      // Otherwise, we merge the two facts together. For example, if
      //
      // * a [0, 1) is disallowed (fact)
      // * a [1, 2) is disallowed (existing)
      //
      // we can remove both [fact] and [existing] and add
      //
      // * a [0, 2) is disallowed
      _disallowed.remove(ref);
      _replaceCurrent(new Disallowed(merged, [existing, fact]));
      return false;
    }
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
    if (trimmed != null) _replaceCurrent(trimmed);
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
      var result = _disallowedAndAllowed(fact, incompatibility);
      if (result == incompatibility) continue;
      _removeIncompatibility(incompatibility);
      if (result != null) _fromCurrent.add(result);
    }
  }

  bool _dependencyIntoDependency(Dependency fact) {
    // Other dependencies from the same package onto the same target. This is
    // used later on to determine whether we can merge this with existing
    // dependencies.
    var siblings = <Dependency>[];

    // Check whether [fact] can be merged with other dependencies with the same
    // depender and allowed.
    for (var dependency in _dependenciesByDepender(fact.depender.toRef())) {
      if (dependency.allowed.toRef() != fact.allowed.toRef()) continue;

      if (dependency.allowed == fact.allowed) {
        var merged = _mergeDeps([dependency.depender, fact.depender]);
        if (merged == dependency.depender) {
          // If [fact.depender] is a subset of [dependency.depender], [fact] is
          // redundant. For example, if
          //
          // * a [0, 1) depends on b [0, 1) (fact)
          // * a [0, 2) depends on b [0, 1) (dependency)
          //
          // we can throw away [fact].
          return false;
        } else if (merged == fact.depender) {
          // If [dependency.depender] is a subset of [fact.depender],
          // [dependency] is redundant. For example, if
          //
          // * a [0, 2) depends on b [0, 1) (fact)
          // * a [0, 1) depends on b [0, 1) (dependency)
          //
          // we can throw away [dependency].
          _removeDependency(dependency);
        } else {
          // Otherwise, create a new requirement from the union. For example, if
          //
          // * a [0, 1) depends on b [0, 1) (fact)
          // * a [1, 2) depends on b [0, 1) (dependency)
          //
          // we can remove both [fact] and [dependency] and add
          //
          // * a [0, 2) depends on b [0, 1).
          _removeDependency(dependency);
          _replaceCurrent(
              new Dependency(merged, fact.allowed, [dependency, fact]));
          return false;
        }
        continue;
      }

      if (!dependency.depender.constraint.allowsAny(fact.depender.constraint)) {
        // If the dependers don't overlap at all and the allowed versions are
        // different, there's no useful merging we can do.
        siblings.add(dependency);
        continue;
      }

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
        if (difference != null) {
          _replaceCurrent(new Dependency(
              difference, fact.allowed, [dependency, fact]));
        }
        return false;
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

        // Add the new dependencies to [_toProcess] so they don't get thrown
        // away when we return `false`.
        _toProcess.add(new Dependency(
            _intersectDeps(dependency.depender, fact.depender),
            _intersectDeps(dependency.allowed, fact.allowed),
            [dependency, fact]));

        var dependencyDifference = _depMinus(dependency, fact.depender);
        if (dependencyDifference != null) {
          // If [intersection] covers the entirety of [dependency], throw it
          // away; otherwise, trim it to exclude [intersection].
          _toProcess.add(new Dependency(
              dependencyDifference, dependency.allowed, [dependency, fact]));
        }

        var factDifference = _depMinus(fact, dependency.depender);
        if (factDifference != null) {
          // If [intersection] covers the entirety of [fact], throw it away;
          // otherwise, trim it to exclude [intersection].
          _toProcess.add(new Dependency(
              factDifference, fact.allowed, [dependency, fact]));
        }

        return false;
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

    return true;
  }

  bool _dependencyIntoRequired(Dependency fact) {
    var required = _required[fact.depender.name];
    if (required != null) {
      if (required.toRef() != fact.depender.toRef()) return false;

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
      if (intersection.isEmpty) return false;
      if (intersection != fact.depender.constraint) {
        _replaceCurrent(new Dependency(
            fact.depender.withConstraint(intersection),
            fact.allowed,
            [required, fact]));
        return false;
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
          _replaceCurrent(newRequired);
          return false;
        } else {
          _fromCurrent.add(newRequired);
        }
      }
    }

    /// Trim [fact]'s allowed version if it's not covered by a requirement.
    required = _required[fact.allowed.name];
    if (required == null) return true;

    var result = _requiredAndAllowed(required, fact);
    if (result == fact) return true;
    if (result != null) _replaceCurrent(result);
    return false;
  }

  bool _dependencyIntoDisallowed(Dependency fact) {
    // Trim [fact] if some of its depender is disallowed.
    var disallowed = _disallowed[fact.depender.toRef()];
    if (disallowed != null) {
      var result = _disallowedAndDepender(disallowed, fact);
      if (result != fact) {
        if (result != null) _replaceCurrent(result);
        return false;
      }
    }

    // Trim [fact] if some of its allowed versions are disallowed.
    disallowed = _disallowed[fact.allowed.toRef()];
    if (disallowed != null) {
      var result = _disallowedAndAllowed(disallowed, fact);
      if (result != fact) {
        if (result != null) _replaceCurrent(result);
        return false;
      }
    }

    return true;
  }

  void _dependencyIntoIncompatibilities(Dependency fact) {
    var byNonMatching = groupBy(
        _incompatibilities[fact.allowed.toRef()],
        (incompatibility) =>
            _nonMatching(incompatibility, fact.allowed).toRef());
    for (var incompatibilities in byNonMatching.values) {
      // If there are incompatibilities where one side covers a [fact.allowed]
      // and the other side has a non-empty intersection, we can create a new
      // incompatibility for [fact.depender]. For example, if
      //
      // * a [0, 1) depends on b [0, 2) (fact)
      // * b [0, 1) is incompatible with c [0, 2) (in incompatibilities)
      // * b [1, 2) is incompatible with c [1, 3) (in incompatibilities)
      //
      // we can add
      //
      // * a [0, 1) is incompatible with c [1, 3)
      var incompatible = _transitiveIncompatible(
          fact.allowed, incompatibilities);
      if (incompatible == null) continue;

      _forCurrent.add(new Incompatibility(fact.depender, incompatible,
          incompatibilities.toList()..add(fact)));
    }
  }

  bool _incompatibilityIntoIncompatibilities(Incompatibility fact) {
    merge(PackageDep dep) {
      assert(dep == fact.dep1 || dep == fact.dep2);
      var otherDep = dep == fact.dep1 ? fact.dep2 : fact.dep1;

      for (var incompatibility in _incompatibilities[dep.toRef()]) {
        // Try to merge [fact] with adjacent incompatibilities. For example, if
        //
        // * a [0, 1) is incompatible with b [0, 1) (fact)
        // * a [1, 2) is incompatible with b [0, 1) (incompatibility)
        //
        // we can remove [fact] and [incompatibility] and add
        //
        // * a [0, 2) is incompatible with b [0, 1)
        var different = _nonMatching(incompatibility, dep);
        if (different != otherDep) continue;

        var same = _matching(incompatibility, dep);
        var merged = _mergeDeps([dep, same]);
        if (merged == null) continue;
        _removeIncompatibility(incompatibility);
        _replaceCurrent(
            new Incompatibility(merged, otherDep, [incompatibility, fact]));
        return false;
      }

      return true;
    }

    return merge(fact.dep1) && merge(fact.dep2);
  }

  bool _incompatibilityIntoRequired(Incompatibility fact) {
    // We only have to resolve one [Required], since it will always cause us to
    // remove the incompatibility and add a new fact of a different type.
    var required = _required[fact.dep1.name] ?? _required[fact.dep2.name];
    if (required == null) return true;
    var result = _requiredAndIncompatibility(fact);

    if (result != null) _replaceCurrent(result);
    return false;
  }

  bool _incompatibilityIntoDisallowed(Incompatibility fact) {
    var disallowed = _disallowed[fact.dep1.toRef()];
    if (disallowed != null) {
      var result = _disallowedAndIncompatibility(disallowed, fact);
      if (result != incompatibility) {
        if (result != null) _replaceCurrent(result);
        return false;
      }
    }

    disallowed = _disallowed[fact.dep2.toRef()];
    if (disallowed != null) {
      var result = _disallowedAndIncompatibility(disallowed, fact);
      if (result != incompatibility) {
        if (result != null) _replaceCurrent(result);
        return false;
      }
    }
  }

  bool _incompatibilityIntoDependencies(Incompatibility fact) {
    // Get all the incompatibilities with the same pair of packages as [fact].
    var ref1 = fact.dep1.toRef();
    var ref2 = fact.dep2.toRef();
    var siblings = _incompatibilities[ref1]
        .where((incompatibility) =>
            incompatibility.dep1.toRef() == ref2 ||
            incompatibility.dep2.toRef() == ref2)
        .toList()..add(fact);

    // If there are dependencies whose allowed constraints are covered entirely
    // by [siblings], we can probably create a new incompatibility for their
    // dependers. For example, if
    //
    // * a [0, 1) is incompatible with b [0, 2) (fact)
    // * a [1, 2) is incompatible with b [1, 3) (in siblings)
    // * c [0, 1) depends on a [0, 2) (dependency)
    //
    // we can add
    //
    // * c [0, 1) is incompatible with b [1, 3)

    for (var dependency in _dependenciesByAllowed[ref1]) {
      var incompatible = _transitiveIncompatible(dependency.allowed, siblings);
      if (incompatible == null) continue;
      _forCurrent.add(new Incompatibility(dependency.depender, incompatible,
          [dependency]..addAll(siblings)));
    }

    for (var dependency in _dependenciesByAllowed[ref2]) {
      var incompatible = _transitiveIncompatible(dependency.allowed, siblings);
      if (incompatible == null) continue;
      _forCurrent.add(new Incompatibility(dependency.depender, incompatible,
          [dependency]..addAll(siblings)));
    }
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
    } else if (intersection == required.dep) {
      // If [intersection] is exactly [required.dep], then this dependency adds
      // no information in addition to [required], so it can be discarded
      // entirely. For example, if
      //
      // * a [0, 1) is required (required)
      // * b [0, 1) depends on a [0, 2) (dependency)
      //
      // we can throw away [dependency].
      return null;
    } else if (intersection == dependency.allowed) {
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
      // * a [0, 1) depends on b [0, 1) (dependency)
      //
      // we can throw away [dependency].
      return null;
    } else if (trimmed == depenendency.depender.constraint) {
      // If no versions in [dependency.depender] are covered by [disallowed],
      // the dependency is fine as-is. For example, if
      //
      // * a [0, 1) is disallowed (disallowed)
      // * a [1, 2) depends on b [0, 1) (dependency)
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
      // * b [0, 1) depends on a [0, 1) (dependency)
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

  /// Resolves [required] and [incompatibility].
  ///
  /// One of [incompatibility]'s packages should be the same as [required.dep].
  ///
  /// Returns a new fact to replace [incompatibility], or `null` if
  /// [incompatibility] is irrelevant.
  Fact _requiredAndIncompatibility(Required required,
      Incompatibility incompatibility) {
    assert(required.dep.name == incompatibility.dep1.name ||
        required.dep.name == incompatibility.dep2.name);
    var same = _matching(incompatibility, required.dep);
    var different = _nonMatching(incompatibility, required.dep);

    // The versions of [required.dep] that aren't in [same], and thus that are
    // compatible with [different].
    var compatible = _depMinus(required.dep, same);
    if (compatible == null) {
      // If [required] is incompatible with all versions of [different], then
      // [different] must be disallowed entirely. For example, if
      //
      // * a [0, 1) is required (required)
      // * a [0, 1) is incompatible with b [0, 1) (incompatibility)
      //
      // we can remove [incompatibility] and add
      //
      // * b [0, 1) is disallowed
      return new Disallowed(different, [incompatibility, required]);
    } else if (compatible.constraint != required.dep.constraint) {
      // If [required] allows versions outside of [same], then we can reframe this
      // incompatibility as a dependency from [different] onto [required.dep].
      // This is safe because [required.dep] needs to be selected anyway. For
      // example, if
      //
      // * a [0, 2) is required (required)
      // * a [0, 1) is incompatible with b [0, 1) (incompatibility)
      //
      // we can remove [incompatibility] and add
      //
      // * b [0, 1) depends on a [1, 2)
      return new Dependency(different, compatible, [incompatibility, required]);
    } else {
      // There's no need to do anything else if *all* the versions allowed by
      // [required] are outside of [same], since one of those versions is already
      // required. For example, if
      //
      // * a [0, 1) is required (required)
      // * a [1, 2) is incompatible with b [0, 1) (incompatibility)
      //
      // we can throw away [incompatibility].
      return null;
    }
  }

  Incompatibility _disallowedAndIncompatibility(Disallowed disallowed,
      Incompatibility incompatibility) {
    var same = _matching(incompatibility, disallowed.dep);
    var different = _nonMatching(incompatibility, disallowed.dep);

    var trimmed = _depMinus(same, disallowed.dep.constraint);
    if (trimmed == null) {
      // If [disallowed] disallows all of the versions in [same], the
      // incompatibility is irrelevant and can be removed. For example, if
      //
      // * a [0, 1) is disallowed (disallowed)
      // * b [0, 1) is incompatible with a [0, 1) (incompatibility)
      //
      // we can throw away [incompatibility].
      return null;
    } else if (trimmed == same.constraint) {
      // If [disallowed] doesn't disallow any of the versions in [same], the
      // incompatibility is fine as-is. For example, if
      //
      // * a [0, 1) is disallowed (disallowed)
      // * a [1, 2) is incompatible with b [0, 1) (incompatibility)
      //
      // there are no changes to be made.
      return incompatibility;
    } else {
      // If [disallowed] disallows some but not all of the versions in [same], we
      // create a new incompatibility with narrower versions. For example, if
      //
      // * a [1, 2) is disallowed (disallowed)
      // * a [0, 2) is incompatible with b [0, 1) (incompatibility)
      //
      // we can remove [incompatibility] and add
      //
      // * a [0, 1) is incompatible with b [0, 1)
      return new Incompatibility(
          trimmed, different, [incompatibility, disallowed]);
    }
  }

  void _removeDependency(Dependency dependency) {
    assert(_dependenciesByDepender[dependency.depender.toRef()]
        .remove(dependency));
    assert(_dependenciesByAllowed[dependency.allowed.toRef()]
        .remove(dependency));
  }

  void _removeIncompatibility(Incompatibility incompatibility) {
    assert(_incompatibilities[incompatibility.dep1.toRef()]
        .remove(incompatibility));
    assert(_incompatibilities[incompatibility.dep2.toRef()]
        .remove(incompatibility));
  }

  /// Enqueue [fact] to be procesed instead of the current fact.
  ///
  /// This adds [fact] to [_toProcess] rather than [_forCurrent] so that the
  /// caller can discard all the processing for the current fact and still
  /// process [fact] next.
  void _replaceCurrent(Fact fact) {
    _toProcess.add(fact);
  }

  /// If [dependencies]' dependers cover all of [depender], returns the union of
  /// their allowed constraints.
  ///
  /// Returns `null` if the dependencies don't cover all of [depender] or the
  /// allowed constraints can't be merged. Assumes that [dependencies]'
  /// dependers are all on the same package as [depender].
  ///
  /// For example, given:
  ///
  /// * a [0, 3) (depender)
  /// * a [0, 1) depends on b [0, 1) (in dependencies)
  /// * a [1, 2) depends on b [1, 2) (in dependencies)
  /// * a [2, 3) depends on b [2, 3) (in dependencies)
  /// * a [3, 4) depends on b [3, 4) (in dependencies)
  ///
  /// This returns:
  ///
  /// * b [0, 3)
  ///
  /// Given:
  ///
  /// * a [0, 3) (depender)
  /// * a [0, 1) depends on b [0, 2) (in dependencies)
  /// * a [2, 3) depends on b [2, 3) (in dependencies)
  ///
  /// This returns `null`, since [dependencies]' dependers don't fully cover
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
    if (mergedDepender == null ||
        !mergedDepender.constraint.allowsAll(depender.constraint)) {
      return null;
    }

    // If the dependencies cover all of [depender], try to union the allowed
    // versions to get the narrowest possible constraint that covers all
    // versions allowed by any selectable depender. There may be no such
    // constraint if different dependers use [allowed] from different sources
    // or with different descriptions.
    return _mergeDeps(dependencies.map((dependency) => dependency.allowed));
  }

  /// If [incompatibilities]' constraints that match [allowed] cover all of
  /// [allowed], returns the union of their non-matching constraints.
  ///
  /// Returns `null` if the incompatibilities don't cover all of [allowed] or
  /// the non-matching constraints can't be merged. Assumes that
  /// [incompatibilities] all have one constraint that matches [allowed].
  ///
  /// For example, given:
  ///
  /// * a [0, 3) (allowed)
  /// * a [0, 1) is incompatible with b [0, 1) (in incompatibilities)
  /// * a [1, 2) is incompatible with b [1, 2) (in incompatibilities)
  /// * a [2, 3) is incompatible with b [2, 3) (in incompatibilities)
  /// * a [3, 4) is incompatible with b [3, 4) (in incompatibilities)
  ///
  /// This returns:
  ///
  /// * b [0, 3)
  ///
  /// Given:
  ///
  /// * a [0, 3) (allowed)
  /// * a [0, 1) is incompatible with b [0, 2) (in incompatibilities)
  /// * a [2, 3) is incompatible with b [2, 3) (in incompatibilities)
  ///
  /// This returns `null`, since [incompatibilities]' matching constraints don't
  /// fully cover [allowed].
  PackageDep _transitiveIncompatible(PackageDep allowed,
      Iterable<Incompatibility> incompatibilities) {
    var allMatching = <PackageDep>[];
    var allNonMatching = <PackageDep>[];

    for (var incompatibility in incompatibilities) {
      var matching = _matching(incompatibility, allowed);
      if (!allowed.allowsAny(matching)) continue;
      allMatching.add(matching);
      allNonMatching.add(_nonMatching(incompatibility, allowed));
    }

    var mergedMatching = _mergeDeps(allMatching);
    if (mergedMatching == null) return null;
    if (!mergedMatching.constraint.allowsAll(allowed)) return null;

    return _mergeDeps(allNonMatching);
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
  // incompatible source/desc.
  //
  // TODO: [_transitiveIncompatible] needs this to return `null` for empty list.
  PackageDep _mergeDeps(Iterable<PackageDep> deps) {
    var list = deps.toList();
    if (list.isEmpty) return null;

    var ref = list.first.toRef();
    for (var dep in list.skip(1)) {
      if (dep.toRef() != ref) return null;
    }

    _maximizers[ref].maximize(list.map((dep) => dep.constraint));
  }

  // Intersect [deps], return `null` if they aren't compatible (diff name, diff
  // source, diff desc, or non-overlapping).
  //
  // Doesn't need to reduce gaps if everything's already maximized.
  PackageDep _intersectDeps(PackageDep dep1, PackageDep dep2) {
    if (dep1.toRef() != dep2.toRef()) return null;
    var intersection = dep1.constraint.intersect(dep2.constraint);
    return intersection.isEmpty ? null : dep1.withConstraint(intersection);
  }

  // Returns packages allowed by [minuend] but not also [subtrahend]. `null` if
  // the resulting constraint is empty.
  PackageDep _depMinus(PackageDep minuend, PackageDep subtrahend) {
    if (minuend.toRef() != subtrahend.toRef()) return minuend;
    var difference = minuend.constraint.difference(subtrahend.constraint);
    return difference.isEmpty ? null : minuend.withConstraint(difference);
  }
}
