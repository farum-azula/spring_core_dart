// An isolate's line to the first one (PrimaryIsolateLink): a question
// that gets no answer does not wait for ever.
import 'dart:async';
import 'dart:isolate';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_web/src/isolates/server_isolate_pool_io.dart';
import 'package:test/test.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  late ReceivePort primary;
  late List<List<Object?>> asked;
  late PrimaryIsolateLink link;

  // The pool's side: answers with what [answer] gives, or not at all.
  void serve(Object? Function(String id, Object? request)? answer) {
    primary.listen((message) {
      final question = message! as List<Object?>;
      asked.add(question);
      if (answer != null) {
        (question[4]! as SendPort).send([
          'answer',
          question[1],
          answer('${question[2]}', question[3]),
          null,
        ]);
      }
    });
  }

  setUp(() {
    primary = ReceivePort();
    asked = [];
    link = PrimaryIsolateLink(primary.sendPort, timeout: _ms * 100);
  });

  tearDown(() {
    link.close();
    primary.close();
  });

  test('an answer comes back to its question', () async {
    serve((id, request) => '$id: $request');
    expect(
      await Future.wait([link.ask('a', 1), link.ask('b', 2)]),
      ['a: 1', 'b: 2'],
    );
    expect(asked.map((question) => question.first), everyElement('ask'));
  });

  test('a first isolate that never answers: the question fails with a '
      'TimeoutException that names it', () async {
    serve(null);
    final watch = Stopwatch()..start();
    await expectLater(
      link
          .ask('tickets.next', null)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('still waiting for the first isolate'),
          ),
      throwsA(
        isA<TimeoutException>()
            .having((e) => e.message, 'message', contains('"tickets.next"'))
            .having((e) => e.duration, 'duration', _ms * 100),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(asked, hasLength(1));
  });

  test('a question may wait longer or shorter than the others', () async {
    serve(null);
    await expectLater(
      link.ask('quick', null, timeout: _ms * 10),
      throwsA(
        isA<TimeoutException>().having((e) => e.duration, 'duration', _ms * 10),
      ),
    );
  });

  test('an answer that comes after its question gave up is dropped, and '
      'the next question gets its own', () async {
    serve(null);
    await expectLater(link.ask('slow', null), throwsA(isA<TimeoutException>()));
    final back = asked.single[4]! as SendPort;
    final next = link.ask('next', null);
    await Future<void>.delayed(_ms * 10);
    back
      ..send(['answer', asked.first[1], 'late', null])
      ..send(['answer', asked.last[1], 'mine', null]);
    expect(await next, 'mine');
  });

  test("the handler's error comes back as a PrimaryIsolateException", () {
    primary.listen((message) {
      final question = message! as List<Object?>;
      (question[4]! as SendPort).send(['answer', question[1], null, 'no']);
    });
    expect(
      link.ask('a', null),
      throwsA(
        isA<PrimaryIsolateException>().having(
          (e) => e.message,
          'message',
          'no',
        ),
      ),
    );
  });

  test('close fails the questions that wait, and every later one', () async {
    serve(null);
    final waiting = link.ask('a', null);
    link.close();
    await expectLater(waiting, throwsStateError);
    await expectLater(link.ask('b', null), throwsStateError);
    await Future<void>.delayed(_ms * 10);
    expect(asked, hasLength(1), reason: 'nothing is sent on a closed line');
  });

  test(
    'a request that cannot cross isolates fails its question only',
    () async {
      serve((id, request) => request);
      final port = ReceivePort();
      addTearDown(port.close);
      await expectLater(link.ask('a', port), throwsArgumentError);
      expect(await link.ask('b', 2), 2);
    },
  );
}
