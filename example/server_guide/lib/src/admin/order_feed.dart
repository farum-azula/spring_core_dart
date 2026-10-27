// Orders as they happen, for the admins' screen: an SseEmitter per
// client, fed from event listeners (chapter 3: events sent from
// anywhere, unlike an EventStream that a handler returns).
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/stock/stock_changed.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@Component()
class AdminOrderFeed {
  final _emitters = <SseEmitter>{};

  /// A new client: its emitter leaves the set when the stream ends.
  SseEmitter subscribe() {
    final emitter = SseEmitter(timeout: const Duration(hours: 1));
    _emitters.add(emitter);
    emitter.onCompletion(() => _emitters.remove(emitter));
    return emitter;
  }

  @EventListener()
  void onPlaced(OrderPlaced placed) => _send(placed.order, 'placed');

  @EventListener()
  void onShipped(OrderShipped shipped) => _send(shipped.order, 'shipped');

  /// `{"orderId": 3, "isbns": ["978..."]}`.
  @EventListener()
  void onLowStock(LowStock low) => _send(low, 'low-stock');

  void _send(Object data, String event) {
    for (final emitter in [..._emitters]) {
      emitter.send(ServerSentEvent(data, event: event)).ignore();
    }
  }
}
