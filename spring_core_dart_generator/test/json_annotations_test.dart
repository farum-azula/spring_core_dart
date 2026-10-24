// JSON annotations the generator checks or writes code for: `@JsonValue`
// (enum getters, class properties and methods; one per class) and
// `@JsonProperty` on enum constants.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header = "import 'package:spring_core_dart/spring_core_dart.dart';\n";

Future<TestBuilderResult> _build(String models) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return testBuilder(
    SpringBuilder(),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/models.dart': '$_header$models',
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

// The generated module and the analyzer errors it has.
Future<(String, List<String>)> _generate(String models) async {
  final result = await _build(models);
  expect(result.errors, isEmpty);
  final output = result.readerWriter.testing.readString(result.outputs.single);
  final errors = await resolveSources<List<String>>(
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/models.dart': '$_header$models',
      'pkg|lib/src/beans.spring.dart': output,
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/src/beans.spring.dart'),
      );
      final result = await library.session.getErrors(
        library.firstFragment.source.fullName,
      );
      return [
        if (result case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|lib/src/beans.spring.dart',
    readAllSourcesFromFilesystem: true,
  );
  return (_normalize(output), errors);
}

Future<String> _errors(String models) async {
  final result = await _build(models);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

const _models = '''
enum Stock {
  inStock('in_stock'),
  soldOut('sold_out');

  const Stock(this._json);
  final String _json;

  @JsonValue()
  String get json => _json;
}

enum Color {
  @JsonProperty('RED')
  red,
  green,
}

@Introspected()
class Isbn {
  const Isbn(this.value);
  @JsonValue()
  final String value;
}

@Introspected()
class Code {
  const Code(this.raw);
  final String raw;
  @JsonValue()
  String get text => 'C-\$raw';
}

@Introspected()
class Label {
  @JsonValue()
  String render() => 'label';
}

@Introspected()
class Account {
  Account(this.id, {this.nickname, this.stock = Stock.inStock, this.color = Color.green});
  @JsonProperty('', required: true)
  final String id;
  final String? nickname;
  final Stock stock;
  final Color color;
  @JsonProperty('pwd', access: JsonPropertyAccess.writeOnly)
  String? password;
}
''';

void main() {
  late final String output;
  late final List<String> errors;

  setUpAll(() async {
    (output, errors) = await _generate(_models);
  });

  test('the generated code compiles', () {
    expect(errors, isEmpty);
  });

  test('@JsonValue on an enum getter', () {
    expect(
      output,
      _has('EnumType<Stock>(Stock.values, jsonValue: (value) => value.json)'),
    );
  });

  test('@JsonProperty on enum constants', () {
    expect(
      output,
      _has(
        "EnumType<Color>(Color.values, jsonValue: (value) => "
        "const {Color.red: r'RED'}[value] ?? value.name)",
      ),
    );
  });

  test(
    '@JsonValue on class properties and methods is kept for the runtime',
    () {
      expect(output, _has("BeanProperty<Isbn>(r'value', type: String,"));
      expect(output, _has('annotations: const [JsonValue()]'));
      expect(output, _has("BeanProperty<Code>(r'text', type: String,"));
      expect(output, _has("BeanMethod<Label>(r'render',"));
      expect(
        output,
        _has("JsonProperty(r'pwd', access: JsonPropertyAccess.writeOnly)"),
      );
      expect(output, _has("JsonProperty(r'', required: true)"));
    },
  );

  group('build errors', () {
    test('two @JsonValue in one class', () async {
      expect(
        await _errors('''
@Introspected()
class Twice {
  @JsonValue()
  final String a = '';
  @JsonValue()
  String get b => '';
}
'''),
        contains('Twice has more than one @JsonValue (a, b)'),
      );
    });

    test('@JsonValue on a method with required parameters', () async {
      expect(
        await _errors('''
@Introspected()
class Render {
  @JsonValue()
  String render(int width) => '';
}
'''),
        contains('@JsonValue on Render.render has required parameters'),
      );
    });

    test('@JsonValue on a setter', () async {
      expect(
        await _errors('''
@Introspected()
class Holder {
  String _v = '';
  String get v => _v;
  @JsonValue()
  set v(String value) => _v = value;
}
'''),
        contains('@JsonValue on Holder.v is a setter'),
      );
    });

    test('@JsonValue on an enum method', () async {
      expect(
        await _errors('''
enum Mood {
  happy;

  @JsonValue()
  String json() => name;
}

@Introspected()
class Person {
  Mood mood = Mood.happy;
}
'''),
        contains('on an enum, @JsonValue goes on a field or getter'),
      );
    });

    test('@JsonValue and @JsonProperty names on one enum', () async {
      expect(
        await _errors('''
enum Mood {
  @JsonProperty('HAPPY')
  happy('h');

  const Mood(this.json);
  @JsonValue()
  final String json;
}

@Introspected()
class Person {
  Mood mood = Mood.happy;
}
'''),
        contains('has both a @JsonValue (json) and @JsonProperty names'),
      );
    });

    test('a private @JsonValue', () async {
      expect(
        await _errors('''
@Introspected()
class Secret {
  @JsonValue()
  final String _value = '';
  String get shown => _value;
}
'''),
        contains('@JsonValue on Secret._value is private'),
      );
    });
  });
}
