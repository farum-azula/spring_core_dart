// The largest messages one client reads:
// spring.websocket.client.config.<name>.max-text-message-size and
// max-binary-message-size, asked from the transport per connection.
import 'dart:async';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

import 'chat.dart';
import 'phoenix_support.dart';
import 'support/client_config.dart';

const _config = 'spring.websocket.client.config';

void main() {
  late MockWebSocketTransport sockets;
  late ApplicationContextRunner runner;

  setUp(() {
    sockets = MockWebSocketTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterWebsocketServerAutoConfiguration,
        )
        .withPropertyValues(['chat.url=ws://chat.test/ws'])
        .withBean<WebSocketTransport>(() => sockets);
  });

  WebSocketClientConfig config(Map<String, String> properties, String name) =>
      configOf(
        StandardEnvironment(systemEnvironment: const {})
          ..propertySources.addFirst(
            MapPropertySource('p', {
              for (final MapEntry(:key, :value) in properties.entries)
                'spring.websocket.client.$key': value,
            }),
          ),
        name,
      );

  test('not set: the limits are left to the transport', () async {
    expect(config(const {}, 'chat').maxTextMessageSize, isNull);
    expect(config(const {}, 'chat').maxBinaryMessageSize, isNull);
    // The global limits are the transport bean's, not a client's.
    final global = config(const {'max-text-message-size': '1MB'}, 'chat');
    expect(global.maxTextMessageSize, isNull);

    await runner.runAsync((context) async {
      await context.getBean<ChatSocket>().connect();
      final server = sockets.lastConnection;
      expect(server.maxTextMessageSize, isNull);
      expect(server.maxBinaryMessageSize, isNull);
    });
  });

  test("a client's own limits, then default's, property by "
      'property', () {
    final properties = {
      'config.default.max-text-message-size': '64KB',
      'config.default.max-binary-message-size': '-1',
      'config.feed.max-text-message-size': '1MB',
      'config.Chat.max-binary-message-size': '2KB',
    };
    final feed = config(properties, 'feed');
    expect(feed.maxTextMessageSize?.toBytes(), 1024 * 1024);
    expect(feed.maxBinaryMessageSize?.toBytes(), -1);
    // The name in any case, as for every client setting.
    final chat = config(properties, 'chat');
    expect(chat.maxTextMessageSize?.toBytes(), 64 * 1024);
    expect(chat.maxBinaryMessageSize?.toBytes(), 2 * 1024);
    final other = config(properties, 'other');
    expect(other.maxTextMessageSize?.toBytes(), 64 * 1024);
    expect(other.maxBinaryMessageSize?.toBytes(), -1);
  });

  test('every connection of the client asks the transport for its '
      'limits, the reconnections too', () async {
    await runner
        .withPropertyValues([
          '$_config.chat.max-text-message-size=1MB',
          '$_config.chat.reconnect.delay=5ms',
        ])
        .runAsync((context) async {
          final received = <String>[];
          context.getBean<ChatSocket>().raw().listen(received.add);
          final first = await sockets.nextConnection;
          expect(first.maxTextMessageSize, 1024 * 1024);
          expect(first.maxBinaryMessageSize, isNull);
          // Over the 8 KB of the application, under the client's 1 MB.
          final large = 'a' * 100000;
          first.push(large);
          await pump();
          expect(received, [large]);

          await first.drop();
          final second = await sockets.nextConnection;
          expect(second.maxTextMessageSize, 1024 * 1024);
        });
  });

  test('a message over the limit of the client closes its connection '
      'with 1009, and its streams end with an error', () async {
    await runner
        .withPropertyValues(['$_config.chat.max-text-message-size=16B'])
        .runAsync((context) async {
          final received = <String>[];
          final errors = <Object>[];
          final done = Completer<void>();
          context.getBean<ChatSocket>().raw().listen(
            received.add,
            onError: errors.add,
            onDone: done.complete,
          );
          final server = await sockets.nextConnection;
          server
            ..push('fits')
            ..push('a' * 17);
          await done.future;
          expect(received, ['fits']);
          expect(server.closeStatus?.code, 1009);
          expect(errors.single, isA<WebSocketException>());
          expect('${errors.single}', contains('1009'));
        });
  });

  test('a Phoenix socket reads up to the limits of its client', () async {
    final socket = PhoenixSocket(
      name: 'feed',
      url: Uri.parse('ws://feed.test/socket/websocket'),
      transport: sockets,
      config: WebSocketClientConfig(
        maxTextMessageSize: DataSize.ofMegabytes(1),
        maxBinaryMessageSize: const DataSize.ofBytes(-1),
        phoenix: const PhoenixSocketConfig(heartbeatInterval: Duration.zero),
      ),
    );
    addTearDown(socket.dispose);
    final lobby = socket.channel('lobby');
    final payloads = <Object?>[];
    lobby.on('snapshot').listen(payloads.add);
    final joined = lobby.join();
    final server = await PhoenixServer.next(sockets);
    expect(server.socket.maxTextMessageSize, 1024 * 1024);
    expect(server.socket.maxBinaryMessageSize, -1);
    await server.acceptJoin();
    await joined;
    final large = 'a' * 100000;
    server.send('lobby', 'snapshot', {'rows': large});
    await pump();
    expect(payloads, [
      {'rows': large},
    ]);
  });

  test('a @PhoenixChannel takes the limits of its client name', () {
    final sized = config(const {
      'config.chat.max-text-message-size': '1MB',
    }, 'chat');
    final factory = PhoenixSocketFactory(
      environment: StandardEnvironment(systemEnvironment: const {}),
      properties: WebSocketProperties()
        ..config = {
          'chat': WebSocketClientSettings()
            ..maxTextMessageSize = sized.maxTextMessageSize,
        },
      transport: sockets,
    );
    final socket = factory.socket(
      'chat',
      url: Uri.parse('ws://chat.test/socket/websocket'),
    );
    expect(socket.config.maxTextMessageSize?.toBytes(), 1024 * 1024);
    expect(socket.config.maxBinaryMessageSize, isNull);
  });
}
