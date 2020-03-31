// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub/src/io.dart';
import 'package:test/test.dart';

import 'descriptor.dart';

void main() {
  group('listDir', () {
    test('ignores hidden files by default', () {
      expect(withTempDir((temp) {
        writeTextFile(path.join(temp, 'file1.txt'), '');
        writeTextFile(path.join(temp, 'file2.txt'), '');
        writeTextFile(path.join(temp, '.file3.txt'), '');
        _createDir(path.join(temp, '.subdir'));
        writeTextFile(path.join(temp, '.subdir', 'file3.txt'), '');

        expect(
            listDir(temp, recursive: true),
            unorderedEquals(
                [path.join(temp, 'file1.txt'), path.join(temp, 'file2.txt')]));
      }), completes);
    });

    test('includes hidden files when told to', () {
      expect(withTempDir((temp) {
        writeTextFile(path.join(temp, 'file1.txt'), '');
        writeTextFile(path.join(temp, 'file2.txt'), '');
        writeTextFile(path.join(temp, '.file3.txt'), '');
        _createDir(path.join(temp, '.subdir'));
        writeTextFile(path.join(temp, '.subdir', 'file3.txt'), '');

        expect(
            listDir(temp, recursive: true, includeHidden: true),
            unorderedEquals([
              path.join(temp, 'file1.txt'),
              path.join(temp, 'file2.txt'),
              path.join(temp, '.file3.txt'),
              path.join(temp, '.subdir'),
              path.join(temp, '.subdir', 'file3.txt')
            ]));
      }), completes);
    });

    test("doesn't ignore hidden files above the directory being listed", () {
      expect(withTempDir((temp) {
        var dir = path.join(temp, '.foo', 'bar');
        ensureDir(dir);
        writeTextFile(path.join(dir, 'file1.txt'), '');
        writeTextFile(path.join(dir, 'file2.txt'), '');
        writeTextFile(path.join(dir, 'file3.txt'), '');

        expect(
            listDir(dir, recursive: true),
            unorderedEquals([
              path.join(dir, 'file1.txt'),
              path.join(dir, 'file2.txt'),
              path.join(dir, 'file3.txt')
            ]));
      }), completes);
    });
  });

  group('canonicalize', () {
    test('resolves a non-link', () {
      expect(_withCanonicalTempDir((temp) {
        var filePath = path.join(temp, 'file');
        writeTextFile(filePath, '');
        expect(canonicalize(filePath), equals(filePath));
      }), completes);
    });

    test('resolves a non-existent file', () {
      expect(_withCanonicalTempDir((temp) {
        expect(canonicalize(path.join(temp, 'nothing')),
            equals(path.join(temp, 'nothing')));
      }), completes);
    });

    test('resolves a symlink', () {
      expect(_withCanonicalTempDir((temp) {
        _createDir(path.join(temp, 'linked-dir'));
        createSymlink(path.join(temp, 'linked-dir'), path.join(temp, 'dir'));
        expect(canonicalize(path.join(temp, 'dir')),
            equals(path.join(temp, 'linked-dir')));
      }), completes);
    });

    test('resolves a relative symlink', () {
      expect(_withCanonicalTempDir((temp) {
        _createDir(path.join(temp, 'linked-dir'));
        createSymlink(path.join(temp, 'linked-dir'), path.join(temp, 'dir'),
            relative: true);
        expect(canonicalize(path.join(temp, 'dir')),
            equals(path.join(temp, 'linked-dir')));
      }), completes);
    });

    test('resolves a single-level horizontally recursive symlink', () {
      expect(_withCanonicalTempDir((temp) {
        var linkPath = path.join(temp, 'foo');
        createSymlink(linkPath, linkPath);
        expect(canonicalize(linkPath), equals(linkPath));
      }), completes);
    });

    test('resolves a multi-level horizontally recursive symlink', () {
      expect(_withCanonicalTempDir((temp) {
        var fooPath = path.join(temp, 'foo');
        var barPath = path.join(temp, 'bar');
        var bazPath = path.join(temp, 'baz');
        createSymlink(barPath, fooPath);
        createSymlink(bazPath, barPath);
        createSymlink(fooPath, bazPath);
        expect(canonicalize(fooPath), equals(fooPath));
        expect(canonicalize(barPath), equals(barPath));
        expect(canonicalize(bazPath), equals(bazPath));

        createSymlink(fooPath, path.join(temp, 'outer'));
        expect(canonicalize(path.join(temp, 'outer')), equals(fooPath));
      }), completes);
    });

    test('resolves a broken symlink', () {
      expect(_withCanonicalTempDir((temp) {
        createSymlink(path.join(temp, 'nonexistent'), path.join(temp, 'foo'));
        expect(canonicalize(path.join(temp, 'foo')),
            equals(path.join(temp, 'nonexistent')));
      }), completes);
    });

    test('resolves multiple nested symlinks', () {
      expect(_withCanonicalTempDir((temp) {
        var dir1 = path.join(temp, 'dir1');
        var dir2 = path.join(temp, 'dir2');
        var subdir1 = path.join(dir1, 'subdir1');
        var subdir2 = path.join(dir2, 'subdir2');
        _createDir(dir2);
        _createDir(subdir2);
        createSymlink(dir2, dir1);
        createSymlink(subdir2, subdir1);
        expect(canonicalize(path.join(subdir1, 'file')),
            equals(path.join(subdir2, 'file')));
      }), completes);
    });

    test('resolves a nested vertical symlink', () {
      expect(_withCanonicalTempDir((temp) {
        var dir1 = path.join(temp, 'dir1');
        var dir2 = path.join(temp, 'dir2');
        var subdir = path.join(dir1, 'subdir');
        _createDir(dir1);
        _createDir(dir2);
        createSymlink(dir2, subdir);
        expect(canonicalize(path.join(subdir, 'file')),
            equals(path.join(dir2, 'file')));
      }), completes);
    });

    test('resolves a vertically recursive symlink', () {
      expect(_withCanonicalTempDir((temp) {
        var dir = path.join(temp, 'dir');
        var subdir = path.join(dir, 'subdir');
        _createDir(dir);
        createSymlink(dir, subdir);
        expect(
            canonicalize(path.join(
                temp, 'dir', 'subdir', 'subdir', 'subdir', 'subdir', 'file')),
            equals(path.join(dir, 'file')));
      }), completes);
    });

    test('resolves a symlink that links to a path that needs more resolving',
        () {
      expect(_withCanonicalTempDir((temp) {
        var dir = path.join(temp, 'dir');
        var linkdir = path.join(temp, 'linkdir');
        var linkfile = path.join(dir, 'link');
        _createDir(dir);
        createSymlink(dir, linkdir);
        createSymlink(path.join(linkdir, 'file'), linkfile);
        expect(canonicalize(linkfile), equals(path.join(dir, 'file')));
      }), completes);
    });

    test('resolves a pair of pathologically-recursive symlinks', () {
      expect(_withCanonicalTempDir((temp) {
        var foo = path.join(temp, 'foo');
        var subfoo = path.join(foo, 'subfoo');
        var bar = path.join(temp, 'bar');
        var subbar = path.join(bar, 'subbar');
        createSymlink(subbar, foo);
        createSymlink(subfoo, bar);
        expect(canonicalize(subfoo),
            equals(path.join(subfoo, 'subbar', 'subfoo')));
      }), completes);
    });
  });

  testExistencePredicate('entryExists', entryExists,
      forFile: true,
      forFileSymlink: true,
      forMultiLevelFileSymlink: true,
      forDirectory: true,
      forDirectorySymlink: true,
      forMultiLevelDirectorySymlink: true,
      forBrokenSymlink: true,
      forMultiLevelBrokenSymlink: true);

  testExistencePredicate('linkExists', linkExists,
      forFile: false,
      forFileSymlink: true,
      forMultiLevelFileSymlink: true,
      forDirectory: false,
      forDirectorySymlink: true,
      forMultiLevelDirectorySymlink: true,
      forBrokenSymlink: true,
      forMultiLevelBrokenSymlink: true);

  testExistencePredicate('fileExists', fileExists,
      forFile: true,
      forFileSymlink: true,
      forMultiLevelFileSymlink: true,
      forDirectory: false,
      forDirectorySymlink: false,
      forMultiLevelDirectorySymlink: false,
      forBrokenSymlink: false,
      forMultiLevelBrokenSymlink: false);

  testExistencePredicate('dirExists', dirExists,
      forFile: false,
      forFileSymlink: false,
      forMultiLevelFileSymlink: false,
      forDirectory: true,
      forDirectorySymlink: true,
      forMultiLevelDirectorySymlink: true,
      forBrokenSymlink: false,
      forMultiLevelBrokenSymlink: false);
}

