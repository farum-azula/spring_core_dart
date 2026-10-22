import 'package:spring_web_dart/src/websocket/io_web_socket_transport.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// `IoWebSocketTransport` on platforms with `dart:io`.
WebSocketTransport createWebSocketTransport() => IoWebSocketTransport();
