import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// Stands in for `platformWebSocketTransport` on a platform with neither
/// `dart:io` nor `dart:js_interop`: always throws an [UnsupportedError],
/// since there is no WebSocket client to build on. Pass your own
/// transport there.
WebSocketTransport createWebSocketTransport({
  int? maxTextMessageSize,
  int? maxBinaryMessageSize,
}) => throw UnsupportedError(
  'No WebSocket transport for this platform; pass your own WebSocketTransport',
);
