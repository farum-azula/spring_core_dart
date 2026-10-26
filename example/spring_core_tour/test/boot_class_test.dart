// boot_test.dart written as a test class, the way Spring writes tests:
// annotations on a class, beans in fields, one method per test. The
// generator turns it into spring/boot_class.test.spring.dart (runSpringTests).
@TestOn('vm')
library;

import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_core_dart_example/src/boot/shop_properties.dart';
import 'package:spring_core_dart_example/src/payments/payments.dart';
import 'package:test/test.dart';

import 'spring/boot_class.test.spring.dart';

class FakeGateway implements PaymentGateway {
  final charged = <double>[];

  @override
  String charge(double amount) {
    charged.add(amount);
    return 'fake charged $amount';
  }
}

@SpringBootTest(args: ['--shop.name=Night Books'])
@ActiveProfiles(['dev', 'test'])
@TestEnvironment({'SHOP_MAX_BASKET_SIZE': '25'})
class BootTest {
  // Replaces the dev profile's 'sandbox' gateway (keeping its types).
  @TestBean(name: 'sandbox')
  final gateway = FakeGateway();

  @Autowired()
  late ShopProperties properties;

  @Autowired()
  late Checkout checkout;

  @Autowired()
  late LogBuffer logBuffer;

  @Autowired()
  late List<PaymentGateway> gateways;

  @Autowired()
  late ApplicationContext context;

  @Value(r'${shop.opening-hours}')
  late String openingHours;

  @Value(r'${shop.unknown:none}')
  late String unknown;

  @CapturedOutput()
  late CapturedLogs logs;

  @Test('@ConfigurationProperties from file, command line and environment')
  void boundProperties() {
    expect(properties.name, 'Night Books'); // command line
    expect(properties.openingHours, '9-21'); // application.properties
    expect(properties.maxBasketSize, 25); // SHOP_MAX_BASKET_SIZE
    expect(openingHours, '9-21'); // @Value
    expect(unknown, 'none');
  }

  @Test()
  void theRunnerPaidThroughTheFakeGateway() {
    expect(gateway.charged, [12.5]);
    expect(checkout.gateway, same(gateway));
    expect(gateways, contains(same(gateway)));
    expect(context, hasSingleBean<LoggingSystem>());
  }

  @Test()
  @DisplayName('logs written during a test are captured')
  void capturedLogs() {
    checkout.pay(3);
    expect(logs.messages, ['paid 3.0', 'gateway answered: fake charged 3.0']);
  }

  @Nested('after a payment')
  final afterAPayment = AfterAPayment();
}

class AfterAPayment {
  @Autowired()
  late Checkout checkout;

  @Autowired()
  late LogBuffer logBuffer;

  @BeforeEach()
  void pay() => checkout.pay(7);

  @Test()
  @Tag('logs')
  void theLogBufferHasIt() {
    final records = logBuffer.query(const LogQuery(logger: 'neon.checkout'));
    expect(records.map((r) => r.message), contains('paid 7.0'));
  }
}

void main() => runSpringTests();
