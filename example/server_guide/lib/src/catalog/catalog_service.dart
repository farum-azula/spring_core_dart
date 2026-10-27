// The catalog: caching (chapter 8), method security (chapter 4), AOP
// (@Timed, chapter 6) and a @Lazy reference to itself (chapter 1), all
// through the proxy the container injects instead of the bean.
import 'package:neon_books_server/src/aop/timed.dart';
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/book_repository.dart';
import 'package:neon_books_server/src/stock/stock_changed.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// What the controllers and other services see of the catalog.
abstract interface class Catalog {
  /// A page of the books whose title, author or tags contain [query].
  @Timed()
  BookPage search(String query, int page);

  /// The book [isbn], or `null`.
  Book? find(String isbn);

  /// The book [isbn]; a [BookNotFoundException] when there is none.
  Book get(String isbn);

  /// The books of [isbns] that exist, in that order.
  List<Book> findAll(Iterable<String> isbns);

  /// Every book (the stock jobs walk through them).
  List<Book> all();

  /// Adds [book] (admins only).
  Book add(NewBook book);

  /// Removes the book [isbn] (admins only).
  @Timed()
  void remove(String isbn);

  /// Changes the copies in stock of [isbn] by [delta]; publishes
  /// [StockChanged].
  Book changeStock(String isbn, int delta);
}

@Service()
@Log()
class CatalogService implements Catalog {
  /// `@Lazy()`: a generated proxy that finds this bean's own proxy on
  /// first use, so calls through [_self] are cached; calls through `this`
  /// skip the proxy (and the cache), as in Spring.
  CatalogService(this._books, this._events, @Lazy() this._self);

  final BookRepository _books;
  final ApplicationEventPublisher _events;
  final Catalog _self;

  /// Field injection with conversion of the property's text.
  @Value(r'${neon.catalog.page-size:10}')
  late final int pageSize;

  @override
  @Cacheable('catalog', key: "#query + '|' + #page")
  BookPage search(String query, int page) {
    final text = query.trim().toLowerCase();
    final matching = [
      for (final book in _books.findAll())
        if (text.isEmpty ||
            book.title.toLowerCase().contains(text) ||
            book.author.toLowerCase().contains(text) ||
            book.tags.contains(text))
          book,
    ];
    log.debug(() => 'catalog query "$query" page $page: ${matching.length}');
    return BookPage(
      items: matching.skip(page * pageSize).take(pageSize).toList(),
      page: page,
      size: pageSize,
      total: matching.length,
    );
  }

  /// Misses (`null`) are not cached (`unless`): a book added later is
  /// found at once.
  @override
  @Cacheable('books', key: '#isbn', unless: '#result == null')
  Book? find(String isbn) => _books.findByIsbn(isbn);

  @override
  Book get(String isbn) =>
      _self.find(isbn) ?? (throw BookNotFoundException(isbn));

  @override
  List<Book> findAll(Iterable<String> isbns) => [
    for (final isbn in isbns) ?_self.find(isbn),
  ];

  @override
  List<Book> all() => _books.findAll();

  /// `@CachePut` stores the new book under its ISBN (`#result.isbn`);
  /// the cached pages are dropped.
  @override
  @PreAuthorize("hasRole('ADMIN')")
  @Caching(
    put: [CachePut('books', key: '#result.isbn')],
    evict: [CacheEvict('catalog', allEntries: true)],
  )
  Book add(NewBook book) {
    if (_books.findByIsbn(book.isbn) != null) {
      throw StateError('A book with ISBN ${book.isbn} exists already');
    }
    final added = _books.save(book.toBook());
    log.info('added $added');
    return added;
  }

  /// Checked here, whoever calls: the request rules let any logged-in
  /// user send `DELETE /api/books/{isbn}`, this answers 403 unless the
  /// user is an admin.
  @override
  @PreAuthorize("hasRole('ADMIN')")
  @Caching(
    evict: [
      CacheEvict('books', key: '#isbn'),
      CacheEvict('catalog', allEntries: true),
    ],
  )
  void remove(String isbn) {
    if (!_books.delete(isbn)) {
      throw BookNotFoundException(isbn);
    }
    log.info('removed $isbn');
  }

  @override
  @Caching(
    evict: [
      CacheEvict('books', key: '#isbn'),
      CacheEvict('catalog', allEntries: true),
    ],
  )
  Book changeStock(String isbn, int delta) {
    final book = _books.findByIsbn(isbn);
    if (book == null) {
      throw BookNotFoundException(isbn);
    }
    final changed = _books.save(
      book.withAvailable((book.available + delta).clamp(0, 1 << 30)),
    );
    _events.publishEvent(
      StockChanged(isbn: isbn, available: changed.available),
    );
    return changed;
  }
}