void testExistencePredicate(String name, bool Function(String path) predicate,
    {bool forFile,
    bool forFileSymlink,
    bool forMultiLevelFileSymlink,
    bool forDirectory,
    bool forDirectorySymlink,
    bool forMultiLevelDirectorySymlink,
    bool forBrokenSymlink,
    bool forMultiLevelBrokenSymlink}) {
  group(name, () {
    test('returns $forFile for a file', () {
      expect(withTempDir((temp) {
        var file = path.join(temp, 'test.txt');
        writeTextFile(file, 'contents');
        expect(predicate(file), equals(forFile));
      }), completes);
    });

    test('returns $forDirectory for a directory', () {
      expect(withTempDir((temp) {
        var file = path.join(temp, 'dir');
        _createDir(file);
        expect(predicate(file), equals(forDirectory));
      }), completes);
    });

    test('returns $forDirectorySymlink for a symlink to a directory', () {
      expect(withTempDir((temp) {
        var targetPath = path.join(temp, 'dir');
        var symlinkPath = path.join(temp, 'linkdir');
        _createDir(targetPath);
        createSymlink(targetPath, symlinkPath);
        expect(predicate(symlinkPath), equals(forDirectorySymlink));
      }), completes);
    });

    test(
        'returns $forMultiLevelDirectorySymlink for a multi-level symlink to '
        'a directory', () {
      expect(withTempDir((temp) {
        var targetPath = path.join(temp, 'dir');
        var symlink1Path = path.join(temp, 'link1dir');
        var symlink2Path = path.join(temp, 'link2dir');
        _createDir(targetPath);
        createSymlink(targetPath, symlink1Path);
        createSymlink(symlink1Path, symlink2Path);
        expect(predicate(symlink2Path), equals(forMultiLevelDirectorySymlink));
      }), completes);
    });

    test('returns $forBrokenSymlink for a broken symlink', () {
      expect(withTempDir((temp) {
        var targetPath = path.join(temp, 'dir');
        var symlinkPath = path.join(temp, 'linkdir');
        _createDir(targetPath);
        createSymlink(targetPath, symlinkPath);
        deleteEntry(targetPath);
        expect(predicate(symlinkPath), equals(forBrokenSymlink));
      }), completes);
    });

    test('returns $forMultiLevelBrokenSymlink for a multi-level broken symlink',
        () {
      expect(withTempDir((temp) {
        var targetPath = path.join(temp, 'dir');
        var symlink1Path = path.join(temp, 'link1dir');
        var symlink2Path = path.join(temp, 'link2dir');
        _createDir(targetPath);
        createSymlink(targetPath, symlink1Path);
        createSymlink(symlink1Path, symlink2Path);
        deleteEntry(targetPath);
        expect(predicate(symlink2Path), equals(forMultiLevelBrokenSymlink));
      }), completes);
    });

    // Windows doesn't support symlinking to files.
    if (!Platform.isWindows) {
      test('returns $forFileSymlink for a symlink to a file', () {
        expect(withTempDir((temp) {
          var targetPath = path.join(temp, 'test.txt');
          var symlinkPath = path.join(temp, 'link.txt');
          writeTextFile(targetPath, 'contents');
          createSymlink(targetPath, symlinkPath);
          expect(predicate(symlinkPath), equals(forFileSymlink));
        }), completes);
      });

      test(
          'returns $forMultiLevelFileSymlink for a multi-level symlink to a '
          'file', () {
        expect(withTempDir((temp) {
          var targetPath = path.join(temp, 'test.txt');
          var symlink1Path = path.join(temp, 'link1.txt');
          var symlink2Path = path.join(temp, 'link2.txt');
          writeTextFile(targetPath, 'contents');
          createSymlink(targetPath, symlink1Path);
          createSymlink(symlink1Path, symlink2Path);
          expect(predicate(symlink2Path), equals(forMultiLevelFileSymlink));
        }), completes);
      });
    }
  });
  group('extractTarGz', () {
    test('decompresses simple archive', () async {
      await withTempDir((tempDir) async {
        await extractTarGz(
            Stream.fromIterable(
              [
                base64Decode(
                    'H4sIAP2weF4AA+3S0QqCMBiG4V2KeAE1nfuF7maViNBqzDyQ6N4z6yCIogOtg97ncAz2wTvfuxCW'
                    'alZ6UFqttIiUYpXObWlzM57fqcyIkcxoU2ZKZyYvtErsvLNuuvboYpKotqm7uPUv74XYeBf7Oh66'
                    '8I1dX+LH/qFbt6HaLHrnd9O/cQ0sxZv++UP/Qob+1srQX08/5dmf9z+le+erdJWOHyE9/3oPAAAA'
                    'AAAAAAAAAAAAgM9dALkoaRMAKAAA')
              ],
            ),
            tempDir);
        await appDir().validate(tempDir);
      });
    });

    test('throws on tar error', () async {
      await withTempDir((tempDir) async {
        await expectLater(
            () async => await extractTarGz(
                Stream.fromIterable(
                  [
                    base64Decode(
                        // Correct Gzip of a faulty tar archive.
                        'H4sICBKyeF4AA215YXBwLnRhcgDt0sEKgjAAh/GdewrxAWpzbkJvs0pEaDVmHiR699Q6BBJ00Dr0'
                        '/Y5jsD98850LYSMWJXuFkUJaITNTmEyPR09Caaut0lIXSkils1yKxCy76KFtLi4miWjqqo0H//Ze'
                        'iLV3saviuQ3f2PUlfkwf2l0Tyv26c/44/xtDYJsP6a0trJn2z1765/3/UMbYvr+cf8rUn/e/pifn'
                        'y3Sbjh8hvf16DwAAAAAAAAAAAAAAAIDPre4CU/3q/CcAAA==')
                  ],
                ),
                tempDir),
            throwsA(isA<FileSystemException>()));
      });
    });

    test('throws on gzip error', () async {
      await withTempDir((tempDir) async {
        await expectLater(
            () async => await extractTarGz(
                Stream.fromIterable(
                  [
                    [10, 20, 30] // Not a good gz stream.
                  ],
                ),
                tempDir),
            throwsA(isA<FileSystemException>()));
      });
    });
  });
}

/// Like [withTempDir], but canonicalizes the path before passing it to [fn].
Future<T> _withCanonicalTempDir<T>(FutureOr<T> Function(String path) fn) =>
    withTempDir((temp) => fn(canonicalize(temp)));

/// Creates a directory [dir].
String _createDir(String dir) {
  Directory(dir).createSync();
  return dir;
}
