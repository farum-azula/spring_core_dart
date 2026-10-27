// Release-mode check, run in CI as minified JavaScript:
//
//   dart compile js -O4 -o /tmp/release_check.js tool/release_check.dart
//   node -e 'globalThis.self = globalThis; require("/tmp/release_check.js")'
//
// (dart2js output uses the browser's `self`, e.g. for the timers of
// @Scheduled tasks; plain node does not define it.)
//
// Minification renames classes, so anything that matched annotations by
// `runtimeType.toString()` would silently stop working here.

// A command line tool: the result goes to the console.
// ignore_for_file: avoid_print
import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_scheduling/spring_auto_configuration.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart'
    show Scheduled, ScheduledAnnotationBeanPostProcessor;
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/aop/aspects.dart';
import 'package:spring_core_dart_example/src/api/book_dto.dart';
import 'package:spring_core_dart_example/src/app.dart';
import 'package:spring_core_dart_example/src/cache/price_list.dart';
import 'package:spring_core_dart_example/src/jobs/stock_jobs.dart';
import 'package:spring_core_dart_example/src/remote/catalog_api.dart';
import 'package:spring_core_dart_example/src/remote/live_feeds.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';

void main() {
  // Config comes from the embedded classpath resources (lib/resources/),
  // so it works without any file system — here under node.
  final modules = [
    shopBeans,
    springBootAutoConfiguration,
    springBootStarterSchedulingAutoConfiguration,
    springBootStarterCacheAutoConfiguration,
    springBootStarterFeignAutoConfiguration,
    springBootStarterWebsocketAutoConfiguration,
  ];
  final environment = StandardEnvironment(systemEnvironment: {});
  ConfigDataEnvironment(environment).processAndApplySync();
  final context = AnnotationConfigApplicationContext(
    modules,
    environment: environment,
  );
  context.beanFactory.registerScope('basket', SimpleMapScope());
  context.refresh();
  tourLog.clear();
  context.getBean<PricingService>().quote('1', 2);
  if (!tourLog.any((line) => line.startsWith('timing: start'))) {
    throw StateError('@annotation(Timed) advice did not run: $tourLog');
  }
  if (context.getMessage('greeting', args: ['x'], locale: 'ru') !=
      'Добро пожаловать в x!') {
    throw StateError('classpath messages were not found');
  }
  // @Cacheable is found by type checks on the annotation objects.
  final prices = context.getBean<PriceList>()
    ..price('1')
    ..price('1');
  if (prices.lookups != 1) {
    throw StateError('@Cacheable did not cache: ${prices.lookups} lookups');
  }
  // @Scheduled methods are found and called through the generated
  // BeanDefinition.annotatedMethods.
  final tasks = context
      .getBean<ScheduledAnnotationBeanPostProcessor>()
      .scheduledTasks;
  if (tasks.length != 2) {
    throw StateError('expected 2 @Scheduled tasks, got $tasks');
  }
  final jobs = context.getBean<StockJobs>();
  context.beanFactory
      .getBeanDefinition('stockJobs')
      .annotatedMethods
      .firstWhere(
        (m) => m.annotations.whereType<Scheduled>().any(
          (s) => s.fixedDelayString != null,
        ),
      )
      .invoke(jobs, const []);
  if (jobs.refreshes == 0) {
    throw StateError('@Scheduled method was not called');
  }
  // ObjectMapper: constructors called with named arguments (symbols) and
  // property names from the metadata, not from minified class members.
  final mapper = context.getBean<ObjectMapper>();
  final book = mapper.readValue<BookDto>(
    mapper.writeValueAsString(
      const BookDto(
        isbn: '1',
        title: 'Dune',
        author: AuthorDto('Herbert', born: 1920),
        availability: Availability.soldOut,
      ),
    ),
  );
  if (book.title != 'Dune' ||
      book.author.born != 1920 ||
      book.availability != Availability.soldOut ||
      book.formats.single != BookFormat.paperback) {
    throw StateError('ObjectMapper round trip failed');
  }
  // Feign: the generated client implementation, created through the
  // starter's factory (with the fetch transport under JavaScript).
  context.getBean<CatalogApi>();
  if (context.getBean<MotdApi>() is OfflineMotd) {
    throw StateError('the Feign client should be primary over its fallback');
  }
  // Streams: the typed streams are built from the generic types (the
  // generated casts throw otherwise); nothing connects until listened to.
  context.getBean<StockFeed>().changes();
  context.getBean<SupportChat>().lines();
  context.close();
  _checkSpel();
  print('release check passed');
}

// SpEL keeps Java's int/double arithmetic under JavaScript, where `7.0`
// and `7` are the same number.
void _checkSpel() {
  final parser = SpelExpressionParser();
  const cases = <String, Object>{
    '7.0 / 2': 3.5,
    '7 / 2': 3,
    '7.0 / 2 * 2 / 4': 1.75,
    '(7.0 ?: 1) / 2': 3.5,
    'T(Math).sqrt(16) / 8': 0.5,
    'T(Math).floor(7.5) / 2': 3.5,
    "'x' + 7.0": 'x7.0',
    '-7 % 3': -1,
    "'d' - 3": 'a',
    '(-2) ^ 33': -2147483648,
    'T(Double).NaN == T(Double).NaN': false,
    '{1, {2}} == {1, {2}}': true,
  };
  cases.forEach((expression, expected) {
    final actual = parser.parseExpression(expression).getValue();
    if (actual != expected) {
      throw StateError('SpEL $expression: expected $expected, got $actual');
    }
  });
  try {
    parser.parseExpression('1 / 0').getValue();
    throw StateError('SpEL 1 / 0 did not fail');
  } on UnsupportedError {
    // Like Java's ArithmeticException.
  }
}
