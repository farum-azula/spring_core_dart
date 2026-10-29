import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/catalog/catalog_service.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// What the Catalog screen shows: the query, the page, the books. A
/// `@ChangeNotifierComponent`: every method notifies the widgets that
/// read the state (after the returned `Future` completes).
@ChangeNotifierComponent()
@BuildContextAccess()
class Catalog {
  Catalog(this._service);

  final CatalogService _service;

  String _query = '';
  int _page = 0;
  PageOfBooks? _books;
  Object? _error;

  String get query => _query;
  int get page => _page;

  /// The books shown, `null` before the first answer.
  PageOfBooks? get books => _books;

  /// The last failure (no server, ...), `null` after a success.
  Object? get error => _error;

  /// Searches; the first page.
  Future<void> search(String query) => _load(query.trim(), 0);

  /// Another page of the same query.
  Future<void> showPage(int page) => _load(_query, page);

  /// The same page again, e.g. after the caches were cleared.
  Future<void> reload() => _load(_query, _page);

  Future<void> _load(String query, int page) async {
    _query = query;
    _page = page;
    try {
      _books = await _service.page(query, page);
      _error = null;
    } on FeignException catch (error) {
      _error = error;
    }
  }
}
