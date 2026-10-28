import 'package:spring_web_dart/src/websocket/io_web_socket_transport.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// Creates the transport for `platformWebSocketTransport` where `dart:io`
/// exists: an `IoWebSocketTransport` with a default `HttpClient`.
WebSocketTransport createWebSocketTransport() => IoWebSocketTransport();
