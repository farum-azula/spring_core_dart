// Chapter 9, the supplier's Feign clients against MockHttpTransport (the
// application's own configuration, no server): URLs and headers, JSON,
// FeignNotFound, retries, the fallback, @Cacheable on a client, and the
// restock job that uses them.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/stock/restock_job.dart';
import 'package:neon_books_server/src/supplier/supplier_clients.dart';
import 'package:neon_books_server/src/supplier/supplier_models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart'
    show FeignNotFound, HttpTransport, HttpTransportException;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

import 'support/app.dart';

const littlePrince = '9780156012195'; // 0 copies in the sample data

void main() {
  final supplier = MockHttpTransport();
  final app = neonBooks(overrides: [BeanOverride<HttpTransport>(supplier)]);
  final logs = captureLogs();

  setUp(supplier.reset);

  test("GET: the URL from the config, the interceptor's headers", () async {
    supplier
        .when(HttpMethod.get, '/supplier/offers/$littlePrince?copies=3')
        .respond(200, json: {'isbn': littlePrince, 'price': 3.5, 'copies': 7});
    final offer = await app.getBean<SupplierOffers>().offer(littlePrince, 3);
    expect((offer.price, offer.copies), (3.5, 7));
    final request = supplier.lastRequest;
    // config/supplier-dev.properties (imported, dev variant).
    expect(
      '${request.url}',
      'http://localhost:8080/supplier/offers/$littlePrince?copies=3',
    );
    expect(request.headers['X-Api-Key'], 'dev-key');
    expect(request.headers['X-Client'], 'neon-books');
  });

  test('@Cacheable on a client method: one request per ISBN', () async {
    supplier
        .when(HttpMethod.get, '/supplier/offers/9780547928227?copies=2')
        .respond(
          200,
          json: {'isbn': '9780547928227', 'price': 6.0, 'copies': 3},
        );
    final offers = app.getBean<SupplierOffers>();
    await offers.offer('9780547928227', 2);
    await offers.offer('9780547928227', 2);
    expect(supplier.requests, hasLength(1));
  });

  test('404 → FeignNotFound', () async {
    supplier
        .when(HttpMethod.get, '/supplier/offers/9790000000000?copies=1')
        .respond(404, json: {'status': 404});
    await expectLater(
      app.getBean<SupplierOffers>().offer('9790000000000', 1),
      throwsA(isA<FeignNotFound>()),
    );
  });

  test('POST: the JSON body, a ResponseEntity', () async {
    supplier
        .when(HttpMethod.post, '/supplier/deliveries')
        .respond(
          201,
          json: {'isbn': littlePrince, 'copies': 2, 'reference': 'D-9'},
        );
    final delivery = await app.getBean<SupplierDeliveries>().order(
      const DeliveryRequest(isbn: littlePrince, copies: 2),
    );
    expect(delivery.statusCode, 201);
    expect(delivery.body!.reference, 'D-9');
    expect(supplier.lastRequest.headers['X-Shop'], 'NEON Books');
    expect(jsonDecode(utf8.decode(supplier.lastRequest.body!)), {
      'copies': 2,
      'isbn': littlePrince,
    });
  });

  test(
    'a supplier down: 3 attempts (the Retryer), then the fallback',
    () async {
      supplier
          .when(HttpMethod.post, '/supplier/deliveries')
          .fail(HttpTransportException('connection refused'));
      final delivery = await app.getBean<SupplierDeliveries>().order(
        const DeliveryRequest(isbn: littlePrince, copies: 2),
      );
      expect(supplier.requests, hasLength(3));
      expect(delivery.statusCode, 503); // NoDeliveries
      expect(delivery.body!.copies, 0);
    },
  );

  test(
    'the restock job: offers, deliveries, a book the supplier lacks',
    () async {
      supplier
        ..when(
          HttpMethod.get,
          '/supplier/offers/$littlePrince',
        ).respond(200, json: {'isbn': littlePrince, 'price': 3.5, 'copies': 50})
        ..when(HttpMethod.post, '/supplier/deliveries').respondWith(
          (request) => HttpResponse(
            201,
            headers: HttpHeaders({
              HttpHeaders.contentTypeHeader: MediaType.applicationJson,
            }),
            body: request.body!,
            request: request,
          ),
        )
        ..when(
          HttpMethod.get,
          '/supplier/offers/9780140421996',
        ).respond(404, json: {});
      // Only two books run low here; the others are in stock.
      final catalog = app.getBean<Catalog>();
      for (final book in catalog.all()) {
        if (book.available < 2 &&
            book.isbn != littlePrince &&
            book.isbn != '9780140421996') {
          catalog.changeStock(book.isbn, 5);
        }
      }
      await app.getBean<RestockJob>().restockLowStock();
      // threshold 2 → up to 4 copies.
      expect(catalog.get(littlePrince).available, 4);
      expect(
        logs.messages,
        contains('the supplier does not sell Leaves of Grass (9780140421996)'),
      );
    },
  );
}
