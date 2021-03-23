import 'dart:convert';
import 'dart:io';

import 'package:tar/tar.dart';

Future<void> main() async {
  // Start reading a tar file
  final reader = TarReader(File('reference/gnu.tar').openRead());

  while (await reader.moveNext()) {
    final header = reader.current.header;
    print('${header.name}: ');

    // Print the output if it's a regular file
    if (header.typeFlag == TypeFlag.reg) {
      await reader.current.contents.transform(utf8.decoder).forEach(print);
    }
  }

  // We can write tar files to any stream sink like this:
  final output = File('test.tar').openWrite();

  await Stream<TarEntry>.value(
    TarEntry.data(
      TarHeader(
          name: 'hello_dart.txt',
          mode: int.parse('644', radix: 8),
          userName: 'Dart',
          groupName: 'Dartgroup'),
      utf8.encode('Hello world'),
    ),
  )
      // transform tar entries back to a byte stream
      .transform(tarWriter)
      // and then write that to the file
      .pipe(output);
}
