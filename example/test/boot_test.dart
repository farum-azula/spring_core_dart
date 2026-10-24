// The shop started the Spring Boot way (bin/shop.dart + generated
// bin/shop.spring.dart), tested with spring_boot_starter_test.
@TestOn('vm')
library;

import 'dart:io';

import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_core_dart_example/src/boot/shop_properties.dart';
import 'package:spring_core_dart_example/src/payments/payments.dart';
import 'package:test/test.dart';

import '../bin/shop.spring.dart';

class FakeGateway implements PaymentGateway {
  final charged = <double>[];

  @override
  String charge(double amount) {
    charged.add(amount);
    return 'fake charged $amount';
  }
}

void main() {
  final logs = captureLogs();
  final gateway = FakeGateway();

  // Like @SpringBootTest: the whole application, once for this file.
  final app = springBootTest(
    springApplication,
    args: ['--shop.name=Night Books'],
    // Like @ActiveProfiles (replaces spring.profiles.active=dev): adds
    // test/resources/application-test.properties (quiet console, own file).
    profiles: ['dev', 'test'],
    systemEnvironment: {'SHOP_MAX_BASKET_SIZE': '25'},
    // Like @MockitoBean: replaces the dev profile's 'sandbox' gateway.
    overrides: [BeanOverride<PaymentGateway>(gateway, name: 'sandbox')],
  );

  test('@ConfigurationProperties from file, command line and environment', () {
    final properties = app.getBean<ShopProperties>();
    expect(properties.name, 'Night Books'); // command line
    expect(properties.openingHours, '9-21'); // application.properties
    expect(properties.deliveryTime, const Duration(days: 2));
    expect(properties.maxBasketSize, 25); // SHOP_MAX_BASKET_SIZE
    expect(app.output, isEmpty); // no failure report
    // Discovered from spring_boot_dart's lib/spring_auto_configuration.dart.
    expect(
      app.context.getMessage('greeting', args: ['NEON'], locale: 'ru'),
      'Добро пожаловать в NEON!',
    );
  });

  test('the runner paid through the fake gateway', () {
    expect(gateway.charged, [12.5]);
    expect(app.getBean<Checkout>().gateway, same(gateway));
  });

  test('the logging starter was discovered and keeps a log buffer', () {
    expect(app, hasSingleBean<LoggingSystem>());
    final records = app.getBean<LogBuffer>().query(
      const LogQuery(logger: 'neon.checkout'),
    );
    expect(records.map((r) => r.message), [
      'paid 12.5',
      'gateway answered: fake charged 12.5', // logging.level.neon=debug
    ]);
    expect(records.first.fields, {'order': 1, 'gateway': FakeGateway});
  });

  test('logging.file.name: the log file is written', () async {
    final file = LoggingSystem.instance.file!;
    expect(file.path, 'build/logs/neon-books-test.log'); // test profile
    file.flush();
    // Spring Boot's file pattern.
    expect(
      File(file.path).readAsStringSync(),
      matches(
        RegExp(
          r' INFO \d+ --- \[neon-books\] \[[^\]]+\] neon\.checkout {28}: '
          r'paid 12\.5 \{order=1, gateway=FakeGateway\}',
        ),
      ),
    );
  });

  test('logs written during a test are captured', () {
    app.getBean<Checkout>().pay(3);
    expect(logs.messages, ['paid 3.0', 'gateway answered: fake charged 3.0']);
  });

  test('invalid configuration fails with a report', () {
    final lines = <String>[];
    expect(
      () => SpringApplication(
        springApplication.modules,
        autoConfigurations: springApplication.autoConfigurations,
        out: lines.add,
      ).run(['--shop.name='], properties: {'logging.enabled': false}),
      throwsA(isA<BeanCreationException>()),
    );
    expect(lines.join('\n'), contains('shop.name: must not be blank'));
  });
}
