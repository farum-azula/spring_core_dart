// The supplier as a controller of this same server, so the application
// runs without the real service (and without internet). Its profile,
// `supplier-stub`, comes with `dev` (a profile group); the expression
// keeps it out of prod whatever is activated. Its security chain is
// `supplierStubChain` (SecurityConfig).
import 'package:neon_books_server/src/supplier/supplier_models.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/supplier')
@Profile(['supplier-stub & !prod'])
class SupplierStub {
  SupplierStub(@Value(r'${neon.supplier.api-key}') this.apiKey);

  final String apiKey;
  var _deliveries = 0;

  /// Any 13-digit ISBN of 978 is known; other books are a 404. From 5
  /// copies on, 10 % off.
  @GetMapping('/offers/{isbn}')
  Offer offer(
    @PathVariable() String isbn,
    @RequestHeader('X-Api-Key') String key, {
    @RequestParam('copies') int copies = 1,
  }) {
    _checkKey(key);
    if (!RegExp(r'^978\d{10}$').hasMatch(isbn)) {
      throw ResponseStatusException(HttpStatus.notFound, 'Unknown book $isbn');
    }
    final price = 4 + int.parse(isbn.substring(10)) / 100;
    return Offer(
      isbn: isbn,
      price: copies >= 5 ? price * 0.9 : price,
      copies: 50,
    );
  }

  @PostMapping('/deliveries')
  ResponseEntity<Delivery> deliver(
    @RequestBody() DeliveryRequest request,
    @RequestHeader('X-Api-Key') String key,
  ) {
    _checkKey(key);
    final delivery = Delivery(
      isbn: request.isbn,
      copies: request.copies,
      reference: 'D-${++_deliveries}',
    );
    return ResponseEntity.created(
      Uri.parse('/supplier/deliveries/${delivery.reference}'),
    ).body(delivery);
  }

  void _checkKey(String key) {
    if (key != apiKey) {
      throw ResponseStatusException(HttpStatus.unauthorized, 'Wrong API key');
    }
  }
}
