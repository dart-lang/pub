import 'package:test/test.dart';
import '../descriptor.dart' as d;
import '../test_pub.dart';

void main() {
  test('It is possible to add an externally hosted package', () async {
    final port = await servePackages((builder) {
      builder.serve('foo', '1.2.3');
      builder.serve('foo', '0.0.1');
      builder.serve('baz', '1.0.0');
    });
    await d.appDir({'baz': '1.0.0'}).create();
    await pubCommand(RunCommand('add', RegExp('')),
        args: ['foo', '--location=http://localhost:$port']);
    await d.cacheDir({'baz': '1.0.0', 'foo': '1.2.3'}).validate();
  });
}
