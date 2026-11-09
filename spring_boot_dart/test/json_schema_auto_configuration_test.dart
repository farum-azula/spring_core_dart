// JsonSchemaAutoConfiguration: the jsonSchemaRegistry bean filled from
// spring.json.schemas, @JsonSchemaSource and JsonSchema beans; an app's own
// registry wins and is filled too; schemas-registry.properties=false; the
// ObjectMapper checking a @JsonSchemaSource class; no warning for the keys.
import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

@JsonSchemaSource('resources:schemas/line.json')
class Line {
  const Line({required this.sku, required this.qty});
  final String sku;
  final int qty;
}

final _lineIntrospection = BeanIntrospection<Line>(
  className: 'Line',
  annotations: const [JsonSchemaSource('resources:schemas/line.json')],
  properties: [
    BeanProperty<Line>(
      'sku',
      typeInfo: const ClassType<String>(),
      get: (b) => b.sku,
    ),
    BeanProperty<Line>(
      'qty',
      typeInfo: const ClassType<int>(),
      get: (b) => b.qty,
    ),
  ],
  constructor: BeanConstructor<Line>(
    parameters: const [
      BeanParameter(
        'sku',
        type: ClassType<String>(),
        symbol: #sku,
        isRequired: true,
      ),
      BeanParameter(
        'qty',
        type: ClassType<int>(),
        symbol: #qty,
        isRequired: true,
      ),
    ],
    create: (_, named) =>
        Line(sku: named[#sku]! as String, qty: named[#qty]! as int),
  ),
);

const _order =
    '{"type": "object", "required": ["id"], '
    '"properties": {"id": {"type": "string"}}}';
const _line =
    '{"type": "object", "required": ["sku", "qty"], '
    '"properties": {"sku": {"type": "string"}, '
    '"qty": {"type": "integer", "minimum": 1}}}';
const _user = '{"type": "object", "properties": {"name": {"type": "string"}}}';

void main() {
  final logs = <String>[];
  late void Function() stop;
  setUp(() {
    logs.clear();
    stop = SpringLog.listen((record) => logs.add(record.message));
  });
  tearDown(() => stop());

  ConfigurableApplicationContext run({
    String properties = '',
    List<BeanDefinition<Object>> beans = const [],
  }) => SpringApplication(
    [
      BeanModule(
        'app',
        beans,
        resources: {
          'application.properties': EmbeddedResource.text(
            'spring.json.schemas[0].location=resources:schemas/order.json\n'
            'spring.json.schemas[1].location='
            'https://example.com/schemas/user.json\n'
            'spring.json.schemas[1].sha256=abc\n'
            'spring.json.schemas[1].prefix=Api\n'
            '$properties',
          ),
          'schemas/order.json': const EmbeddedResource.text(_order),
          'schemas/line.json': const EmbeddedResource.text(_line),
          // The build's copy of the remote schema.
          'json-schemas/example.com/schemas/user.json':
              const EmbeddedResource.text(_user),
        },
        introspections: [_lineIntrospection],
      ),
    ],
    autoConfigurations: [springBootAutoConfiguration],
    out: (_) {},
  ).run(const [], systemEnvironment: const {});

  test('the registry has the schemas of the properties and annotations', () {
    final context = run();
    addTearDown(context.close);
    final registry = context.getBean<JsonSchemaRegistry>();
    expect(
      [for (final uri in registry.schemas.keys) '$uri'],
      unorderedEquals([
        'resources:schemas/order.json',
        'https://example.com/schemas/user.json',
        'resources:schemas/line.json',
      ]),
    );
    expect(
      registry.resolve(Uri.parse('https://example.com/schemas/user.json')),
      isNotNull,
    );
    // The keys of spring.json.schemas are no unknown spring.json.* keys.
    expect(logs.where((m) => m.contains('unsupported property')), isEmpty);
  });

  test('the ObjectMapper checks a @JsonSchemaSource class', () {
    final context = run();
    addTearDown(context.close);
    final mapper = context.getBean<ObjectMapper>();
    expect(mapper.readValue<Line>('{"sku": "x", "qty": 2}').qty, 2);
    expect(
      () => mapper.readValue<Line>('{"sku": "x", "qty": 0}'),
      throwsA(
        isA<JsonSchemaValidationException>().having(
          (e) => e.violations.single.path,
          'path',
          '/qty',
        ),
      ),
    );
  });

  test("the app's own registry wins and gets the schemas too", () {
    final own = JsonSchemaRegistry();
    final context = run(
      beans: [
        BeanDefinition<JsonSchemaRegistry>(
          name: 'ownRegistry',
          create: (_) => own,
        ),
        BeanDefinition<JsonSchema>(
          name: 'partner',
          create: (_) => JsonSchema.parse(
            r'{"$id": "https://partner.dev/a.json", "type": "string"}',
          ),
        ),
        BeanDefinition<JsonSchemaRegistryCustomizer>(
          name: 'extra',
          create: (_) => JsonSchemaRegistryCustomizer.of(
            (registry) => registry.add(
              JsonSchema.parse('{"type": "integer"}'),
              uri: Uri.parse('urn:extra'),
            ),
          ),
        ),
      ],
    );
    addTearDown(context.close);
    expect(context.containsBean('jsonSchemaRegistry'), isFalse);
    expect(identical(context.getBean<JsonSchemaRegistry>(), own), isTrue);
    expect(
      [for (final uri in own.schemas.keys) '$uri'],
      containsAll([
        'resources:schemas/order.json',
        'https://partner.dev/a.json',
        'urn:extra',
      ]),
    );
  });

  test('schemas-registry.properties=false leaves them out', () {
    final context = run(
      properties: 'spring.json.schemas-registry.properties=false\n',
    );
    addTearDown(context.close);
    expect(context.getBean<JsonSchemaRegistry>().schemas, isEmpty);
    // Nothing to check against: the mapper reads as before.
    expect(
      context.getBean<ObjectMapper>().readValue<Line>(
        '{"sku": "x", "qty": 0}',
      ),
      isA<Line>(),
    );
  });

  test('the customizers run in their order, once', () {
    final calls = <String>[];
    final context = run(
      beans: [
        BeanDefinition<_Ordered>(
          name: 'late',
          types: const [_Ordered, JsonSchemaRegistryCustomizer, Ordered],
          create: (_) => _Ordered('late', 10, calls),
        ),
        BeanDefinition<_Ordered>(
          name: 'early',
          types: const [_Ordered, JsonSchemaRegistryCustomizer, Ordered],
          create: (_) => _Ordered('early', -10, calls),
        ),
      ],
    );
    addTearDown(context.close);
    context
      ..getBean<JsonSchemaRegistry>()
      ..getBean<ObjectMapper>();
    expect(calls, ['early', 'late']);
  });
}

final class _Ordered implements JsonSchemaRegistryCustomizer, Ordered {
  _Ordered(this.name, this.order, this.calls);

  final String name;
  @override
  final int order;
  final List<String> calls;

  @override
  void customize(JsonSchemaRegistry registry) => calls.add(name);
}
