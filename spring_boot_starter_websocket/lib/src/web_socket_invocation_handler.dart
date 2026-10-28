import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_config.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_connection_manager.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The implementation behind one `@WebSocketClient` interface: the
/// generated class passes every method call here, and this object answers
/// it over the client's [WebSocketConnectionManager].
///
/// `@OnMessage` methods give typed streams of the incoming messages,
/// `@SendMessage` methods send, `connect()` and `close()` open and close.
/// The `WebSocketClientFactory` creates one per client; applications do
/// not use it directly. Every method, and the URL, is checked when the
/// client bean is created, so a method the starter cannot implement or a
/// missing or wrong URL stops the application at startup with the reason.
///
/// Differs from Spring: Spring has no declarative WebSocket client (see
/// `WebSocketClient`).
final class WebSocketInvocationHandler implements InvocationHandler {
  /// The implementation of the interface described by [metadata], marked
  /// with [client]. Throws a [StateError] listing every problem of the
  /// interface: no URL, a URL that does not start with `ws://` or
  /// `wss://`, a method of the wrong shape.
  WebSocketInvocationHandler({
    required InterfaceMetadata<Object> metadata,
    required this.client,
    required this.config,
    required Environment environment,
    required this.mapper,
    required WebSocketTransport transport,
    List<WebSocketHandshakeInterceptor> interceptors = const [],
  }) : typeName = metadata.typeName {
    final problems = <String>[];
    final url = _resolveUrl(environment, problems);
    for (final method in metadata.methods) {
      final plan = _plan(method, problems);
      if (plan != null) {
        _plans[method] = plan;
      }
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Invalid WebSocket client $typeName:\n'
        '${problems.map((p) => '  - $p').join('\n')}',
      );
    }
    connectionManager = WebSocketConnectionManager(
      clientName: client.name,
      url: url!,
      protocols: client.protocols,
      config: config,
      transport: transport,
      interceptors: interceptors,
      log: SpringLog('websocket.$typeName'),
    );
  }

  /// The name of the interface, used in error messages and in the logger
  /// name (`websocket.<typeName>`).
  final String typeName;

  /// The `@WebSocketClient` annotation on the interface.
  final WebSocketClient client;

  /// The client's settings, from `spring.websocket.client.config.*`.
  final WebSocketClientConfig config;

  /// Reads and writes the JSON messages.
  final ObjectMapper mapper;

  /// Keeps the client's one connection, shared by all its methods.
  late final WebSocketConnectionManager connectionManager;

  final _plans = Map<ProxyMethod, Object? Function(List<Object?>)>.identity();

  Uri? _resolveUrl(Environment environment, List<String> problems) {
    final raw = client.url ?? config.url;
    if (raw == null || raw.trim().isEmpty) {
      problems.add(
        'no URL: set @WebSocketClient(url: ...) or '
        'spring.websocket.client.config.${client.name}.url',
      );
      return null;
    }
    final String resolved;
    try {
      resolved = environment.resolveRequiredPlaceholders(raw.trim());
    } on Object catch (error) {
      problems.add('cannot resolve the URL "$raw": $error');
      return null;
    }
    final url = Uri.tryParse(resolved);
    if (url == null || (url.scheme != 'ws' && url.scheme != 'wss')) {
      problems.add('the URL "$resolved" must start with ws:// or wss://');
      return null;
    }
    return url;
  }

  Object? Function(List<Object?>)? _plan(
    ProxyMethod method,
    List<String> problems,
  ) {
    final name = '$typeName.${method.name}';
    final onMessage = method.annotation<OnMessage>() != null;
    final sendMessage = method.annotation<SendMessage>() != null;
    final type = method.returnType;
    if (onMessage && sendMessage) {
      problems.add('$name has both @OnMessage and @SendMessage');
      return null;
    }
    if (onMessage) {
      final isStream =
          !method.isFuture &&
          type is GenericType<Object?> &&
          type.isSubtypeOf<Stream<Object?>>() &&
          type.arguments.length == 1;
      if (!isStream || method.parameters.isNotEmpty) {
        problems.add(
          '$name: an @OnMessage method takes no parameters and returns '
          'Stream<T>',
        );
        return null;
      }
      final stream = type.arguments.single.accept(_Streams(this));
      return (_) => stream();
    }
    if (sendMessage) {
      if (!method.isFuture || !method.isVoid || method.parameters.length != 1) {
        problems.add(
          '$name: a @SendMessage method takes one parameter and returns '
          'Future<void>',
        );
        return null;
      }
      final parameter = method.parameters.single;
      final binaryList = switch (parameter.type) {
        ListType(:final element) => element.type == int,
        _ => false,
      };
      return (arguments) => connectionManager.sendMessage(
        _frame(arguments.single, binaryList: binaryList),
      );
    }
    final lifecycle =
        method.isFuture && method.isVoid && method.parameters.isEmpty;
    if (lifecycle && method.name == 'connect') {
      return (_) => connectionManager.connect();
    }
    if (lifecycle && method.name == 'close') {
      return (_) => connectionManager.close();
    }
    problems.add(
      '$name: mark it @OnMessage (Stream<T> name()) or @SendMessage '
      '(Future<void> name(T message)); only Future<void> connect() and '
      'Future<void> close() need no annotation',
    );
    return null;
  }

  Object _frame(Object? value, {required bool binaryList}) {
    switch (value) {
      case String():
        return value;
      case Uint8List():
        return value;
      case List<int>() when binaryList:
        return value;
    }
    try {
      return mapper.writeValueAsString(value);
    } on Object catch (error) {
      throw MessageConversionException(
        'cannot write the message of $typeName: $error',
        cause: error,
      );
    }
  }

  // The incoming messages as a Stream<T>.
  Stream<T> _messages<T>(TypeInfo<T> type) {
    final raw = type.type;
    return connectionManager.messages().transform(
      StreamTransformer<Object, T>.fromHandlers(
        handleData: (message, sink) {
          if (type is DynamicType) {
            sink.add(message as T);
          } else if (raw == String) {
            if (message is String) {
              sink.add(message as T);
            }
          } else if (raw == Uint8List) {
            if (message is Uint8List) {
              sink.add(message as T);
            }
          } else if (message is String) {
            try {
              sink.add(mapper.treeToValue<T>(jsonDecode(message), type));
            } on Object catch (error, stackTrace) {
              sink.addError(
                MessageConversionException(
                  'cannot read a message of $typeName as $type: $error',
                  message: message,
                  cause: error,
                ),
                stackTrace,
              );
            }
          }
        },
      ),
    );
  }

  @override
  Object? invoke(ProxyMethod method, List<Object?> arguments) =>
      _plans[method]!(arguments);
}

