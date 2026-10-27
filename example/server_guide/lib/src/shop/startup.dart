// What happens when the application starts (chapter 1): a callback once
// every singleton exists, runners in @Order, events of Spring Boot and of
// the web server.
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/book_repository.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// dev only: fills the empty catalog from `classpath:data/books.json`
/// (through the repository: the service would ask for an admin).
@Component()
@Profile(['dev'])
@Order(1)
@Log()
class SampleData implements ApplicationRunner {
  SampleData(
    this._books,
    this._mapper,
    @Value(r'${neon.catalog.sample-data}') this._data,
  );

  final BookRepository _books;
  final ObjectMapper _mapper;
  final Resource _data;

  @override
  Future<void> run(ApplicationArguments args) async {
    final books = _mapper.readList<NewBook>(await _data.readAsString());
    for (final book in books) {
      _books.save(book.toBook());
    }
    log.info('${books.length} sample books loaded from ${_data.filename}');
  }
}

/// Says hello once everything runs. A `CommandLineRunner` (the raw
/// arguments) after [SampleData] (`@Order(2)`).
@Component()
@Order(2)
@Log()
class StartupAnnouncement implements CommandLineRunner {
  StartupAnnouncement(this._books, this._messages);

  final BookRepository _books;
  final MessageSource _messages;

  /// SpEL: `#{...}` reads the `shopProperties` bean (and calls a method).
  @Value('#{shopProperties.name.toUpperCase()}')
  late final String banner;

  late Environment _environment;
  late ApplicationContext _context;

  /// Method injection: called once the fields and setters are injected.
  @Autowired()
  void configure(Environment environment, ApplicationContext context) {
    _environment = environment;
    _context = context;
  }

  @override
  void run(List<String> args) {
    final profiles = _environment.activeProfiles;
    final runners = _context.getBeanNamesForType(CommandLineRunner);
    // Every line logged inside carries these fields.
    SpringLog.withFields({'profiles': profiles.join(',')}, () {
      log.info(
        '$banner: ${_books.count()} books. '
        '${_messages.getMessage('shop.welcome', args: [banner], locale: 'ja')}',
        fields: {'runners': runners.length},
      );
    });
  }
}

/// Called once every eager singleton exists, before the runners.
@Component()
@Log()
class CatalogStatistics implements SmartInitializingSingleton {
  CatalogStatistics(this._shop);

  final ShopProperties _shop;

  @override
  void afterSingletonsInstantiated() => log.debug(
    '${_shop.name}: open ${_shop.opensAt}-${_shop.closesAt}, '
    'baskets up to ${_shop.maxBasketSize} books, '
    'delivery in ${_shop.deliveryTime.inDays} days',
  );
}

/// Application and web server events, as `@EventListener` methods.
@Component()
@Log()
class ServerAnnouncer {
  /// After the runners: the application is ready.
  @EventListener()
  void onReady(ApplicationReadyEvent event) =>
      log.debug('ready; the web server is listening once it has bound');

  /// Several event types for one method (`classes:`), the event as the
  /// parameter's common supertype.
  @EventListener(classes: [ContextRefreshedEvent, ContextClosedEvent])
  void onContext(ApplicationEvent event) => log.debug(
    event is ContextClosedEvent ? 'NEON Books is closing' : 'context ready',
  );

  /// The server listens (it binds its socket asynchronously, after the
  /// context started).
  @EventListener()
  void onServerStarted(WebServerInitializedEvent event) => log.info(
    'NEON Books is open at http://localhost:${event.port}/api/books',
  );
}
