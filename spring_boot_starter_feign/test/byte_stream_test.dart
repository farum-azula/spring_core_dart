@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/io.dart';
import 'package:test/test.dart';

// A client with streamed answers as an application writes it, with the
// code the generator writes for it (see catalog.dart).
@FeignClient('files', url: r'${files.url}')
abstract interface class FilesClient {
  @GetMapping('/{name}')
  Stream<List<int>> download(@PathVariable() String name);

  @GetMapping('/{name}')
  EventStream<String> events(@PathVariable() String name);
}

class FilesClientImpl implements FilesClient {
  FilesClientImpl(this._handler, this._metadata);

  static FilesClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<FilesClient>(
      typeName: 'FilesClient',
      annotations: const [FeignClient('files', url: r'${files.url}')],
      methods: [
        ProxyMethod(
          'download',
          parameters: const [
            BeanParameter(
              'name',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          returnType: const GenericType<Stream<List<int>>>([
            ListType<int>(ClassType<int>()),
          ]),
          annotations: const [GetMapping('/{name}')],
          call: (target, arguments) =>
              (target as FilesClient).download(arguments[0]! as String),
        ),
        ProxyMethod(
          'events',
          parameters: const [
            BeanParameter(
              'name',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          returnType: const GenericType<EventStream<String>>([
            ClassType<String>(),
          ]),
          annotations: const [GetMapping('/{name}')],
          call: (target, arguments) =>
              (target as FilesClient).events(arguments[0]! as String),
        ),
      ],
    );
    return FilesClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<FilesClient> _metadata;

  @override
  Stream<List<int>> download(String name) =>
      _handler.invoke(_metadata.methods[0], [name])! as Stream<List<int>>;

  @override
  EventStream<String> events(String name) =>
      _handler.invoke(_metadata.methods[1], [name])! as EventStream<String>;
}

final filesModule = BeanModule('files', [
  BeanDefinition<FilesClient>(
    name: 'filesClient',
    primary: true,
    create: FilesClientImpl.$create,
  ),
]);

/// One connection a client opened to the [_Server].
final class _Connection {
  /// Completes when the request line and the headers have arrived.
  final requested = Completer<String>();

  /// Completes when the client closes (or resets) the connection.
  final closed = Completer<void>();
}

/// A server on a plain socket, so that a test sees exactly when a client
/// closes its connection, also before any answer was written:
///
/// - `/slow` never answers;
/// - `/drip` sends its headers and a first chunk (`one`), then waits;
/// - `/whole` answers `hello world`;
/// - `/missing` answers 404 with `nope`.
final class _Server {
  _Server._(this._socket) {
    _socket.listen(_accept);
  }

  static Future<_Server> start() async =>
      _Server._(await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0));

  final io.ServerSocket _socket;
  final _sockets = <io.Socket>[];
  final connections = <_Connection>[];
  final _opened = StreamController<_Connection>.broadcast();

  String get url => 'http://127.0.0.1:${_socket.port}';

  /// The next connection a client opens.
  Future<_Connection> get next => _opened.stream.first;

  void _accept(io.Socket socket) {
    final connection = _Connection();
    _sockets.add(socket);
    connections.add(connection);
    _opened.add(connection);
    final received = StringBuffer();
    void close() {
      if (!connection.closed.isCompleted) {
        connection.closed.complete();
      }
      socket.destroy();
    }

    socket.listen(
      (bytes) {
        received.write(latin1.decode(bytes));
        final text = received.toString();
        if (connection.requested.isCompleted || !text.contains('\r\n\r\n')) {
          return;
        }
        final path = text.split(' ')[1];
        connection.requested.complete(path);
        switch (path) {
          case '/drip':
            socket.write(
              'HTTP/1.1 200 OK\r\n'
              'content-type: application/octet-stream\r\n'
              'transfer-encoding: chunked\r\n\r\n'
              '3\r\none\r\n',
            );
          case '/whole':
            socket.write(
              'HTTP/1.1 200 OK\r\n'
              'content-type: application/octet-stream\r\n'
              'content-length: 11\r\n\r\n'
              'hello world',
            );
          case '/missing':
            socket.write(
              'HTTP/1.1 404 Not Found\r\n'
              'content-type: text/plain\r\n'
              'content-length: 4\r\n\r\n'
              'nope',
            );
        }
      },
      onError: (Object _) => close(),
      onDone: close,
    );
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _socket.close();
    await _opened.close();
  }
}

final class _SlowInterceptor implements RequestInterceptor {
  @override
  FutureOr<void> apply(RequestTemplate template) =>
      Future<void>.delayed(const Duration(milliseconds: 200));
}

const _second = Duration(seconds: 1);

void main() {
  late _Server server;
  late IoHttpTransport transport;

  ApplicationContextRunner runner([String? url]) =>
      const ApplicationContextRunner()
          .withUserConfiguration(filesModule)
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
          .withPropertyValues(['files.url=${url ?? server.url}'])
          .withBean<HttpTransport>(() => transport);

  setUp(() async {
    server = await _Server.start();
    transport = IoHttpTransport();
  });

  tearDown(() async {
    transport.close();
    await server.stop();
  });

  test('a body read to its end', () async {
    await runner().runAsync((context) async {
      final chunks = await context
          .getBean<FilesClient>()
          .download('whole')
          .toList();
      expect(
        utf8.decode([for (final chunk in chunks) ...chunk]),
        'hello world',
      );
    });
  });

  test('a failed status and a failed connection are stream errors', () async {
    await runner().runAsync((context) async {
      await expectLater(
        context.getBean<FilesClient>().download('missing'),
        emitsInOrder([
          emitsError(
            isA<FeignException>().having((e) => e.status, 'status', 404),
          ),
          emitsDone,
        ]),
      );
    });
    final closed = await io.ServerSocket.bind(
      io.InternetAddress.loopbackIPv4,
      0,
    );
    final port = closed.port;
    await closed.close();
    await runner('http://127.0.0.1:$port').runAsync((context) async {
      await expectLater(
        context.getBean<FilesClient>().download('whole'),
        emitsInOrder([emitsError(isA<RetryableException>()), emitsDone]),
      );
    });
  });

  test('cancelled while waiting for the headers: the connection closes and '
      'cancel() completes', () async {
    await runner().runAsync((context) async {
      final opened = server.next;
      final errors = <Object>[];
      final subscription = context
          .getBean<FilesClient>()
          .download('slow')
          .listen((_) {}, onError: errors.add);
      final connection = await opened.timeout(_second);
      expect(await connection.requested.future.timeout(_second), '/slow');
      await subscription.cancel().timeout(_second);
      await connection.closed.future.timeout(_second);
      expect(errors, isEmpty);
    });
  });

  test('cancelled in the middle of the body: the connection closes and '
      'cancel() completes', () async {
    await runner().runAsync((context) async {
      final opened = server.next;
      final first = Completer<List<int>>();
      final subscription = context
          .getBean<FilesClient>()
          .download('drip')
          .listen(first.complete);
      final connection = await opened.timeout(_second);
      expect(utf8.decode(await first.future.timeout(_second)), 'one');
      expect(connection.closed.isCompleted, isFalse);
      await subscription.cancel().timeout(_second);
      await connection.closed.future.timeout(_second);
    });
  });

  test('cancelled before the request is sent: nothing is sent', () async {
    await runner().withBean<RequestInterceptor>(_SlowInterceptor.new).runAsync((
      context,
    ) async {
      final subscription = context
          .getBean<FilesClient>()
          .download('slow')
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel().timeout(_second);
      // Long after the interceptor has finished.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.connections, isEmpty);
    });
  });

  test('timeout() on a server that does not answer leaves no connection '
      'open', () async {
    await runner().runAsync((context) async {
      final opened = server.next;
      final bytes = context.getBean<FilesClient>().download('slow');
      await expectLater(
        bytes.timeout(const Duration(milliseconds: 200)).first,
        throwsA(isA<TimeoutException>()),
      );
      final connection = await opened.timeout(_second);
      await connection.closed.future.timeout(_second);
    });
  });

  test('first leaves no connection open', () async {
    await runner().runAsync((context) async {
      final opened = server.next;
      final first = await context.getBean<FilesClient>().download('drip').first;
      expect(utf8.decode(first), 'one');
      final connection = await opened.timeout(_second);
      await connection.closed.future.timeout(_second);
    });
  });

  test('an event stream cancelled while waiting for the headers closes its '
      'connection', () async {
    await runner().runAsync((context) async {
      final opened = server.next;
      final subscription = context
          .getBean<FilesClient>()
          .events('slow')
          .listen((_) {});
      final connection = await opened.timeout(_second);
      await connection.requested.future.timeout(_second);
      await subscription.cancel().timeout(_second);
      await connection.closed.future.timeout(_second);
      // And it does not connect again.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.connections, hasLength(1));
    });
  });
}
