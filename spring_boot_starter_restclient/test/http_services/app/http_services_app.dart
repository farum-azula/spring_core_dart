// An application with HTTP service interfaces in two groups: every
// parameter role, every return type, request attributes, a `${...}`
// header and a @Retryable call; and a third group imported by a
// configuration with a @Profile. The generator writes their classes and
// beans (../../spring_gen/http_services/app/http_services_app.spring.dart,
// from `dart run build_runner build`), with spring.resilience.enabled: true
// (lib/resources/application.yml) for the retried call.
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

import '../../spring_gen/http_services/app/http_services_app.spring.dart';

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
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
