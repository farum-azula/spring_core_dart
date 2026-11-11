import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import 'spring_gen/main.spring.dart';

@Introspected()
class Book {
  const Book({required this.isbn, required this.title});

  @NotBlank()
  final String isbn;

  @NotBlank()
  final String title;
}

/// Where the books are. A function keeps nothing between requests, so a
/// real one is a database or an API the function calls; this one answers
/// from a constant so that the example runs by itself.
@Service()
class Catalog {
  static const _books = [
    Book(isbn: '9780441013593', title: 'Dune'),
    Book(isbn: '9780141439587', title: 'Emma'),
  ];

  Future<List<Book>> all() async => _books;

  Future<void> audit(String who, Book book) async {
    // A call to a log service, a queue, a table.
  }
}

/// The same controller a server has.
@RestController()
@RequestMapping('/books')
class BooksController {
  BooksController(this.catalog, this.runtime);

  final Catalog catalog;
  final EdgeRuntime runtime;

  /// Open to everyone.
  @GetMapping()
  Future<List<Book>> list() => catalog.all();

  /// For a signed-in user. The audit record is written after the answer:
  /// `waitUntil` tells the platform to keep the instance until it ended.
  @PostMapping()
  @ResponseStatus(HttpStatus.accepted)
  Book suggest(@RequestBody() @Valid() Book book, Authentication caller) {
    runtime.waitUntil(catalog.audit(caller.name, book));
    return book;
  }
}

/// Work by the platform's schedule (a Cloudflare cron trigger, an
/// EventBridge schedule): what `@Scheduled` is on a server.
@Component()
@Log(topic: 'example')
class NightlyReport implements EdgeScheduledHandler {
  NightlyReport(this.catalog);

  final Catalog catalog;

  @override
  Future<void> onScheduled(EdgeScheduledEvent event) async {
    log.info('${(await catalog.all()).length} books at ${event.time}');
  }
}

@Configuration()
class SecurityConfig {
  /// Bearer tokens, no sessions: a function keeps nothing between
  /// requests.
  @Bean()
  SecurityFilterChain api(HttpSecurity http) => http
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchersFor(HttpMethod.get, ['/books'])
            .permitAll()
            .anyRequest()
            .authenticated(),
      )
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .oauth2ResourceServer((server) => server.jwt())
      .build();
}
