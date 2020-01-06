// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pub/src/error_group.dart';
import 'package:test/test.dart';

ErrorGroup errorGroup;

// TODO(nweiz): once there's a global error handler, we should test that it does
// and does not get called at appropriate times. See issue 5958.
//
// One particular thing we should test that has no tests now is that a stream
// that has a subscription added and subsequently canceled counts as having no
// listeners.

void main() {
  group('with no futures or streams', () {
    setUp(() {
      errorGroup = ErrorGroup();
    });

    test('should pass signaled errors to .done', () {
      expect(errorGroup.done, throwsFormatException);
      errorGroup.signalError(FormatException());
    });

    test(
        "shouldn't allow additional futures or streams once an error has been "
        'signaled', () {
      expect(errorGroup.done, throwsFormatException);
      errorGroup.signalError(FormatException());

      expect(() => errorGroup.registerFuture(Future.value()), throwsStateError);
      expect(
          () => errorGroup.registerStream(StreamController(sync: true).stream),
          throwsStateError);
    });
  });

  group('with a single future', () {
    Completer completer;
    Future future;

    setUp(() {
      errorGroup = ErrorGroup();
      completer = Completer();
      future = errorGroup.registerFuture(completer.future);
    });

    test('should pass through a value from the future', () {
      expect(future, completion(equals('value')));
      expect(errorGroup.done, completes);
      completer.complete('value');
    });

    test(
        "shouldn't allow additional futures or streams once .done has "
        'been called', () {
      completer.complete('value');

      expect(
          completer.future
              .then((_) => errorGroup.registerFuture(Future.value())),
          throwsStateError);
      expect(
          completer.future.then((_) =>
              errorGroup.registerStream(StreamController(sync: true).stream)),
          throwsStateError);
    });

    test(
        'should pass through an exception from the future if it has a '
        'listener', () {
      expect(future, throwsFormatException);
      // errorGroup shouldn't top-level the exception
      completer.completeError(FormatException());
    });

    test(
        'should notify the error group of an exception from the future even '
        'if it has a listener', () {
      expect(future, throwsFormatException);
      expect(errorGroup.done, throwsFormatException);
      completer.completeError(FormatException());
    });

    test(
        'should pass a signaled exception to the future if it has a listener '
        'and should ignore a subsequent value from that future', () {
      expect(future, throwsFormatException);
      // errorGroup shouldn't top-level the exception
      errorGroup.signalError(FormatException());
      completer.complete('value');
    });

    test(
        'should pass a signaled exception to the future if it has a listener '
        'and should ignore a subsequent exception from that future', () {
      expect(future, throwsFormatException);
      // errorGroup shouldn't top-level the exception
      errorGroup.signalError(FormatException());
      completer.completeError(ArgumentError());
    });

    test(
        'should notify the error group of a signaled exception even if the '
        'future has a listener', () {
      expect(future, throwsFormatException);
      expect(errorGroup.done, throwsFormatException);
      errorGroup.signalError(FormatException());
    });

    test(
        'should complete .done if the future receives a value even if the '
        "future doesn't have a listener", () {
      expect(errorGroup.done, completes);
      completer.complete('value');

      // A listener added afterwards should receive the value
      expect(errorGroup.done.then((_) => future), completion(equals('value')));
    });

    test(
        'should pipe an exception from the future to .done if the future '
        "doesn't have a listener", () {
      expect(errorGroup.done, throwsFormatException);
      completer.completeError(FormatException());

      // A listener added afterwards should receive the exception
      expect(errorGroup.done.catchError((_) {
        expect(future, throwsFormatException);
      }), completes);
    });

    test(
        "should pass a signaled exception to .done if the future doesn't have "
        'a listener', () {
      expect(errorGroup.done, throwsFormatException);
      errorGroup.signalError(FormatException());

      // A listener added afterwards should receive the exception
      expect(errorGroup.done.catchError((_) {
        completer.complete('value'); // should be ignored
        expect(future, throwsFormatException);
      }), completes);
    });
  });

  group('with multiple futures', () {
    Completer completer1;
    Completer completer2;
    Future future1;
    Future future2;

    setUp(() {
      errorGroup = ErrorGroup();
      completer1 = Completer();
      completer2 = Completer();
      future1 = errorGroup.registerFuture(completer1.future);
      future2 = errorGroup.registerFuture(completer2.future);
    });

    test(
        'should pipe exceptions from one future to the other and to '
        '.complete', () {
      expect(future1, throwsFormatException);
      expect(future2, throwsFormatException);
      expect(errorGroup.done, throwsFormatException);

      completer1.completeError(FormatException());
    });

    test(
        'each future should be able to complete with a value '
        'independently', () {
      expect(future1, completion(equals('value1')));
      expect(future2, completion(equals('value2')));
      expect(errorGroup.done, completes);

      completer1.complete('value1');
      completer2.complete('value2');
    });

    test(
        "shouldn't throw a top-level exception if a future receives an error "
        'after the other listened future completes', () {
      expect(future1, completion(equals('value')));
      completer1.complete('value');

      expect(future1.then((_) {
        // shouldn't cause a top-level exception
        completer2.completeError(FormatException());
      }), completes);
    });

    test(
        "shouldn't throw a top-level exception if an error is signaled after "
        'one listened future completes', () {
      expect(future1, completion(equals('value')));
      completer1.complete('value');

      expect(future1.then((_) {
        // shouldn't cause a top-level exception
        errorGroup.signalError(FormatException());
      }), completes);
    });
  });

  group('with a single stream', () {
    StreamController controller;
    Stream stream;

    setUp(() {
      errorGroup = ErrorGroup();
      controller = StreamController.broadcast(sync: true);
      stream = errorGroup.registerStream(controller.stream);
    });

    test('should pass through values from the stream', () {
      var iter = StreamIterator(stream);
      iter.moveNext().then((hasNext) {
        expect(hasNext, isTrue);
        expect(iter.current, equals(1));
        iter.moveNext().then((hasNext) {
          expect(hasNext, isTrue);
          expect(iter.current, equals(2));
          expect(iter.moveNext(), completion(isFalse));
        });
      });
      expect(errorGroup.done, completes);

      controller
        ..add(1)
        ..add(2)
        ..close();
    });

    test(
        'should pass through an error from the stream if it has a '
        'listener', () {
      expect(stream.first, throwsFormatException);
      // errorGroup shouldn't top-level the exception
      controller.addError(FormatException());
    });

    test(
        'should notify the error group of an exception from the stream even '
        'if it has a listener', () {
      expect(stream.first, throwsFormatException);
      expect(errorGroup.done, throwsFormatException);
      controller.addError(FormatException());
    });

    test(
        'should pass a signaled exception to the stream if it has a listener '
        'and should unsubscribe that stream', () {
      // errorGroup shouldn't top-level the exception
      expect(stream.first, throwsFormatException);
      errorGroup.signalError(FormatException());

      expect(() => controller.add('value'), returnsNormally);
    });

    test(
        'should notify the error group of a signaled exception even if the '
        'stream has a listener', () {
      expect(stream.first, throwsFormatException);
      expect(errorGroup.done, throwsFormatException);
      errorGroup.signalError(FormatException());
    });

    test(
        'should see one value and complete .done when the stream is done even '
        "if the stream doesn't have a listener", () {
      expect(errorGroup.done, completes);
      controller.add('value');
      controller.close();

      // Now that broadcast controllers have been removed a listener should
      // see the value that has been put into the controller.
      expect(errorGroup.done.then((_) => stream.toList()),
          completion(equals(['value'])));
    });
  });

  group('with a single single-subscription stream', () {
    StreamController controller;
    Stream stream;

    setUp(() {
      errorGroup = ErrorGroup();
      controller = StreamController(sync: true);
      stream = errorGroup.registerStream(controller.stream);
    });

    test(
        'should complete .done when the stream is done even if the stream '
        "doesn't have a listener", () {
      expect(errorGroup.done, completes);
      controller.add('value');
      controller.close();

      // A listener added afterwards should receive the value
      expect(errorGroup.done.then((_) => stream.toList()),
          completion(equals(['value'])));
    });

    test(
        'should pipe an exception from the stream to .done if the stream '
        "doesn't have a listener", () {
      expect(errorGroup.done, throwsFormatException);
      controller.addError(FormatException());

      // A listener added afterwards should receive the exception
      expect(errorGroup.done.catchError((_) {
        controller.add('value'); // should be ignored
        expect(stream.first, throwsFormatException);
      }), completes);
    });

    test(
        "should pass a signaled exception to .done if the stream doesn't "
        'have a listener', () {
      expect(errorGroup.done, throwsFormatException);
      errorGroup.signalError(FormatException());

      // A listener added afterwards should receive the exception
      expect(errorGroup.done.catchError((_) {
        controller.add('value'); // should be ignored
        expect(stream.first, throwsFormatException);
      }), completes);
    });
  });

  group('with multiple streams', () {
    StreamController controller1;
    StreamController controller2;
    Stream stream1;
    Stream stream2;

    setUp(() {
      errorGroup = ErrorGroup();
      controller1 = StreamController.broadcast(sync: true);
      controller2 = StreamController.broadcast(sync: true);
      stream1 = errorGroup.registerStream(controller1.stream);
      stream2 = errorGroup.registerStream(controller2.stream);
    });

    test('should pipe exceptions from one stream to the other and to .done',
        () {
      expect(stream1.first, throwsFormatException);
      expect(stream2.first, throwsFormatException);
      expect(errorGroup.done, throwsFormatException);

      controller1.addError(FormatException());
    });

    test('each future should be able to emit values independently', () {
      expect(stream1.toList(), completion(equals(['value1.1', 'value1.2'])));
      expect(stream2.toList(), completion(equals(['value2.1', 'value2.2'])));
      expect(errorGroup.done, completes);

      controller1
        ..add('value1.1')
        ..add('value1.2')
        ..close();
      controller2
        ..add('value2.1')
        ..add('value2.2')
        ..close();
    });

    test(
        "shouldn't throw a top-level exception if a stream receives an error "
        'after the other listened stream completes', () {
      var signal = Completer();
      expect(stream1.toList().whenComplete(signal.complete),
          completion(equals(['value1', 'value2'])));
      controller1
        ..add('value1')
        ..add('value2')
        ..close();

      expect(signal.future.then((_) {
        // shouldn't cause a top-level exception
        controller2.addError(FormatException());
      }), completes);
    });

    test(
        "shouldn't throw a top-level exception if an error is signaled after "
        'one listened stream completes', () {
      var signal = Completer();
      expect(stream1.toList().whenComplete(signal.complete),
          completion(equals(['value1', 'value2'])));
      controller1
        ..add('value1')
        ..add('value2')
        ..close();

      expect(signal.future.then((_) {
        // shouldn't cause a top-level exception
        errorGroup.signalError(FormatException());
      }), completes);
    });
  });

  group('with a stream and a future', () {
    StreamController controller;
    Stream stream;
    Completer completer;
    Future future;

    setUp(() {
      errorGroup = ErrorGroup();
      controller = StreamController.broadcast(sync: true);
      stream = errorGroup.registerStream(controller.stream);
      completer = Completer();
      future = errorGroup.registerFuture(completer.future);
    });

    test('should pipe exceptions from the stream to the future', () {
      expect(stream.first, throwsFormatException);
      expect(future, throwsFormatException);
      expect(errorGroup.done, throwsFormatException);

      controller.addError(FormatException());
    });

    test('should pipe exceptions from the future to the stream', () {
      expect(stream.first, throwsFormatException);
      expect(future, throwsFormatException);
      expect(errorGroup.done, throwsFormatException);

      completer.completeError(FormatException());
    });

    test(
        'the stream and the future should be able to complete/emit values '
        'independently', () {
      expect(stream.toList(), completion(equals(['value1.1', 'value1.2'])));
      expect(future, completion(equals('value2.0')));
      expect(errorGroup.done, completes);

      controller
        ..add('value1.1')
        ..add('value1.2')
        ..close();
      completer.complete('value2.0');
    });

    test(
        "shouldn't throw a top-level exception if the stream receives an error "
        'after the listened future completes', () {
      expect(future, completion(equals('value')));
      completer.complete('value');

      expect(future.then((_) {
        // shouldn't cause a top-level exception
        controller.addError(FormatException());
      }), completes);
    });

    test(
        "shouldn't throw a top-level exception if the future receives an "
        'error after the listened stream completes', () {
      var signal = Completer();
      expect(stream.toList().whenComplete(signal.complete),
          completion(equals(['value1', 'value2'])));
      controller
        ..add('value1')
        ..add('value2')
        ..close();

      expect(signal.future.then((_) {
        // shouldn't cause a top-level exception
        completer.completeError(FormatException());
      }), completes);
    });
  });
}
