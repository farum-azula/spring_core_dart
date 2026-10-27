import 'package:neon_books_server/src/stock/stock_changed.dart';
import 'package:neon_books_server/src/stock/stock_feed.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/api/stock')
class StockController {
  StockController(this.feed);

  final StockFeed feed;

  /// `text/event-stream` of `{"isbn": ..., "available": ...}`, each event
  /// with an id; a reconnecting client sends the last one it saw.
  @GetMapping('/events')
  EventStream<StockChanged> events(
    @RequestHeader('Last-Event-ID') String? lastEventId,
  ) => feed.subscribe(lastEventId: lastEventId);
}
