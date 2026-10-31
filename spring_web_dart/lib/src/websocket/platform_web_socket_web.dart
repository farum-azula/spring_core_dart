import 'package:spring_web_dart/src/websocket/browser_web_socket_transport.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// Creates the transport for `platformWebSocketTransport` in the browser:
/// a `BrowserWebSocketTransport`. The browser has no message size limits
/// to set, so the sizes are ignored.
WebSocketTransport createWebSocketTransport({
  int? maxTextMessageSize,
  int? maxBinaryMessageSize,
}) => BrowserWebSocketTransport();
