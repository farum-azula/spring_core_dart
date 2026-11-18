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

const _invoice =
    '{"title": "Invoice", "type": "object", "required": ["customer"], '
    r'"properties": {"customer": {"$ref": "resources:customer.json"}}}';

const _employee =
    r'{"title": "Employee", "allOf": [{"$ref": "#/$defs/Person"}, '
    '{"type": "object", "required": ["salary"], '
    '"properties": {"salary": {"type": "integer"}}}], '
    r'"$defs": {"Person": {"type": "object", "required": ["name"], '
    '"properties": {"name": {"type": "string"}}}}}';

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
  group('cases', () {
    LoadedJsonSchema at(String location, String text) => (
      entry: (location: location, sha256: null, prefix: '', name: null),
      text: text,
      document: jsonDecode(text) as Map<String, Object?>,
      resource: '',
    );

    test(r'a $ref to another listed schema is its class', () {
      final code = JsonSchemaClasses.code([
        at(
          'resources:invoice.json',
          _invoice,
        ),
        at(
          'resources:customer.json',
          '{"title": "Customer", "type": "object", '
              '"properties": {"name": {"type": "string"}}}',
        ),
      ], report: false)!;
      expect(code, contains('final Customer customer;'));
      // One class per schema, not one per use.
      expect('class Customer {'.allMatches(code), hasLength(1));
    });

    test('allOf of objects: their properties together', () {
      final code = JsonSchemaClasses.code([
        at(
          'resources:a.json',
          _employee,
        ),
      ], report: false)!;
      expect(code, contains('class Employee {'));
      expect(code, contains('final String name;'));
      expect(code, contains('final int salary;'));
    });

    test('a list of an enum; Dart keywords as names', () {
      final code = JsonSchemaClasses.code([
        at(
          'resources:a.json',
          '{"title": "Shape", "type": "object", "properties": { '
              '"tags": {"type": "array", "items": '
              '{"enum": ["red", "the-blue", "class"]}}, '
              '"class": {"type": "string"}, '
              '"default": {"type": "integer"}}}',
        ),
      ], report: false)!;
      expect(code, contains('final List<ShapeTagsItem>? tags;'));
      expect(code, contains('enum ShapeTagsItem {'));
      expect(code, contains('theBlue,'));
      // A keyword is no Dart name: a suffix, the JSON name kept.
      expect(code, contains('valueClass,'));
      expect(code, contains('final String? classValue;'));
      expect(code, contains("@_sj.JsonProperty(r'class')"));
      expect(code, contains('final int? defaultValue;'));
    });

    test('names of types and of members of an enum get a suffix', () {
      final code = JsonSchemaClasses.code([
        at(
          'resources:a.json',
          '{"title": "Cell", "type": "object", "properties": { '
              '"int": {"type": "integer"}, "bool": {"type": "boolean"}, '
              '"kind": {"enum": ["index", "name", "values", "plain"]}}}',
        ),
      ], report: false)!;
      expect(code, contains('final int? intValue;'));
      expect(code, contains('final bool? boolValue;'));
      expect(code, contains('valueIndex,'));
      expect(code, contains('valueName,'));
      expect(code, contains('valueValues,'));
      expect(code, contains('plain,'));
    });

    test('a value with a line break of either kind stays text', () {
      for (final lineBreak in [r'\n', r'\r']) {
        final code = JsonSchemaClasses.code([
          at(
            'resources:a.json',
            '{"title": "Cell", "type": "object", "properties": { '
                '"kind": {"enum": ["a${lineBreak}b; } void stolen() {", '
                '"c"]}}}',
          ),
        ], report: false)!;
        // In a comment or within a string of one line, never code.
        for (final line in const LineSplitter().convert(code)) {
          if (line.contains('stolen')) {
            expect(
              line.trimLeft(),
              anyOf(startsWith('///'), contains(r'"a\')),
              reason: line,
            );
          }
        }
        expect('stolen'.allMatches(code), hasLength(greaterThan(1)));
      }
    });

    test(r'a nullable definition is nullable at every $ref to it', () {
      final code = JsonSchemaClasses.code([
        at(
          'resources:a.json',
          '{"title": "Pair", "type": "object", "required": ["a", "b"], '
              r'"properties": {"a": {"$ref": "#/$defs/Mode"}, '
              r'"b": {"$ref": "#/$defs/Mode"}}, "$defs": {"Mode": '
              '{"type": ["string", "null"], "enum": ["x", "y"]}}}',
        ),
      ], report: false)!;
      expect(code, contains('final Mode? a;'));
      expect(code, contains('final Mode? b;'));
    });

    test('the name of a class of Spring is warned about', () {
      final warnings = <String>[];
      JsonSchemaClasses.code(
        [at('resources:order.json', _order)],
        report: false,
        warnings: warnings,
      );
      expect(
        warnings,
        contains(contains('the class Order has the name of a class')),
      );
    });

    test('anyOf of a type and null is nullable; of two types Object?', () {
      final warnings = <String>[];
      final code = JsonSchemaClasses.code(
        [
          at(
            'resources:a.json',
            '{"title": "Note", "type": "object", '
                '"required": ["text", "size"], "properties": { '
                '"text": {"anyOf": [{"type": "string"}, {"type": "null"}]}, '
                '"size": {"oneOf": [{"type": "string"}, '
                '{"type": "integer"}]}}}',
          ),
        ],
        report: false,
        warnings: warnings,
      )!;
      expect(code, contains('final String? text;'));
      expect(code, contains('final Object? size;'));
      expect(warnings, contains(contains('oneOf of 2 kinds')));
    });
  });
}
