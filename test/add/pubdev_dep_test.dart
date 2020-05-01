import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  final addCommand = RunCommand('add', RegExp(''));

  test('A package from pub server can be added', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.2.3');
      builder.serve('foo', '0.0.1');
      builder.serve('baz', '1.0.0');
    });
    await d.appDir({'baz': '1.0.0'}).create();
    await pubCommand(addCommand, args: ['foo']);
    await pubGet();
    await d.cacheDir({'baz': '1.0.0', 'foo': '1.2.3'}).validate();
  });

  test('Refuses to add package if it already exists in pubspec', () async {
    await servePackages((builder) {
      builder.serve('foo', '1.2.3');
    });
    await d.appDir({'foo': '0.0.1'}).create();
    const expectedError =
        'pubspec.yaml already contains foo. Refusing to alter it.';
    await pubCommand(addCommand,
        args: ['foo'], error: expectedError, exitCode: 0);
  });
}
