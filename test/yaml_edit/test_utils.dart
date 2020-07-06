import 'package:test/test.dart';

import 'package:pub/src/yaml_edit.dart';
import 'package:pub/src/yaml_edit/equality.dart';
import 'package:pub/src/yaml_edit/errors.dart';

/// Asserts that a string containing a single YAML document is unchanged
/// when dumped right after loading.
void Function() expectLoadPreservesYAML(String source) {
  final doc = YamlEditor(source);
  return () => expect(doc.toString(), equals(source));
}

/// Asserts that [builder] has the same internal value as [expected].
void expectYamlBuilderValue(YamlEditor builder, Object expected) {
  final builderValue = builder.parseAt([]);
  expectDeepEquals(builderValue, expected);
}

/// Asserts that [builder] has the same internal value as [expected].
void expectDeepEquals(Object actual, Object expected) {
  expect(
      actual, predicate((actual) => deepEquals(actual, expected), '$expected'));
}

Matcher notEquals(dynamic expected) => isNot(equals(expected));

/// A matcher for functions that throw [PathError].
Matcher throwsPathError = throwsA(isA<PathError>());

/// A matcher for functions that throw [AliasError].
Matcher throwsAliasError = throwsA(isA<AliasError>());

/// Enum to hold the possible modification methods.
enum YamlModificationMethod {
  appendTo,
  assign,
  remove,
  prependTo,
  insert,
  splice
}
