import 'dart:typed_data';

import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The catalog of the server, anonymous: an interface, the generator
/// writes the HTTP calls on the `server` group's `RestClient` (its base
/// URL is `api.base-url`). A call that gets no answer (no connection, a
/// timeout) is tried twice more; one that got an answer never is.
@HttpExchange('/api/books')
@Retryable(
  includes: [ResourceAccessException],
  maxRetries: 2,
  delay: Duration(milliseconds: 150),
  multiplier: 1.5,
)
abstract interface class CatalogClient {
  /// `GET /api/books?q=dune&page=0`; a `null` query is left out.
  @GetExchange()
  Future<PageOfBooks> page({
    @RequestParam('q') String? query,
    @RequestParam('page') int? page,
  });

  /// `GET /api/books/{isbn}`; a 404 throws an `HttpClientErrorException`.
  @GetExchange('/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  /// `GET /api/books/{isbn}/cover`: the image bytes.
  @GetExchange.of(url: '/{isbn}/cover', accept: ['image/*'])
  Future<Uint8List> cover(@PathVariable() String isbn);
}
