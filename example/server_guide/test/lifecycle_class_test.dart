// Chapter 12: every annotation of a test class at work, and the order
// they run in: @BeforeAll before the context, @ContextInitializer at each
// start, @BeforeEach / @AfterEach around each test, @DirtiesContext for a
// new context, @AfterAll after the context is closed.
@TestOn('vm')
library;

import 'package:neon_books_server/src/catalog/book_repository.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/shop/payments.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'spring/lifecycle_class.test.spring.dart';

class FakeGateway implements PaymentGateway {
  @override
  String charge(CustomerOrder order) => 'fake-${order.id}';
}

@SpringBootTest(properties: {'test.inline': 'from @SpringBootTest'})
@ActiveProfiles(['dev', 'test'])
@TestPropertySource(
  properties: {'test.source': 'from @TestPropertySource'},
  locations: ['classpath:lifecycle.properties'],
)
@TestEnvironment({'TEST_FROM_ENV': 'env'})
class LifecycleTest {
  static final events = <String>[];
  static ConfigurableApplicationContext? firstContext;
  static int port = 0;

  @BeforeAll()
  static void startServer() {
    events.add('beforeAll');
    port = 4242; // known only now, read by the dynamic property
  }

  @DynamicPropertySource()
  static void server(DynamicPropertyRegistry registry) =>
      registry.add('test.server-url', () => 'http://localhost:$port');

  @ContextInitializer()
  static void initialize(ConfigurableApplicationContext context) =>
      events.add('initializer');

  // The order of what ran. `dart test --total-shards` (CI) and `--name`
  // run only some of the tests of a file, so the check is about the tests
  // that ran, not a fixed list.
  @AfterAll()
  static void checkOrder() {
    expect(events.take(2), ['beforeAll', 'initializer']);
    const tests = {'first', 'second', 'options'};
    for (var i = 0; i < events.length; i++) {
      if (tests.contains(events[i])) {
        expect(events[i - 1], 'beforeEach', reason: 'before ${events[i]}');
        expect(events[i + 1], 'afterEach', reason: 'after ${events[i]}');
      }
    }
    // @DirtiesContext on `first`: the next test starts a new context.
    final first = events.indexOf('first');
    if (first >= 0 && first + 2 < events.length) {
      expect(events[first + 2], 'initializer');
    }
    // After the context is closed (it is, by the time @AfterAll runs).
    expect(firstContext?.isActive ?? false, isFalse);
  }

  // A type and a name: replaces 'sandbox', registered as PaymentGateway.
  @TestBean(type: PaymentGateway, name: 'sandbox')
  final FakeGateway fake = FakeGateway();

  @Autowired()
  late Checkout checkout;

  @Autowired()
  @Qualifier('offline')
  late PaymentGateway offline;

  @Autowired()
  late LiveGateway? live; // its profile (prod) is not active

  @Autowired()
  late SpringBootTestContext app;

  @Autowired()
  late Environment environment;

  @Value(r'${test.server-url}')
  late String serverUrl;

  @Value(r'${test.missing}')
  late String? missing;

  @BeforeEach()
  void before() => events.add('beforeEach');

  @AfterEach()
  void after() => events.add('afterEach');

  @Test()
  @DirtiesContext()
  void first() {
    events.add('first');
    firstContext = app.context;
    expect(checkout.gateway, same(fake));
    expect(offline, isA<OfflineGateway>());
    expect(live, isNull);
    expect(serverUrl, 'http://localhost:4242');
    expect(missing, isNull);
    expect(environment.getProperty('test.inline'), 'from @SpringBootTest');
    expect(environment.getProperty('test.source'), 'from @TestPropertySource');
    expect(environment.getProperty('test.from-file'), 'yes');
    expect(environment.getProperty('TEST_FROM_ENV'), 'env');
    app.getBean<BookRepository>().delete('9780441013593');
  }

  @Test()
  void second() {
    events.add('second');
    expect(app.context, isNot(same(firstContext)));
    expect(checkout.gateway, same(fake)); // the same fake in the new context
    // A new context: the book removed by `first` is back.
    expect(
      app.getBean<BookRepository>().findByIsbn('9780441013593'),
      isNotNull,
    );
  }

  @Test()
  @Disabled('shows a skipped test')
  void skipped() => fail('skipped tests do not run');

  @Test('options of test()')
  @TestOptions(timeout: Timeout(Duration(seconds: 30)), retry: 1)
  void options() => events.add('options');
}

void main() => runSpringTests();
