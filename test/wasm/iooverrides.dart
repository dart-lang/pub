import 'dart:io';

import 'package:file/file.dart' as f;

/// Creates an [IOOverrides] that uses [fs] for all operations.
IOOverrides createFileSystemIOOverrides(f.FileSystem fs) =>
    _FileSystemIOOverrides(fs);

/// An [IOOverrides] that uses a [f.FileSystem] for all operations.
final class _FileSystemIOOverrides extends IOOverrides {
  final f.FileSystem _fs;

  _FileSystemIOOverrides(this._fs);

  @override
  File createFile(String path) => _fs.file(path);

  @override
  Directory createDirectory(String path) => _fs.directory(path);

  @override
  Link createLink(String path) => _fs.link(path);

  @override
  Future<FileStat> stat(String path) => _fs.stat(path);

  @override
  FileStat statSync(String path) => _fs.statSync(path);

  @override
  Future<bool> fseIdentical(String path1, String path2) =>
      _fs.identical(path1, path2);

  @override
  bool fseIdenticalSync(String path1, String path2) =>
      _fs.identicalSync(path1, path2);

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) =>
      _fs.type(path, followLinks: followLinks);

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) =>
      _fs.typeSync(path, followLinks: followLinks);

  @override
  Directory getCurrentDirectory() => _fs.currentDirectory;

  @override
  void setCurrentDirectory(String path) {
    _fs.currentDirectory = path;
  }

  @override
  Directory getSystemTempDirectory() => _fs.systemTempDirectory;
}
