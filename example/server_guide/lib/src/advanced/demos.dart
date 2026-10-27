// The parts of the advanced chapter that are not beans: contexts built by
// hand (a parent and a child, startup failures) and the SpEL and binding
// APIs used directly. bin/advanced.dart prints them; test/advanced_test.dart
// checks them.
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/shop/clock.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A parent context with shared beans (a clock) and a child context whose
/// beans use them; events published in the child reach the parent's
/// listeners. Returns what the child's bean saw and what the parent heard.
(String, List<String>) parentAndChild() {
  final parent = AnnotationConfigApplicationContext([
    BeanModule('platform', [
      BeanDefinition<Clock>(name: 'clock', create: (_) => const SystemClock()),
    ]),
  ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
  final heard = <String>[];
  parent.addListener<StockAlert>((alert) => heard.add('parent: ${alert.isbn}'));
  final child = AnnotationConfigApplicationContext(
    [
      BeanModule('shop', [
        BeanDefinition<StockAlert>(
          name: 'firstAlert',
          dependencies: const [Dependency(Clock)],
          create: (r) =>
              StockAlert('9780441013593', r.dependency<Clock>().now()),
        ),
      ]),
    ],
    parent: parent,
    environment: StandardEnvironment(systemEnvironment: {}),
  )..refresh();
  final alert = child.getBean<StockAlert>();
  child
    ..publishEvent(alert)
    ..close();
  parent.close();
  return ('child bean with the parent clock: ${alert.isbn}', heard);
}

/// An event of [parentAndChild].
class StockAlert {
  StockAlert(this.isbn, this.at);

  final String isbn;
  final DateTime at;
}

/// What Spring Boot prints when the application cannot start (`APPLICATION
/// FAILED TO START`, a description and an action), for a bean whose
/// dependency does not exist and for two beans that need each other. The
/// refresh validates the whole graph before any bean is created.
Map<String, String> failureReports() {
  String reportOf(List<BeanDefinition<Object>> definitions) {
    final lines = <String>[];
    try {
      SpringApplication(
        [BeanModule('broken', definitions)],
        bannerMode: BannerMode.off,
        out: lines.add,
      ).run(
        const [],
        properties: {
          'spring.main.log-startup-info': false,
          'logging.level.root': 'warn',
        },
      );
    } on Object {
      // The report is in [lines].
    }
    return lines.join('\n');
  }

  return {
    'missing bean': reportOf([
      BeanDefinition<ShopProperties>(
        name: 'shop',
        dependencies: const [Dependency(Clock)],
        create: (r) => ShopProperties(),
      ),
    ]),
    'cycle': reportOf([
      BeanDefinition<Clock>(
        name: 'clock',
        dependencies: const [Dependency(ShopProperties)],
        create: (_) => const SystemClock(),
      ),
      BeanDefinition<ShopProperties>(
        name: 'shop',
        dependencies: const [Dependency(Clock)],
        create: (_) => ShopProperties(),
      ),
    ]),
  };
}

/// SpEL used directly (Spring's `SpelExpressionParser`): over the books
/// of [books] (`@Introspected`, so SpEL can read their properties), with a
/// variable and a function; and a `SimpleEvaluationContext` that allows
/// reading properties only (for expressions from users).
Map<String, Object?> spel(List<Book> books, BeanIntrospector introspector) {
  final parser = SpelExpressionParser();
  final context = StandardEvaluationContext(books.first)
    ..propertyAccessors.insert(0, IntrospectionPropertyAccessor(introspector))
    ..setVariable('books', books)
    ..registerFunction('withVat', (num price) => price * 1.07);
  Object? eval(String expression) =>
      parser.parseExpression(expression).getValue(context);

  final restricted = SimpleEvaluationContext.forReadOnlyDataBinding()
      .withRootObject({'title': 'Dune', 'price': 9.99})
      .build();
  return {
    'title.toUpperCase()': eval('title.toUpperCase()'),
    '#books.?[price > 10].![title]': eval('#books.?[price > 10].![title]'),
    '#books.^[year < 1900]?.title': eval('#books.^[year < 1900]?.title'),
    '#withVat(price)': eval('#withVat(price)'),
    "year ?: 'unknown' (Elvis)": eval("year ?: 'unknown'"),
    'T(Math).max(price, 10)': eval('T(Math).max(price, 10)'),
    r"isbn matches '97[89]\d{10}'": eval(r"isbn matches '97[89]\d{10}'"),
    "tags.contains('fiction') ? 'novel' : 'other'": eval(
      "tags.contains('fiction') ? 'novel' : 'other'",
    ),
    'template': parser
        .parseExpression('#{title} for #{price} EUR', ParserContext.template)
        .getValue(context),
    'SimpleEvaluationContext': parser
        .parseExpression('title')
        .getValue(restricted),
  };
}

/// Spring's `DataBinder` and `BeanWrapper`: text values (a form, a CSV
/// line) bound to a mutable object with conversion and validation, and
/// properties read and written by name.
(ShopProperties, List<String>) bindShopSettings(
  Map<String, String> values,
  BeanIntrospector introspector,
) {
  final settings = ShopProperties();
  final binder =
      DataBinder(settings, objectName: 'shop', introspector: introspector)
        ..disallowedFields = ['name']
        ..validators.add(BeanValidator(introspector: introspector))
        ..bind(values)
        ..validate();
  final wrapper = BeanWrapper(settings, introspector: introspector);
  final errors = [
    for (final error in binder.bindingResult.allErrors)
      [
        if (error is FieldError) error.field else error.objectName,
        error.codes.first,
      ].join(': '),
    'opensAt via BeanWrapper: ${wrapper.getPropertyValue('opensAt')}',
  ];
  return (settings, errors);
}
