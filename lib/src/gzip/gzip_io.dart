// gzip_io.dart
import 'dart:convert';
import 'dart:io';

/// Exposes the standard IO GZip decoder.
final Converter<List<int>, List<int>> gzipDecoder = GZipCodec().decoder;
