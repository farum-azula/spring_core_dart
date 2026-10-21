// @Configuration classes and @Bean methods.
//
// Spring (Java): @Configuration class with @Bean(name, initMethod, ...),
// @Scope("prototype"), @Lazy, static @Bean methods, @PropertySource and
// @Import.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/external/legacy_config.dart';
import 'package:spring_core_dart_example/src/catalog/catalog.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';

/// Read by SpEL (`#{appInfo.name}`), so it is @Introspected.
@Introspected()
class AppInfo {
  AppInfo(this.name, this.currency);
  final String name;
  final String currency;
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class IdGenerator {
  static int _next = 0;
  final int id = ++_next;
}

/// A resource with an explicit init method and an inferred destroy
/// method (`close`).
class ConnectionPool {
  ConnectionPool(this.url);
  final String url;
  bool open = false;

  void connect() {
    open = true;
    tourLog.add('pool: connect $url');
  }

  void close() {
    open = false;
    tourLog.add('pool: close');
  }
}

/// Returned from a @Bean method; its own annotations still apply.
class SearchIndex {
  @Autowired()
  late final BookRepository books;

  int size = 0;

  @PostConstruct()
  void build() {
    size = books.findAll().length;
    tourLog.add('index: built with $size books');
  }
}

@Configuration()
@Import([LegacyConfig])
class ShopConfig {
  @Bean()
  AppInfo appInfo(
    @Value(r'${app.name}') String name,
    @Value(r'${app.currency}') String currency,
  ) => AppInfo(name, currency);

  /// Static: created without instantiating ShopConfig.
  @Bean()
  static Clock clock() => const SystemClock();

  @Bean(name: 'ids', aliases: ['idGenerator'])
  @Scope(ScopeType.prototype)
  IdGenerator ids() => IdGenerator();

  @Bean(initMethod: 'connect')
  @Lazy()
  ConnectionPool pool(@Value(r'${db.url}') String url) => ConnectionPool(url);

  @Bean()
  SearchIndex searchIndex() => SearchIndex();

  /// The bean named `messageSource` is used by `context.getMessage`.
  @Bean()
  MessageSource messageSource() =>
      PropertiesMessageSource(basenames: ['file:messages/messages']);
}

/// Only in prod: its @PropertySource is loaded only when the class is.
@Configuration()
@Profile(['prod'])
@PropertySource(['file:config/prod-only.properties'])
class ProdOnlyConfig {}
