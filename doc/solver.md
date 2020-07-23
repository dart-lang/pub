* [Overview](#overview)
* [Definitions](#definitions)
  * [Term](#term)
  * [Incompatibility](#incompatibility)
  * [Partial Solution](#partial-solution)
  * [Derivation Graph](#derivation-graph)
* [The Algorithm](#the-algorithm)
  * [Unit Propagation](#unit-propagation)
  * [Conflict Resolution](#conflict-resolution)
  * [Decision Making](#decision-making)
  * [Error Reporting](#error-reporting)
* [Examples](#examples)
  * [No Conflicts](#no-conflicts)
  * [Avoiding Conflict During Decision Making](#avoiding-conflict-during-decision-making)
  * [Performing Conflict Resolution](#performing-conflict-resolution)
  * [Conflict Resolution With a Partial Satisfier](#conflict-resolution-with-a-partial-satisfier)
  * [Linear Error Reporting](#linear-error-reporting)
  * [Branching Error Reporting](#branching-error-reporting)
* [Differences From CDCL and Answer Set Solving](#differences-from-cdcl-and-answer-set-solving)
  * [Version Ranges](#version-ranges)
  * [Implicit Mutual Exclusivity](#implicit-mutual-exclusivity)
  * [Lazy Formulas](#lazy-formulas)
  * [No Unfounded Set Detection](#no-unfounded-set-detection)

# Overview

Choosing appropriate versions is a core piece of a package manager's
functionality, and a tricky one to do well. Many different package managers use
many different algorithms, but they often end up taking exponential time for
real-world use cases or producing difficult-to-understand output when no
solution is found. Pub's version solving algorithm, called **Pubgrub**, solves
these issues by adapting state-of-the-art techniques for solving
[Boolean satisfiability][] and related difficult search problems.

[Boolean satisfiability]: https://en.wikipedia.org/wiki/Boolean_satisfiability_problem

Given a universe of package versions with constrained dependencies on one
another, one of which is designated as the root, version solving is the problem
of finding a set of package versions such that

* each version's dependencies are satisfied;
* only one version of each package is selected; and
* no extra packages are selected–that is, all selected packages are
  transitively reachable from the root package.

This is an [NP-hard][] problem, which means that there's (probably) no algorithm
for solving it efficiently in all cases. However, there are approaches that are
efficient in enough cases to be useful in practice. Pubgrub is one such
algorithm. It's based on the [Conflict-Driven Clause Learning][] algorithm for
solving the NP-hard [Boolean satisfiability problem][], and particularly on the
version of that algorithm used by the [clasp][] answer set solver as described
in the book [*Answer Set Solving in Practice*][book] by Gebser *et al*.

[NP-hard]: https://en.wikipedia.org/wiki/NP-hardness
[Conflict-Driven Clause Learning]: https://en.wikipedia.org/wiki/Conflict-Driven_Clause_Learning
[Boolean satisfiability problem]: https://en.wikipedia.org/wiki/Boolean_satisfiability_problem
[clasp]: https://potassco.org/clasp/
[book]: https://potassco.org/book/

At a high level, Pubgrub works like many other search algorithms. Its core loop
involves speculatively choosing package versions that match outstanding
dependencies. Eventually one of two things happens:

* All dependencies are satisfied, in which case a solution has been found and
  Pubgrub has succeeded.

* It finds a dependency that can't be satisfied, in which case the current set
  of versions are incompatible and the solver needs to backtrack.

When a conflict is found, Pubgrub backtracks to the package that caused the
conflict and chooses a different version. However, unlike many search
algorithms, it also records the root cause of that conflict. This is the
"conflict-driven clause learning" that lends CDCL its name.

Recording the root causes of conflicts allows Pubgrub to avoid retreading dead
ends in the search space when the context has changed. This makes the solver
substantially more efficient than a naïve search algorithm when there are
consistent causes for each conflict. If no solution exists, clause learning also
allows Pubgrub to explain to the user the root causes of the conflicts that
prevented a solution from being found.

# Definitions

## Term

The fundamental unit on which Pubgrub operates is a `Term`, which represents a
statement about a package that may be true or false for a given selection of
package versions. For example, `foo ^1.0.0` is a term that's true if `foo 1.2.3`
is selected and false if `foo 2.3.4` is selected. Conversely, `not foo ^1.0.0`
is false if `foo 1.2.3` is selected and true if `foo 2.3.4` is selected or if
no version of `foo` is selected at all.

We say that a set of terms `S` "satisfies" a term `t` if `t` must be true
whenever every term in `S` is true. Conversely, `S` "contradicts" `t` if `t`
must be false whenever every term in `S` is true. If neither of these is true,
we say that `S` is "inconclusive" for `t`. As a shorthand, we say that a term
`v` satisfies or contradicts `t` if `{v}` satisfies or contradicts it. For
example:

* `{foo >=1.0.0, foo <2.0.0}` satisfies `foo ^1.0.0`,
* `foo ^1.5.0` contradicts `not foo ^1.0.0`,
* and `foo ^1.0.0` is inconclusive for `foo ^1.5.0`.

Terms can be viewed as denoting sets of allowed versions, with negative terms
denoting the complement of the corresponding positive term. Set relations and
operations can be defined accordingly. For example:

* `foo ^1.0.0 ∪ foo ^2.0.0` is `foo >=1.0.0 <3.0.0`.
* `foo >=1.0.0 ∩ not foo >=2.0.0` is `foo ^1.0.0`.
* `foo ^1.0.0 \ foo ^1.5.0` is `foo >=1.0.0 <1.5.0`.

> **Note:** we use the [ISO 31-11 standard notation][ISO 31-11] for set
> operations.

[ISO 31-11]: https://en.wikipedia.org/wiki/ISO_31-11#Sets

This turns out to be useful for computing satisfaction and contradiction. Given
a term `t` and a set of terms `S`, we have the following identities:

* `S` satisfies `t` if and only if `⋂S ⊆ t`.
* `S` contradicts `t` if and only if `⋂S` is disjoint with `t`.

## Incompatibility

An incompatibility is a set of terms that are not *all* allowed to be true. A
given set of package versions can only be valid according to an incompatibility
if at least one of the incompatibility's terms is false for that solution. For
example, the incompatibility `{foo ^1.0.0, bar ^2.0.0}` indicates that
`foo ^1.0.0` is incompatible with `bar ^2.0.0`, so a solution that contains
`foo 1.1.0` and `bar 2.0.2` would be invalid. Incompatibilities are
*context-independent*, meaning that their terms are mutually incompatible
regardless of which versions are selected at any given point in time.

There are two sources of incompatibilities:

1. An incompatibility may come from an external fact about packages—for example,
  "`foo ^1.0.0` depends on `bar ^2.0.0`" is represented as the incompatibility
  `{foo ^1.0.0, not bar ^2.0.0}`, while "`foo <1.3.0` has an incompatible SDK
  constraint" is represented by the incompatibility `{not foo <1.3.0}`. These
  are known as "external incompatibilities", and they track the external facts
  that caused them to be generated.

2. An incompatibility may also be derived from two existing incompatibilities
  during [conflict resolution](#conflict-resolution). These are known as
  "derived incompatibilities", and we call the prior incompatibilities from
  which they were derived their "causes". Derived incompatibilities are used to
  avoid exploring the same dead-end portion of the state space over and over.

Incompatibilities are normalized so that at most one term refers to any given
package name. For example, `{foo >=1.0.0, foo <2.0.0}` is normalized to
`{foo ^1.0.0}`. Derived incompatibilities with more than one term are also
normalized to remove positive terms referring to the root package, since these
terms will always be satisfied.

We say that a set of terms `S` satisfies an incompatibility `I` if `S` satisfies
every term in `I`. We say that `S` contradicts `I` if `S` contradicts at least
one term in `I`. If `S` satisfies all but one of `I`'s terms and is inconclusive
for the remaining term, we say `S` "almost satisfies" `I` and we call the
remaining term the "unsatisfied term".

## Partial Solution

A partial solution is an ordered list of terms known as "assignments". It
represents Pubgrub's current best guess about what's true for the eventual set
of package versions that will comprise the total solution. The solver
continuously modifies its partial solution as it progresses through the search
space.

There are two categories of assignments. **Decisions** are assignments that
select individual package versions (pub's `PackageId`s). They represent guesses
Pubgrub has made about versions that might work. **Derivations** are assignments
that usually select version ranges (pub's `PackageRange`s). They represent terms
that must be true given the previous assignments in the partial solution and any
incompatibilities we know about. Each derivation keeps track of its "cause", the
incompatibility that caused it to be derived. The process of finding new
derivations is known as [unit propagation](#unit-propagation).

Each assignment has an associated "decision level", a non-negative integer
indicating the number of decisions at or before it in the partial solution other
than the root package. This is used to determine how far back to look for root
causes during [conflict resolution](#conflict-resolution), and how far back to
jump when a conflict is found.

If a partial solution has, for every positive derivation, a corresponding
decision that satisfies that assignment, it's a total solution and version
solving has succeeded.

## Derivation Graph

A derivation graph is a directed acyclic binary graph whose vertices are
incompatibilities, with edges to each derived incompatibility from both of its
causes. This means that all internal vertices are derived incompatibilities, and
all leaf vertices are external incompatibilities. The derivation graph *for an
incompatibility* is the graph that contains that incompatibility's causes, their
causes, and so on transitively. We refer to that incompatibility as the "root"
of the derivation graph.

> **Note:** if you're unfamiliar with graph theory, check out the
> [Wikipedia page][graphs] on the subject. If you don't know a specific bit of
> terminology, check out [this glossary][graph terminology].

[graphs]: https://en.wikipedia.org/wiki/Graph_(discrete_mathematics)
[graph terminology]: https://en.wikipedia.org/wiki/Glossary_of_graph_theory_terms

A derivation graph represents a proof that the terms in its root incompatibility
are in fact incompatible. Because all derived incompatibilities track their
causes, we can find a derivation graph for any of them and thereby prove it. In
particular, when Pubgrub determines that no solution can be found, it uses the
derivation graph for the incompatibility `{root any}` to
[explain to the user](#error-reporting) why no versions of the root package can
be selected and thus why version solving failed.

Here's an example of a derivation graph:

```
┌1───────────────────────────┐ ┌2───────────────────────────┐
│{foo ^1.0.0, not bar ^2.0.0}│ │{bar ^2.0.0, not baz ^3.0.0}│
└─────────────┬──────────────┘ └──────────────┬─────────────┘
              │      ┌────────────────────────┘
              ▼      ▼
┌3────────────┴──────┴───────┐ ┌4───────────────────────────┐
│{foo ^1.0.0, not baz ^3.0.0}│ │{root 1.0.0, not foo ^1.0.0}│
└─────────────┬──────────────┘ └──────────────┬─────────────┘
              │      ┌────────────────────────┘
              ▼      ▼
 ┌5───────────┴──────┴──────┐  ┌6───────────────────────────┐
 │{root any, not baz ^3.0.0}│  │{root 1.0.0, not baz ^1.0.0}│
 └────────────┬─────────────┘  └──────────────┬─────────────┘
              │   ┌───────────────────────────┘
              ▼   ▼
        ┌7────┴───┴──┐
        │{root 1.0.0}│
        └────────────┘
```

This represents the following proof (with numbers corresponding to the
incompatibilities above):

1. Because `foo ^1.0.0` depends on `bar ^2.0.0`
2. and `bar ^2.0.0` depends on `baz ^3.0.0`,
3. `foo ^1.0.0` requires `baz ^3.0.0`.
4. And, because `root` depends on `foo ^1.0.0`,
5. `root` requires `baz ^3.0.0`.
6. So, because `root` depends on `baz ^1.0.0`,
7. `root` isn't valid and version solving has failed.

# The Algorithm

The core of Pubgrub works as follows:

* Begin by adding an incompatibility indicating that the current version of the
  root package must be selected (for example, `{not root 1.0.0}`). Note that
  although there's only one version of the root package, this is just an
  incompatibility, not an assignment.

* Let `next` be the name of the root package.

* In a loop:

  * Perform [unit propagation](#unit-propagation) on `next` to find new
    derivations.

    * If this causes an incompatibility to be satisfied by the partial solution,
      we have a conflict. Unit propagation will try to
      [resolve the conflict](#conflict-resolution). If this fails, version
      solving has failed and [an error should be reported](#error-reporting).

  * Once there are no more derivations to be found,
    [make a decision](#decision-making) and set `next` to the package name
    returned by the decision-making process. Note that the first decision will
    always select the single available version of the root package.

    * Decision making may determine that there's no more work to do, in which
      case version solving is done and the partial solution represents a total
      solution.

## Unit Propagation

Unit propagation combines the partial solution with the known incompatibilities
to derive new assignments. Given an incompatibility, if the partial solution is
inconclusive for one term *t* in that incompatibility and satisfies the rest,
then *t* must be contradicted in order for the incompatibility to be
contradicted. Thus, we add *not t* to the partial solution as a derivation.

When looking for incompatibilities that have a single inconclusive term, we may
also find an incompatibility that's satisfied by the partial solution. If we do,
we know the partial solution can't produce a valid solution, so we go to
[conflict resolution](#conflict-resolution) to try to resolve the conflict. This
either throws an error, or jumps back in the partial solution and returns a new
incompatibility that represents the root cause of the conflict which we use to
continue unit propagation.

While we could iterate over every incompatibility over and over until we can't
find any more derivations, this isn't efficient when many of them represent
dependencies of packages that are currently irrelevant. Instead, we index them
by the names of the packages they refer to and only iterate over those that
refer to the most recently-decided package or new derivations that have been
added during the current propagation session.

The unit propagation algorithm takes a package name and works as follows:

* Let `changed` be a set containing the input package name.

* While `changed` isn't empty:

  * Remove an element from `changed`. Call it `package`.

  * For each `incompatibility` that refers to `package` from newest to oldest
    (since conflict resolution tends to produce more general incompatibilities
    later on):

    * If `incompatibility` is satisfied by the partial solution:

      * Run [conflict resolution](#conflict-resolution) with `incompatibility`.
        If this succeeds, it returns an incompatibility that's guaranteed to be
        almost satisfied by the partial solution. Call this incompatibility's
        unsatisfied term `term`.
      * Add `not term` to the partial solution with `incompatibility` as its
        cause.
      * Replace `changed` with a set containing only `term`'s package name.
        
    * Otherwise, if the partial solution almost satisfies `incompatibility`:
    
      * Call `incompatibility`'s unsatisfied term `term`.
      * Add `not term` to the partial solution with `incompatibility` as its
        cause.
      * Add `term`'s package name to `changed`.

## Conflict Resolution

When an incompatibility is satisfied by the partial solution, that indicates
that the partial solution's decisions aren't a subset of any total solution. The
process of returning the partial solution to a state where the incompatibility
is no longer satisfied is known as conflict resolution.

Following CDCL and Answer Set Solving, Pubgrub's conflict resolution includes
determining the root cause of a conflict and using that to avoid satisfying the
same incompatibility for the same reason in the future. This makes Pubgrub
substantially more efficient in real-world cases, since it avoids re-exploring
parts of the solution space that are known not to work.

The core of conflict resolution is based on the rule of [resolution][]: given
`a or b` and `not a or c`, you can derive `b or c`. This means that given
incompatibilities `{t, q}` and `{not t, r}`, we can derive the incompatibility
`{q, r}`—if this is satisfied, one of the existing incompatibilities will also
be satisfied.

[Resolution]: https://en.wikipedia.org/wiki/Resolution_(logic)

In fact, we can generalize this: given *any* incompatibilities `{t1, q}` and
`{t2, r}`, we can derive `{q, r, t1 ∪ t2}`, since either `t1` or `t2` is true in
every solution in which `t1 ∪ t2` is true. This reduces to `{q, r}` in any case
where `not t2 ⊆ t1` (that is, where `not t2` satisfies `t1`), including the case
above where `t1 = t` and `t2 = not t`.

We use this to describe the notion of a "prior cause" of a conflicting
incompatibility—another incompatibility that's one step closer to the root
cause. We find a prior cause by finding the earliest assignment that fully
satisfies the conflicting incompatibility, then applying the generalized
resolution above to that assignment's cause and the conflicting incompatibility.
This produces a new incompatibility which is our prior cause.

We then find the root cause by applying that procedure repeatedly until the
satisfying assignment is either a decision or the only assignment at its
decision level that's relevant to the conflict. In the former case, there is no
underlying cause; in the latter, we've moved far enough back that we can
backtrack the partial solution and be guaranteed to derive new assignments.

Putting this all together, we get a conflict resolution algorithm. It takes as
input an `incompatibility` that's satisfied by the partial solution, and returns
another `incompatibility` that represents the root cause of the conflict. As a
side effect, it backtracks the partial solution to get rid of the incompatible
decisions. It works as follows:

* In a loop:

  * If `incompatibility` contains no terms, or if it contains a single positive
    term that refers to the root package version, that indicates that the root
    package can't be selected and thus that version solving has failed.
    [Report an error](#error-reporting) with `incompatibility` as the root
    incompatibility.

  * Find the earliest assignment in the partial solution such that
    `incompatibility` is satisfied by the partial solution up to and including
    that assignment. Call this `satisfier`, and call the term in `incompatibility`
    that refers to the same package `term`.

  * Find the earliest assignment in the partial solution *before* `satisfier` such
    that `incompatibility` is satisfied by the partial solution up to and
    including that assignment plus `satisfier`. Call this `previousSatisfier`.

    * Note: `satisfier` may not satisfy `term` on its own. For example, if term
      is `foo >=1.0.0 <2.0.0`, it may be satisfied by
      `{foo >=1.0.0, foo <2.0.0}` but not by either assignment individually. If
      this is the case, `previousSatisfier` may refer to the same package as
      `satisfier`.

  * Let `previousSatisfierLevel` be `previousSatisfier`'s decision level, or
    decision level 1 if there is no `previousSatisfier`.

    * Note: decision level 1 is the level where the root package was selected.
      It's safe to go back to decision level 0, but stopping at 1 tends to
      produce better error messages, because references to the root package end
      up closer to the final conclusion that no solution exists.

  * If `satisfier` is a decision or if `previousSatisfierLevel` is different
    than `satisfier`'s decision level:

    * If `incompatibility` is different than the original input, add it to the
      solver's incompatibility set. (If the conflicting incompatibility was
      added lazily during [decision making](#decision-making), it may not have a
      distinct root cause.)

    * Backtrack by removing all assignments whose decision level is greater than
      `previousSatisfierLevel` from the partial solution.

    * Return `incompatibility`.

  * Otherwise, let `priorCause` be the union of the terms in incompatibility and
    the terms in `satisfier`'s cause, minus the terms referring to `satisfier`'s
    package.

    * Note: this corresponds to the derived incompatibility `{q, r}` in the
      example above.

  * If `satisfier` doesn't satisfy `term`, add `not (satisfier \ term)` to
    `priorCause`.

    * Note: `not (satisfier \ term)` corresponds to `t1 ∪ t2` above with
      `term = t1` and `satisfier = not t2`, by the identity `(Sᶜ \ T)ᶜ = S ∪ T`.

  * Set `incompatibility` to `priorCause`.

## Decision Making

Decision making is the process of speculatively choosing an individual package
version in hope that it will be part of a total solution and ensuring that that
package's dependencies are properly handled. There's some flexibility in exactly
which package version is selected; any version that meets the following criteria
is valid:

* The partial solution contains a positive derivation for that package.
* The partial solution *doesn't* contain a decision for that package.
* The package version matches all assignments in the partial solution.

Pub chooses the latest matching version of the package with the fewest versions
that match the outstanding constraint. This tends to find conflicts earlier if
any exist, since these packages will run out of versions to try more quickly.
But there's likely room for improvement in these heuristics.

Part of the process of decision making also involves converting packages'
dependencies to incompatibilities. This is done lazily when each package version
is first chosen to avoid flooding the solver with incompatibilities that are
likely to be irrelevant.

Pubgrub collapses identical dependencies from adjacent package versions into
individual incompatibilities. This substantially reduces the total number of
incompatibilities and makes it much easier for Pubgrub to reason about multiple
versions of packages at once. For example, rather than representing
`foo 1.0.0 depends on bar ^1.0.0` and `foo 1.1.0 depends on bar ^1.0.0` as two
separate incompatibilities, they're collapsed together into the single
incompatibility `{foo ^1.0.0, not bar ^1.0.0}`.

The version ranges of the dependers (`foo` in the example above) always have an
inclusive lower bound of the first version that has the dependency, and an
exclusive upper bound of the first package that *doesn't* have the dependency.
if the last published version of the package has the dependency, the upper bound
is omitted (as in `foo >=1.0.0`); similarly, if the first published version of
the package has the dependency, the lower bound is omitted (as in `foo <2.0.0`).
Expanding the version range in this way makes it more closely match the format
users tend to use when authoring dependencies, which makes it easier for Pubgrub
to reason efficiently about the relationship between dependers and the packages
they depend on.

If a package version can't be selected—for example, because it's incompatible
with the current version of the underlying programming language—we avoid adding
its dependencies at all. Instead, we just add an incompatibility indicating that
it (as well as any adjacent versions that are also incompatible) should never be
selected.

For more detail on how adjacent package versions' dependencies are combined and
converted to incompatibilities, see `lib/src/solver/package_lister.dart`.

The decision making algorithm works as follows:

* Let `package` be a package with a positive derivation but no decision in the
  partial solution, and let `term` be the intersection of all assignments in the
  partial solution referring to that package.

* Let `version` be a version of `package` that matches `term`.

* If there is no such `version`, add an incompatibility `{term}` to the
  incompatibility set and return `package`'s name. This tells Pubgrub to avoid
  this range of versions in the future.

* Add each `incompatibility` from `version`'s dependencies to the
  incompatibility set if it's not already there.

* Add `version` to the partial solution as a decision, unless this would produce
  a conflict in any of the new incompatibilities.

* Return `package`'s name.

### Error Reporting

When version solving has failed, it's important to explain to the user what went
wrong so that they can figure out how to fix it. But version solving is
complicated—for the same reason that it's difficult for a computer to quickly
determine that version solving will fail, it's difficult to straightforwardly
explain to the user why it *did* fail.

Fortunately, Pubgrub's structure makes it possible to explain even the most
tangled failures. This is due once again to its root-cause tracking: because the
algorithm derives new incompatibilities every time it encounters a conflict, it
naturally generates a chain of derivations that ultimately derives the fact that
no solution exists.

When [conflict resolution](#conflict-resolution) fails, it produces an
incompatibility with a single positive term: the root package. This
incompatibility indicates that the root package isn't part of any solution, and
thus that no solution exists and version solving has failed. We use the
derivation graph for this incompatibility to generate a human-readable
explanation of why version solving failed.

Most commonly, derivation graphs look like the example
[above](#derivation-graph): a linear chain of derived incompatibilities with one
external and one derived cause. These derivations can be explained fairly
straightforwardly by just describing each external incompatibility followed by
the next derived incompatibility. The only nuance is that, in practice, this
tends to end up a little verbose. You can skip every other derived
incompatibility without losing clarity. For example, instead of

> ... And, because `root` depends on `foo ^1.0.0`, `root` requires `baz ^3.0.0`.
> So, because `root` depends on `baz ^1.0.0`, `root` isn't valid and version
> solving has failed.

you would emit:

> ... So, because `root` depends on both `foo ^1.0.0` and `baz ^3.0.0`, `root`
> isn't valid and version solving has failed.

However, it's possible for derivation graphs to be more complex. A derived
incompatibility may be caused by multiple incompatibilities that are also
derived:

```
┌───┐ ┌───┐ ┌───┐ ┌───┐
│   │ │   │ │   │ │   │
└─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘
  └▶┐ ┌◀┘     └▶┐ ┌◀┘
   ┌┴─┴┐       ┌┴─┴┐
   │   │       │   │
   └─┬─┘       └─┬─┘
     └──▶─┐ ┌─◀──┘
         ┌┴─┴┐
         │   │
         └───┘
```

The same incompatibility may even cause multiple derived incompatibilities:

```
    ┌───┐ ┌───┐
    │   │ │   │
    └─┬─┘ └─┬─┘
      └▶┐ ┌◀┘
┌───┐  ┌┴─┴┐  ┌───┐
│   │  │   │  │   │
└─┬─┘  └┬─┬┘  └─┬─┘
  └▶┐ ┌◀┘ └▶┐ ┌◀┘
   ┌┴─┴┐   ┌┴─┴┐
   │   │   │   │
   └─┬─┘   └─┬─┘
     └─▶┐ ┌◀─┘
       ┌┴─┴┐
       │   │
       └───┘
```

In these cases, a naïvely linear explanation won't be clear. We need to refer to
previous derivations that may not be physically nearby. We use line numbers to
do this, but we only number incompatibilities that we *know* will need to be
referred to later on. In the simple linear case, we don't include line numbers
at all.

Before running the error reporting algorithm proper, walk the derivation graph
and record how many outgoing edges each derived incompatibility has–that is, how
many different incompatibilities it causes.

The error reporting algorithm takes as input a derived `incompatibility` and
writes lines of output (which may have associated numbers). Each line describes
a single derived incompatibility and indicates why it's true. It works as
follows:

1. If `incompatibility` is caused by two other derived incompatibilities:

   1. If both causes already have line numbers:

      * Write "Because `cause1` (`cause1.line`) and `cause2` (`cause2.line`),
        `incompatibility`."

   2. Otherwise, if only one cause has a line number:
  
      * Recursively run error reporting on the cause without a line number.

      * Call the cause with the line number `cause`.

      * Write "And because `cause` (`cause.line`), `incompatibility`."

   3. Otherwise (when neither has a line number):

      1. If at least one cause's incompatibility is caused by two external
         incompatibilities:

         * Call this cause `simple` and the other cause `complex`. The
           `simple` cause can be described in a single line, which is short
           enough that we don't need to use a line number to refer back to
           `complex`.

         * Recursively run error reporting on `complex`.

         * Recursively run error reporting on `simple`.

         * Write "Thus, `incompatibility`."

      2. Otherwise:

         * Recursively run error reporting on the first cause, and give the
           final line a line number if it doesn't have one already. Set this
           as the first cause's line number.

         * Write a blank line. This helps visually indicate that we're
           starting a new line of derivation.

         * Recursively run error reporting on the second cause, and add a line
           number to the final line. Associate this line number with the first
           cause.

         * Write "And because `cause1` (`cause1.line`), `incompatibility`."

2. Otherwise, if only one of `incompatibility`'s causes is another derived
   incompatibility:

   * Call the derived cause `derived` and the external cause `external`.

   1. If `derived` already has a line number:

      * Write "Because `external` and `derived` (`derived.line`),
        `incompatibility`."

   2. Otherwise, if `derived` is itself caused by exactly one derived
      incompatibility and that incompatibility doesn't have a line number:

      * Call `derived`'s derived cause `priorDerived` and its external cause
        `priorExternal`.

      * Recursively run error reporting on `priorDerived`.

      * Write "And because `priorExternal` and `external`,
        `incompatibility`."

   3. Otherwise:

      * Recursively run error reporting on `derived`.

      * Write "And because `external`, `incompatibility`."

3. Otherwise (when both of `incompatibility`'s causes are external
   incompatibilities):

   * Write "Because `cause1` and `cause2`, `incompatibility`."

* Finally, if `incompatibility` causes two or more incompatibilities, give the
  line that was just written a line number. Set this as `incompatibility`'s line
  number.

Note that the text in the "Write" lines above is meant as a suggestion rather
than a prescription. It's up to each implementation to determine the best way to
convert each incompatibility to a human-readable string representation in a way
that makes sense for that package manager's particular domain.

# Examples

## No Conflicts

First, let's look at a simple case where no actual conflicts occur to get a
sense of how unit propagation and decision making operate. Given the following
packages:

* `root 1.0.0` depends on `foo ^1.0.0`.
* `foo 1.0.0` depends on `bar ^1.0.0`.
* `bar 1.0.0` and `2.0.0` have no dependencies.

Pubgrub goes through the following steps. The table below shows each step in the
algorithm where the state changes, either by adding an assignment to the partial
solution or by adding an incompatibility to the incompatibility set.

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 1 | `root 1.0.0` | decision | top level | | 0 |
| 2 | `{root 1.0.0, not foo ^1.0.0}` | incompatibility | top level | | |
| 3 | `foo ^1.0.0` | derivation | unit propagation | step 2 | 0 |
| 4 | `{foo any, not bar ^1.0.0}` | incompatibility | decision making | |  |
| 5 | `foo 1.0.0` | decision | decision making | | 1 |
| 6 | `bar ^1.0.0` | derivation | unit propagation | step 4 | 1 |
| 7 | `bar 1.0.0` | decision | decision making | | 2 |

In steps 1 and 2, Pubgrub adds the information about the root package. This
gives it a place to start its derivations. It then moves to unit propagation in
step 3, where it sees that `root 1.0.0` is selected, which means that the
incompatibility `{root 1.0.0, not foo ^1.0.0}` is almost satisfied. It adds the
inverse of the unsatisfied term, `foo ^1.0.0`, to the partial solution as a
derivation.

Note in step 7 that Pubgrub chooses `bar 1.0.0` rather than `bar 2.0.0`. This is
because it knows that the partial solution contains `bar ^1.0.0`, which
`bar 2.0.0` not compatible with.

Once the algorithm is done, we look at the decisions to see which package
versions are selected: `root 1.0.0`, `foo 1.0.0`, and `bar 1.0.0`.

## Avoiding Conflict During Decision Making

In this example, decision making examines a package version that would cause a
conflict and chooses not to select it. Given the following packages:

* `root 1.0.0` depends on `foo ^1.0.0` and `bar ^1.0.0`.
* `foo 1.1.0` depends on `bar ^2.0.0`.
* `foo 1.0.0` has no dependencies.
* `bar 1.0.0`, `1.1.0`, and `2.0.0` have no dependencies.

Pubgrub goes through the following steps:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 1 | `root 1.0.0` | decision | top level | | 0 |
| 2 | `{root 1.0.0, not foo ^1.0.0}` | incompatibility | top level | | |
| 3 | `{root 1.0.0, not bar ^1.0.0}` | incompatibility | top level | | |
| 4 | `foo ^1.0.0` | derivation | unit propagation | step 2 | 0 |
| 5 | `bar ^1.0.0` | derivation | unit propagation | step 3 | 0 |
| 6 | `{foo >=1.1.0, not bar ^2.0.0}` | incompatibility | decision making | | |
| 7 | `not foo >=1.1.0` | derivation | unit propagation | step 6 | 0 |
| 8 | `foo 1.0.0` | decision | decision making | | 1 |
| 9 | `bar 1.1.0` | decision | decision making | | 2 |

In step 6, the decision making process considers `foo 1.1.0` by adding its
dependency as the incompatibility `{foo >=1.1.0, not bar ^2.0.0}`. However, if
`foo 1.1.0` were selected, this incompatibility would be satisfied: `foo 1.1.0`
satisfies `foo >=1.1.0`, and `bar ^1.0.0` from step 5 satisfies
`not bar ^2.0.0`. So decision making ends without selecting a version, and unit
propagation is run again.

Unit propagation determines that the new incompatibility,
`{foo >=1.1.0, not bar ^2.0.0}`, is almost satisfied (again because `bar ^1.0.0`
satisfies `not bar ^2.0.0`). Thus it's able to deduce `not foo >=1.1.0` in step
7, which lets the next iteration of decision making choose `foo 1.0.0` which is
compatible with `root`'s constraint on `bar`.

## Performing Conflict Resolution

This example shows full conflict resolution in action. Given the following
packages:

* `root 1.0.0` depends on `foo >=1.0.0`.
* `foo 2.0.0` depends on `bar ^1.0.0`.
* `foo 1.0.0` has no dependencies.
* `bar 1.0.0` depends on `foo ^1.0.0`.

Pubgrub goes through the following steps:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 1 | `root 1.0.0` | decision | top level | | 0 |
| 2 | `{root 1.0.0, not foo >=1.0.0}` | incompatibility | top level | | |
| 3 | `foo >=1.0.0` | derivation | unit propagation | step 2 | 0 |
| 4 | `{foo >=2.0.0, not bar ^1.0.0}` | incompatibility | decision making | | |
| 5 | `foo 2.0.0` | decision | decision making | | 1 |
| 6 | `bar ^1.0.0` | derivation | unit propagation | step 4 | 1 |
| 7 | `{bar any, not foo ^1.0.0}` | incompatibility | decision making | | |

The incompatibility added at step 7 is satisfied by the partial assignment: `bar
any` is satisfied by `bar ^1.0.0` from step 6, and `not foo ^1.0.0` is satisfied
by `foo 2.0.0` from step 5. This causes Pubgrub to enter conflict resolution,
where it iteratively works towards the root cause of the conflict:

| Step | Incompatibility | Term | Satisfier | Satisfier Cause | Previous Satisfier |
| ---- | --------------- | ---- | --------- | --------------- | ------------------ |
| 8 | `{bar any, not foo ^1.0.0}` | `bar any` | `bar ^1.0.0` from step 6 | `{foo >=2.0.0, not bar ^1.0.0}` | `foo 2.0.0` from step 5 |
| 9 | `{foo >=2.0.0}` | `foo >=1.0.0` | `foo 2.0.0` from step 5 | | |

In step 9, we merge the two incompatibilities `{bar any, not foo ^1.0.0}` and
`{foo >=2.0.0, not bar ^1.0.0}` as described in
[conflict resolution](#conflict-resolution), to produce
`{not foo ^1.0.0, foo >=2.0.0, bar any ∪ not bar ^1.0.0}`. Since
`not not bar ^1.0.0 = bar ^1.0.0` satisfies `bar any`, this simplifies to
`{not foo ^1.0.0, foo >=2.0.0}`. We can then take the intersection of the two
`foo` terms to get `{foo >=2.0.0}`.

Now Pubgrub has learned that, no matter which other package versions are
selected, `foo 2.0.0` is never going to be a valid choice because of its
dependency on `bar`. Because there's no previous satisfier in step 9, it
backtracks all the way to level 0 and continues the main loop with the new
incompatibility:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 10 | `{foo >=2.0.0}` | incompatibility | conflict resolution | | |
| 11 | `not foo >=2.0.0` | derivation | unit propagation | step 10 | 0 |
| 12 | `foo 1.0.0` | decision | decision making | | 1 |

Given this new incompatibility, Pubgrub knows to avoid selecting `foo 2.0.0` and
selects the correction version, `foo 1.0.0`, instead. Because it backtracked,
all decisions previously made at decision levels higher than 0 are discarded,
and the solution is `root 1.0.0` and `foo 1.0.0`.

## Conflict Resolution With a Partial Satisfier

In this example, we see a more complex example of conflict resolution where the
term in question isn't totally satisfied by a single satisfier. Given the
following packages:

* `root 1.0.0` depends on `foo ^1.0.0` and `target ^2.0.0`.
* `foo 1.1.0` depends on `left ^1.0.0` and `right ^1.0.0`.
* `foo 1.0.0` has no dependencies.
* `left 1.0.0` depends on `shared >=1.0.0`.
* `right 1.0.0` depends on `shared <2.0.0`.
* `shared 2.0.0` has no dependencies.
* `shared 1.0.0` depends on `target ^1.0.0`.
* `target 2.0.0` and `1.0.0` have no dependencies.

`foo 1.1.0` transitively depends on a version of `target` that's not
compatible with `root`'s constraint. However, this dependency only exists
because of both `left` *and* `right`—either alone would allow a version of
`shared` without a problematic dependency to be selected.

Pubgrub goes through the following steps:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 1 | `root 1.0.0` | decision | top level | | 0 |
| 2 | `{root 1.0.0, not foo ^1.0.0}` | incompatibility | top level | | |
| 3 | `{root 1.0.0, not target ^2.0.0}` | incompatibility | top level | | |
| 4 | `foo ^1.0.0` | derivation | unit propagation | step 2 | 0 |
| 5 | `target ^2.0.0` | derivation | unit propagation | step 3 | 0 |
| 6 | `{foo >=1.1.0, not left ^1.0.0}` | incompatibility | decision making | | |
| 7 | `{foo >=1.1.0, not right ^1.0.0}` | incompatibility | decision making | | |
| 8 | `target 2.0.0` | decision | decision making | | 1 |
| 9 | `foo 1.1.0` | decision | decision making | | 2 |
| 10 | `left ^1.0.0` | derivation | unit propagation | step 6 | 2 |
| 11 | `right ^1.0.0` | derivation | unit propagation | step 7 | 2 |
| 12 | `{right any, not shared <2.0.0}` | incompatibility | decision making | | |
| 13 | `right 1.0.0` | decision | decision making | | 3 |
| 14 | `shared <2.0.0` | derivation | unit propagation | step 12 | 3 |
| 15 | `{left any, not shared >=1.0.0}` | incompatibility | decision making | | |
| 16 | `left 1.0.0` | decision | decision making | | 4 |
| 17 | `shared >=1.0.0` | derivation | unit propagation | step 15 | 4 |
| 18 | `{shared ^1.0.0, not target ^1.0.0}` | incompatibility | decision making | | |

The incompatibility at step 18 is in conflict: `not target ^1.0.0` is satisfied
by `target ^2.0.0` from step 5, and `shared ^1.0.0` is *jointly* satisfied by
`shared <2.0.0` from step 14 and `shared >=1.0.0` from step 17. However, because
the satisfier and the previous satisfier have different decision levels,
conflict resolution has no root cause to find and just backtracks to decision
level 3, where it can make a new derivation:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 19 | `not shared ^1.0.0` | derivation | unit propagation | step 18 | 3 |

But this derivation causes a new conflict, which needs to be resolved:

| Step | Incompatibility | Term | Satisfier | Satisfier Cause | Previous Satisfier |
| ---- | --------------- | ---- | --------- | --------------- | ------------------ |
| 20 | `{left any, not shared >=1.0.0}` | `not shared >=1.0.0` | `not shared ^1.0.0` from step 19 | `{shared ^1.0.0, not target ^1.0.0}` | `shared <2.0.0` from step 14 |
| 21 | `{left any, not target ^1.0.0, not shared >=2.0.0}` | `not shared >=2.0.0` | `shared <2.0.0` from step 14 | `{right any, not shared <2.0.0}` | `left ^1.0.0` from step 10 |

Once again, we merge two incompatibilities, but this time we aren't able to
simplify the result.
`{left any, not target ^1.0.0, not shared >=1.0.0 ∪ shared ^1.0.0}` becomes
`{left any, not target ^1.0.0, not shared >=2.0.0}`.

We once again stop conflict resolution and start backtracking, because the
satisfier (`shared <2.0.0`) and the previous satisfier (`left ^1.0.0`) have
different decision levels. This pattern happens frequently in conflict
resolution: Pubgrub finds the root cause of one conflict, backtracks a little
bit, and sees another related conflict that allows it to determine a more
broadly-applicable root cause. In this case, we backtrack to decision level 2,
where `left ^1.0.0` was derived:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 22 | `{left any, not target ^1.0.0, not shared >=2.0.0}` | incompatibility | conflict resolution | | |
| 23 | `shared >=2.0.0` | derivation | unit propagation | step 22 | 2 |

And we re-enter conflict resolution:

| Step | Incompatibility | Term | Satisfier | Satisfier Cause | Previous Satisfier |
| ---- | --------------- | ---- | --------- | --------------- | ------------------ |
| 24 | `{right any, not shared <2.0.0}` | `not shared <2.0.0` | `shared >=2.0.0` from step 23 | `{left any, not target ^1.0.0, not shared >=2.0.0}` | `right ^1.0.0` from step 11 |
| 25 | `{left any, right any, not target ^1.0.0}` | `right any` | `right ^1.0.0` from step 11 | `{foo >=1.1.0, not right ^1.0.0}` | `left ^1.0.0` from step 10 |
| 26 | `{left any, foo >=1.1.0, not target ^1.0.0}` | `left any` | `left ^1.0.0` from step 10 | `{foo >=1.1.0, not left ^1.0.0}` | `foo 1.1.0` from step 9 |
| 27 | `{foo >=1.1.0, not target ^1.0.0}` | `foo >=1.1.0` | `foo 1.1.0` from step 9 | | `target ^2.0.0` from step 5 |

Pubgrub has figured out that `foo 1.1.0` transitively depends on `target
^1.0.0`, even though that dependency goes through `left`, `right`, and `shared`.
From here it backjumps to decision level 0, where `target ^2.0.0` was derived,
and quickly finds the correct solution:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 28 | `{foo >=1.1.0, not target ^1.0.0}` | incompatibility | conflict resolution | | |
| 29 | `not foo >=1.1.0` | derivation | unit propagation | step 28 | 0 |
| 30 | `foo 1.0.0` | decision | decision making | | 1 |
| 31 | `target 2.0.0` | decision | decision making | | 2 |

This produces the correct solution: `root 1.0.0`, `foo 1.0.0`, and
`target 2.0.0`.

## Linear Error Reporting

This example's dependency graph doesn't have a valid solution. It shows how
error reporting works when the derivation graph is straightforwardly linear.
Given the following packages:

* `root 1.0.0` depends on `foo ^1.0.0` and `baz ^1.0.0`.
* `foo 1.0.0` depends on `bar ^2.0.0`.
* `bar 2.0.0` depends on `baz ^3.0.0`.
* `baz 1.0.0` and `3.0.0` have no dependencies.

`root` transitively depends on a version of `baz` that's not compatible with
`root`'s constraint.

Pubgrub goes through the following steps:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 1 | `root 1.0.0` | decision | top level | | 0 |
| 2 | `{root 1.0.0, not foo ^1.0.0}` | incompatibility | top level | | |
| 3 | `{root 1.0.0, not baz ^1.0.0}` | incompatibility | top level | | |
| 4 | `foo ^1.0.0` | derivation | unit propagation | step 2 | 0 |
| 5 | `baz ^1.0.0` | derivation | unit propagation | step 3 | 0 |
| 6 | `{foo any, not bar ^2.0.0}` | incompatibility | decision making | | |
| 7 | `foo 1.0.0` | decision | decision making | | 1 |
| 8 | `bar ^2.0.0` | derivation | unit propagation | step 6 | 1 |
| 9 | `{bar any, not baz ^3.0.0}` | incompatibility | decision making | | |

The incompatibility added at step 10 is in conflict: `bar any` is satisfied by
`bar ^2.0.0` from step 8, and `not baz ^3.0.0` is satisfied by `baz ^1.0.0` from
step 5. Because these two satisfiers have different decision levels, conflict
resolution backtracks to level 0 where it can make a new derivation:

| Step | Incompatibility | Term | Satisfier | Cause | Decision Level |
| ---- | --------------- | ---- | --------- | ----- | ------------------ |
| 10 | `not bar any` | derivation | unit propagation | step 9 | 0 |

This derivation causes a new conflict, which needs to be resolved:

| Step | Incompatibility | Term | Satisfier | Satisfier Cause | Previous Satisfier |
| ---- | --------------- | ---- | --------- | --------------- | ------------------ |
| 11 | `{foo any, not bar ^2.0.0}` | `not bar ^2.0.0` | `not bar any` from step 10 | `{bar any, not baz ^3.0.0}` | `foo ^1.0.0` from step 4 |
| 12 | `{foo any, not baz ^3.0.0}` | `not baz ^3.0.0` | `baz ^1.0.0` from step 5 | `{root 1.0.0, not baz ^1.0.0}` | `foo ^1.0.0` from step 4 |
| 13 | `{foo any, root 1.0.0}` | `foo any` | `foo ^1.0.0` from step 4 | `{root 1.0.0, not foo ^1.0.0}` | `root 1.0.0` from step 1 |
| 14 | `{root 1.0.0}` | | | | |

By deriving the incompatibility `{root 1.0.0}`, we've determined that no
solution can exist and thus that version solving has failed. Our next task is to
construct a derivation graph for `{root 1.0.0}`. Each derived incompatibility's
causes are the incompatibility that came before it in the conflict resolution
table (`{foo any, root 1.0.0}` for the root incompatibility) and that
incompatibility's satisfier cause (`{root 1.0.0, not foo ^1.0.0}` for the root
incompatibility).

This gives us the following derivation graph, with each incompatibility's step
number indicated:

```
┌6────────────────────────┐  ┌9────────────────────────┐
│{foo any, not bar ^2.0.0}│  │{bar any, not baz ^3.0.0}│
└────────────┬────────────┘  └────────────┬────────────┘
             │      ┌─────────────────────┘
             ▼      ▼
┌12──────────┴──────┴─────┐ ┌3───────────────────────────┐
│{foo any, not baz ^3.0.0}│ │{root 1.0.0, not baz ^1.0.0}│
└────────────┬────────────┘ └─────────────┬──────────────┘
             │    ┌───────────────────────┘
             ▼    ▼
  ┌13────────┴────┴─────┐   ┌2───────────────────────────┐
  │{foo any, root 1.0.0}│   │{root 1.0.0, not foo ^1.0.0}│
  └──────────┬──────────┘   └─────────────┬──────────────┘
             │   ┌────────────────────────┘
             ▼   ▼
       ┌14───┴───┴──┐
       │{root 1.0.0}│
       └────────────┘
```

We run the [error reporting](#error-reporting) algorithm on this graph starting
with the root incompatibility, `{root 1.0.0}`. Because this algorithm does a
depth-first traversal of the graph, it starts by printing the outermost external
incompatibilities and works its way towards the root. Here's what it prints,
with the step of the algorithm that prints each line indicated:

| Message | Algorithm Step | Line |
| ------- | -------------- | ---- |
| Because every version of `foo` depends on `bar ^2.0.0` which depends on `baz ^3.0.0`, every version of `foo` requires `baz ^3.0.0`. | 3 | |
| So, because `root` depends on both `baz ^1.0.0` and `foo ^1.0.0`, version solving failed. | 2.ii | |

There are a couple things worth noting about this output:

* Pub's implementation of error reporting has some special cases to make output
  more human-friendly:

  * When we're talking about every version of a package, we explicitly write
    "every version of `foo`" rather than "`foo any`".

  * In the first line, instead of writing "every version of `foo` depends on
    `bar ^2.0.0` and every version of `bar` depends on `baz ^3.0.0`", we write
    "every version of `foo` depends on `bar ^2.0.0` which depends on
    `baz ^3.0.0`".

  * In the second line, instead of writing "`root` depends on `baz ^1.0.0` and
    `root` depends on `foo ^1.0.0`", we write "`root` depends on both
    `baz ^1.0.0` and `foo ^1.0.0`".

  * We omit the version number for the entrypoint package `root`.

  * Instead of writing "And" for the final line, we write "So," to help indicate
    that it's a conclusion.

  * Instead of writing "`root` is forbidden", we write "version solving failed".

* The second line collapses together the explanations of two incompatibilities
  (`{foo any, root 1.0.0}` and `{root 1.0.0}`), as described in step 2.ii. We
  never explicitly explain that every version of `foo` is incompatible with
  `root`, but the output is still clear.

## Branching Error Reporting

This example fails for a reason that's too complex to explain in a linear chain
of reasoning. It shows how error reporting works when it has to refer back to a
previous derivation. Given the following packages:

* `root 1.0.0` depends on `foo ^1.0.0`.
* `foo 1.0.0` depends on `a ^1.0.0` and `b ^1.0.0`.
* `foo 1.1.0` depends on `x ^1.0.0` and `y ^1.0.0`.
* `a 1.0.0` depends on `b ^2.0.0`.
* `b 1.0.0` and `2.0.0` have no dependencies.
* `x 1.0.0` depends on `y ^2.0.0`.
* `y 1.0.0` and `2.0.0` have no dependencies.

Neither version of `foo` can be selected due to their conflicting direct and
transitive dependencies on `b` and `y`, which means version solving fails.

Pubgrub goes through the following steps:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 1 | `root 1.0.0` | decision | top level | | 0 |
| 2 | `{root 1.0.0, not foo ^1.0.0}` | incompatibility | top level | | |
| 3 | `foo ^1.0.0` | derivation | unit propagation | step 2 | 0 |
| 4 | `foo 1.1.0` | decision | decision making | | 1 |
| 5 | `{foo >=1.1.0, not y ^1.0.0}` | incompatibility | decision making | | |
| 6 | `{foo >=1.1.0, not x ^1.0.0}` | incompatibility | decision making | | |
| 7 | `y ^1.0.0` | derivation | unit propagation | step 5 | 1 |
| 8 | `x ^1.0.0` | derivation | unit propagation | step 6 | 1 |
| 9 | `{x any, not y ^2.0.0}` | incompatibility | decision making | | |

This incompatibility is in conflict, so we enter conflict resolution:

| Step | Incompatibility | Term | Satisfier | Satisfier Cause | Previous Satisfier |
| ---- | --------------- | ---- | --------- | --------------- | ------------------ |
| 10 | `{x any, not y ^2.0.0}` | `x any` | `x ^1.0.0` from step 8 | `{foo >=1.1.0, not x ^1.0.0}` | `y ^1.0.0` from step 7 |
| 11 | `{foo >=1.1.0, not y ^2.0.0}` | `not y ^2.0.0` | `y ^1.0.0` from step 7 | `{foo >=1.1.0, not y ^1.0.0}` | `foo 1.1.0` from step 4 |
| 12 | `{foo >=1.1.0}` | `foo >=1.1.0` | `foo 1.1.0` from step 4 | `{root 1.0.0, not foo ^1.0.0}` | |

We then backtrack to decision level 0, since there is no previous satisfier:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 13 | `{foo >=1.1.0}` | incompatibility | conflict resolution | | |
| 14 | `not foo >=1.1.0` | derivation | unit propagation | step 13 | 0 |
| 15 | `{foo <1.1.0, not b ^1.0.0}` | incompatibility | decision making | | |
| 16 | `{foo <1.1.0, not a ^1.0.0}` | incompatibility | decision making | | |
| 17 | `foo 1.0.0` | decision | decision making | | 1 |
| 18 | `b ^1.0.0` | derivation | unit propagation | step 15 | 1 |
| 19 | `a ^1.0.0` | derivation | unit propagation | step 16 | 1 |
| 20 | `{a any, not b ^2.0.0}` | incompatibility | decision making | | |

We've found another conflicting incompatibility, so we'll go back into conflict
resolution:

| Step | Incompatibility | Term | Satisfier | Satisfier Cause | Previous Satisfier |
| ---- | --------------- | ---- | --------- | --------------- | ------------------ |
| 21 | `{a any, not b ^2.0.0}` | `a any` | `a ^1.0.0` from step 19 | `{foo <1.1.0, not a ^1.0.0}` | `b ^1.0.0` from step 18 |
| 22 | `{foo <1.1.0, not b ^2.0.0}` | `not b ^2.0.0` | `b ^1.0.0` from step 18 | `{foo >=1.1.0, not b ^1.0.0}` | `not foo >=1.0.0` from step 14 |

We now backtrack to decision level 0 where the previous satisfier was derived:

| Step | Value | Type | Where it was added | Cause | Decision level |
| ---- | ----- | ---- | ------------------ | ----- | -------------- |
| 23 | `{foo <1.1.0, not b ^2.0.0}` | incompatibility | conflict resolution | | |
| 24 | `b ^2.0.0` | derivation | unit propagation | step 23 | 0 |

But this produces another conflict, this time in the incompatibility from line
15:

| Step | Incompatibility | Term | Satisfier | Satisfier Cause | Previous Satisfier |
| ---- | --------------- | ---- | --------- | --------------- | ------------------ |
| 25 | `{foo <1.1.0, not b ^1.0.0}` | `not b ^1.0.0` | `b ^2.0.0` from step 24 | `{foo <1.1.0, not b ^2.0.0}` | `not foo >=1.1.0` from step 14 |
| 26 | `{foo <1.1.0}` | `foo <1.1.0` | `not foo >=1.1.0` from step 14 | `{foo >=1.1.0}` | `foo ^1.0.0` from step 3 |
| 27 | `{foo any}` | `foo any` | `foo ^1.0.0` from step 3 | `{root 1.0.0, not foo ^1.0.0}` | |
| 28 | `{root 1.0.0}` | | | | |

This produces a more complex derivation graph than the previous example:

```
  ┌20───────────────────┐    ┌16────────────────────────┐
  │{a any, not b ^2.0.0}│    │{foo <1.1.0, not a ^1.0.0}│
  └──────────┬──────────┘    └────────────┬─────────────┘
             │      ┌─────────────────────┘
             ▼      ▼
┌22──────────┴──────┴──────┐ ┌15────────────────────────┐
│{foo <1.1.0, not b ^2.0.0}│ │{foo <1.1.0, not b ^1.0.0}│
└────────────┬─────────────┘ └────────────┬─────────────┘
             │    ┌───────────────────────┘
             ▼    ▼
     ┌26─────┴────┴───┐  ┌9────────────────────┐    ┌6──────────────────────────┐
     │{not foo <1.1.0}│  │{x any, not y ^2.0.0}│    │{foo >=1.1.0, not x ^1.0.0}│
     └───────┬────────┘  └──────────┬──────────┘    └─────────────┬─────────────┘
             │                      │      ┌──────────────────────┘
             │                      ▼      ▼
             │        ┌11───────────┴──────┴──────┐ ┌5──────────────────────────┐
             │        │{foo >=1.1.0, not y ^2.0.0}│ │{foo >=1.1.0, not y ^1.0.0}│
             │        └─────────────┬─────────────┘ └─────────────┬─────────────┘
             │                      │    ┌────────────────────────┘
             ▼                      ▼    ▼
      ┌27────┴──────┐      ┌12──────┴────┴───┐
      │{not foo any}├◀─────┤{not foo >=1.1.0}│
      └──────┬──────┘      └─────────────────┘
             ▼
      ┌28────┴─────┐  ┌2───────────────────────────┐
      │{root 1.0.0}├◀─┤{root 1.0.0, not foo ^1.0.0}│
      └────────────┘  └────────────────────────────┘
```

We run the [error reporting](#error-reporting) algorithm on this graph:

| Message | Algorithm Step | Line |
| ------- | -------------- | ---- |
| Because `foo <1.1.0` depends on `a ^1.0.0` which depends on `b ^2.0.0`, `foo <1.1.0` requires `b ^2.0.0`. | 3 | |
| So, because `foo <1.1.0` depends on `b ^1.0.0`, `foo <1.1.0` is forbidden. | 2.iii | 1 |
| | |
| Because `foo >=1.1.0` depends on `x ^1.0.0` which depends on `y ^2.0.0`, `foo >=1.1.0` requires `y ^2.0.0`. | 3 | |
| And because `foo >=1.1.0` depends on `y ^1.0.0`, `foo >=1.1.0` is forbidden. | 2.iii | |
| And because `foo <1.1.0` is forbidden (1), `foo` is forbidden. | 1.ii | |
| So, because `root` depends on `foo ^1.0.0`, version solving failed. | 2.iii | |

Because the derivation graph is non-linear–the incompatibility `{not foo any}`
is caused by two derived incompatibilities–we can't just explain everything in a
single sequence like we did in the last example. We first explain why
`foo <1.1.0` is forbidden, giving the conclusion an explicit line number so that
we can refer back to it later on. Then we explain why `foo >=1.1.0` is forbidden
before finally concluding that version solving has failed.

# Differences From CDCL and Answer Set Solving

Although Pubgrub is based on CDCL and answer set solving, it differs from the
standard algorithms for those techniques in a number of important ways. These
differences make it more efficient for version solving in particular and
simplify away some of the complexity inherent in the general-purpose algorithms.

## Version Ranges

The original algorithms work exclusively on atomic boolean variables that must
each be assigned either "true" or "false" in the solution. In package terms,
these would correspond to individual package versions, so dependencies would
have to be represented as:

    (foo 1.0.0 or foo 1.0.1 or ...) → (bar 1.0.0 or bar 1.0.1 or ...)

This would add a lot of overhead in translating dependencies from version ranges
to concrete sets of individual versions. What's more, we'd have to try to
reverse that conversion when displaying messages to users, since it's much more
natural to think of packages in terms of version ranges.

So instead of operating on individual versions, Pubgrub uses as its logical
terms `PackageName`s that may be either `PackageId`s (representing individual
versions) or `PackageRange`s (representing ranges of allowed versions). The
dependency above is represented much more naturally as:

    foo ^1.0.0 → bar ^1.0.0

## Implicit Mutual Exclusivity

In the original algorithms, all relationships between variables must be
expressed as explicit formulas. A crucial feature of package solving is that the
solution must contain at most one package version with a given name, but
representing that in pure boolean logic would require a separate formula for
each pair of versions for each package. This would mean an up-front cost of
O(n²) in the number of versions per package.

To avoid that overhead, the mutual exclusivity of different versions of the same
package (as well as packages with the same name from different sources) is built
into Pubgrub. For example, it considers `foo ^1.0.0` and `foo ^2.0.0` to be
contradictory even though it doesn't have an explicit formula saying so.

## Lazy Formulas

The original algorithms are written with the assumption that all formulas
defining the relationships between variables are available throughout the
algorithm. However, when doing version solving, it's impractical to eagerly list
all dependencies of every package. What's more, the set of packages that may be
relevant can't be known in advance.

Instead of listing all formulas immediately, Pubgrub adds only the formulas that
are relevant to individual package versions, and then only when those versions
are candidates for selection. Because those formulas always involve a package
being selected, they're guaranteed not to contradict the existing set of
selected packages.

## No Unfounded Set Detection

Answer set solving has a notion of "unfounded sets": sets of variables whose
formulas reference one another in a cycle. A naïve answer set solving algorithm
may end up marking these variables as true even when that's not necessary,
producing a non-minimal solution. To avoid this, the algorithm presented in
Gebser *et al* adds explicit formulas that force these variable to be false if
they aren't required by some formula outside the cycle.

This adds a lot of complexity to the algorithm which turns out to be unnecessary
for version solving. Pubgrub avoids selecting package versions in unfounded sets
by only choosing versions for packages that are known to have outstanding
dependencies.
