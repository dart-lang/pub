import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:pub/src/path.dart';

void main() {
  test('withPathContext overrides p', () async {
    final customContext = path.Context(style: path.Style.posix, current: '/custom');
    
    expect(p.current, isNot('/custom'));
    
    await withPathContext(() {
      expect(p.current, '/custom');
      expect(p.style, path.Style.posix);
      return Future.value();
    }, pathContext: customContext);
    
    expect(p.current, isNot('/custom'));
  });

  test('withPathContext works with nested zones', () async {
    final context1 = path.Context(style: path.Style.posix, current: '/1');
    final context2 = path.Context(style: path.Style.posix, current: '/2');
    
    await withPathContext(() async {
      expect(p.current, '/1');
      await withPathContext(() async {
        expect(p.current, '/2');
      }, pathContext: context2);
      expect(p.current, '/1');
    }, pathContext: context1);
  });
}
