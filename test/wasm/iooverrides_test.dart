import 'dart:io';

import 'package:file/memory.dart';
import 'package:test/test.dart';

import 'iooverrides.dart';

void main() {
  test('FileSystemIOOverrides redirects IO operations', () async {
    final fs = MemoryFileSystem();
    await IOOverrides.runWithIOOverrides(() async {
      final file = File('/test.txt');
      await file.writeAsString('hello');

      expect(fs.file('/test.txt').readAsStringSync(), 'hello');
      expect(await file.readAsString(), 'hello');

      final dir = Directory('/subdir');
      await dir.create();
      expect(fs.directory('/subdir').existsSync(), isTrue);

      final list = await Directory('/').list().toList();
      expect(list.map((e) => e.path), containsAll(['test.txt', 'subdir']));
    }, createFileSystemIOOverrides(fs));
  });

  test('getCurrentDirectory and setCurrentDirectory', () async {
    final fs = MemoryFileSystem();
    fs.directory('/a/b').createSync(recursive: true);
    await IOOverrides.runWithIOOverrides(() async {
      expect(Directory.current.path, '/');
      Directory.current = '/a/b';
      expect(Directory.current.path, '/a/b');
      expect(fs.currentDirectory.path, '/a/b');
    }, createFileSystemIOOverrides(fs));
  });

  test('systemTempDirectory', () async {
    final fs = MemoryFileSystem();
    await IOOverrides.runWithIOOverrides(() async {
      expect(Directory.systemTemp.path, fs.systemTempDirectory.path);
    }, createFileSystemIOOverrides(fs));
  });
}
