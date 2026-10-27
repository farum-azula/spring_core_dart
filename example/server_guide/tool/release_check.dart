// Release-mode check, run in CI as minified JavaScript:
//
//   dart compile js -O4 -o /tmp/release_check.js tool/release_check.dart
//   node -e 'globalThis.self = globalThis; require("/tmp/release_check.js")'
//
// (dart2js output uses the browser's `self`, e.g. for the timers of
// @Scheduled tasks; plain node does not define it.)
//
// Minification renames classes and members, so anything that matched
// annotations or properties by name at runtime would silently stop working
// here. The whole application starts (without a web server: JavaScript has
// no server sockets) and its AOP, cache, method security, scheduling, JSON,
// messages and SpEL are checked.

// A command line tool: the result goes to the console.
// ignore_for_file: avoid_print
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/book_repository.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart'
    show Scheduled, ScheduledAnnotationBeanPostProcessor;
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import '../bin/main.spring.dart';

Future<void> main() async {
  // Config comes from the embedded classpath resources (lib/resources/),
  // so it works without any file system — here under node.
  final context = await springApplication.runAsync(
    const [],
    properties: {
      'spring.main.web-application-type': 'none',
      'spring.main.banner-mode': 'off',
      'spring.main.register-shutdown-hook': false,
      'logging.level.root': 'warn',
      'logging.level.shop': 'warn',
      'logging.level.feign': 'warn',
      // TimingAspect writes at debug level.
      'logging.level.neon.timing': 'debug',
      'logging.threshold.console': 'warn',
      // Not from the JavaScript build's working directory.
      'logging.file.name': '',
    },
  );

  // The dev profile's sample data, read from classpath:data/books.json by
  // the ObjectMapper (constructor parameters by name, @JsonValue enums).
  final books = context.getBean<BookRepository>();
  final dune = books.findByIsbn('9780441013593');
  if (dune == null ||
      dune.format != BookFormat.paperback ||
      dune.year != 1965) {
    throw StateError('sample data not loaded: $dune');
  }

  // AOP: @Around('@annotation(timed)') matched by the names the generator
  // writes, not by class names.
  final timed = <String>[];
  final stopListening = SpringLog.listen((record) {
    if (record.loggerName == 'neon.timing') {
      timed.add(record.message);
    }
  });
  context.getBean<Catalog>().search('dune', 0);
  stopListening();
  if (!timed.any((line) => line.startsWith('search took'))) {
    throw StateError('the @Timed advice did not run: $timed');
  }

  // @Cacheable through the generated proxy: the second search is a hit
  // (the repository changes, the cached page does not).
  final catalog = context.getBean<Catalog>();
  final before = catalog.search('', 0).total;
  books.save(dune.withAvailable(99).copyAs('9780000000002'));
  if (catalog.search('', 0).total != before) {
    throw StateError('@Cacheable did not cache the catalog page');
  }

  // Method security: @PreAuthorize is found by type checks on the
  // annotation objects and its SpEL is evaluated.
  try {
    await SecurityContextHolder.runWithContext(
      () async => catalog.remove('9780441013593'),
      SecurityContextImpl(
        UsernamePasswordAuthenticationToken.authenticated('ada', null, [
          SimpleGrantedAuthority('ROLE_USER'),
        ]),
      ),
    );
    throw StateError('@PreAuthorize let a user remove a book');
  } on AccessDeniedException {
    // As expected.
  }

  // @Scheduled methods are found through BeanDefinition.annotatedMethods.
  final tasks = context
      .getBean<ScheduledAnnotationBeanPostProcessor>()
      .scheduledTasks;
  if (tasks.length != 2) {
    throw StateError('expected 2 @Scheduled tasks, got $tasks');
  }
  final scheduled = context.beanFactory
      .getBeanDefinition('stockReport')
      .annotatedMethods
      .where((m) => m.annotations.whereType<Scheduled>().isNotEmpty);
  if (scheduled.length != 1) {
    throw StateError('@Scheduled cron method not found');
  }

  // JSON: property names from the metadata, not from minified members.
  final mapper = context.getBean<ObjectMapper>();
  final order = mapper.readValue<CustomerOrder>(
    mapper.writeValueAsString(
      CustomerOrder(
        id: 7,
        customer: 'ada',
        lines: const [
          OrderLine(
            isbn: '9780441013593',
            title: 'Dune',
            price: 9.99,
            quantity: 1,
            total: 9.99,
          ),
        ],
        total: 9.99,
        placedAt: DateTime.utc(2026),
        status: OrderStatus.shipped,
      ),
    ),
  );
  if (order.lines.single.title != 'Dune' ||
      order.status != OrderStatus.shipped ||
      !mapper.writeValueAsString(order).contains('"status":"SHIPPED"')) {
    throw StateError('ObjectMapper round trip failed');
  }

  // Messages from the embedded classpath, in Japanese.
  if (!context
      .getMessage('shop.welcome', args: ['x'], locale: 'ja')
      .contains('ようこそ')) {
    throw StateError('classpath messages were not found');
  }

  await context.closeAsync();
  _checkSpel();
  print('release check passed');
}

extension on Book {
  Book copyAs(String isbn) => Book(
    isbn: isbn,
    title: title,
    author: author,
    price: price,
    available: available,
  );
}

// SpEL keeps Java's int/double arithmetic under JavaScript, where `7.0`
// and `7` are the same number.
void _checkSpel() {
  final parser = SpelExpressionParser();
  const cases = <String, Object>{
    '7.0 / 2': 3.5,
    '7 / 2': 3,
    '(7.0 ?: 1) / 2': 3.5,
    "'x' + 7.0": 'x7.0',
    '-7 % 3': -1,
    '{1, {2}} == {1, {2}}': true,
  };
  cases.forEach((expression, expected) {
    final actual = parser.parseExpression(expression).getValue();
    if (actual != expected) {
      throw StateError('SpEL $expression: expected $expected, got $actual');
    }
  });
}
