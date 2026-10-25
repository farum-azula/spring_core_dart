// Streams from a remote service: server-sent events through a Feign
// client (EventStream<T>) and a declarative WebSocket client
// (spring_boot_starter_websocket). StockEvent and ChatLine are
// introspected automatically (same package), so JSON needs no code.
//
// Spring (Java): no direct counterpart — Spring reads events as
// Flux<ServerSentEvent<T>> from WebClient, and its WebSocket client is
// imperative (WebSocketClient + WebSocketHandler). These two are this
// project's own, in the style of @FeignClient.
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart'
    show OnMessage, SendMessage, WebSocketClient;

/// A change of stock, pushed by the server.
class StockEvent {
  const StockEvent({required this.isbn, required this.copies});
  final String isbn;
  final int copies;
}

/// Server-sent stock changes (`text/event-stream`).
@FeignClient(
  'stock-feed',
  url: r'${neon.catalog-api.url:http://localhost:8080}',
)
abstract interface class StockFeed {
  /// A `Stream<StockEvent>`; `.events` adds id, event name and retry.
  @GetMapping('/stock/events')
  EventStream<StockEvent> changes();
}

/// One chat line.
class ChatLine {
  const ChatLine({required this.from, required this.text});
  final String from;
  final String text;
}

/// The shop's support chat over a WebSocket.
@WebSocketClient(
  'support-chat',
  url: r'${neon.chat.url:ws://localhost:8080/chat}',
)
abstract interface class SupportChat {
  @OnMessage()
  Stream<ChatLine> lines();

  @SendMessage()
  Future<void> say(ChatLine line);

  // No close(): the connection is closed when the application stops.
}
