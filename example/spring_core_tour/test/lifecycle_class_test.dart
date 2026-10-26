// Every annotation of a test class at work, and the order they run in:
// @BeforeAll before the context, @ContextInitializer at each start,
// @BeforeEach / @AfterEach around each test, @DirtiesContext for a new
// context, @AfterAll after the context is closed.
@TestOn('vm')
library;

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_core_dart_example/src/payments/payments.dart';
import 'package:test/test.dart';

import 'spring/lifecycle_class.test.spring.dart';

class FakeGateway implements PaymentGateway {
  @override
  String charge(double amount) => 'fake $amount';
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
  static var port = 0;

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

  @AfterAll()
  static void checkOrder() {
    expect(firstContext!.isActive, isFalse);
    expect(events, [
      'beforeAll',
      'initializer',
      'beforeEach', 'first', 'afterEach', // then a new context
      'initializer',
      'beforeEach', 'second', 'afterEach',
      'beforeEach', 'options', 'afterEach',
    ]);
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
  }

  @Test()
  void second() {
    events.add('second');
    expect(app.context, isNot(same(firstContext)));
    expect(checkout.gateway, same(fake)); // the same fake in the new context
  }

  @Test()
  @Disabled('shows a skipped test')
  void skipped() => fail('skipped tests do not run');

  @Test('options of test()')
  @TestOptions(timeout: Timeout(Duration(seconds: 30)), retry: 1)
  void options() => events.add('options');
}

void main() => runSpringTests();
