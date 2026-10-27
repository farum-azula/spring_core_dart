// The catalog's REST API (chapter 3): request parameters, path
// variables, a cookie, a validated JSON body, ResponseEntity, file
// download with Range, multipart upload.
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/catalog/cover_store.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/api/books')
class BookController {
  BookController(this.catalog, this.covers, this.shop, {this.recentLimit = 5});

  final Catalog catalog;

  /// The cover store is a lazy bean: created on the first cover request.
  final ObjectProvider<CoverStore> covers;
  final ShopProperties shop;

  /// Books the `neon-recent` cookie keeps. No `int` bean exists and no
  /// `@Value` asks for a property: the Dart default value stays.
  final int recentLimit;

  /// The cookie keeping the books a browser looked at last.
  static const recentCookie = 'neon-recent';

  /// `GET /api/books?q=dune&page=0`: both parameters are optional.
  @GetMapping()
  BookPage search({
    @RequestParam.of(name: 'q', defaultValue: '') String query = '',
    @RequestParam.of(name: 'page', defaultValue: '0') int page = 0,
  }) {
    if (page < 0) {
      throw ResponseStatusException(HttpStatus.badRequest, 'page must be >= 0');
    }
    return catalog.search(query, page);
  }

  /// `GET /api/books/recent`: the books of the `neon-recent` cookie that
  /// [find] sets (most recent first).
  @GetMapping('/recent')
  List<Book> recent({@CookieValue(recentCookie) String recent = ''}) =>
      catalog.findAll(recent.split('.').where((s) => s.isNotEmpty));

  /// A missing book is a [BookNotFoundException]: `ApiErrors` answers it
  /// with a 404 ProblemDetail.
  @GetMapping('/{isbn}')
  Book find(
    @PathVariable() String isbn,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    final book = catalog.get(isbn);
    final seen = [
      isbn,
      ...?request.cookies[recentCookie]?.split('.').where((s) => s != isbn),
    ].take(recentLimit);
    response.addCookie(
      ResponseCookie(recentCookie, seen.join('.'), path: '/api/books'),
    );
    return book;
  }

  /// The cover image: a `Resource` (streamed from the file, `Range` and
  /// `If-Modified-Since` answered), cached by clients for a day.
  @GetMapping('/{isbn}/cover')
  ResponseEntity<Resource> cover(@PathVariable() String isbn) {
    catalog.get(isbn);
    return ResponseEntity.status(HttpStatus.ok)
        .header(HttpHeaders.cacheControlHeader, ['public, max-age=86400'])
        .body<Resource>(covers.getObject().coverOf(isbn));
  }

  /// `@Valid()`: a violation is a 400 with the field errors; created is a
  /// 201 with `Location`.
  @PostMapping()
  ResponseEntity<Book> add(@RequestBody() @Valid() NewBook newBook) {
    final added = catalog.add(newBook);
    return ResponseEntity.created(Uri.parse('/api/books/${added.isbn}'))
        .body(added);
  }

  /// `multipart/form-data` with the image in the part `file` (PNG or
  /// JPEG).
  @PutMapping('/{isbn}/cover')
  @ResponseStatus(HttpStatus.noContent)
  Future<void> uploadCover(
    @PathVariable() String isbn,
    @RequestPart('file') MultipartFile cover,
  ) async {
    catalog.get(isbn);
    if (!CoverStore.extensions.containsKey(cover.contentType)) {
      throw ResponseStatusException(
        HttpStatus.unsupportedMediaType,
        'A cover is a PNG or JPEG image',
      );
    }
    if (cover.size > shop.maxCoverSize.toBytes()) {
      throw ResponseStatusException(
        HttpStatus.contentTooLarge,
        'A cover is at most ${shop.maxCoverSize}',
      );
    }
    await covers.getObject().store(isbn, cover);
  }

  @DeleteMapping('/{isbn}')
  @ResponseStatus(HttpStatus.noContent)
  void remove(@PathVariable() String isbn) => catalog.remove(isbn);
}
