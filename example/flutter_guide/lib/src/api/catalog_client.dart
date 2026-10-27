import 'dart:typed_data';

import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// The catalog of the server, anonymous: an interface, the generator
/// writes the HTTP calls. The URL is a property (`api.base-url`).
@FeignClient('catalog', url: r'${api.base-url}', path: '/api/books')
abstract interface class CatalogClient {
  /// `GET /api/books?q=dune&page=0`; a `null` query is left out.
  @GetMapping()
  Future<PageOfBooks> page({
    @RequestParam('q') String? query,
    @RequestParam('page') int? page,
  });

  /// `GET /api/books/{isbn}`; a 404 throws `FeignNotFound`.
  @GetMapping('/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  /// `GET /api/books/{isbn}/cover`: the image bytes.
  @GetMapping.of(path: '/{isbn}/cover', produces: 'image/*')
  Future<Uint8List> cover(@PathVariable() String isbn);
}
