// Regression tests of the review before 0.5.0 over real sockets: what
// MockMvc cannot show (a body sent in pieces, a client that aborts or reads
// nothing, the server's own answers, compression, WebSocket frames, a port
// in use, the shutdown).
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_web/src/multipart_store_io.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_web_dart/io.dart' show webSocketAccept;
import 'package:test/test.dart';

import 'app/app.dart';
import 'support.dart';

/// Sends [head] (and [body]) on a raw socket and returns what comes back
/// until the server closes the connection or [timeout] passes.
Future<String> raw(
  int port,
  String head, {
  List<int>? body,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final socket = await io.Socket.connect('127.0.0.1', port);
  socket.add(latin1.encode(head));
  if (body != null) {
    socket.add(body);
  }
  unawaited(socket.flush().catchError((Object _) {}));
  final out = BytesBuilder();
  final done = Completer<void>();
  socket.listen(
    out.add,
    onError: (Object _) => done.isCompleted ? null : done.complete(),
    onDone: () => done.isCompleted ? null : done.complete(),
  );
  await done.future.timeout(timeout, onTimeout: () {});
  socket.destroy();
  return latin1.decode(out.takeBytes());
}

int statusOf(String response) =>
    int.parse(response.split('\r\n').first.split(' ')[1]);

Map<String, Object?> problemOf(String response) =>
    jsonDecode(response.substring(response.indexOf('\r\n\r\n') + 4))
        as Map<String, Object?>;

Future<IoWebServer> serve(
  FutureOr<void> Function(ServerHttpRequest, ServerHttpResponse) handle, [
  ServerProperties settings = const ServerProperties(),
]) async {
  final server = IoWebServer(
    FunctionHttpHandler(
      (request, response) async => await handle(request, response),
    ),
    settings.copyWith(port: 0, address: '127.0.0.1'),
  );
  await server.start();
  return server;
}

/// The regular files below [directory], recursively.
List<io.File> filesIn(io.Directory directory) => [
  for (final entity in directory.listSync(recursive: true))
    if (entity is io.File) entity,
];

Future<void> until(bool Function() condition, {int seconds = 10}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > Duration(seconds: seconds)) {
      fail('timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('the server answers before the handler, with problems', () {
    late IoWebServer server;
    var handled = 0;

    setUp(() async {
      handled = 0;
      server = await serve((request, response) {
        handled++;
        return response.send(200, 'handled ${request.path}');
      });
    });

    tearDown(() => server.stop());

    test(r'an encoded "/", "\" or NUL in the path is a 400', () async {
      for (final path in [
        '/covers/..%2F..%2Fsecret.png',
        '/covers/..%2f..%2fsecret.png',
        '/covers/..%5C..%5Csecret.png',
        '/covers/a%00.png',
      ]) {
        final response = await raw(
          server.port,
          'GET $path HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
        );
        expect(statusOf(response), 400, reason: path);
        expect(response, contains('application/problem+json'));
        expect(problemOf(response)['status'], 400);
      }
      expect(handled, 0);
      final ok = await raw(
        server.port,
        'GET /covers/a%20b.png HTTP/1.1\r\nHost: localhost\r\n'
        'Connection: close\r\n\r\n',
      );
      expect(statusOf(ok), 200);
    });

    test('a malformed Host header is a 400, not a 500', () async {
      for (final host in ['a b', '[::1', 'evil.example/path', 'a@b']) {
        final response = await raw(
          server.port,
          'GET / HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
        );
        expect(statusOf(response), 400, reason: host);
        expect(problemOf(response)['detail'], 'Invalid Host header');
      }
      expect(handled, 0);
      for (final host in ['localhost:8080', '127.0.0.1', '[::1]:80', 'a.b']) {
        final response = await raw(
          server.port,
          'GET / HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
        );
        expect(statusOf(response), 200, reason: host);
      }
    });

    test('an unknown method is a 501 problem', () async {
      final response = await raw(
        server.port,
        'BREW / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
      );
      expect(statusOf(response), 501);
      expect(problemOf(response)['status'], 501);
    });
  });

  test('a header dart:io cannot send is a 500 problem, not an empty '
      '200', () async {
    final server = await serve((request, response) {
      response.headers.set('X-Name', 'café');
      return response.send(200, 'never sent');
    });
    try {
      final response = await raw(
        server.port,
        'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
      );
      expect(statusOf(response), 500);
      expect(response.toLowerCase(), isNot(contains('x-name')));
      expect(problemOf(response)['status'], 500);
    } finally {
      await server.stop();
    }
  });

  group('compression (server.compression.*)', () {
    late IoWebServer server;
    final big = jsonEncode([for (var i = 0; i < 400; i++) 'book $i']);

    setUp(() async {
      server = await serve(
        (request, response) async {
          switch (request.path) {
            case '/big':
              await response.send(200, big, contentType: 'application/json');
            case '/small':
              await response.send(200, '[1]', contentType: 'application/json');
            case '/png':
              await response.send(200, big, contentType: 'image/png');
            case '/vary-own':
              response.headers.add('Vary', 'accept-encoding, Origin');
              await response.send(200, big, contentType: 'application/json');
            case '/vary-any':
              response.headers.add('Vary', '*');
              await response.send(200, big, contentType: 'application/json');
            case '/stream':
              response.headers.contentType = 'text/plain';
              await response.addStream(
                Stream.fromIterable([
                  for (var i = 0; i < 50; i++) utf8.encode('line $i\n' * 20),
                ]),
              );
              await response.close();
            case '/events':
              response.headers.contentType = 'text/event-stream';
              response.write('data: first\n\n');
              await response.flush();
              await Future<void>.delayed(const Duration(seconds: 30));
              await response.close();
          }
        },
        const ServerProperties(
          compression: true,
          compressionMimeTypes: [
            ...ServerProperties.defaultCompressionMimeTypes,
            'text/event-stream',
          ],
        ),
      );
    });

    tearDown(() => server.stop(timeout: Duration.zero));

    Future<io.HttpClientResponse> get(String path, {bool gzip = true}) async {
      final client = io.HttpClient()..autoUncompress = false;
      addTearDown(() => client.close(force: true));
      final request = await client.get('127.0.0.1', server.port, path);
      request.headers.set('Accept-Encoding', gzip ? 'gzip, deflate' : 'br');
      return await request.close();
    }

    test('JSON from min-response-size on is gzipped', () async {
      final response = await get('/big');
      expect(response.headers.value('content-encoding'), 'gzip');
      expect(response.headers.value('vary'), contains('Accept-Encoding'));
      final bytes = await response.expand((c) => c).toList();
      expect(bytes.length, lessThan(big.length));
      expect(utf8.decode(io.gzip.decode(bytes)), big);
    });

    test('Vary is merged: Accept-Encoding once, nothing after *', () async {
      for (final (path, vary) in [
        ('/big', ['Accept-Encoding']),
        ('/vary-own', ['accept-encoding, Origin']),
        ('/vary-any', ['*']),
      ]) {
        final response = await get(path);
        expect(response.headers.value('content-encoding'), 'gzip');
        expect(response.headers['vary'], vary, reason: path);
        await response.drain<void>();
      }
    });

    test(
      'small bodies, other types and clients without gzip are not',
      () async {
        for (final (path, gzip) in [
          ('/small', true),
          ('/png', true),
          ('/big', false),
        ]) {
          final response = await get(path, gzip: gzip);
          expect(response.headers.value('content-encoding'), isNull);
          await response.drain<void>();
        }
      },
    );

    test('a streamed body and a flushed event stream are gzipped', () async {
      var response = await get('/stream');
      expect(response.headers.value('content-encoding'), 'gzip');
      final text = utf8.decode(
        io.gzip.decode(await response.expand((c) => c).toList()),
      );
      expect(text, startsWith('line 0\n'));
      expect(text, endsWith('line 49\n'));
      // The first event can be read while the stream is still open: flush
      // writes what is compressed so far.
      response = await get('/events');
      expect(response.headers.value('content-encoding'), 'gzip');
      final first = await response
          .cast<List<int>>()
          .transform(io.gzip.decoder)
          .transform(utf8.decoder)
          .firstWhere((chunk) => chunk.contains('first'))
          .timeout(const Duration(seconds: 5));
      expect(first, contains('data: first'));
    });
  });

  group('WebSocket messages', () {
    late IoWebServer server;
    late List<Object> received;

    setUp(() async {
      received = [];
      server = await serve((request, response) async {
        final session = await request.upgradeToWebSocket();
        session.messages.listen((message) {
          received.add(message);
          session.sendMessage(message);
        }, onError: (Object _) {});
      });
    });

    tearDown(() => server.stop(timeout: Duration.zero));

    Future<io.WebSocket> connect() =>
        io.WebSocket.connect('ws://127.0.0.1:${server.port}/ws');

    test('within the limit, messages pass both ways', () async {
      final socket = await connect();
      socket.add('x' * 8192);
      expect(await socket.first, 'x' * 8192);
      await socket.close();
    });

    test('a text or binary message over 8 KB closes the session with '
        '1009', () async {
      for (final message in <Object>['x' * 8193, Uint8List(8193)]) {
        final socket = await connect();
        socket.add(message);
        await socket.drain<void>().timeout(const Duration(seconds: 10));
        expect(socket.closeCode, io.WebSocketStatus.messageTooBig);
      }
      expect(received, isEmpty);
    });

    test('a message in small frames is counted whole; no permessage-deflate '
        'is negotiated', () async {
      final socket = await io.Socket.connect('127.0.0.1', server.port);
      final key = base64.encode(List.generate(16, (i) => i));
      socket.add(
        latin1.encode(
          'GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n'
          'Connection: Upgrade\r\nSec-WebSocket-Key: $key\r\n'
          'Sec-WebSocket-Version: 13\r\n'
          'Sec-WebSocket-Extensions: permessage-deflate; '
          'client_max_window_bits\r\n\r\n',
        ),
      );
      final incoming = StreamIterator(socket);
      final buffer = BytesBuilder();
      while (!latin1.decode(buffer.toBytes()).contains('\r\n\r\n')) {
        expect(await incoming.moveNext(), isTrue);
        buffer.add(incoming.current);
      }
      final handshake = latin1.decode(buffer.takeBytes());
      expect(handshake, startsWith('HTTP/1.1 101'));
      expect(
        handshake,
        contains('sec-websocket-accept: ${webSocketAccept(key)}'),
      );
      expect(
        handshake.toLowerCase(),
        isNot(contains('sec-websocket-extensions')),
      );
      // Three masked frames of 4000 bytes: one 12000-byte text message.
      List<int> frame(int opcode, int length, {required bool fin}) => [
        (fin ? 0x80 : 0) | opcode,
        0x80 | 126,
        length >> 8,
        length & 0xFF,
        1, 2, 3, 4, // mask key
        ...List.filled(length, 0x61 ^ 1).indexed.map(
          (e) => 0x61 ^ [1, 2, 3, 4][e.$1 % 4],
        ),
      ];
      socket
        ..add(frame(1, 4000, fin: false))
        ..add(frame(0, 4000, fin: false))
        ..add(frame(0, 4000, fin: true));
      // The server's close frame: opcode 8, code 1009.
      final rest = BytesBuilder();
      while (true) {
        final bytes = rest.toBytes();
        final index = bytes.indexOf(0x88);
        if (index >= 0 && bytes.length >= index + 4) {
          expect((bytes[index + 2] << 8) | bytes[index + 3], 1009);
          break;
        }
        expect(await incoming.moveNext(), isTrue);
        rest.add(incoming.current);
      }
      socket.destroy();
      expect(received, isEmpty);
    });

    test('webSocketAccept follows RFC 6455', () {
      expect(
        webSocketAccept('dGhlIHNhbXBsZSBub25jZQ=='),
        's3pPLMBiTxaQ9kYGzzhZRbK+xOo=',
      );
    });
  });

  group('event streams: back pressure', () {
    test('a client that reads nothing pauses the source', () async {
      var produced = 0;
      final writer = ResponseWriter(mapper: ObjectMapper());
      final server = await serve(
        (request, response) => writer.writeResult(
          Stream<String>.periodic(Duration.zero, (_) {
            produced++;
            return 'x' * 10000;
          }),
          request,
          response,
        ),
      );
      final socket = await io.Socket.connect('127.0.0.1', server.port);
      socket.add(
        latin1.encode('GET /events HTTP/1.1\r\nHost: localhost\r\n\r\n'),
      );
      // The client reads nothing: the kernel buffers fill, then the writes
      // wait, and the source is paused instead of queueing 10 KB events.
      await Future<void>.delayed(const Duration(seconds: 2));
      final whilePaused = produced;
      expect(whilePaused, lessThan(5000));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(produced - whilePaused, lessThan(50));
      socket.destroy();
      await server.stop(timeout: Duration.zero);
    });

    test('an SseEmitter whose sends are not awaited gives up past 1000 '
        'waiting events', () async {
      final emitter = SseEmitter();
      final writer = ResponseWriter(mapper: ObjectMapper());
      final server = await serve(
        (request, response) => writer.writeResult(emitter, request, response),
      );
      final socket = await io.Socket.connect('127.0.0.1', server.port);
      socket.add(
        latin1.encode('GET /events HTTP/1.1\r\nHost: localhost\r\n\r\n'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final errors = <Object>[];
      for (var i = 0; i < 5000 && !emitter.isComplete; i++) {
        unawaited(emitter.send('x' * 10000).catchError(errors.add));
      }
      await until(() => errors.isNotEmpty);
      expect(errors.first, isA<StateError>());
      expect(emitter.isComplete, isTrue);
      socket.destroy();
      await server.stop(timeout: Duration.zero);
    });
  });

  group('uploads over a real socket', () {
    late io.Directory uploads;

    setUp(() {
      uploads = io.Directory.systemTemp.createTempSync('uploads_test_');
    });

    tearDown(() => uploads.deleteSync(recursive: true));

    ApplicationContextRunner runner([List<String> properties = const []]) =>
        webRunner([
          'spring.servlet.multipart.location=${uploads.path}',
          'spring.servlet.multipart.max-file-size=-1',
          'spring.servlet.multipart.max-request-size=64KB',
          ...properties,
        ]);

    String multipartHead(int port, {String length = ''}) =>
        'POST /files/save HTTP/1.1\r\nHost: localhost\r\n'
        'Content-Type: multipart/form-data; boundary=b\r\n'
        '$length\r\n';

    final partStart = latin1.encode(
      '--b\r\nContent-Disposition: form-data; name="file"; '
      'filename="a.bin"\r\nContent-Type: application/octet-stream\r\n\r\n',
    );

    test('the request limit passed inside a file part (chunked): a 413, '
        'nothing left behind', () async {
      await runner().runAsync((context) async {
        final client = await Client.of(context.context);
        // Chunked: no Content-Length the server could refuse up front, so
        // the limit is met in the middle of the file part. The pieces go
        // out one by one until the answer comes, as a browser sends.
        final socket = await io.Socket.connect('127.0.0.1', client.port);
        final answer = BytesBuilder();
        final closed = Completer<void>();
        socket
          ..listen(
            answer.add,
            onError: (Object _) =>
                closed.isCompleted ? null : closed.complete(),
            onDone: () => closed.isCompleted ? null : closed.complete(),
          )
          ..add(
            latin1.encode(
              multipartHead(
                client.port,
                length: 'Transfer-Encoding: chunked\r\n',
              ),
            ),
          )
          ..add(
            latin1.encode('${partStart.length.toRadixString(16)}\r\n'),
          )
          ..add(partStart)
          ..add(latin1.encode('\r\n'));
        final piece = List.filled(8192, 7);
        for (var sent = 0; sent < 1 << 20 && answer.isEmpty; sent += 8192) {
          socket
            ..add(latin1.encode('2000\r\n'))
            ..add(piece)
            ..add(latin1.encode('\r\n'));
          try {
            await socket.flush();
          } on io.SocketException {
            break; // the server answered and closed
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        await closed.future.timeout(const Duration(seconds: 10));
        socket.destroy();
        final response = latin1.decode(answer.takeBytes());
        expect(statusOf(response), 413);
        expect(problemOf(response)['detail'], contains('65536 bytes'));
        await until(() => filesIn(uploads).isEmpty);
        client.close();
      });
    });

    test('a client that aborts in the middle of a file: no hang, no '
        'temporary file, the shutdown is not held up', () async {
      final watch = Stopwatch();
      await runner([
        'spring.servlet.multipart.max-request-size=10MB',
      ]).runAsync((context) async {
        final client = await Client.of(context.context);
        final socket = await io.Socket.connect('127.0.0.1', client.port);
        socket
          ..add(
            latin1.encode(
              multipartHead(client.port, length: 'Content-Length: 5000000\r\n'),
            ),
          )
          ..add(partStart)
          ..add(List.filled(100 * 1024, 7));
        await socket.flush();
        // The file part reaches a temporary file...
        await until(() => filesIn(uploads).isNotEmpty);
        // ...and the client goes away.
        socket.destroy();
        await until(() => filesIn(uploads).isEmpty);
        client.close();
        watch.start();
      }); // closes the context: graceful, 30 s at most
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test(
      'temporary files are in a private directory, with random names',
      () async {
        await runner([
          'spring.servlet.multipart.max-request-size=10MB',
        ]).runAsync((context) async {
          final client = await Client.of(context.context);
          final socket = await io.Socket.connect('127.0.0.1', client.port);
          socket
            ..add(
              latin1.encode(
                multipartHead(
                  client.port,
                  length: 'Content-Length: 5000000\r\n',
                ),
              ),
            )
            ..add(partStart)
            ..add(List.filled(10 * 1024, 7));
          await socket.flush();
          await until(() => filesIn(uploads).isNotEmpty);
          final file = filesIn(uploads).single;
          final directory = file.parent;
          expect(directory.path, isNot(uploads.path));
          if (!io.Platform.isWindows) {
            // rwx------
            expect(directory.statSync().mode & 0x1FF, 0x1C0);
          }
          expect(
            file.uri.pathSegments.last,
            matches(RegExp(r'^upload_[0-9a-f]{32}\.tmp$')),
          );
          socket.destroy();
          await until(() => filesIn(uploads).isEmpty);
          client.close();
        });
      },
    );
  });

  group('server.max-http-request-body-size for every body', () {
    test(
      'a multipart Content-Type read as text keeps the server limit',
      () async {
        await webRunner([
          'server.max-http-request-body-size=1KB',
        ]).runAsync((context) async {
          final client = await Client.of(context.context);
          final reply = await client.send(
            'POST',
            '/plain/text',
            body: 'x' * 5000,
            headers: {'Content-Type': 'multipart/form-data; boundary=b'},
          );
          expect(reply.status, 413);
          client.close();
        });
      },
    );

    test('a body nothing can read is a 415 before it is read', () async {
      await webRunner().runAsync((context) async {
        final client = await Client.of(context.context);
        // 400 MB announced, a few bytes sent: the answer comes at once.
        final response = await raw(
          client.port,
          'POST /api/books HTTP/1.1\r\nHost: localhost\r\n'
          'Content-Type: multipart/form-data; boundary=b\r\n'
          'Content-Length: 400000000\r\n\r\n',
          body: latin1.encode('--b\r\n'),
          timeout: const Duration(seconds: 5),
        );
        expect(statusOf(response), 415);
        client.close();
      });
    });
  });

  test(
    'a header dart:io cannot send, from a controller: a 500 problem',
    () async {
      await webRunner().runAsync((context) async {
        final client = await Client.of(context.context);
        final reply = await client.get('/plain/bad-header');
        expect(reply.status, 500);
        expect(reply.headers.value('x-name'), isNull);
        expect(reply.headers.contentType?.mimeType, 'application/problem+json');
        client.close();
      });
    },
  );

  group('a port in use fails the start (SpringApplication)', () {
    late io.ServerSocket blocker;
    late List<String> events;
    late List<String> out;
    late bool ran;

    setUp(() async {
      blocker = await io.ServerSocket.bind('127.0.0.1', 0);
      events = [];
      out = [];
      ran = false;
    });

    tearDown(() => blocker.close());

    SpringApplication application() => SpringApplication(
      [
        webTestBeans,
        BeanModule('runners', [
          BeanDefinition<ApplicationRunner>(
            name: 'runner',
            types: const [ApplicationRunner],
            create: (_) => _Runner(() => ran = true),
          ),
        ]),
      ],
      autoConfigurations: [
        springBootAutoConfiguration,
        springBootStarterLoggingAutoConfiguration,
        springBootStarterWebAutoConfiguration,
        springBootStarterWebsocketAutoConfiguration,
      ],
      bannerMode: BannerMode.off,
      out: out.add,
      listeners: [
        ApplicationListenerAdapter.of<SpringApplicationEvent>(
          (event) => events.add('${event.runtimeType}'),
        ),
      ],
    );

    Map<String, Object?> properties() => {
      'server.port': '${blocker.port}',
      'server.address': '127.0.0.1',
      'logging.level.root': 'off',
    };

    test('runAsync throws; no ApplicationReadyEvent, no runner', () async {
      await expectLater(
        application().runAsync(
          const [],
          systemEnvironment: const {},
          properties: properties(),
        ),
        throwsA(isA<PortInUseException>()),
      );
      expect(events, contains('ApplicationFailedEvent'));
      expect(events, isNot(contains('ApplicationStartedEvent')));
      expect(events, isNot(contains('ApplicationReadyEvent')));
      expect(ran, isFalse);
      expect(
        out.join('\n'),
        contains('Port ${blocker.port} was already in use'),
      );
    });

    test('run: the failure ends the program (uncaught), the context '
        'closes', () async {
      final uncaught = Completer<Object>();
      late ConfigurableApplicationContext context;
      runZonedGuarded(() {
        context = application().run(
          const [],
          systemEnvironment: const {},
          properties: properties(),
        );
      }, (error, _) => uncaught.complete(error));
      expect(
        await uncaught.future.timeout(const Duration(seconds: 10)),
        isA<PortInUseException>(),
      );
      expect(context.isActive, isFalse);
      expect(events, isNot(contains('ApplicationReadyEvent')));
      expect(ran, isFalse);
    });
  });

  test('spring.lifecycle.timeout-per-shutdown-phase reaches the lifecycle '
      'processor: an 11 s request finishes before the beans are '
      'destroyed', () async {
    final order = <String>[];
    late Future<Reply> slow;
    late Client client;
    await webRunner(['spring.lifecycle.timeout-per-shutdown-phase=30s'])
        .withUserConfiguration(
          BeanModule('slow', [
            BeanDefinition<_SleepMapping>(
              name: 'sleepMapping',
              types: const [_SleepMapping, HandlerMapping],
              create: (_) => _SleepMapping(order),
            ),
            BeanDefinition<_DestroyRecorder>(
              name: 'destroyRecorder',
              types: const [_DestroyRecorder, DisposableBean],
              create: (_) => _DestroyRecorder(order),
            ),
          ]),
        )
        .runAsync((context) async {
          client = await Client.of(context.context);
          slow = client.get('/sleep');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }); // closes the context while the request runs
    expect((await slow).body, 'slept');
    expect(order, ['request done', 'destroyed']);
    client.close();
  }, timeout: const Timeout(Duration(seconds: 60)));

  secondReview();
}

/// The handshake of a raw WebSocket client on [port], at [path]: the
/// socket and its paused subscription (the client reads nothing more).
Future<(io.Socket, StreamSubscription<Uint8List>)> rawWebSocket(
  int port, {
  String path = '/ws',
}) async {
  final socket = await io.Socket.connect('127.0.0.1', port);
  final key = base64.encode(List.generate(16, (i) => i));
  socket.add(
    latin1.encode(
      'GET $path HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n'
      'Connection: Upgrade\r\nSec-WebSocket-Key: $key\r\n'
      'Sec-WebSocket-Version: 13\r\n\r\n',
    ),
  );
  final head = Completer<void>();
  final buffer = BytesBuilder();
  // Returned to the caller, paused; destroying the socket ends it.
  // ignore: cancel_subscriptions
  late final StreamSubscription<Uint8List> subscription;
  subscription = socket.listen(
    (chunk) {
      buffer.add(chunk);
      if (!head.isCompleted &&
          latin1.decode(buffer.toBytes()).contains('\r\n\r\n')) {
        expect(latin1.decode(buffer.toBytes()), startsWith('HTTP/1.1 101'));
        head.complete();
      }
    },
    onError: (Object _) {},
    cancelOnError: false,
  );
  await head.future.timeout(const Duration(seconds: 10));
  subscription.pause();
  return (socket, subscription);
}

/// Regression tests of the second review before 0.5.0.
void secondReview() {
  group('WebSocket: a client that reads nothing', () {
    // The session's close status once its messages end.
    Future<IoWebServer> serveWebSocket(
      Completer<CloseStatus?> closed,
      ServerProperties settings, {
      Future<void> Function(WebSocketSession session)? then,
    }) => serve((request, response) async {
      final session = await request.upgradeToWebSocket();
      session.messages.listen(
        (_) {},
        onError: (Object _) {},
        onDone: () => closed.complete(session.closeStatus),
      );
      await then?.call(session);
    }, settings);

    test('what waits to be sent is bounded: past '
        'server.websocket.send-buffer-size-limit the connection is dropped '
        '(4500)', () async {
      final closed = Completer<CloseStatus?>();
      var sent = 0;
      final server = await serveWebSocket(
        closed,
        const ServerProperties(
          webSocketSendBufferSizeLimit: 64 * 1024,
          webSocketSendTimeLimit: Duration(minutes: 1),
        ),
        then: (session) async {
          final chunk = 'x' * 16384;
          while (session.isOpen && sent < 256 << 20) {
            session.sendMessage(chunk);
            sent += chunk.length;
            await Future<void>.delayed(Duration.zero);
          }
        },
      );
      final (socket, _) = await rawWebSocket(server.port);
      try {
        final status = await closed.future.timeout(
          const Duration(seconds: 20),
        );
        expect(status?.code, 4500);
        expect(status?.reason, contains('Buffer size'));
        // The kernel's buffers and the limit, not everything sent.
        expect(sent, lessThan(64 << 20));
      } finally {
        socket.destroy();
        await server.stop(timeout: Duration.zero);
      }
    });

    test('what was sent and has not left within '
        'server.websocket.send-time-limit drops the connection', () async {
      final closed = Completer<CloseStatus?>();
      final server = await serveWebSocket(
        closed,
        const ServerProperties(
          webSocketSendTimeLimit: Duration(milliseconds: 300),
        ),
        // One message larger than the kernel's buffers.
        then: (session) async => session.sendMessage('x' * (32 << 20)),
      );
      final (socket, _) = await rawWebSocket(server.port);
      try {
        final status = await closed.future.timeout(
          const Duration(seconds: 20),
        );
        expect(status?.code, 4500);
        expect(status?.reason, contains('Send time'));
      } finally {
        socket.destroy();
        await server.stop(timeout: Duration.zero);
      }
    });

    test('pings whose pongs are not read: the pongs wait with the '
        'messages, past the limit the connection is dropped', () async {
      final closed = Completer<CloseStatus?>();
      final server = await serveWebSocket(
        closed,
        const ServerProperties(webSocketSendTimeLimit: Duration(seconds: 1)),
      );
      final (socket, _) = await rawWebSocket(server.port);
      try {
        // Masked pings with 125 bytes of payload, 64 KB at a time.
        final ping = [0x89, 0x80 | 125, 1, 2, 3, 4, ...List.filled(125, 0)];
        final batch = Uint8List.fromList([
          for (var i = 0; i < 65536 ~/ ping.length; i++) ...ping,
        ]);
        var written = 0;
        while (written < 256 << 20) {
          socket.add(batch);
          final flushed = await socket
              .flush()
              .then((_) => true, onError: (Object _) => false)
              .timeout(const Duration(seconds: 3), onTimeout: () => false);
          if (!flushed) {
            break; // the server dropped the connection
          }
          written += batch.length;
        }
        expect(written, lessThan(64 << 20));
        final status = await closed.future.timeout(
          const Duration(seconds: 20),
        );
        expect(status?.code, 4500);
        expect(status?.reason, contains('Buffer size'));
      } finally {
        socket.destroy();
        await server.stop(timeout: Duration.zero);
      }
    });

    test('a client that reads gets a burst of 4 MB, in order', () async {
      final closed = Completer<CloseStatus?>();
      // The client runs on this isolate, so it reads nothing until the
      // whole burst is queued: a limit above the burst.
      final server = await serveWebSocket(
        closed,
        const ServerProperties(webSocketSendBufferSizeLimit: 8 << 20),
        then: (session) async {
          for (var i = 0; i < 256; i++) {
            session.sendMessage('$i'.padRight(16384, '.'));
          }
          await session.close();
        },
      );
      try {
        final client = await io.WebSocket.connect(
          'ws://127.0.0.1:${server.port}/ws',
        );
        final received = await client.cast<String>().toList().timeout(
          const Duration(seconds: 20),
        );
        expect(received, hasLength(256));
        expect(received.last, startsWith('255.'));
        expect((await closed.future)?.code, 1000);
      } finally {
        await server.stop(timeout: Duration.zero);
      }
    });
  });

  group('the server answers before the handler (second review)', () {
    late IoWebServer server;
    var handled = 0;

    setUp(() async {
      handled = 0;
      server = await serve((request, response) {
        handled++;
        return response.send(200, 'handled ${request.path}');
      });
    });

    tearDown(() => server.stop());

    Future<String> get(String target, {String host = 'Host: localhost\r\n'}) =>
        raw(
          server.port,
          'GET $target HTTP/1.1\r\n${host}Connection: close\r\n\r\n',
        );

    test('a %-escape that is malformed or not UTF-8, in the path or the '
        'query, is a 400 problem', () async {
      for (final target in [
        '/%FF',
        '/misc/files/%C0%AF',
        '/books?id=%FF',
        '/books?%FF=1',
      ]) {
        final response = await get(target);
        expect(statusOf(response), 400, reason: target);
        expect(problemOf(response)['status'], 400, reason: target);
      }
      expect(handled, 0);
      expect(statusOf(await get('/caf%C3%A9?q=%C3%A9')), 200);
      // dart:io reads a `%` without two hex digits as a plain `%`
      // (Tomcat: 400); it can never decode to a separator.
      expect(await get('/a%G1'), endsWith('handled /a%25G1'));
    });

    test('a "." or ".." segment behind matrix parameters is a 400', () async {
      for (final target in [
        '/files/..;/secret',
        '/files/..;x=1/secret',
        '/files/%2e%2e;/secret',
        '/files/.;/secret',
      ]) {
        final response = await get(target);
        expect(statusOf(response), 400, reason: target);
        expect(
          problemOf(response)['detail'],
          'The path contains a "." or ".." segment',
        );
      }
      expect(handled, 0);
      expect(statusOf(await get('/books/1;v=1')), 200);
    });

    test("Host: none in HTTP/1.1, or not the absolute target's host, is a "
        '400', () async {
      var response = await get('/', host: '');
      expect(statusOf(response), 400);
      expect(problemOf(response)['detail'], 'The Host header is missing');
      response = await get('http://evil.example/');
      expect(statusOf(response), 400);
      response = await get('http://localhost:8443/');
      expect(statusOf(response), 400);
      expect(handled, 0);
      response = await raw(server.port, 'GET / HTTP/1.0\r\n\r\n');
      expect(statusOf(response), 200);
      response = await get('http://LOCALHOST:80/x');
      expect(statusOf(response), 200);
      expect(response, endsWith('handled /x'));
    });
  });

  test('WebSocket handshakes with a header sent twice or a bad key: 400 or '
      '426 problems, never a 500', () async {
    await webRunner().runAsync((context) async {
      final client = await Client.of(context.context);
      final key = base64.encode(List.generate(16, (i) => i));
      Future<String> handshake(String headers) => raw(
        client.port,
        'GET /ws/echo/ann HTTP/1.1\r\nHost: localhost\r\n'
        'Connection: Upgrade\r\n$headers\r\n',
        timeout: const Duration(seconds: 2),
      );
      const upgrade = 'Upgrade: websocket\r\n';
      const version = 'Sec-WebSocket-Version: 13\r\n';
      for (final (headers, status) in [
        (
          '${upgrade}Sec-WebSocket-Key: $key\r\nSec-WebSocket-Key: $key\r\n'
              '$version',
          400,
        ),
        ('${upgrade}Sec-WebSocket-Key: $key\r\n$version$version', 400),
        ('${upgrade}Sec-WebSocket-Key: abc\r\n$version', 400),
        (
          '${upgrade}Sec-WebSocket-Key: '
              '${base64.encode(List.filled(15, 1))}\r\n$version',
          400,
        ),
        ('$upgrade$version', 400),
        ('${upgrade}Sec-WebSocket-Key: $key\r\n', 426),
        (
          '${upgrade}Sec-WebSocket-Key: $key\r\nSec-WebSocket-Version: 8\r\n',
          426,
        ),
      ]) {
        final response = await handshake(headers);
        expect(statusOf(response), status, reason: headers);
        expect(problemOf(response)['status'], status, reason: headers);
        if (status == 426) {
          expect(response.toLowerCase(), contains('sec-websocket-version: 13'));
        }
      }
      // Upgrade is a list: sent twice, it still names websocket.
      final twice = await handshake(
        '$upgrade${upgrade}Sec-WebSocket-Key: $key\r\n$version',
      );
      expect(twice, startsWith('HTTP/1.1 101'));
      client.close();
    });
  });

  group('the application (second review)', () {
    Future<String> post(int port, String path, String head, String body) => raw(
      port,
      'POST $path HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n'
      '${head}Content-Length: ${utf8.encode(body).length}\r\n\r\n',
      body: utf8.encode(body),
    );

    test('a form field with a bad %-escape is a 400, not a 500', () async {
      await webRunner().runAsync((context) async {
        final client = await Client.of(context.context);
        for (final title in ['%FF', '%G1', '%C0%AF']) {
          final response = await post(
            client.port,
            '/api/books/form',
            'Content-Type: application/x-www-form-urlencoded\r\n',
            'title=$title&count=1',
          );
          expect(statusOf(response), 400, reason: title);
          expect(problemOf(response)['status'], 400);
        }
        client.close();
      });
    });

    test('a JSON body without a Content-Type is a 415 '
        '(application/octet-stream); without a body, a 400', () async {
      await webRunner().runAsync((context) async {
        final client = await Client.of(context.context);
        const book = '{"isbn":"1","title":"T","author":"A"}';
        var response = await post(client.port, '/api/books', '', book);
        expect(statusOf(response), 415);
        expect(
          problemOf(response)['detail'],
          "Content-Type 'application/octet-stream' is not supported.",
        );
        response = await post(client.port, '/api/books', '', '');
        expect(statusOf(response), 400);
        response = await post(
          client.port,
          '/api/books',
          'Content-Type: json\r\n',
          book,
        );
        expect(statusOf(response), 415);
        response = await post(
          client.port,
          '/plain/text',
          'Content-Type: text\r\n',
          'hello',
        );
        expect(statusOf(response), 415);
        // Text and bytes read any body.
        response = await post(client.port, '/plain/text', '', 'hello');
        expect(statusOf(response), 200);
        client.close();
      });
    });

    test('a request body that stalls for server.connection-timeout is a '
        '408; the connection closes', () async {
      await webRunner(['server.connection-timeout=500ms']).runAsync((
        context,
      ) async {
        final client = await Client.of(context.context);
        final watch = Stopwatch()..start();
        final response = await raw(
          client.port,
          'POST /api/books HTTP/1.1\r\nHost: localhost\r\n'
          'Content-Type: application/json\r\nContent-Length: 100\r\n\r\n',
          body: latin1.encode('{"isbn":'),
          timeout: const Duration(seconds: 20),
        );
        expect(statusOf(response), 408);
        expect(problemOf(response)['status'], 408);
        expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
        client.close();
      });
    });

    test('an error after the response was committed drops the connection: '
        'no final chunk', () async {
      await webRunner().runAsync((context) async {
        final dispatcher = context.context.getBean<DispatcherHandler>();
        final failing = DispatcherHandler(
          handlerMappings: dispatcher.handlerMappings,
          requestMapping: dispatcher.requestMapping,
          writer: dispatcher.writer,
          filters: [_FailAfterCommit()],
        );
        final server = await serve(failing.handle);
        try {
          final response = await raw(
            server.port,
            'GET /api/books/1 HTTP/1.1\r\nHost: localhost\r\n\r\n',
          );
          expect(response, startsWith('HTTP/1.1 200'));
          expect(response, isNot(endsWith('0\r\n\r\n')));
          expect(response, isNot(contains('problem')));
        } finally {
          await server.stop();
        }
      });
    });
  });

  test('a handler failing after the response was committed: the connection '
      'is dropped', () async {
    final server = await serve((request, response) async {
      response.headers.contentType = 'text/plain';
      response.write('partial');
      await response.flush();
      throw StateError('late');
    });
    try {
      final response = await raw(
        server.port,
        'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n',
      );
      expect(response, startsWith('HTTP/1.1 200'));
      expect(response, isNot(endsWith('0\r\n\r\n')));
    } finally {
      await server.stop();
    }
  });

  test('a body nobody reads that stalls does not hold the answer; the '
      'connection closes', () async {
    final server = await serve((request, response) => response.send(200, 'ok'));
    try {
      final watch = Stopwatch()..start();
      final response = await raw(
        server.port,
        'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n',
        body: latin1.encode('0123456789'),
        timeout: const Duration(seconds: 20),
      );
      expect(statusOf(response), 200);
      expect(response, endsWith('ok'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    } finally {
      await server.stop();
    }
  });

  test('the private upload directory is made again when the system removed '
      'it', () async {
    final location = io.Directory.systemTemp.createTempSync('uploads_');
    try {
      Future<void> store() async {
        final writer = FileWriter(threshold: 0, location: location.path);
        await writer.add([1, 2, 3]);
        final stored = await writer.close();
        expect(await stored.readBytes(), [1, 2, 3]);
        await stored.delete();
      }

      await store();
      for (final entity in location.listSync()) {
        entity.deleteSync(recursive: true);
      }
      await store();
      expect(location.listSync(), hasLength(1));
    } finally {
      location.deleteSync(recursive: true);
    }
  });
}

final class _FailAfterCommit implements WebFilter {
  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    response.headers.contentType = 'text/plain';
    response.write('partial');
    await response.flush();
    throw StateError('failed after the commit');
  }
}

final class _SleepMapping implements HandlerMapping {
  _SleepMapping(this.order);

  final List<String> order;

  @override
  HttpHandler? getHandler(ServerHttpRequest request) => request.path == '/sleep'
      ? FunctionHttpHandler((request, response) async {
          // Longer than Spring Framework's default of 10 s per phase.
          await Future<void>.delayed(const Duration(seconds: 11));
          order.add('request done');
          await response.send(200, 'slept');
        })
      : null;
}

final class _DestroyRecorder implements DisposableBean {
  _DestroyRecorder(this.order);

  final List<String> order;

  @override
  void destroy() => order.add('destroyed');
}

final class _Runner implements ApplicationRunner {
  _Runner(this.onRun);

  final void Function() onRun;

  @override
  void run(ApplicationArguments args) => onRun();
}
