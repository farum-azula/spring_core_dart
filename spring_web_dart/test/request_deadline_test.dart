import 'dart:async';

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  group('RequestDeadline', () {
    test('there is none outside run', () {
      expect(RequestDeadline.current, isNull);
    });

    test(
      'run makes it current, for the body and what the body starts',
      () async {
        await RequestDeadline.run(const Duration(seconds: 5), () async {
          final deadline = RequestDeadline.current!;
          expect(deadline.budget, const Duration(seconds: 5));
          expect(deadline.isExpired, isFalse);
          expect(deadline.remaining, lessThanOrEqualTo(deadline.budget));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          expect(RequestDeadline.current, same(deadline));
          final fromTimer = Completer<RequestDeadline?>();
          Timer(
            Duration.zero,
            () => fromTimer.complete(RequestDeadline.current),
          );
          expect(await fromTimer.future, same(deadline));
        });
        expect(RequestDeadline.current, isNull);
      },
    );

    test('run returns what the body returns', () async {
      expect(RequestDeadline.run(const Duration(seconds: 1), () => 42), 42);
      expect(
        await RequestDeadline.run(
          const Duration(seconds: 1),
          () async => 'done',
        ),
        'done',
      );
    });

    test('it expires, remaining stops at zero, check throws', () async {
      await RequestDeadline.run(const Duration(milliseconds: 30), () async {
        final deadline = RequestDeadline.current!..check();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(deadline.isExpired, isTrue);
        expect(deadline.remaining, Duration.zero);
        expect(
          deadline.check,
          throwsA(
            isA<RequestDeadlineExceededException>()
                .having((e) => e.budget, 'budget', deadline.budget)
                .having((e) => e.message, 'message', contains('30 ms')),
          ),
        );
      });
    });

    test('a zero or negative budget has passed already', () {
      RequestDeadline.run(Duration.zero, () {
        expect(RequestDeadline.current!.isExpired, isTrue);
      });
      RequestDeadline.run(const Duration(seconds: -1), () {
        expect(RequestDeadline.current!.isExpired, isTrue);
        expect(RequestDeadline.current!.remaining, Duration.zero);
      });
    });

    test('a nested deadline takes the earlier end', () {
      RequestDeadline.run(const Duration(seconds: 10), () {
        final outer = RequestDeadline.current!;
        RequestDeadline.run(const Duration(seconds: 1), () {
          final inner = RequestDeadline.current!;
          expect(inner, isNot(same(outer)));
          expect(inner.budget, const Duration(seconds: 1));
        });
        expect(RequestDeadline.current, same(outer));
      });
    });

    test('a nested deadline never extends the outer one', () {
      RequestDeadline.run(const Duration(seconds: 1), () {
        RequestDeadline.run(const Duration(hours: 1), () {
          final inner = RequestDeadline.current!;
          expect(inner.budget, lessThanOrEqualTo(const Duration(seconds: 1)));
          expect(
            inner.remaining,
            lessThanOrEqualTo(const Duration(seconds: 1)),
          );
        });
      });
    });

    test('a nested deadline expires with the outer one', () async {
      await RequestDeadline.run(const Duration(milliseconds: 40), () async {
        await RequestDeadline.run(const Duration(hours: 1), () async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          expect(RequestDeadline.current!.isExpired, isTrue);
        });
      });
    });

    test('runUntil ends at the instant, and never later than the outer', () {
      RequestDeadline.runUntil(
        DateTime.now().add(const Duration(seconds: 2)),
        () {
          final deadline = RequestDeadline.current!;
          expect(deadline.remaining, greaterThan(const Duration(seconds: 1)));
          expect(
            deadline.remaining,
            lessThanOrEqualTo(const Duration(seconds: 2)),
          );
        },
      );
      RequestDeadline.runUntil(
        DateTime.now().subtract(const Duration(seconds: 1)),
        () => expect(RequestDeadline.current!.isExpired, isTrue),
      );
      RequestDeadline.run(const Duration(seconds: 1), () {
        RequestDeadline.runUntil(
          DateTime.now().add(const Duration(hours: 1)),
          () => expect(
            RequestDeadline.current!.remaining,
            lessThanOrEqualTo(const Duration(seconds: 1)),
          ),
        );
      });
    });

    test('release ends it for the code under it', () async {
      await RequestDeadline.run(const Duration(milliseconds: 20), () async {
        final deadline = RequestDeadline.current!..release();
        expect(deadline.isReleased, isTrue);
        expect(RequestDeadline.current, isNull);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(deadline.isExpired, isFalse);
        deadline.check();
        // A new one under a released one stands alone.
        RequestDeadline.run(const Duration(hours: 1), () {
          expect(RequestDeadline.current!.budget, const Duration(hours: 1));
        });
      });
    });

    test('concurrent bodies have their own deadlines', () async {
      final seen = await Future.wait([
        for (final ms in [100, 200, 300])
          RequestDeadline.run(Duration(milliseconds: ms), () async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return RequestDeadline.current!.budget.inMilliseconds;
          }),
      ]);
      expect(seen, [100, 200, 300]);
    });

    test('errors of the body reach the caller as usual', () {
      expect(
        () => RequestDeadline.run(
          const Duration(seconds: 1),
          () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('toString shows what is left', () {
      RequestDeadline.run(const Duration(seconds: 1), () {
        expect(RequestDeadline.current.toString(), contains('of 1000 ms'));
      });
      expect(
        RequestDeadlineExceededException(const Duration(seconds: 2)).toString(),
        contains('2000 ms'),
      );
    });
  });
}
