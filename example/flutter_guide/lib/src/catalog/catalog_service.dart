import 'dart:typed_data';

import 'package:neon_books_app/main.spring.dart';
import 'package:neon_books_app/src/api/catalog_client.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// The catalog as the screens read it: the server's answers, cached
/// (`@Cacheable`), so going back to a page or a book shows it at once and
/// costs no request. `CatalogRefresh` empties the caches now and then.
@Service()
@Log(topic: 'neon.catalog')
class CatalogService {
  CatalogService(this._client);

  final CatalogClient _client;

  /// One page of the catalog; [query] empty for all books. Cached per
  /// query and page (the key is both arguments).
  @Cacheable('catalog')
  Future<PageOfBooks> page(String query, int page) {
    log.debug('loading page $page of "$query"');
    return _client.page(query: query.isEmpty ? null : query, page: page);
  }

  /// The book [isbn], or `null` when the server knows none (a 404:
  /// `FeignNotFound`). A miss is not cached (`unless`), so a book added
  /// later is found.
  @Cacheable('books', unless: '#result == null')
  Future<Book?> find(String isbn) async {
    try {
      return await _client.find(isbn);
    } on FeignNotFound {
      return null;
    }
  }

  /// The cover image, or `null` when the book has none.
  @Cacheable('covers', unless: '#result == null')
  Future<Uint8List?> cover(String isbn) async {
    try {
      return await _client.cover(isbn);
    } on FeignNotFound {
      return null;
    }
  }

  /// Forgets the cached pages and books (covers rarely change).
  @CacheEvict.of(cacheNames: ['catalog', 'books'], allEntries: true)
  void refresh() => log.debug('catalog cache cleared');

  /// Forgets the cover of [isbn] (after an upload).
  @CacheEvict('covers', key: '#isbn')
  void coverChanged(String isbn) {}
}
