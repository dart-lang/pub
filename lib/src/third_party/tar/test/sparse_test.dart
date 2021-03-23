import 'dart:io';

import 'dart:math';
import 'dart:typed_data';

import 'package:chunked_stream/chunked_stream.dart';
import 'package:tar/src/sparse.dart';
import 'package:tar/tar.dart';
import 'package:test/test.dart';

import 'system_tar.dart';

/// Writes [size] random bytes to [path].
Future<void> createTestFile(String path, int size) {
  final random = Random();
  final file = File(path);
  final sink = file.openWrite();

  const chunkSize = 1024;
  for (var i = 0; i < size ~/ chunkSize; i++) {
    final buffer = Uint8List(chunkSize);
    fillRandomBytes(buffer, random);
    sink.add(buffer);
  }

  final remaining = Uint8List(size % chunkSize);
  fillRandomBytes(remaining, random);
  sink.add(remaining);

  return sink.close();
}

/// Creates a sparse file with a logical size of [size]. The file will be all
/// zeroes.
Future<void> createCleanSparseTestFile(String path, int size) async {
  await Process.run('truncate', ['--size=$size', path]);
}

/// Creates a file with [size], where some chunks are zeroes.
Future<void> createSparseTestFile(String path, int size) {
  final sink = File(path).openWrite();
  final random = Random();

  var remaining = size;
  while (remaining > 0) {
    final nextBlockSize = min(remaining, 512);
    if (random.nextBool()) {
      sink.add(Uint8List(nextBlockSize));
    } else {
      final block = Uint8List(nextBlockSize);
      fillRandomBytes(block, random);
      sink.add(block);
    }

    remaining -= nextBlockSize;
  }

  return sink.close();
}

void fillRandomBytes(List<int> bytes, Random random) {
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
}

Future<void> validate(Stream<List<int>> tar, Map<String, String> files) async {
  final reader = TarReader(tar);

  for (var i = 0; i < files.length; i++) {
    expect(await reader.moveNext(), isTrue);

    final fileName = reader.current.name;
    final matchingFile = files[fileName];

    if (matchingFile == null) {
      fail('Unexpected file $fileName in tar file');
    }

    final actualContents = ChunkedStreamIterator(File(matchingFile).openRead());
    final tarContents = ChunkedStreamIterator(reader.current.contents);

    while (true) {
      final actualChunk = await actualContents.read(1024);
      final tarChunk = await tarContents.read(1024);
      expect(tarChunk, actualChunk);

      if (actualChunk.isEmpty) break;
    }
  }
}

