import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// Stock changes as server-sent events. `EventStream<T>` is a `Stream<T>`
/// of the events' data; it connects when listened to, reconnects after a
/// break (sending `Last-Event-ID`, so no change is missed) and closes when
/// the subscription is cancelled.
@FeignClient('stock', url: r'${api.base-url}', path: '/api/stock')
abstract interface class StockClient {
  @GetMapping('/events')
  EventStream<StockChanged> events();
}
