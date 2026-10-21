// The shop started the Spring Boot way (bin/shop.dart + generated
// bin/shop.beans.dart).
@TestOn('vm')
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_core_dart_example/src/boot/shop_properties.dart';
import 'package:test/test.dart';

import '../bin/shop.beans.dart';

void main() {
  final lines = <String>[];
  setUp(lines.clear);

  // Same as the generated springApplication (with the discovered
  // auto-configuration), but capturing its output.
  ConfigurableApplicationContext start(List<String> args) => SpringApplication(
    [$application],
    autoConfigurations: springApplication.autoConfigurations,
    out: lines.add,
  ).run(args, systemEnvironment: const {'SHOP_MAX_BASKET_SIZE': '25'});

  test('@ConfigurationProperties from file, command line and environment', () {
    final context = start(['--shop.name=Night Books']);
    final properties = context.getBean<ShopProperties>();
    expect(properties.name, 'Night Books'); // command line
    expect(properties.openingHours, '9-21'); // application.properties
    expect(properties.deliveryTime, const Duration(days: 2));
    expect(properties.maxBasketSize, 25); // SHOP_MAX_BASKET_SIZE
    expect(lines.last, startsWith('Started neon-books in '));
    // Discovered from spring_boot_dart's lib/spring_auto_configuration.dart.
    expect(
      context.getMessage('greeting', args: ['NEON'], locale: 'ru'),
      'Добро пожаловать в NEON!',
    );
    context.close();
  });

  test('invalid configuration fails with a report', () {
    expect(
      () => start(['--shop.name=']),
      throwsA(isA<BeanCreationException>()),
    );
    expect(lines.join('\n'), contains('shop.name: must not be blank'));
  });
}
