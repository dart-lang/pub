# Test Data

Data used in tests is called _test data_ and is located in this folder, or
sub-folders thereof. This is not for test files, this folder should not contain
test code, only data used in tests.

## Golden Test

The helper command `runPubGoldenTest` will run a `pub` command and compare the
output to a folder in `test/testdata/goldens/`. If the file does not exist, it
will be created. Thus, it is safe to delete all files in `test/testdata/goldens`
and recreate them -- just carefully review the changes before committing.

**Maintaining goldens**:
 1. Delete `test/testdata/goldens/`.
 2. Re-run tests to re-create files in `test/testdata/goldens/`.
 3. Compare changes, using `git diff test/testdata/goldens/`.

