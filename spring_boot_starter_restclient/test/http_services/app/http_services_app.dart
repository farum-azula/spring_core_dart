// An application with HTTP service interfaces in two groups: every
// parameter role (maps of values, HttpHeaders, request attributes, a
// UriBuilderFactory), every return type, request attributes, a `${...}`
// header and a @Retryable call; a third group imported by a configuration
// with a @Profile; and the stock group, whose interfaces (clients/) are
// found by basePackageClasses and ask for API versions. The generator
// writes their classes and
// beans (../../spring_gen/http_services/app/http_services_app.spring.dart,
// from `dart run build_runner build`), with spring.resilience.enabled: true
// (lib/resources/application.yml) for the retried call.
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

import '../../spring_gen/http_services/app/http_services_app.spring.dart';
import 'clients/stock_service.dart';

@Introspected()
class Book {
  const Book({required this.isbn, required this.title});

  final String isbn;
  final String title;
}

enum Shelf { fiction, science }

/// The tenant of a call, a request attribute the interceptors read.
class Tenant extends HttpRequestAttribute {
  const Tenant(String id) : super('tenant', id);
}

@HttpExchange('/books')
@Tenant('neon')
abstract interface class BookService {
  @GetExchange('/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  @GetExchange()
  Future<List<Book>> search(
    @RequestParam() String q, {
    @RequestParam() int? year,
    @RequestParam() List<Shelf> shelves = const [],
    @RequestHeader('X-Tag') List<String> tags = const [],
    @CookieValue() String? session,
  });

  @PostExchange.of(
    headers: [r'X-Source=${app.source}'],
    accept: ['application/json'],
  )
  Future<ResponseEntity<Book>> create(
    @RequestBody() Book book,
    @RequestHeader('X-Request-Id') int requestId,
  );

  @PutExchange('/{isbn}')
  Future<void> replace(@PathVariable() String isbn, @RequestBody() Book book);

  @DeleteExchange('/{isbn}')
  Future<ResponseEntity<void>> remove(@PathVariable() String isbn);

  @HttpExchange.of(url: '/{isbn}', method: HttpMethod.head)
  Future<HttpHeaders> head(@PathVariable() String isbn);

  @PostExchange('/{isbn}/cover')
  Future<void> upload(
    @PathVariable() String isbn,
    @RequestPart() MultipartFile cover,
    @RequestPart() Book meta,
    @RequestPart() String? note,
  );

  @GetExchange('/events')
  EventStream<Book> events();

  @GetExchange('/{isbn}/pdf')
  Stream<List<int>> pdf(@PathVariable() String isbn);

  @PostExchange.of(
    url: '/login',
    contentType: 'application/x-www-form-urlencoded',
  )
  @Tenant('login')
  Future<String> login(
    @RequestParam() String user,
    @RequestParam() Shelf? shelf,
  );

  @GetExchange('/{isbn}')
  @Retryable(
    includes: [ResourceAccessException],
    delay: Duration(milliseconds: 1),
  )
  Future<Book> findPatiently(@PathVariable() String isbn);

  @HttpExchange()
  Future<String> exchange(HttpMethod method, Uri url);

  @PostExchange('/{isbn}/scan')
  @Retryable(
    includes: [ResourceAccessException],
    delay: Duration(milliseconds: 1),
  )
  Future<void> scanPatiently(
    @PathVariable() String isbn,
    @RequestPart() MultipartFile scan,
  );

  @GetExchange('/filter')
  Future<String> filter(
    @RequestParam() Map<String, String> filters, {
    @RequestParam() Map<String, List<Shelf>>? shelves,
    @RequestHeader() Map<String, int> counts = const {},
    @RequestHeader() HttpHeaders? more,
    @CookieValue() Map<String, List<String>> cookies = const {},
    @RequestAttribute('trace.tag') String? tag,
    @RequestAttribute() Map<String, Object?> marks = const {},
  });

  @GetExchange('/{shelf}/{isbn}')
  Future<Book> onShelf(@PathVariable() Map<String, String> location);

  @GetExchange('/{isbn}')
  Future<Book> fromMirror(
    UriBuilderFactory? mirror,
    @PathVariable() String isbn,
  );

  @PostExchange.of(
    url: '/subscribe',
    contentType: 'application/x-www-form-urlencoded',
  )
  Future<String> subscribe(@RequestParam() Map<String, Shelf> topics);
}

@HttpExchange('/payments')
abstract interface class PaymentService {
  @PostExchange('/{id}')
  Future<void> pay(@PathVariable() String id, @RequestParam() int cents);
}

@HttpExchange('/reports')
abstract interface class ReportService {
  @GetExchange('/{id}')
  Future<String> find(@PathVariable() String id);
}

/// The reports' client, only with the `reports` profile: the interfaces
/// a configuration imports follow its conditions, as in Spring.
@Profile(['reports'])
@Configuration()
@ImportHttpServices(group: 'reports', types: [ReportService])
class ReportClients {}

@SpringBootApplication()
@ImportHttpServices(group: 'catalog', types: [BookService])
@ImportHttpServices(group: 'payments', types: [PaymentService])
@ImportHttpServices(group: 'stock', basePackageClasses: [StockService])
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
