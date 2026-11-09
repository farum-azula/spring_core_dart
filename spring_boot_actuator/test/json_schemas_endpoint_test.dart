// The jsonschemas endpoint: the registry's schemas by location, the
// introspected classes' schemas by name, one by a selector, none for an
// unknown name.
import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:test/test.dart';

class Book {
  const Book({required this.title, this.pages});
  final String title;
  final int? pages;
}

final _introspector = BeanIntrospector(
  introspections: [
    BeanIntrospection<Book>(
      className: 'Book',
      properties: [
        BeanProperty<Book>(
          'title',
          typeInfo: const ClassType<String>(),
          get: (b) => b.title,
        ),
        BeanProperty<Book>(
          'pages',
          typeInfo: const ClassType<int>(nullable: true),
          nullable: true,
          get: (b) => b.pages,
        ),
      ],
      constructor: BeanConstructor<Book>(
        parameters: const [
          BeanParameter(
            'title',
            type: ClassType<String>(),
            symbol: #title,
            isRequired: true,
          ),
          BeanParameter(
            'pages',
            type: ClassType<int>(nullable: true),
            symbol: #pages,
          ),
        ],
        create: (_, named) => Book(
          title: named[#title]! as String,
          pages: named[#pages] as int?,
        ),
      ),
    ),
  ],
);

void main() {
  final registry = JsonSchemaRegistry()
    ..add(
      JsonSchema.parse('{"type": "object"}'),
      uri: Uri.parse('resources:schemas/order.json'),
    );
  final endpoint = JsonSchemasEndpoint(
    registry: registry,
    generator: JsonSchemaGenerator(introspector: _introspector),
  );

  test('every schema: the registry by location, the classes by name', () {
    final all = endpoint.schemas();
    expect(all['registry'], {
      'resources:schemas/order.json': {'type': 'object'},
    });
    final book = (all['introspected']! as Map)['Book'] as Map;
    expect(book['title'], 'Book');
    expect(book['required'], ['title']);
  });

  test('one schema by a class name or a location; null for none', () {
    expect(endpoint.schema(['Book'])?['title'], 'Book');
    expect(endpoint.schema(['resources:schemas', 'order.json']), {
      'type': 'object',
    });
    expect(endpoint.schema(['Nothing']), isNull);
  });

  test('without a registry: only the classes', () {
    final bare = JsonSchemasEndpoint(
      generator: JsonSchemaGenerator(introspector: _introspector),
    );
    expect(bare.schemas()['registry'], isEmpty);
  });
}
