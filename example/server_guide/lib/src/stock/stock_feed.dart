// Live stock for clients, as server-sent events. Clients that lose the
// connection come back with `Last-Event-ID` and get what they missed.
import 'dart:async';

import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/stock/stock_changed.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// A `SmartLifecycle`: started with the context, stopped before the web
/// server (a higher phase stops first), which ends the open streams so
/// the graceful shutdown does not wait for them.
@Component()
@Log()
class StockFeed with SmartLifecycle {
  StockFeed(@Value(r'${neon.stock.replay-size:100}') this.replaySize);

  /// Events kept for clients that reconnect.
  final int replaySize;

  final _recent = <ServerSentEvent<StockChanged>>[];
  var _nextId = 1;
  StreamController<ServerSentEvent<StockChanged>>? _live;

  @override
  bool get isRunning => _live != null;

  @override
  void start() => _live = StreamController.broadcast();

  @override
  void stop() {
    unawaited(_live?.close());
    _live = null;
    log.debug('stock feed closed');
  }

  @EventListener()
  void onStockChanged(StockChanged change) {
    final event = ServerSentEvent(change, id: '${_nextId++}', event: 'stock');
    _recent.add(event);
    if (_recent.length > replaySize) {
      _recent.removeAt(0);
    }
    _live?.add(event);
  }

  /// The changes from now on; with [lastEventId], first the kept ones
  /// after it. Each listener (each client) gets its own stream.
  EventStream<StockChanged> subscribe({String? lastEventId}) => EventStream(() {
    final after = int.tryParse(lastEventId ?? '');
    StreamSubscription<ServerSentEvent<StockChanged>>? live;
    late final StreamController<ServerSentEvent<StockChanged>> events;
    events = StreamController(
      onListen: () {
        if (after != null) {
          _recent.where((e) => int.parse(e.id!) > after).forEach(events.add);
        }
        live = _live?.stream.listen(events.add, onDone: events.close);
        if (live == null) {
          unawaited(events.close());
        }
      },
      onCancel: () => live?.cancel(),
    );
    return events.stream;
  });
}
