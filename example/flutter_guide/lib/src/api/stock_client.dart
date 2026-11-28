import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// Stock changes as server-sent events. `EventStream<T>` is a `Stream<T>`
/// of the events' data; it connects when listened to, reconnects after a
/// break (after 3 s, sending `Last-Event-ID`, so no change is missed) and
/// closes when the subscription is cancelled.
@HttpExchange('/api/stock')
abstract interface class StockClient {
  @GetExchange('/events')
  EventStream<StockChanged> events();
}
