import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class MyMessages extends StaticMessageSource {}

class Order {
  const Order({required this.orderId, this.note});
  final int orderId;
  final String? note;
}

final class OrderIdSerializer extends JsonSerializer<Uri> {
  const OrderIdSerializer();
  @override
  Object? serialize(Uri value, ObjectMapper mapper) => 'uri:$value';
}

class Money {
  const Money(this.cents);
  final int cents;
}

final class MoneySerializer extends JsonSerializer<Money> {
  const MoneySerializer();
  @override
  Object? serialize(Money value, ObjectMapper mapper) => '${value.cents}c';
}

final class MoneyDeserializer extends JsonDeserializer<Money> {
  const MoneyDeserializer();
  @override
  Money deserialize(Object json, ObjectMapper mapper) =>
      Money(int.parse((json as String).replaceAll('c', '')));
}

final _orderIntrospection = BeanIntrospection<Order>(
  properties: [
    BeanProperty<Order>(
      'orderId',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.orderId,
    ),
    BeanProperty<Order>(
      'note',
      type: String,
      nullable: true,
      typeInfo: const ClassType<String>(nullable: true),
      get: (b) => b.note,
    ),
  ],
  constructor: BeanConstructor<Order>(
    parameters: const [
      BeanParameter(
        'orderId',
        type: ClassType<int>(),
        symbol: #orderId,
        isRequired: true,
      ),
      BeanParameter(
        'note',
        type: ClassType<String>(nullable: true),
        symbol: #note,
      ),
    ],
    create: (positional, named) =>
        Function.apply(Order.new, positional, named) as Order,
  ),
);

