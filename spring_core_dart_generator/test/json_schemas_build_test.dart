// The classes of spring.json.schemas in a build: the classes builder writes
// the part (a resources: schema and a downloaded one); the main builder
// makes it a part, spreads its introspections into the module and embeds the
// downloaded schema; a download of another sha256 is refused; an offline
// build uses the copy of an earlier one.
import 'dart:convert';

import 'package:build_test/build_test.dart';
import 'package:crypto/crypto.dart';
import 'package:spring_core_dart_generator/src/json_schema_classes.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => springApplication.run(args);
''';

const _order = '''
{"title": "Purchase", "type": "object", "required": ["id"],
 "properties": {"id": {"type": "string"}}}
''';

const _user = '''
{"title": "User", "type": "object",
 "properties": {"name": {"type": "string"}}}
''';

// A remote address of its own per test: the copies the downloads keep are
// shared by the tests of this process.
String _remote(String test) => 'https://example.com/$test/user.json';

String _config(String remote, {String? sha256}) =>
    '''
spring:
  json:
    schemas:
      - location: resources:schemas/order.json
      - location: $remote
${sha256 == null ? '' : '        sha256: $sha256\n'}''';

Map<String, Object> _sources(String remote, {String? sha256}) => {
  'pkg|lib/main.dart': _main,
  'pkg|lib/resources/application.yml': _config(remote, sha256: sha256),
  'pkg|lib/resources/schemas/order.json': _order,
};

Future<TestBuilderResult> _classes(Map<String, Object> sources) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    JsonSchemasBuilder(),
    sources,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

String _part(TestBuilderResult result) =>
    result.readerWriter.testing.readString(
      result.outputs.singleWhere(
        (o) => o.path == 'lib/spring_gen/json_schemas.spring.dart',
      ),
    );

void main() {
  late List<Uri> fetched;
  setUp(() {
    JsonSchemaClasses.reset();
    fetched = [];
    JsonSchemaClasses.defaultFetch = (uri) async {
      fetched.add(uri);
      return _user;
    };
  });
  tearDown(() {
    JsonSchemaClasses.defaultFetch = null;
    JsonSchemaClasses.reset();
  });

  test('the classes builder writes the classes of both schemas', () async {
    final remote = _remote('classes');
    final result = await _classes(_sources(remote));
    expect(result.errors, isEmpty);
    final part = _part(result);
    expect(part, contains("part of 'main.spring.dart';"));
    expect(part, contains('class Purchase {'));
    expect(part, contains('class User {'));
    expect(part, contains("@_sj.JsonSchemaSource(r'$remote')"));
    expect(fetched, [Uri.parse(remote)]);
  });

  test('the main builder makes it a part, with its introspections and the '
      'downloaded schema', () async {
    final remote = _remote('module');
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    await readerWriter.testing.loadIsolateSources();
    final result = await testBuilder(
      SpringBuilder(),
      _sources(remote),
      rootPackage: 'pkg',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.errors, isEmpty);
    final module = result.readerWriter.testing.readString(
      result.outputs.singleWhere(
        (o) => o.path == 'lib/spring_gen/main.spring.dart',
      ),
    );
    expect(module, contains("part 'json_schemas.spring.dart';"));
    expect(
      module,
      contains(
        "import 'package:spring_core_dart/spring_core_dart.dart' as _sj;",
      ),
    );
    expect(module, contains(r'..._$jsonSchemaIntrospections'));
    // The downloaded schema is a resource of the app, under its place.
    expect(module, contains("r'json-schemas/example.com/module/user.json'"));
    expect(module, contains('"title": "User"'));
  });

  test('a download of another sha256 is refused: no class of it', () async {
    final remote = _remote('pinned');
    final result = await _classes(
      _sources(remote, sha256: 'a' * 64),
    );
    final part = _part(result);
    expect(part, contains('class Purchase {'));
    expect(part, isNot(contains('class User {')));
  });

  test('the right sha256 is taken', () async {
    final remote = _remote('pinned-right');
    final digest = sha256.convert(utf8.encode(_user)).toString();
    final result = await _classes(_sources(remote, sha256: digest));
    expect(_part(result), contains('class User {'));
  });

  test('offline, the copy of an earlier build is used', () async {
    final remote = _remote('offline');
    await _classes(_sources(remote));
    JsonSchemaClasses.reset();
    JsonSchemaClasses.defaultFetch = (uri) async => null;
    final result = await _classes(_sources(remote));
    expect(_part(result), contains('class User {'));
  });

  test('no spring.json.schemas: nothing is written', () async {
    final result = await _classes({'pkg|lib/main.dart': _main});
    expect(
      result.outputs.where(
        (o) => o.path == 'lib/spring_gen/json_schemas.spring.dart',
      ),
      isEmpty,
    );
  });
}
