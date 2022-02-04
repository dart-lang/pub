# Test Data

Data used in tests is called _test data_ and is located in this folder, or
sub-folders thereof. This is not for test files, this folder should not contain
test code, only data used in tests.

## Golden Test

The `test` wrapper `testWithGolden('<name>', (ctx) async {` will register a
test case, and create a file:
  `test/testdata/goldens/path/to/myfile_test/<name>.txt`
, where `path/to/myfile_test.dart` is the name of the file containing the test
case, and `<name>` is the name of the test case.

Any calls to `ctx.run` will run `pub` and compare the output to a section in the
golden file. If the file does not exist, it is created and the
test is marked as skipped.
Thus, it is safe to delete all files in `test/testdata/goldens` and recreate
them -- just carefully review the changes before committing.

**Maintaining goldens**:
 1. Delete `test/testdata/goldens/`.
 2. Re-run tests to re-create files in `test/testdata/goldens/`.
 3. Compare changes, using `git diff test/testdata/goldens/`.

