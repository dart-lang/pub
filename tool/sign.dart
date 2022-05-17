import 'dart:ffi';
import 'dart:io';

import 'package:pub/src/package_signing/gpgme.dart';

void main() async {
  final lib = GpgmeBindings(DynamicLibrary.open('libgpgme.so'));
  print('Using ${lib.version}');

  final context = lib.newContext();

  Future<void> check(String source, String sign) async {
    final data = await File(source).readAsBytes();
    final signature = await File(sign).readAsBytes();

    final signatures = context.verifyDetached(
        lib.dataFromBytes(data), lib.dataFromBytes(signature));
    print('Result for $source: $signatures');
  }

  await check('README.md', 'README.md.asc');
  await check('/tmp/test/google-analytics-admin-0.9.1.pom',
      '/tmp/test/google-analytics-admin-0.9.1.pom.asc');
  await check('/tmp/test/sqlite3-native-library-3.38.5.pom',
      '/tmp/test/sqlite3-native-library-3.38.5.pom.asc');
}
