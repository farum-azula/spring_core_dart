@Tags(['supabase'])
library;

import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';
import 'support.dart';

void main() {
  late MockHttpTransport transport;

  setUp(() => transport = MockHttpTransport());

  Future<void> withApp(
    Future<void> Function(AssertableApplicationContext context) body, [
    List<String> properties = const [],
  ]) => appRunner(transport, properties).runAsync((context) async {
    expect(context.startupFailure, isNull);
    await body(context);
  });

  test('a function is called with the key, the token and JSON', () async {
    transport
        .when(HttpMethod.post, '/functions/v1/send-invite')
        .respond(200, json: {'id': 'inv-1'});
    await withApp((context) async {
      final result = await context.getBean<Functions>().sendInvite(
        Invite(email: 'a@b.c'),
      );
      expect(result.id, 'inv-1');
    });
    final request = transport.requests.single;
    expect('${request.url}', '$projectUrl/functions/v1/send-invite');
    expect(jsonDecode(utf8.decode(request.body!)), {'email': 'a@b.c'});
    expect(request.headers['apikey'], 'anon-key');
    expect(request.headers['Authorization'], 'Bearer anon-key');
    expect(request.followRedirects, isFalse);
  });

  test('a query parameter, a path variable and a text answer', () async {
    transport
        .when(HttpMethod.get, '/functions/v1/stats')
        .respond(200, json: {'count': 3});
    transport
        .when(HttpMethod.get, '/functions/v1/reports/2026')
        .respond(200, body: 'report');
    await withApp((context) async {
      final functions = context.getBean<Functions>();
      expect(await functions.stats('2026-01-01'), {'count': 3});
      expect(await functions.report(2026), 'report');
    });
    expect(transport.requests.first.url.queryParameters, {
      'from': '2026-01-01',
    });
  });

  test("a failed answer is Feign's exception", () async {
    transport
        .when(HttpMethod.get, '/functions/v1/reports/1')
        .respond(404, json: {'error': 'no such report'});
    await withApp((context) async {
      await expectLater(
        context.getBean<Functions>().report(1),
        throwsA(isA<FeignNotFound>()),
      );
    });
  });

  test('inside asServiceRole the service role key is sent', () async {
    transport
        .when(HttpMethod.get, '/functions/v1/reports/2')
        .respond(200, body: 'r');
    await withApp((context) async {
      await context.getBean<SupabaseCredentials>().asServiceRole(
        () => context.getBean<Functions>().report(2),
      );
    });
    final request = transport.requests.single;
    expect(request.headers['apikey'], 'service-key');
    expect(request.headers['Authorization'], 'Bearer service-key');
  });

  test('the region of the configuration is asked for', () async {
    transport
        .when(HttpMethod.get, '/functions/v1/reports/3')
        .respond(200, body: 'r');
    await withApp(
      (context) => context.getBean<Functions>().report(3),
      ['spring.supabase.functions.region=eu-west-1'],
    );
    expect(transport.requests.single.headers['x-region'], 'eu-west-1');
  });

  group('what a function may answer', () {
    test('server-sent events, one by one', () async {
      transport.when(HttpMethod.get, '/functions/v1/progress').respondEvents([
        const ServerSentEvent({'done': 1}),
        const ServerSentEvent({'done': 2}),
      ]);
      await withApp((context) async {
        final events = await context
            .getBean<Functions>()
            .progress()
            .take(2)
            .toList();
        expect(events, [
          {'done': 1},
          {'done': 2},
        ]);
      });
      final request = transport.requests.first;
      expect(request.headers['Accept'], 'text/event-stream');
      expect(request.headers['Authorization'], 'Bearer anon-key');
    });

    test('a file, whole', () async {
      transport
          .when(HttpMethod.get, '/functions/v1/export')
          .respond(200, bytes: [1, 2, 3]);
      await withApp((context) async {
        expect(await context.getBean<Functions>().export(), [1, 2, 3]);
      });
    });

    test('a body as it arrives, with the key and the token', () async {
      transport
          .when(HttpMethod.get, '/functions/v1/export')
          .respondStream(
            200,
            () => Stream.fromIterable([
              [1, 2],
              [3],
            ]),
          );
      await withApp((context) async {
        expect(await context.getBean<Functions>().exportStream().toList(), [
          [1, 2],
          [3],
        ]);
      });
      final request = transport.requests.single;
      expect(request.headers['Accept'], '*/*');
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer anon-key');
    });

    test('a failed status fails the stream', () async {
      transport
          .when(HttpMethod.get, '/functions/v1/export')
          .respond(403, json: {'error': 'no'});
      await withApp((context) async {
        await expectLater(
          context.getBean<Functions>().exportStream().toList(),
          throwsA(isA<FeignForbidden>()),
        );
      });
    });
  });

  group('cached calls keep each caller apart', () {
    test('one user, another user and nobody', () async {
      transport
          .when(HttpMethod.get, '/functions/v1/reports/2026')
          .respond(200, body: 'report');
      await withApp((context) async {
        final reports = context.getBean<Reports>();
        await reports.byYear(2026);
        await reports.byYear(2026);
        expect(reports.calls, 1);
        final credentials = context.getBean<SupabaseCredentials>();
        await credentials.asServiceRole(() => reports.byYear(2026));
        expect(reports.calls, 2);
        await credentials.asServiceRole(() => reports.byYear(2026));
        expect(reports.calls, 2);
        await reports.byYear(2026);
        expect(reports.calls, 2);
      });
    });

    test('with a key of its own too', () async {
      transport
          .when(HttpMethod.get, '/functions/v1/reports/2026')
          .respond(200, body: 'report');
      await withApp((context) async {
        final reports = context.getBean<Reports>();
        final credentials = context.getBean<SupabaseCredentials>();
        await reports.byYearWithKey(2026);
        await credentials.asServiceRole(() => reports.byYearWithKey(2026));
        expect(reports.calls, 2);
        await reports.byYearWithKey(2026);
        await credentials.asServiceRole(() => reports.byYearWithKey(2026));
        expect(reports.calls, 2);
      });
    });

    test('a shared cache is the same for everyone', () async {
      transport
          .when(HttpMethod.get, '/functions/v1/reports/2026')
          .respond(200, body: 'report');
      await withApp((context) async {
        final reports = context.getBean<Reports>();
        await reports.shared(2026);
        await context.getBean<SupabaseCredentials>().asServiceRole(
          () => reports.shared(2026),
        );
        expect(reports.calls, 1);
      }, ['spring.supabase.cache.shared=catalog']);
    });
  });
}
