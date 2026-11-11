@Tags(['supabase', 'supabase-stack'])
library;

// Level 4, Edge Functions: the declared interface `Functions` against the
// functions of the test project (test/stack/supabase/functions), which
// answer what they got and who called; and what the gateway does with a
// stream of events and with a file.
import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'stack_support.dart';

void main() {
  group('Edge Functions of the stack', skip: Stack.skip, () {
    late StackApp ada;
    // Nobody signs in here: the anon key.
    late StackApp nobody;

    setUpAll(() async {
      Stack.require();
      ada = await StackApp.start();
      nobody = await StackApp.start();
      await ada.signInAsNewUser();
    });

    tearDownAll(() async {
      await ada.close();
      await nobody.close();
    });

    group('the declared interface', () {
      test('a POST with a JSON body, answered as an object; the function '
          "got the user's token", () async {
        await ada.run(() async {
          final result = await ada.functions.sendInvite(
            Invite(email: 'grace@example.com'),
          );
          expect(result.id, '${ada.userId}|grace@example.com');
        });
      });

      test('a GET with a query parameter, answered as a map; Auth knows '
          'the token the function got', () async {
        await ada.run(() async {
          final stats = await ada.functions.stats('2026-01-01 & more');
          expect(stats['from'], '2026-01-01 & more');
          expect(stats['method'], 'GET');
          expect(stats['user'], ada.userId);
          expect(stats['role'], 'authenticated');
          // The function asked Auth who the token is.
          expect(stats['verified'], ada.userId);
          expect(stats['apikey'], isTrue);
        });
      });

      test("a path under the function's name, answered as text; the "
          'gateway checked the token itself', () async {
        await ada.run(() async {
          expect(
            await ada.functions.report(2026),
            'report 2026 for ${ada.userId}',
          );
        });
      });

      test('nobody signed in: the functions are called with the anon '
          'key', () async {
        await nobody.run(() async {
          final stats = await nobody.functions.stats('today');
          expect(stats['user'], isNull);
          expect(stats['role'], 'anon');
          expect(stats['verified'], isNull);
          expect(
            (await nobody.functions.sendInvite(Invite(email: 'a@b.c'))).id,
            'anon|a@b.c',
          );
        });
      });

      test('an error status of a function is a FeignException with its '
          'status and body', () async {
        await ada.run(() async {
          await expectLater(
            ada.functions.stats('fail'),
            throwsA(
              isA<FeignException>()
                  .having((e) => e.status, 'status', 422)
                  .having(
                    (e) => e.responseBody,
                    'responseBody',
                    contains('no stats from fail'),
                  ),
            ),
          );
          await expectLater(
            ada.functions.report(0),
            throwsA(
              isA<FeignException>().having((e) => e.status, 'status', 404),
            ),
          );
        });
      });

      test('a cached call of a function is kept apart per caller', () async {
        final her = await ada.run(() => ada.bean<Reports>().byYear(2031));
        final nobodys = await nobody.run(
          () => nobody.bean<Reports>().byYear(2031),
        );
        expect(her, 'report 2031 for ${ada.userId}');
        expect(nobodys, 'report 2031 for anon');
        await ada.run(() async {
          final reports = ada.bean<Reports>();
          final calls = reports.calls;
          expect(await reports.byYear(2031), her);
          expect(reports.calls, calls);
        });
      });
    });

    // No Feign interface of the test application returns an EventStream
    // or bytes (one would need the generator): the same client under it
    // (SupabaseHttp, the key and the token of the caller) reads them, and
    // test/stack/README.md has the interface for a check by hand.
    group('through the gateway', () {
      test('server-sent events of a function arrive one by one', () async {
        await ada.run(() async {
          final response = await ada.http.stream(
            SupabaseService.functions,
            HttpMethod.get,
            '/events',
            headers: {'accept': 'text/event-stream'},
          );
          expect(response.statusCode.value, 200);
          expect(response.headers.contentType, startsWith('text/event-stream'));
          final watch = Stopwatch()..start();
          final arrivals = <Duration>[];
          final events = await response.body
              .transform(const SseDecoder())
              .where((event) => event.data != null)
              .map((event) {
                arrivals.add(watch.elapsed);
                return event;
              })
              .toList();
          expect(events.map((event) => event.event), ['tick', 'tick', 'tick']);
          expect(events.map((event) => event.id), ['1', '2', '3']);
          expect(
            [for (final event in events) jsonDecode(event.data!)],
            [
              for (var n = 1; n <= 3; n++) {'n': n, 'user': ada.userId},
            ],
          );
          // Not held back until the end: the first came well before the
          // last (they are sent 200 ms apart).
          expect(
            arrivals.last - arrivals.first,
            greaterThan(const Duration(milliseconds: 150)),
            reason: 'the gateway buffered the stream: $arrivals',
          );
        });
      });

      test('a file of a function arrives whole, with its headers', () async {
        await ada.run(() async {
          final response = await ada.http.send(
            SupabaseService.functions,
            HttpMethod.get,
            '/download',
          );
          expect(response.statusCode.value, 200);
          expect(response.headers.contentType, 'application/octet-stream');
          expect(
            response.headers['content-disposition'],
            'attachment; filename="stack.bin"',
          );
          expect(response.bodyBytes, [
            for (var i = 0; i < 4096; i++) i % 251,
          ]);
        });
      });
    });
  });
}
