import 'package:collection/collection.dart';

abstract class Step {
  final List<Step> parents;

  factory Step(String message) = _MessageStep;
}

class _MessageStep implements Step {
  final String _message;

  _MessageStep(this._message);

  String toString() {
    var dependency = allowed.length == 1
        ? allowed.first.toString()
        : "one of ${allowed.join(', ')}";
    return "because (${parents.join(' and ')}) $_message";
  }
}

class Version {
  final String name;
  final int version;

  Version(this.name, this.version);

  bool operator ==(other) => other is Version && other.name == name && other.version == version;
  int get hashCode => toString().hashCode;

  String toString() => "$name$version";
}

class Constraint implements Step {
  String get package => dependers.first.name;

  String get target => allowed.first.name;

  final List<Step> parents;
  final List<Version> dependers;
  final List<Version> allowed;

  Constraint(this.dependers, this.allowed, [this.parents = const []]);

  String toString() {
    var depender = dependers.length == 1
        ? dependers.first.toString()
        : "${dependers.first.version}-${dependers.last.version}";

    var dependency = allowed.length == 1
        ? allowed.first.toString()
        : "one of ${allowed.join(', ')}";

    return "$depender needs $dependency";
  }
}

class Clause implements Step {
  final List<Step> parents;
  final List<Version> allowed;

  Clause(this.parents, this.allowed);

  String toString() {
    var dependency = allowed.length == 1
        ? allowed.first.toString()
        : "one of ${allowed.join(', ')}";
    return "because (${parents.join(' and ')}) we need $dependency";
  }
}

class Solver {
  final List<Constraint> constraints;
  final Map<String, Set<int>> versions;
  final List<Clause> clauses;
  final List<Version> selected;

  Solver(this.constraints, this.versions, [this.clauses = const [], List<Version> selected])
      : selected = selected ?? [] {
    var clause = _findUnitClause();
    while (clause != null) {
      var version = clause.allowed.single;
      selected.add(version);
      clauses.removeWhere((clause) => clause.allowed.contains(version));

      constraints.removeWhere((constraint) {
        // Make the selected package's dependencies into clauses.
        if (constraint.package == version.name) {
          clauses.add(new Clause([clause, constraint], constraint.allowed));
          return true;
        }

        // If a dependency includes the selected version, it's satisfied and can
        // be removed.
        if (constraint.allowed.contains(version)) return true;

        // If a constraint doesn't allow this version, we can't select any of
        // the constraint's dependers.
        if (constraint.target == version.name) {
          // TODO: Should we somehow record that we removed these versions here
          // for this reason?
          versions[constraint.target]
              .removeAll(constraint.dependers.map((version) => version.version));
          if (versions[constraint.target].isEmpty) 
            // TODO: backtrack here
            throw "out of versions of ${version.name}";
          }
          return true;
        }

        return false;
      });

      // If a clause includes the selected version, it's satisfied and can be
      // removed.
      clauses.removeWhere((clause) => clause.allowed.contains(version));
    }
  }

  Clause _findUnitClause() {
    var clause = clauses.firstWhere((clause) => clause.allowed.length == 1, orElse: () => null);
    if (clause == null) return null;

    clauses.remove(clause);
    return clause;
  }

  String toString() => constraints.join("\n") + "\n" + clauses.join("\n");
}

void main() {
  var solver = new Solver([
    new Constraint([new Version('a', 1)], [new Version('b', 2), new Version('b', 3)]),
    new Constraint([new Version('a', 1)], [new Version('c', 2)]),
    new Constraint([new Version('b', 2)], [new Version('c', 3)]),
    new Constraint([new Version('b', 3)], [new Version('c', 2), new Version('c', 3)])
  ], {
    'a': new Set.from([1]),
    'b': new Set.from([2, 3]),
    'c': new Set.from([2, 3])
  });

  print(solver);
  print('=' * 100);

  solver.select(new Version('a', 1));
}