// A full server says so at once: server.max-concurrent-requests and
// server.max-connections answer 503 with Retry-After instead of letting
// requests wait. Over real sockets.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('no limits by default', () {
    const defaults = ServerProperties();
    expect(defaults.maxConnections, isNull);
    expect(defaults.maxConcurrentRequests, isNull);
    expect(defaults.retryAfter, const Duration(seconds: 1));
    final bound = ServerProperties.from(
      ServerSettings()
        ..maxConnections = 0
        ..maxConcurrentRequests = -1
        ..retryAfter = const Duration(seconds: 5),
    );
    expect(bound.maxConnections, isNull, reason: '0 or less: no limit');
    expect(bound.maxConcurrentRequests, isNull);
    expect(bound.retryAfter, const Duration(seconds: 5));
  });

  test('past max-concurrent-requests: 503 at once, then room again', () async {
    await webRunner([
      'server.max-concurrent-requests=2',
      'server.retry-after=3s',
    ]).runAsync((context) async {
      final client = await Client.of(context.context);
      addTearDown(client.close);
      final server =
          context.getBean<WebServerStartStopLifecycle>().webServer!
              as WebServerActivity;
      final watch = Stopwatch()..start();
      final refusedAfter = <Duration>[];
      final replies = await Future.wait([
        for (var i = 0; i < 5; i++)
          client.get('/isolate/slow?ms=400').then((reply) {
            if (reply.status == 503) {
              refusedAfter.add(watch.elapsed);
            }
            return reply;
          }),
      ]);
      expect(replies.where((r) => r.status == 200), hasLength(2));
      final refused = replies.where((r) => r.status == 503).toList();
      expect(refused, hasLength(3));
      // Refused while the two were still being answered.
      expect(
        refusedAfter,
        everyElement(lessThan(const Duration(milliseconds: 300))),
      );
      expect(refused.first.headers.value('retry-after'), '3');
      // The connection stays for the next try.
      expect(refused.first.headers.value('connection'), isNot('close'));
      expect(
        (refused.first.json! as Map)['detail'],
        contains('most requests at a time (2)'),
      );
      expect(server.refusedCount, 3);
      // The server has room again.
      expect((await client.get('/isolate/name')).status, 200);
      expect(server.refusedCount, 3);
    });
  });

  test('one at a time: requests one after the other all fit', () async {
    await webRunner(['server.max-concurrent-requests=1']).runAsync((
      context,
    ) async {
      final client = await Client.of(context.context);
      addTearDown(client.close);
      for (var i = 0; i < 3; i++) {
        expect((await client.get('/isolate/name')).status, 200);
      }
    });
  });

  test('past max-connections: 503 and the connection closed', () async {
    await webRunner(['server.max-connections=2']).runAsync((context) async {
      final client = await Client.of(context.context);
      addTearDown(client.close);
      expect((await client.get('/isolate/name')).status, 200);
      // Connections that send nothing still take their place.
      final idle = [
        for (var i = 0; i < 3; i++)
          await io.Socket.connect('127.0.0.1', client.port),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final full = await client.get('/isolate/name');
      expect(full.status, 503);
      expect(full.headers.value('retry-after'), '1');
      expect(full.headers.value('connection'), 'close');
      expect(
        (full.json! as Map)['detail'],
        contains('most connections open (2)'),
      );
      for (final socket in idle) {
        socket.destroy();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect((await client.get('/isolate/name')).status, 200);
    });
  });
}
