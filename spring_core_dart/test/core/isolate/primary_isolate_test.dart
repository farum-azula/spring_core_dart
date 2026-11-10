import 'dart:async';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

final class _Tickets implements PrimaryIsolateHandler {
  var _next = 0;

  @override
  String get id => 'tickets.next';

  @override
  Object? handle(Object? request) => _next += (request as int?) ?? 1;
}

final class _Slow implements PrimaryIsolateHandler {
  @override
  String get id => 'slow';

  @override
  Future<Object?> handle(Object? request) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return 'done $request';
  }
}

final class _Failing implements PrimaryIsolateHandler {
  @override
  String get id => 'failing';

  @override
  Object? handle(Object? request) => throw const FormatException('no');
}

void main() {
  tearDown(() => PrimaryIsolate.remote = null);

  test('in the first isolate the handler of that id answers', () async {
    final primary = PrimaryIsolate([_Tickets(), _Slow()]);
    expect(await primary.ask('tickets.next'), 1);
    expect(await primary.ask('tickets.next', 5), 6);
    expect(await primary.ask('slow', 'x'), 'done x');
  });

  test('no handler of that id: a StateError that names it', () async {
    await expectLater(
      PrimaryIsolate(const []).ask('nobody'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('"nobody"'), contains('main')),
        ),
      ),
    );
  });

  test("a handler's error is the answer's error", () async {
    await expectLater(
      PrimaryIsolate([_Failing()]).ask('failing'),
      throwsFormatException,
    );
  });

  test('in another isolate the question is sent to the first', () async {
    final sent = <(String, Object?)>[];
    PrimaryIsolate.remote = (id, request) async {
      sent.add((id, request));
      return 'from the first';
    };
    final local = _Tickets();
    final primary = PrimaryIsolate([local]);
    expect(await primary.ask('tickets.next', 3), 'from the first');
    expect(sent, [('tickets.next', 3)]);
    expect(await primary.ask('tickets.next'), 'from the first');
    // The handler of this isolate was never asked.
    PrimaryIsolate.remote = null;
    expect(await primary.ask('tickets.next'), 1);
  });

  test('PrimaryIsolateException is the text of the error', () {
    expect(
      '${const PrimaryIsolateException('Bad state: x')}',
      'PrimaryIsolateException: Bad state: x',
    );
  });
}
