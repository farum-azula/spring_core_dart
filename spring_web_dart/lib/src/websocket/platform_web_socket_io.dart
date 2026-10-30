import 'package:spring_web_dart/src/websocket/io_web_socket_transport.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// Creates the transport for `platformWebSocketTransport` where `dart:io`
/// exists: an `IoWebSocketTransport` with a default `HttpClient`, and the
/// default message size limits for a `null` size.
WebSocketTransport createWebSocketTransport({
  int? maxTextMessageSize,
  int? maxBinaryMessageSize,
}) => IoWebSocketTransport(
  maxTextMessageSize:
      maxTextMessageSize ?? IoWebSocketSession.defaultMaxMessageSize,
  maxBinaryMessageSize:
      maxBinaryMessageSize ?? IoWebSocketSession.defaultMaxMessageSize,
);
