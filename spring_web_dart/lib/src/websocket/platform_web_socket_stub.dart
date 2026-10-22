import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// No transport on platforms without `dart:io` or `dart:js_interop`.
WebSocketTransport createWebSocketTransport() => throw UnsupportedError(
  'No WebSocket transport for this platform; pass your own WebSocketTransport',
);