void main() {
  ClasspathResources.registerAll(const {
    'i18n/messages.properties': EmbeddedResource.text('hello=Hello {0}'),
    'i18n/messages_ru.properties': EmbeddedResource.text('hello=Привет {0}'),
  });

  ConfigurableApplicationContext run(
    List<BeanModule> modules,
    List<String> args,
  ) => SpringApplication(
    modules,
    autoConfigurations: [springBootAutoConfiguration],
    out: (_) {},
  ).run(args, systemEnvironment: const {});

  test('MessageSourceAutoConfiguration reads spring.messages.basename', () {
    final context = run([], ['--spring.messages.basename=i18n/messages']);
    expect(context.getMessage('hello', args: ['Ada']), 'Hello Ada');
    expect(
      context.getMessage('hello', args: ['Ada'], locale: 'ru'),
      'Привет Ada',
    );
    expect(
      context.getBean<MessageSource>(),
      isA<ReloadableResourceBundleMessageSource>()
          .having((s) => s.cacheSeconds, 'cacheSeconds', -1)
          .having((s) => s.fallbackToSystemLocale, 'fallback', isTrue),
    );
    context.close();
  });

  test('spring.messages cache-duration and fallback-to-system-locale', () {
    final context = run([], [
      '--spring.messages.basename=i18n/messages',
      '--spring.messages.cache-duration=10',
      '--spring.messages.fallback-to-system-locale=false',
    ]);
    final source =
        context.getBean<MessageSource>()
            as ReloadableResourceBundleMessageSource;
    expect(source.cacheSeconds, 10);
    expect(source.fallbackToSystemLocale, isFalse);
    context.close();
    final minutes = run([], [
      '--spring.messages.basename=i18n/messages',
      '--spring.messages.cache-duration=2m',
    ]);
    expect(
      (minutes.getBean<MessageSource>()
              as ReloadableResourceBundleMessageSource)
          .cacheSeconds,
      120,
    );
    minutes.close();
  });

  test('the context id is spring.application.name, else application', () {
    final named = run([], ['--spring.application.name=shop']);
    expect(named.id, 'shop');
    named.close();
    final plain = run([], []);
    expect(plain.id, 'application');
    plain.close();
  });

  test('dotted basenames are paths, like Boot', () {
    final context = run([], ['--spring.messages.basename=i18n.messages']);
    expect(context.getMessage('hello', args: ['Ada']), 'Hello Ada');
    context.close();
  });

  group('ValidationAutoConfiguration', () {
    test('defaultValidator and methodValidationPostProcessor', () {
      final context = run([], []);
      expect(context.getBeanByName('defaultValidator'), isA<BeanValidator>());
      expect(context.getBean<Validator>(), isA<BeanValidator>());
      final processor = context.getBean<MethodValidationPostProcessor>();
      expect(processor.excludeFilters.single(const [Validated()]), isFalse);
      expect(
        processor.excludeFilters.single(const [
          ConfigurationProperties('db'),
          Validated(),
        ]),
        isTrue,
        reason: '@ConfigurationProperties beans are not proxied',
      );
      context.close();
    });

    test('backs off for an application Validator', () {
      final mine = BeanValidator();
      final context = run([
        BeanModule('app', [
          BeanDefinition<BeanValidator>(
            name: 'myValidator',
            types: const [BeanValidator, Validator],
            create: (_) => mine,
          ),
        ]),
      ], []);
      expect(context.containsBean('defaultValidator'), isFalse);
      expect(context.getBean<Validator>(), same(mine));
      expect(
        context.getBean<MethodValidationPostProcessor>().advice.validator,
        same(mine),
      );
      context.close();
    });
  });

  test('backs off without a bundle or with an application messageSource', () {
    final none = run([], ['--spring.messages.basename=missing']);
    // The context's own empty DelegatingMessageSource.
    expect(none.getBeanByName('messageSource'), isA<DelegatingMessageSource>());
    none.close();

    final custom = run(
      [
        BeanModule('app', [
          BeanDefinition<MyMessages>(
            name: 'messageSource',
            types: const [MyMessages, MessageSource],
            create: (_) => MyMessages(),
          ),
        ]),
      ],
      ['--spring.messages.basename=i18n/messages'],
    );
    expect(custom.getBeanByName('messageSource'), isA<MyMessages>());
    custom.close();
  });

  group('JacksonAutoConfiguration', () {
    final app = BeanModule(
      'app',
      [
        BeanDefinition<JsonModule>(
          name: 'uriModule',
          create: (_) => const JsonModule(serializers: [OrderIdSerializer()]),
        ),
      ],
      introspections: [_orderIntrospection],
    );

    test('an ObjectMapper from spring.jackson.* with the app classes', () {
      final context = run(
        [app],
        [
          '--spring.jackson.property-naming-strategy=SNAKE_CASE',
          '--spring.jackson.default-property-inclusion=non_null',
          '--spring.jackson.deserialization.fail-on-unknown-properties=true',
        ],
      );
      final mapper = context.getBean<ObjectMapper>();
      expect(
        mapper.writeValueAsString(const Order(orderId: 7)),
        '{"order_id":7}',
      );
      expect(mapper.readValue<Order>('{"order_id":8,"note":"x"}').note, 'x');
      expect(
        () => mapper.readValue<Order>('{"order_id":8,"extra":1}'),
        throwsA(isA<JsonMappingException>()),
      );
      // JsonModule beans are added.
      expect(mapper.writeValueAsString(Uri.parse('a')), '"uri:a"');
      context.close();
    });

    test('JsonSerializer / JsonDeserializer beans (@JsonComponent)', () {
      final context = run([
        BeanModule('json', [
          // The types the generator lists for these beans.
          BeanDefinition<MoneySerializer>(
            name: 'moneySerializer',
            types: const [
              MoneySerializer,
              JsonSerializer<Money>,
              JsonSerializer<Object>,
            ],
            create: (_) => const MoneySerializer(),
          ),
          BeanDefinition<MoneyDeserializer>(
            name: 'moneyDeserializer',
            types: const [
              MoneyDeserializer,
              JsonDeserializer<Money>,
              JsonDeserializer<Object>,
            ],
            create: (_) => const MoneyDeserializer(),
          ),
        ]),
      ], []);
      final mapper = context.getBean<ObjectMapper>();
      expect(mapper.writeValueAsString(const Money(250)), '"250c"');
      expect(mapper.readValue<Money>('"99c"').cents, 99);
      context.close();
    });

    test('spring.jackson.time-zone', () {
      final context = run([app], ['--spring.jackson.time-zone=+02:00']);
      final mapper = context.getBean<ObjectMapper>();
      expect(mapper.timeZone, '+02:00');
      expect(
        mapper.writeValueAsString(DateTime.utc(2026, 1, 1, 10)),
        '"2026-01-01T12:00:00.000+02:00"',
      );
      context.close();
    });

    test('spring.jackson.mapper.sort-properties-alphabetically=false', () {
      final context = run(
        [app],
        ['--spring.jackson.mapper.sort-properties-alphabetically=false'],
      );
      final mapper = context.getBean<ObjectMapper>();
      expect(mapper.sortPropertiesAlphabetically, isFalse);
      expect(
        mapper.writeValueAsString(const Order(orderId: 1)),
        '{"orderId":1,"note":null}',
      );
      context.close();
    });

    test('defaults, and backs off for an application ObjectMapper', () {
      final defaults = run([app], []);
      final mapper = defaults.getBean<ObjectMapper>();
      expect(mapper.namingStrategy, PropertyNamingStrategy.lowerCamelCase);
      expect(mapper.failOnUnknownProperties, isFalse);
      expect(
        mapper.writeValueAsString(const Order(orderId: 1)),
        '{"note":null,"orderId":1}',
      );
      expect(mapper.sortPropertiesAlphabetically, isTrue);
      defaults.close();

      final own = ObjectMapper(indentOutput: true);
      final custom = run([
        BeanModule('own', [
          BeanDefinition<ObjectMapper>(name: 'myMapper', create: (_) => own),
        ]),
      ], []);
      expect(custom.getBean<ObjectMapper>(), same(own));
      custom.close();
    });
  });
}
