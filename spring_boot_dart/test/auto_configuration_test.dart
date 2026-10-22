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
    expect(context.getBean<MessageSource>(), isA<PropertiesMessageSource>());
    context.close();
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

    test('defaults, and backs off for an application ObjectMapper', () {
      final defaults = run([app], []);
      final mapper = defaults.getBean<ObjectMapper>();
      expect(mapper.namingStrategy, PropertyNamingStrategy.lowerCamelCase);
      expect(mapper.failOnUnknownProperties, isFalse);
      expect(
        mapper.writeValueAsString(const Order(orderId: 1)),
        '{"orderId":1,"note":null}',
      );
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
