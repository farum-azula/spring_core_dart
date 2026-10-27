// The supplier, another service, through Feign clients (chapter 9): an
// interface with mapping annotations becomes an injectable HTTP client;
// the generator writes the implementation, JSON goes through the
// ObjectMapper. In dev the supplier is this same server (supplier_stub.dart).
import 'package:neon_books_server/src/supplier/supplier_models.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart'
    show Cacheable;
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// Prices and copies at the supplier. No fallback: an unknown book is a
/// `FeignNotFound` the caller handles.
@FeignClient('supplier-offers', url: r'${neon.supplier.url}')
abstract interface class SupplierOffers {
  /// `GET /offers/{isbn}?copies=4`. Cached for 5 minutes
  /// (`spring.cache.simple.caches.supplier-offers.*`): AOP works on
  /// clients like on any bean.
  @GetMapping('/offers/{isbn}')
  @Cacheable('supplier-offers', key: "#isbn + '*' + #copies")
  Future<Offer> offer(
    @PathVariable() String isbn,
    @RequestParam('copies') int copies,
  );
}

/// Orders copies. When the supplier cannot be reached (after the
/// Retryer's attempts), [NoDeliveries] answers instead.
@FeignClient(
  'supplier-deliveries',
  url: r'${neon.supplier.url}',
  fallback: NoDeliveries,
)
abstract interface class SupplierDeliveries {
  /// A header with a placeholder, resolved from the configuration.
  @PostMapping.of(path: '/deliveries', headers: [r'X-Shop=${neon.shop.name}'])
  Future<ResponseEntity<Delivery>> order(
    @RequestBody() DeliveryRequest request,
  );
}

/// The fallback: nothing is delivered (503), the next run tries again.
@Component()
class NoDeliveries implements SupplierDeliveries {
  @override
  Future<ResponseEntity<Delivery>> order(DeliveryRequest request) async =>
      ResponseEntity.status(HttpStatus.serviceUnavailable)
          .body(Delivery(isbn: request.isbn, copies: 0));
}
