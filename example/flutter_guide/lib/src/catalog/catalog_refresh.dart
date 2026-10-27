import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/catalog/catalog.dart';
import 'package:neon_books_app/src/catalog/catalog_service.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';

/// Refreshes the catalog every `catalog.refresh-interval` (5 minutes by
/// default): empties the caches and reloads the page on screen, so new
/// books and prices show up.
///
/// Only while the app is in the foreground: when it goes to the
/// background `SpringApplicationWidget` pauses the context, which stops
/// `@Scheduled` tasks, and starts them again when the app is back.
@Component()
@Log(topic: 'neon.catalog')
class CatalogRefresh {
  CatalogRefresh(this._service, this._catalog);

  final CatalogService _service;
  final Catalog _catalog;

  @Scheduled(
    fixedDelayString: r'${catalog.refresh-interval:5m}',
    initialDelayString: r'${catalog.refresh-interval:5m}',
  )
  Future<void> refresh() async {
    log.info('refreshing the catalog');
    _service.refresh();
    // A method of the Catalog, not a read of its state: reading it here,
    // outside any widget's build, would make every widget holding the
    // Catalog listen to it from then on.
    await _catalog.reload();
  }
}
