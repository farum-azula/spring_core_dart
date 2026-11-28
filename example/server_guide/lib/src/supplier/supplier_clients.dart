// The supplier, another service, through HTTP service clients (chapter 9):
// an interface with exchange annotations becomes an injectable HTTP client;
// the generator writes the implementation (the RestClient calls), JSON goes
// through the ObjectMapper. Both interfaces are in the `supplier` group
// (SupplierClientConfig). In dev the supplier is this same server
// (supplier_stub.dart).
import 'package:neon_books_server/src/supplier/supplier_models.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart'
    show Cacheable;
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

/// Prices and copies at the supplier. An unknown book is a 404: an
/// `HttpClientErrorException` the caller handles.
@HttpExchange('/offers')
abstract interface class SupplierOffers {
  /// `GET /offers/{isbn}?copies=4`. Cached for 5 minutes
  /// (`spring.cache.simple.caches.supplier-offers.*`): AOP works on
  /// clients like on any bean.
  @GetExchange('/{isbn}')
  @Cacheable('supplier-offers', key: "#isbn + '*' + #copies")
  Future<Offer> offer(
    @PathVariable() String isbn,
    @RequestParam('copies') int copies,
  );
}

/// Orders copies. A call that gets no answer (the connection fails or
/// times out) is tried twice more; then the `ResourceAccessException`
/// reaches the caller, and the restock job tries again on its next run.
@HttpExchange('/deliveries')
abstract interface class SupplierDeliveries {
  /// A header with a placeholder, resolved from the configuration.
  @PostExchange.of(headers: [r'X-Shop=${neon.shop.name}'])
  @Retryable(
    includes: [ResourceAccessException],
    maxRetries: 2,
    delay: Duration(milliseconds: 100),
  )
  Future<ResponseEntity<Delivery>> order(
    @RequestBody() DeliveryRequest request,
  );
}
