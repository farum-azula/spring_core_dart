// Chapter 2, configuration: files and profiles, imports, typed and
// validated properties, @Value, environment variables, conditions,
// @PropertySource, classpath resources and messages.
@TestOn('vm')
library;

import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/orders/mail.dart';
import 'package:neon_books_server/src/shop/clock.dart';
import 'package:neon_books_server/src/shop/payments.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:neon_books_server/src/stock/restock_job.dart';
import 'package:neon_books_server/src/supplier/supplier_stub.dart';
import 'package:neon_books_server/src/support/support_bot.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart';
import 'support/app.dart';

class FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 10, 27, 12);
}

/// The application's modules as an ApplicationContextRunner: no config
/// files unless read (like Spring Boot's `ConfigDataApplicationContext
/// Initializer`), each run a fresh context.
ApplicationContextRunner applicationRunner() {
  var runner = const ApplicationContextRunner()
      .withInitializer(
        ApplicationContextInitializer.of(
          (context) =>
              ConfigDataEnvironment(context.environment).processAndApplySync(),
        ),
      )
      .withPropertyValues(['logging.console.enabled=false']);
  for (final module in springApplication.modules) {
    runner = runner.withUserConfiguration(module);
  }
  for (final module in springApplication.autoConfigurations) {
    runner = runner.withAutoConfiguration(module);
  }
  return runner;
}

void main() {
  group('dev, with a variable and an argument', () {
    final app = neonBooks(
      // Relaxed binding: NEON_SHOP_NAME is neon.shop.name.
      systemEnvironment: {'NEON_SHOP_NAME': 'Night Books'},
    );

    test('profile files and imports', () {
      final environment = app.context.environment;
      // spring.profiles.group.dev=supplier-stub
      expect(environment.activeProfiles, ['dev', 'supplier-stub', 'test']);
      // The second document of application.properties (on-profile !prod).
      expect(
        environment.getProperty('neon.cors.allowed-origin-patterns'),
        startsWith('http://localhost'),
      );
      // application-dev.properties over application.properties.
      expect(environment.getProperty('neon.stock.restock-interval'), '20s');
      // config/supplier-dev.properties, imported with its profile variant.
      expect(
        environment.getProperty('neon.supplier.url'),
        'http://localhost:8080/supplier',
      );
      // test/resources/application-test.properties.
      expect(environment.getProperty('neon.orders.shipping-delay'), '50ms');
    });

    test('@ConfigurationProperties: bound, converted, from the variable', () {
      final shop = app.getBean<ShopProperties>();
      expect(shop.name, 'Night Books'); // the environment variable
      expect(shop.opensAt, 9);
      expect(shop.deliveryTime, const Duration(days: 2)); // "2d"
      expect(shop.maxCoverSize.toBytes(), 512 * 1024); // "512KB"
    });

    test('@Value: placeholders with defaults, conversion', () {
      final catalog = app.getBean<CatalogService>();
      expect(catalog.pageSize, 10); // ${neon.catalog.page-size:10}
    });

    test('@Profile and conditions', () {
      expect(app, hasSingleBean<SupplierStub>()); // @Profile dev
      expect(app, hasSingleBean<RestockJob>()); // @Conditional: key set
      expect(app, hasSingleBean<SupportBot>()); // @ConditionalOnProperty
      expect(app, doesNotHaveBean<LiveGateway>()); // @Profile prod
      // One bean name in two profile configurations, its type inferred
      // from the @Bean method's body.
      expect(app.getBean<MailSender>(), isA<LogMailSender>());
      expect(app.context.getBeanNamesForType(LogMailSender), ['mailSender']);
    });

    test('@PropertySource of the bot, classpath resources, messages', () {
      final environment = app.context.environment;
      expect(environment.getProperty('bot.answers.delivery'), 'bot.delivery');
      final books = app.context.getResource('classpath:data/books.json');
      expect(books.exists(), isTrue);
      expect(
        app.context.getMessage('shop.welcome', args: ['NEON'], locale: 'ja'),
        'NEONへようこそ！',
      );
      expect(
        app.context.getMessage('order.items', args: [3]),
        '3 books', // MessageFormat choice
      );
      // ja_JP falls back to messages_ja.properties.
      expect(
        app.context.getMessage('order.items', args: [1], locale: 'ja_JP'),
        '本1冊',
      );
    });
  });

  group('prod', () {
    final app = neonBooks(profiles: ['prod', 'test']);

    test('YAML profile file, prod beans, no secrets: no restocking', () {
      final environment = app.context.environment;
      expect(environment.getProperty('neon.stock.restock-interval'), '5m');
      expect(environment.getProperty('server.address'), '0.0.0.0');
      expect(app.getBean<Checkout>().gateway, isA<LiveGateway>());
      expect(app.getBean<MailSender>(), isA<SmtpMailSender>());
      // The YAML's value; the !prod document of application.properties
      // does not apply.
      expect(
        environment.getProperty('neon.cors.allowed-origin-patterns'),
        'https://*.neon.books',
      );
      expect(app, doesNotHaveBean<SupplierStub>());
      // SUPPLIER_API_KEY is not set: SupplierConfigured does not match.
      expect(app, doesNotHaveBean<RestockJob>());
    });
  });

  group('conditions, one context per case', () {
    test('@ConditionalOnMissingBean: a Clock of our own wins', () {
      applicationRunner()
          .withPropertyValues(['spring.profiles.active=test'])
          .withBean<Clock>(FixedClock.new, name: 'fixedClock')
          .run((context) {
            expect(context, hasSingleBean<Clock>());
            expect(context.getBean<Clock>(), isA<FixedClock>());
          });
    });

    test('@ConditionalOnProperty: the bot can be switched off', () {
      applicationRunner()
          .withPropertyValues([
            'spring.profiles.active=test',
            'neon.support.bot.enabled=false',
          ])
          .run((context) => expect(context, doesNotHaveBean<SupportBot>()));
    });
  });

  test('invalid properties stop the start with a report', () {
    String reportOf(Map<String, Object?> properties) {
      final lines = <String>[];
      expect(
        () =>
            SpringApplication(
              springApplication.modules,
              autoConfigurations: springApplication.autoConfigurations,
              bannerMode: BannerMode.off,
              out: lines.add,
            ).run(
              const [],
              properties: {'logging.console.enabled': false, ...properties},
            ),
        throwsA(isA<BeanCreationException>()),
      );
      return lines.join('\n');
    }

    expect(
      reportOf({'neon.shop.max-basket-size': 0}),
      contains('neon.shop.max-basket-size: must be greater than or equal to 1'),
    );
    // A cascade (@Valid) into the users: a plain password.
    expect(
      reportOf({'neon.security.users.ada.password': 'ada-secret'}),
      contains('must be a hash with its {id}'),
    );
    // The class-level constraint.
    expect(
      reportOf({'neon.shop.opens-at': 22}),
      contains('neon.shop: the shop must close after it opens'),
    );
  });
}
