import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/spring_core_dart_example.dart';
import 'package:test/test.dart';

void main() {
  late ConfigurableApplicationContext context;

  setUp(() {
    final environment = StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(
        const MapPropertySource('test', {'pool.size': '2'}),
      );
    context = ApplicationContext.run([exampleBeans], environment: environment);
  });

  tearDown(() => context.close());

  test('primary constructor with @Value', () {
    expect(context.getBean<InventorySettings>().capacity, 2);
    expect(context.getBean<SkuFormat>().format('ab'), 'AB');
  });

  test('new(...) constructor with a private named parameter, proxied', () {
    final inventory = context.getBean<Inventory>();
    expect(inventory, isA<Advised>());
    expect(inventory.add('a-1'), isTrue);
    expect(inventory.add('b-2'), isTrue);
    expect(inventory.add('c-3'), isFalse, reason: 'capacity from config');
    expect(inventory.items, ['A-1', 'B-2']);
    expect(context.getBean<CountingAspect>().calls, 3);
  });

  test('@Autowired factory constructor', () {
    final report = context.getBean<InventoryReport>();
    context.getBean<Inventory>().add('x');
    expect(report.summary(), '1 items');
  });

  test('configuration class with a primary constructor', () {
    expect(context.getBean<int>(qualifier: 'reorderLevel'), 1);
  });

  test('validation of primary constructor properties', () {
    final introspector = context.getBean<BeanIntrospector>();
    final validator = BeanValidator(introspector: introspector);
    final violations = validator.validateObject(StockForm('', quantity: 0));
    expect(
      violations.map((v) => v.propertyPath),
      unorderedEquals(['sku', 'quantity']),
    );
    final binder = DataBinder(
      StockForm('x'),
      objectName: 'stock',
      introspector: introspector,
    )..bind({'quantity': '5'});
    expect((binder.target as StockForm).quantity, 5);
  });
}
