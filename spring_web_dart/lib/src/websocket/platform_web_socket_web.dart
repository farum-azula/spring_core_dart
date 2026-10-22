import 'package:spring_web_dart/src/websocket/browser_web_socket_transport.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// `BrowserWebSocketTransport` on the web.
WebSocketTransport createWebSocketTransport() => BrowserWebSocketTransport();