void main() {
  // map from file names to desired size
  const testFiles = {
    'reg_1': 65023,
    'reg_2': 65539,
    'reg_3': 65534,
    'sparse_1': 131076,
    'sparse_2': 65534,
    'clean_sparse_1': 131076,
    'clean_sparse_2': 65534,
  };
  late String baseDirectory;

  String path(String fileName) => '$baseDirectory/$fileName';

  setUpAll(() async {
    baseDirectory = Directory.systemTemp.path +
        '/tar_test/${DateTime.now().millisecondsSinceEpoch}';
    await Directory(baseDirectory).create(recursive: true);

    for (final entry in testFiles.entries) {
      final name = entry.key;
      final size = entry.value;

      if (name.contains('clean')) {
        await createCleanSparseTestFile(path(name), size);
      } else if (name.contains('sparse')) {
        await createSparseTestFile(path(name), size);
      } else {
        await createTestFile(path(entry.key), entry.value);
      }
    }
  });

  tearDownAll(() {
    Directory(baseDirectory).delete(recursive: true);
  });

  Future<void> testSubset(
      Iterable<String> keys, String format, String? sparse) {
    final files = {for (final file in keys) file: path(file)};
    final tar = createTarStream(files.keys,
        baseDir: baseDirectory, archiveFormat: format, sparseVersion: sparse);
    return validate(tar, files);
  }

  for (final format in ['gnu', 'v7', 'oldgnu', 'posix', 'ustar']) {
    group('reads large files in $format', () {
      test('single file', () {
        return testSubset(['reg_1'], format, null);
      });

      test('reads multiple large files successfully', () {
        return testSubset(['reg_1', 'reg_2', 'reg_3'], format, null);
      });
    });
  }

  for (final format in ['gnu', 'posix']) {
    for (final sparseVersion in ['0.0', '0.1', '1.0']) {
      group('sparse format $format, version $sparseVersion', () {
        test('reads a clean sparse file', () {
          return testSubset(['clean_sparse_1'], format, sparseVersion);
        });

        test('reads a sparse file', () {
          return testSubset(['sparse_1'], format, sparseVersion);
        });

        test('reads clean sparse / regular files', () {
          return testSubset(
            ['reg_1', 'clean_sparse_1', 'reg_3', 'clean_sparse_2'],
            format,
            sparseVersion,
          );
        });

        test('reads mixed regular / sparse / clean sparse files', () {
          return testSubset(
            ['reg_1', 'sparse_2', 'clean_sparse_1', 'reg_3'],
            format,
            sparseVersion,
          );
        });
      });
    }
  }

  group('sparse entries', () {
    final tests = [
      _SparseTestcase(
        input: [],
        size: 0,
        isValid: true,
        inverted: [SparseEntry(0, 0)],
      ),
      _SparseTestcase(
        input: [],
        size: 5000,
        isValid: true,
        inverted: [SparseEntry(0, 5000)],
      ),
      _SparseTestcase(
        input: [SparseEntry(0, 5000)],
        size: 5000,
        isValid: true,
        inverted: [SparseEntry(5000, 0)],
      ),
      _SparseTestcase(
        input: [SparseEntry(1000, 4000)],
        size: 5000,
        isValid: true,
        inverted: [SparseEntry(0, 1000), SparseEntry(5000, 0)],
      ),
      _SparseTestcase(
        input: [SparseEntry(0, 3000)],
        size: 5000,
        isValid: true,
        inverted: [SparseEntry(3000, 2000)],
      ),
      _SparseTestcase(
        input: [SparseEntry(3000, 2000)],
        size: 5000,
        isValid: true,
        inverted: [SparseEntry(0, 3000), SparseEntry(5000, 0)],
      ),
      _SparseTestcase(
        input: [SparseEntry(2000, 2000)],
        size: 5000,
        isValid: true,
        inverted: [SparseEntry(0, 2000), SparseEntry(4000, 1000)],
      ),
      _SparseTestcase(
        input: [SparseEntry(0, 2000), SparseEntry(8000, 2000)],
        size: 10000,
        isValid: true,
        inverted: [SparseEntry(2000, 6000), SparseEntry(10000, 0)],
      ),
      _SparseTestcase(
        input: [
          SparseEntry(0, 2000),
          SparseEntry(2000, 2000),
          SparseEntry(4000, 0),
          SparseEntry(4000, 3000),
          SparseEntry(7000, 1000),
          SparseEntry(8000, 0),
          SparseEntry(8000, 2000)
        ],
        size: 10000,
        isValid: true,
        inverted: [SparseEntry(10000, 0)],
      ),
      _SparseTestcase(
        input: [
          SparseEntry(0, 0),
          SparseEntry(1000, 0),
          SparseEntry(2000, 0),
          SparseEntry(3000, 0),
          SparseEntry(4000, 0),
          SparseEntry(5000, 0),
        ],
        size: 5000,
        isValid: true,
        inverted: [SparseEntry(0, 5000)],
      ),
      _SparseTestcase(
        input: [SparseEntry(1, 0)],
        size: 0,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(-1, 0)],
        size: 100,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(0, -1)],
        size: 100,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(0, 1)],
        size: -100,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(9223372036854775807, 3), SparseEntry(6, -5)],
        size: 35,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(1, 3), SparseEntry(6, -5)],
        size: 35,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(9223372036854775807, 9223372036854775807)],
        size: 9223372036854775807,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(3, 3)],
        size: 5,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(2, 0), SparseEntry(1, 0), SparseEntry(0, 0)],
        size: 3,
        isValid: false,
      ),
      _SparseTestcase(
        input: [SparseEntry(1, 3), SparseEntry(2, 2)],
        size: 10,
        isValid: false,
      ),
    ];

    for (var i = 0; i < tests.length; i++) {
      final testcase = tests[i];

      test('validateSparseEntries #$i', () {
        expect(validateSparseEntries(testcase.input, testcase.size),
            testcase.isValid);
      });

      if (testcase.isValid) {
        test('invertSparseEntries #$i', () {
          expect(invertSparseEntries(testcase.input, testcase.size),
              testcase.inverted);
        });
      }
    }
  });
}

class _SparseTestcase {
  final List<SparseEntry> input;
  final int size;
  final bool isValid;
  final List<SparseEntry>? inverted;

  _SparseTestcase({
    required this.input,
    required this.size,
    required this.isValid,
    this.inverted,
  });
}
