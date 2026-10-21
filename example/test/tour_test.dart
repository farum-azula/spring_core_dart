// End-to-end tests over the generated code: the tour's output proves each
// feature works.
@TestOn('vm')
library;

import 'package:spring_core_dart_example/tour.dart';
import 'package:test/test.dart';

void main() {
  late String output;

  setUpAll(() async {
    final lines = <String>[];
    await runTour(
      const [],
      out: lines.add,
      systemEnvironment: const {
        'DB_PASSWORD': 's3cret',
        'SHOP_MOTTO': 'Read more',
      },
    );
    output = lines.join('\n');
  });

  void expectLine(String line) => expect(output, contains(line));

  test('config data, profiles and conditions', () {
    expectLine('active profiles: [dev, dev-tools]');
    // Environment variables: one set, one falling back to its default.
    expectLine(r'db.password (${DB_PASSWORD:changeme}): s3cret');
    expectLine(r'db.user (${DB_USER:books}): books');
    expectLine(
      'db.connection (placeholders inside the file): books@memory://books',
    );
    expectLine('shop.motto (env SHOP_MOTTO, relaxed name): Read more');
    expectLine('payment.mode (application-dev.properties): sandbox');
    expectLine('support.email (spring.config.import): help@neon.books');
    expectLine('log.level (on-profile=!prod document): DEBUG');
    expectLine('legacy.greeting (@PropertySource via @Import): Hello');
    expectLine('prod.secret (@PropertySource of a prod-only class): null');
    expectLine('gateway (@Profile dev): sandbox charged');
    expectLine('backup (@Qualifier): offline');
    expectLine('DebugToolbar (dev-tools & !prod): true');
    expectLine('Recommendations (condition on property): true');
    expectLine('WeekendSale (@Conditional never): false');
    // The second context with --spring.profiles.active=prod.
    expectLine('log.level (!prod guard): null');
    expectLine('prod.secret: 42');
    expectLine('gateway (@Profile prod): live charged');
    expectLine('DebugToolbar: false');
  });

  test('beans and injection', () {
    expectLine('first page (@Value page-size=2): [Dune, Cosmos]');
    expectLine('retries (Dart default kept): 3');
    expectLine(
      'discount (@Primary composite of the others): best of poetry/loyalty',
    );
    expectLine('price of Leaves of Grass: 6.4');
    expectLine('plugins (no beans: empty list): []');
    expectLine('deliveryTime (Duration from "2d"): 48:00:00.000000');
    expectLine('tags (List from "a,b,c"): [fiction, science, poetry]');
    expectLine('banner (SpEL + placeholder): NEON BOOKS (sandbox)');
    expectLine(
      'motto (optional @Value: null unless SHOP_MOTTO is set): Read more',
    );
    expectLine('clock (setter injection): SystemClock');
    expectLine('prototype ids: [');
    expectLine('lazy pool created yet?: false');
    expectLine('pool open (initMethod connect): true');
    expectLine('search index (@Bean product with @PostConstruct): 3');
    expectLine('@Configurable screen: NEON Books, page 2');
    // lib/resources/ as the classpath.
    expectLine(
      'classpath:templates/welcome.txt (@Value Resource): Dear reader, '
      'welcome to NEON Books — 3 titles are waiting for you.',
    );
    expectLine('classpath:logo.png (binary, embedded): 16 bytes');
  });

  test('lifecycle callbacks run in Spring order', () {
    const order = [
      'probe: constructor',
      'probe: @Autowired setter',
      'probe: setBeanName(probe)',
      'probe: setBeanFactory',
      'probe: setEnvironment',
      'probe: setApplicationContext',
      'probe: @PostConstruct',
      'probe: afterPropertiesSet',
      'probe: initMethod',
      'startup: all singletons instantiated',
      'warehouse: start (phase 0)',
      'courier: start (phase 10)',
      'courier: stop',
      'warehouse: stop',
      'probe: @PreDestroy',
      'probe: DisposableBean.destroy',
      'probe: destroyMethod',
    ];
    var at = 0;
    for (final line in order) {
      final found = output.indexOf(line, at);
      expect(found, greaterThanOrEqualTo(0), reason: '"$line" after #$at');
      at = found;
    }
    // Created lazily after the probe, so destroyed before it.
    expect(
      output.indexOf('pool: close'),
      lessThan(output.indexOf('probe: @PreDestroy')),
    );
  });

  test('extension points', () {
    expectLine(
      'InvoiceService audit trail: [audited by AuditingPostProcessor]',
    );
    expectLine(
      'banner (registered by a registry post-processor): Sale! NEON Books',
    );
    expectLine('salesReport lazy (set by a factory post-processor): true');
    expectLine('salesReport: created on first use');
    expectLine('basket (custom scope): [Dune]');
    expectLine('basket after the scope ended: []');
    expectLine('destruction-aware bpp: invoiceService');
  });

  test('events', () {
    expectLine('vip desk: big order 2');
    expect(
      output.indexOf('vip desk: big order 2'),
      lessThan(output.indexOf('shipping: order 2')),
    );
    expectLine('notifier: order 1 shipped');
    expectLine('lambda listener: order 3');
    expect(output, isNot(contains('lambda listener: order 4')));
  });

  test('messages', () {
    expectLine('ru: Добро пожаловать в NEON Books!');
    expectLine('de_AT (falls back to de): Willkommen bei NEON Books!');
    expectLine('choice 0: Your cart has no books.');
    expectLine('choice 7: Your cart has 7 books.');
    expectLine(
      'messageSource (Spring Boot MessageSourceAutoConfiguration): '
      'package:spring_boot_dart#MessageSourceAutoConfiguration',
    );
  });

  test('SpEL', () {
    expectLine('7 / 2, 7.0 / 2, -7 % 3: [3, 3.5, -1]');
    expectLine('#books.?[price > 10].![title]: [Dune, Cosmos]');
    expectLine('#books.^[price < 10]?.title: Leaves of Grass');
    expectLine('template: Total: 25.0 EUR');
    expectLine('SimpleEvaluationContext: Ada');
  });

  test('validation and data binding', () {
    expectLine('suppressed (disallowedFields): [giftNote]');
    expectLine('quantity: has an invalid value');
    expectLine("(object): e-mails don't match");
    expectLine('name: Please tell us your name');
    expectLine('address.zip: must be 5 digits like [0-9]{5}');
    expectLine('name (ru): Укажите имя');
    expectLine('group OnGift only: [giftNote: must not be blank]');
    expectLine('BeanWrapper address.city: Kyiv');
  });

  test('AOP', () {
    expectLine('slogans (advisor bean): READ MORE BOOKS');
    expectLine('proxy target: DefaultPricingService');
    expectLine('self-invocation through this: timed calls: 0');
    expectLine('self-invocation through @Lazy self: timed calls: 2');
    const order = [
      'audit: before quote[1, 3]',
      'timing: start',
      'timing: end',
      'audit: quote returned 30.0',
      'audit: after quote',
      'audit: failed refunds are closed',
      'audit: async "reserved 2"',
    ];
    var at = 0;
    for (final line in order) {
      final found = output.indexOf(line, at);
      expect(found, greaterThanOrEqualTo(0), reason: line);
      at = found;
    }
  });

  test('hierarchy and startup failures', () {
    expectLine('child bean using a parent bean: hello from the parent context');
    expectLine('event propagated to the parent: [parent heard order 42]');
    expectLine('missing dependency: NoSuchBeanDefinitionException');
    expectLine(
      'cycle: BeanCurrentlyInCreationException: Circular dependency: a -> b -> a.',
    );
  });
}
