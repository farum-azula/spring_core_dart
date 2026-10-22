import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// A [WebSocketTransport] on the browser's `WebSocket` (Flutter web, Dart
/// on the web), through `dart:js_interop`. Browsers send no custom
/// headers with the handshake, so a non-empty `headers` fails: put a
/// token in the URL or a protocol.
///
/// ```dart
/// import 'package:spring_web_dart/browser.dart';
///
/// final transport = BrowserWebSocketTransport();
/// final socket = await transport.connect(Uri.parse('wss://chat.neon.books/ws?token=$token'));
/// ```
///
/// Spring (Java): no browser in Java; on the browser side Spring
/// applications use JavaScript (`WebSocket`, SockJS, STOMP.js).
class BrowserWebSocketTransport implements WebSocketTransport {
  /// A transport on `WebSocket`.
  BrowserWebSocketTransport();

  @override
  Future<WebSocketConnection> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
  }) async {
    if (headers != null && !headers.isEmpty) {
      throw WebSocketException(
        'browsers cannot send headers (${headers.names.join(', ')}) with a '
        'WebSocket handshake: pass them as query parameters or a protocol',
        url: url,
      );
    }
    final _WebSocket socket;
    try {
      socket = _WebSocket(
        url.toString().toJS,
        [for (final protocol in protocols) protocol.toJS].toJS,
      )..binaryType = 'arraybuffer'.toJS;
    } catch (error) {
      throw WebSocketException(
        'cannot connect: $error',
        url: url,
        cause: error,
      );
    }
    final connection = _BrowserConnection(socket, url);
    final opened = connection._opened.future;
    try {
      if (timeout == null) {
        await opened;
      } else {
        await opened.timeout(timeout);
      }
      return connection;
    } on TimeoutException catch (error) {
      socket.close();
      throw WebSocketException(
        'no handshake within ${timeout!.inMilliseconds} ms',
        url: url,
        cause: error,
        isTimeout: true,
      );
    }
  }
}

final class _BrowserConnection implements WebSocketConnection {
  _BrowserConnection(this._socket, this._url) {
    _socket
      ..addEventListener(
        'open'.toJS,
        ((JSAny? _) {
          if (!_opened.isCompleted) {
            _opened.complete();
          }
        }).toJS,
      )
      ..addEventListener(
        'message'.toJS,
        ((_MessageEvent event) {
          final data = event.data;
          if (data.isA<JSString>()) {
            _messages.add((data as JSString).toDart);
          } else if (data.isA<JSArrayBuffer>()) {
            _messages.add((data as JSArrayBuffer).toDart.asUint8List());
          }
        }).toJS,
      )
      ..addEventListener(
        'error'.toJS,
        ((JSAny? _) {
          if (!_opened.isCompleted) {
            _opened.completeError(
              WebSocketException('cannot connect', url: _url),
            );
          }
        }).toJS,
      )
      ..addEventListener(
        'close'.toJS,
        ((_CloseEvent event) {
          _closeCode = event.code;
          _closeReason = event.reason.toDart;
          if (!_opened.isCompleted) {
            _opened.completeError(
              WebSocketException(
                'cannot connect (close code ${event.code})',
                url: _url,
              ),
            );
          }
          if (!_closed.isCompleted) {
            _closed.complete();
          }
          unawaited(_messages.close());
        }).toJS,
      );
  }

  final _WebSocket _socket;
  final Uri _url;
  final _opened = Completer<void>();
  final _closed = Completer<void>();
  final _messages = StreamController<Object>();
  int? _closeCode;
  String? _closeReason;

  @override
  Stream<Object> get messages => _messages.stream;

  @override
  String? get protocol {
    final value = _socket.protocol.toDart;
    return value.isEmpty ? null : value;
  }

  @override
  void send(Object message) {
    if (_socket.readyState != 1) {
      throw WebSocketException('the connection is closed', url: _url);
    }
    switch (message) {
      case String():
        _socket.send(message.toJS);
      case List<int>():
        final bytes = message is Uint8List
            ? message
            : Uint8List.fromList(message);
        _socket.send(bytes.toJS);
      default:
        throw ArgumentError.value(
          message,
          'message',
          'a String or a List<int>',
        );
    }
  }

  @override
  Future<void> close([int? code, String? reason]) {
    if (code == null) {
      _socket.close();
    } else if (reason == null) {
      _socket.close(code);
    } else {
      _socket.close(code, reason.toJS);
    }
    return _closed.future;
  }

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;
}

@JS('WebSocket')
extension type _WebSocket._(JSObject _) implements JSObject {
  external factory _WebSocket(JSString url, JSArray<JSString> protocols);
  external set binaryType(JSString value);
  external int get readyState;
  external JSString get protocol;
  external void send(JSAny data);
  external void close([int code, JSString reason]);
  external void addEventListener(JSString type, JSFunction listener);
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny get data;
}

extension type _CloseEvent._(JSObject _) implements JSObject {
  external int get code;
  external JSString get reason;
}
