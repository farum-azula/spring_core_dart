// Scheduled jobs (chapter 8): restocking with a fixed delay from the
// properties, a report at a cron time.
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/stock/stock_service.dart';
import 'package:neon_books_server/src/supplier/supplier_clients.dart';
import 'package:neon_books_server/src/supplier/supplier_configured.dart';
import 'package:neon_books_server/src/supplier/supplier_models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';

@Component()
@Conditional([SupplierConfigured])
@Log()
class RestockJob {
  RestockJob(this._stock, this._offers, this._deliveries);

  final StockService _stock;
  final SupplierOffers _offers;
  final SupplierDeliveries _deliveries;

  /// How many runs happened.
  int runs = 0;

  /// Every `neon.stock.restock-interval` after the previous run ended
  /// (its Future), the first one `restock-initial-delay` after the start.
  @Scheduled(
    fixedDelayString: r'${neon.stock.restock-interval:30s}',
    initialDelayString: r'${neon.stock.restock-initial-delay:10s}',
  )
  Future<void> restockLowStock() async {
    runs++;
    for (final book in _stock.lowStock()) {
      try {
        final wanted = (_stock.lowThreshold * 2 - book.available).clamp(1, 100);
        final offer = await _offers.offer(book.isbn, wanted);
        final delivery = await _deliveries.order(
          DeliveryRequest(
            isbn: book.isbn,
            copies: wanted < offer.copies ? wanted : offer.copies,
          ),
        );
        if (delivery.statusCode == HttpStatus.created) {
          _stock.restock(book.isbn, delivery.body!.copies);
        } else {
          log.info('no delivery of ${book.isbn} (${delivery.statusCode})');
        }
      } on FeignNotFound {
        log.info('the supplier does not sell $book');
      } on FeignException catch (error) {
        log.warning('restocking $book failed: ${error.status}');
      }
    }
  }
}

/// A primary constructor (Dart 3.13): the field is declared in the body,
/// the header names it.
@Component()
@Log()
class StockReport(this._stock) {
  final StockService _stock;

  /// At 06:00 every day (`neon.stock.report-cron`, Spring's six fields:
  /// second minute hour day month weekday).
  @Scheduled(cron: r'${neon.stock.report-cron:0 0 6 * * *}')
  void dailyReport() {
    final low = _stock.lowStock();
    log.info(
      low.isEmpty
          ? 'stock report: every book in stock'
          : 'stock report: low on ${low.join(', ')}',
    );
  }
}