/// Thrown when a WebSocket message cannot be converted to or from the
/// declared type: an incoming text that is not valid JSON for the type of
/// an `@OnMessage` stream, or a value a `@SendMessage` method cannot write
/// as JSON.
///
/// An incoming message that fails arrives as an error event on the
/// stream, and the stream goes on, so one bad message does not stop a
/// client.
///
/// ```dart
/// // Show the good messages, log the bad ones.
/// socket.messages().listen(show, onError: (Object error) {
///   if (error is MessageConversionException) print(error.message);
/// });
/// ```
///
/// Spring (Java):
/// `org.springframework.messaging.converter.MessageConversionException`.
class MessageConversionException implements Exception {
  /// A conversion failure described by [description], with the text
  /// [message] that could not be read and the [cause].
  MessageConversionException(this.description, {this.message, this.cause});

  /// What went wrong, naming the client and the type.
  final String description;

  /// The text message that could not be read; `null` for a message that
  /// could not be written.
  final String? message;

  /// The error of the JSON reader or writer.
  final Object? cause;

  @override
  String toString() => 'MessageConversionException: $description';
}

/// Builds the typed stream of an `@OnMessage` method, with the type
/// argument in scope so the stream has the declared runtime type.
final class _Streams implements TypeInfoVisitor<Stream<Object?> Function()> {
  _Streams(this.handler);

  final WebSocketInvocationHandler handler;

  @override
  Stream<Object?> Function() visitClass<T>(ClassType<T> type) =>
      () => handler._messages<T>(type);

  @override
  Stream<Object?> Function() visitList<E>(ListType<E> type) =>
      () => handler._messages<List<E>>(type);

  @override
  Stream<Object?> Function() visitSet<E>(SetType<E> type) =>
      () => handler._messages<Set<E>>(type);

  @override
  Stream<Object?> Function() visitMap<K, V>(MapType<K, V> type) =>
      () => handler._messages<Map<K, V>>(type);

  @override
  Stream<Object?> Function() visitEnum<E extends Enum>(EnumType<E> type) =>
      () => handler._messages<E>(type);

  @override
  Stream<Object?> Function() visitGeneric<T>(GenericType<T> type) =>
      () => handler._messages<T>(type);

  @override
  Stream<Object?> Function() visitDynamic(DynamicType type) =>
      () => handler._messages<Object?>(type);
}
