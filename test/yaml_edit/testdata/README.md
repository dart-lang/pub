# Golden Testing

This folder contains the files used for Golden testing performed by [golden_test.dart](../golden_test.dart).

With golden testing, we are able to quickly ensure that our output conforms to our expectations given input parameters, which are extremely valuable especially on complex test cases not easily captured by unit tests.

When the tests are run (see [Running Tests](#Running-Tests)), the series of specified modifications will be performed on the input, and the various output states will be compared against the `.golden` files if they exist. Othweise, if the `.golden` files do not exist (such as in the case of a new test case), they will be created.

## Table of Contents

1. [Running Tests](#Running-Tests)
1. [Input Format](#Input-Format)
1. [Adding Test Cases](#Adding-Test-Cases)
1. [Output Format](#Output-Format)

## Running Tests

By default, golden testing is performed with `pub run test`. If we only wanted to
performed golden testing, simply do: `pub run test test/golden_test.dart`.

## Input Format

Input files have the following format:

```
INFORMATION (e.g. description) - parsed as text
---
INPUT - parsed as YAML
---
Modifications - parsed as YAML, must be a list.
```

The information section is meant for a brief description of your test, and other further elaboration on what your test is targeted at (e.g. modification of complex keys). The Input section should be the YAML that you wish to parse, and the modifications section should be a list of modification operations, formatted as a YAML list. The valid list of modifications are as follows:

- [update, [ path ], newValue]
- [remove, [ path ], keyOrIndex]
- [append, [ collectionPath ], newValue]

An example of what an input file might look like is:

```
BASIC LIST TEST - Ensures that the basic list operations work.
---
- 0
- 1
- 2
- 3
---
- [remove, [1]]
- [append, [], 4]
```

Note that the parser uses `\n---\n` as the delimiter to separate the different sections.

## Adding Test Cases

To add test cases, simple create `<your-test-name>.test` files in `/test/testdata/input` in the format explained in [Input Format](#Input-Format). When the test script is first run, the respective `.golden` files will be created in `/test/testdata/output`, you should check to ensure that the output is as expected since future collaborators will be counting on your output!

## Output Format

The output `.golden` files contain a series of YAML strings representing the state of the YAML after each specified modification, with the first string being the inital state as specified in the ouput. These states are separated by `\n---\n` as a delimiter. For example, the output file for the sample input file above is:

```
- 0
- 1
- 2
- 3
---
- 0
- 2
- 3
---
- 0
- 2
- 3
- 4
```

The first state is the input, the second state is the first state with the removal of the element at index 1, and the last state is the result of the second state with the insertion of the element 4 into the list.
