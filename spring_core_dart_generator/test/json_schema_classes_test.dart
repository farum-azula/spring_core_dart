// The classes of spring.json.schemas: the entries of the configuration, a
// schema's classes, enums, nullability, constraints and $refs, and the code
// compiled and run: the ObjectMapper reads and writes them, and rejects a
// JSON that breaks the schema.
import 'dart:convert';
import 'dart:io';

import 'package:spring_core_dart_generator/src/json_schema_classes.dart';
import 'package:test/test.dart';

const _order = r'''
{
  "title": "Order",
  "description": "An order of the shop.",
  "type": "object",
  "required": ["id", "customer_email", "items"],
  "properties": {
    "id": {"type": "string", "pattern": "^ORD-[0-9]+$"},
    "customer_email": {"type": "string", "format": "email"},
    "status": {"enum": ["NEW", "IN_PROGRESS"]},
    "placed": {"type": "string", "format": "date-time"},
    "items": {"type": "array", "minItems": 1,
              "items": {"$ref": "#/$defs/OrderLine"}},
    "note": {"type": ["string", "null"], "maxLength": 200},
    "tags": {"type": "object", "additionalProperties": {"type": "integer"}},
    "extra": {"oneOf": [{"type": "string"}, {"type": "integer"}]}
  },
  "$defs": {
    "OrderLine": {
      "type": "object",
      "required": ["sku", "qty"],
      "properties": {
        "sku": {"type": "string"},
        "qty": {"type": "integer", "minimum": 1},
        "price": {"type": "number", "exclusiveMinimum": 0}
      }
    }
  }
}
''';

LoadedJsonSchema _schema(String text, {String prefix = ''}) => (
  entry: (
    location: 'resources:schemas/order.json',
    sha256: null,
    prefix: prefix,
    name: null,
  ),
  text: text,
  document: jsonDecode(text) as Map<String, Object?>,
  resource: 'schemas/order.json',
);

const _written =
    '{"customer_email":"a@b.dev","id":"ORD-1",'
    '"items":[{"qty":2,"sku":"x"}],"status":"IN_PROGRESS",'
    '"tags":{"a":1}}';

void main() {
  test('the entries of spring.json.schemas', () {
    final entries = JsonSchemaClasses.entries({
      'application.yml': '''
spring:
  json:
    schemas:
      - location: resources:schemas/order.json
      - location: github:acme/contracts/invoice.json@v2
        sha256: ABC
        prefix: Api
        name: Invoice
''',
    });
    expect(entries, [
      (
        location: 'resources:schemas/order.json',
        sha256: null,
        prefix: '',
        name: null,
      ),
      (
        location: 'github:acme/contracts/invoice.json@v2',
        sha256: 'abc',
        prefix: 'Api',
        name: 'Invoice',
      ),
    ]);
    expect(JsonSchemaClasses.entries({'application.yml': 'a: 1'}), isEmpty);
  });

  test('classes, an enum, nullability, constraints and names', () {
    final code = JsonSchemaClasses.code([_schema(_order)], report: false)!;
    expect(
      code,
      contains("@_sj.JsonSchemaSource(r'resources:schemas/order.json')"),
    );
    expect(code, contains('class Order {'));
    expect(code, contains('class OrderLine {'));
    expect(code, contains('enum OrderStatus {'));
    expect(code, contains('required this.id,'));
    expect(code, contains('final String id;'));
    expect(code, contains('final String? note;'));
    expect(code, contains('final DateTime? placed;'));
    expect(code, contains('final List<OrderLine> items;'));
    expect(code, contains('final Map<String, int>? tags;'));
    // oneOf of two kinds: any JSON value.
    expect(code, contains('final Object? extra;'));
    expect(code, contains("@_sj.JsonProperty(r'customer_email')"));
    expect(code, contains('final String customerEmail;'));
    expect(code, contains(r"@_sj.Matches(r'^ORD-[0-9]+$')"));
    expect(code, contains('@_sj.Email()'));
    expect(code, contains('@_sj.Size(min: 1)'));
    expect(code, contains('@_sj.Size(max: 200)'));
    expect(code, contains('@_sj.Min(1)'));
    expect(code, contains("@_sj.DecimalMin('0', inclusive: false)"));
    expect(code, contains('/// An order of the shop.'));
  });

  test('a prefix names every class', () {
    final code = JsonSchemaClasses.code(
      [_schema(_order, prefix: 'Api')],
      report: false,
    )!;
    expect(code, contains('class ApiOrder {'));
    expect(code, contains('class ApiOrderLine {'));
    expect(code, contains('enum ApiOrderStatus {'));
  });

  test(
    'the code compiles; the mapper reads, writes and checks it',
    () async {
      final code = JsonSchemaClasses.code([_schema(_order)], report: false)!;
      final dir = Directory('.dart_tool/json_schema_classes_test')
        ..createSync(recursive: true);
      final program = File('${dir.path}/main.dart')
        ..writeAsStringSync('''
// ignore_for_file: type=lint
import 'package:spring_core_dart/spring_core_dart.dart' as _sj;
import 'package:spring_core_dart/spring_core_dart.dart' hide Order;

$code

void main() {
  BeanIntrospector.shared.registerAll(_\$jsonSchemaIntrospections);
  final schema = JsonSchema.parse(r\'\'\'$_order\'\'\');
  final mapper = JsonMapper(schemaResolver: (_) => schema);
  final order = mapper.readValue<Order>(
    '{"id": "ORD-1", "customer_email": "a@b.dev", "status": "IN_PROGRESS", '
    '"items": [{"sku": "x", "qty": 2}], "tags": {"a": 1}}',
  );
  print(order.status);
  print(order.items.single.qty);
  print(mapper.writeValueAsString(order));
  try {
    mapper.readValue<Order>('{"id": "1", "customer_email": "a@b.dev", "items": []}');
  } on JsonSchemaValidationException catch (e) {
    print(e.violations.map((v) => v.path).join(','));
  }
}
''');
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        program.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}${result.stdout}');
      final lines = const LineSplitter()
          .convert('${result.stdout}')
          .where((l) => !l.startsWith('Running build hooks'))
          .toList();
      expect(lines, [
        'OrderStatus.inProgress',
        '2',
        _written,
        '/id,/items',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
