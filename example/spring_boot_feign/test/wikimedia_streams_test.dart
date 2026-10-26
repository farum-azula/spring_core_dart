// The server-sent events client against MockHttpTransport.
import 'package:spring_boot_feign_example/src/models.dart';
import 'package:spring_boot_feign_example/src/wikimedia_client.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/app.dart';
import 'support/fixtures.dart' as fixtures;

const _path = '/v2/stream/recentchange';

List<ServerSentEvent<Object?>> _events(Iterable<int> numbers) => [
  for (final n in numbers)
    ServerSentEvent(fixtures.recentChange(n), id: '$n', event: 'message'),
];

void main() {
  late MockHttpTransport server;

  setUp(() => server = MockHttpTransport());

  Future<void> withStreams(
    Future<void> Function(WikimediaStreams streams) body,
  ) => appContext()
      .withBean<HttpTransport>(() => server)
      .withPropertyValues([
        'spring.cloud.openfeign.client.config.wikimedia.event-stream.reconnect-delay=1ms',
      ])
      .runAsync((context) => body(context.getBean<WikimediaStreams>()));

  test(
    'events become RecentChange objects (unknown JSON fields ignored)',
    () async {
      server
        ..when(HttpMethod.get, _path).respondEvents(_events([1, 2, 3]))
        ..when(HttpMethod.get, _path).respond(204); // no more
      await withStreams((streams) async {
        final changes = await streams.recentChanges().toList();
        expect(changes, isA<List<RecentChange>>());
        expect(
          [for (final c in changes) c.title],
          ['Page 1', 'Page 2', 'Page 3'],
        );
        expect([for (final c in changes) c.type], ['new', 'edit', 'new']);
        expect(changes.last.bot, isTrue);
        expect(changes.first.wiki, 'enwiki');
      });
      final request = server.requests.first;
      expect(
        '${request.url}',
        'https://stream.wikimedia.org/v2/stream/recentchange',
      );
      expect(
        request.headers[HttpHeaders.acceptHeader],
        MediaType.textEventStream,
      );
      // From wikimedia.user-agent in application.properties.
      expect(
        request.headers['User-Agent'],
        'spring-boot-feign-example/0.1 '
        '(https://github.com/farum-azula/spring_core_dart)',
      );
    },
  );

  test('a lost connection is opened again with Last-Event-ID', () async {
    server
      ..when(HttpMethod.get, _path).respondEvents(_events([1, 2]))
      ..when(HttpMethod.get, _path).respondEvents(_events([3]))
      ..when(HttpMethod.get, _path).respond(204);
    await withStreams((streams) async {
      final titles = await streams.recentChanges().map((c) => c.title).toList();
      expect(titles, ['Page 1', 'Page 2', 'Page 3']);
    });
    expect(
      [for (final r in server.requests) r.headers['Last-Event-ID']],
      [null, '2', '3'],
    );
  });

  test('.events adds the id and the event name', () async {
    server
      ..when(HttpMethod.get, _path).respondEvents(_events([7]))
      ..when(HttpMethod.get, _path).respond(204);
    await withStreams((streams) async {
      final event = await streams.recentChanges().events.first;
      expect(event.id, '7');
      expect(event.event, 'message');
      expect(event.data.title, 'Page 7');
    });
  });

  test('an error status ends the stream with a FeignException', () async {
    server.when(HttpMethod.get, _path).respond(503, body: 'busy');
    await withStreams(
      (streams) => expectLater(
        streams.recentChanges().toList(),
        throwsA(isA<FeignException>().having((e) => e.status, 'status', 503)),
      ),
    );
  });
}
