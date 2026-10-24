import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header = "import 'package:spring_core_dart/spring_core_dart.dart';\n";

Future<TestBuilderResult> _build(
  Map<String, Object> sources, {
  ProxyMode proxyMode = ProxyMode.none,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return testBuilder(
    SpringBuilder(proxyMode: proxyMode),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

/// Builds a scan root plus [beans] and returns the generated source without
/// whitespace (the formatter may wrap lines).
Future<String> _generate(
  String beans, {
  Map<String, Object> extra = const {},
  ProxyMode proxyMode = ProxyMode.none,
}) async {
  final result = await _build({
    'lib/src/beans.dart': _scan,
    'lib/src/service.dart': '$_header$beans',
    ...extra,
  }, proxyMode: proxyMode);
  expect(result.errors, isEmpty);
  return _normalize(
    result.readerWriter.testing.readString(result.outputs.single),
  );
}

/// Drops whitespace, trailing commas (formatter choices) and import
/// prefixes (``, whose numbers depend on the order of first use).
String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

/// Builds [files] (with the scan root) and returns the analyzer errors of
/// the generated library, resolved together with the real runtime: the
/// generated code must compile, not just look right.
Future<List<String>> _compileErrors(
  Map<String, String> files, {
  ProxyMode proxyMode = ProxyMode.all,
}) async {
  final sources = {
    'lib/src/beans.dart': _scan,
    for (final MapEntry(:key, :value) in files.entries) key: '$_header$value',
  };
  final result = await _build(sources, proxyMode: proxyMode);
  expect(result.errors, isEmpty);
  final output = result.readerWriter.testing.readString(result.outputs.single);
  return resolveSources<List<String>>(
    {
      for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value,
      'pkg|lib/src/beans.spring.dart': output,
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/src/beans.spring.dart'),
      );
      final errors = await library.session.getErrors(
        library.firstFragment.source.fullName,
      );
      return [
        if (errors case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|lib/src/beans.spring.dart',
    readAllSourcesFromFilesystem: true,
  );
}

/// An injection style: the class [name] taking the injected type [k], and
/// the name of the injection point (the parameter, field or setter name).
typedef _Style = ({String source, String point});

_Style _constructorPositional(String name, String k) => (
  source: 'class $name { final $k items; $name(this.items); }',
  point: 'items',
);

_Style _constructorNamed(String name, String k) => (
  source: 'class $name { final $k items; $name({required this.items}); }',
  point: 'items',
);

_Style _primaryHeader(String name, String k) =>
    (source: 'class $name(final $k items);', point: 'items');

_Style _primaryBody(String name, String k) =>
    (source: 'class $name(this._items) { final $k _items; }', point: '_items');

_Style _field(String name, String k) => (
  source: 'class $name { @Autowired() late final $k items; }',
  point: 'items',
);

_Style _setter(String name, String k) => (
  source:
      'class $name { late $k got; @Autowired() set items($k v) => got = v; }',
  point: 'items',
);

_Style _method(String name, String k) => (
  source: 'class $name { @Autowired() void wire($k items, String extra) {} }',
  point: 'items',
);

/// An injected kind: the Dart type of the point and the emitted resolver
/// call, for a constructor (collections are lenient there: an empty one is
/// fine) and for a field, setter or method (strict).
typedef _Kind = ({
  String label,
  String Function(String t) type,
  String Function(String t, String point) constructor,
  String Function(String t, String point) member,
  String? dependency,
});

final _kinds = <_Kind>[
  (
    label: 'single bean',
    type: (t) => t,
    constructor: (t, p) => "r.dependency<$t>(name: r'$p')",
    member: (t, p) => "r.dependency<$t>(name: r'$p')",
    dependency: null,
  ),
  (
    label: 'List',
    type: (t) => 'List<$t>',
    constructor: (t, p) => 'r.optionalDependencyList<$t>() ?? <$t>[]',
    member: (t, p) => 'r.dependencyList<$t>()',
    dependency: 'Dependency.collection',
  ),
  (
    label: 'Set',
    type: (t) => 'Set<$t>',
    constructor: (t, p) =>
        'r.optionalDependencyMap<$t>()?.values.toSet() ?? <$t>{}',
    member: (t, p) => 'r.dependencyMap<$t>().values.toSet()',
    dependency: 'Dependency.collection',
  ),
  (
    label: 'Map<String, T>',
    type: (t) => 'Map<String, $t>',
    constructor: (t, p) => 'r.optionalDependencyMap<$t>() ?? <String, $t>{}',
    member: (t, p) => 'r.dependencyMap<$t>()',
    dependency: 'Dependency.map',
  ),
  (
    label: 'Iterable',
    type: (t) => 'Iterable<$t>',
    constructor: (t, p) => 'r.optionalDependencyList<$t>() ?? <$t>[]',
    member: (t, p) => 'r.dependencyList<$t>()',
    dependency: 'Dependency.collection',
  ),
  (
    label: 'ObjectProvider',
    type: (t) => 'ObjectProvider<$t>',
    constructor: (t, p) => "r.provider<$t>(name: r'$p')",
    member: (t, p) => "r.provider<$t>(name: r'$p')",
    dependency: null,
  ),
];

/// A small bean type and `String`: two `@Bean` methods each.
const _elements = {
  'Greeting': '''
class Greeting {}

@Configuration()
class GreetingConfig {
  @Bean() Greeting hello() => Greeting();
  @Bean() Greeting hi() => Greeting();
}
''',
  'String': '''
@Configuration()
class TextConfig {
  @Bean() String helloText() => 'hello';
  @Bean() String hiText() => 'hi';
}
''',
};

/// The generated definition of the bean [type], up to its annotations.
String _definition(String output, String type) {
  final start = output.indexOf('BeanDefinition<$type>(');
  expect(start, isNonNegative, reason: 'no definition of $type');
  return output.substring(start, output.indexOf('annotations:', start));
}

void main() {
  final styles = <String, (_Style Function(String, String), bool)>{
    'constructor, positional parameter': (_constructorPositional, true),
    'constructor, named required parameter': (_constructorNamed, true),
    'primary constructor, field in the header': (_primaryHeader, true),
    'primary constructor, private field in the body': (_primaryBody, true),
    'public @Autowired() late final field': (_field, false),
    '@Autowired() setter': (_setter, false),
    '@Autowired() method with several parameters': (_method, false),
  };

  for (final MapEntry(key: styleName, value: (style, isConstructor))
      in styles.entries) {
    group('injection by $styleName', () {
      for (final MapEntry(key: element, value: config) in _elements.entries) {
        // One build per style and element type, one class per kind.
        final styled = [
          for (final (i, kind) in _kinds.indexed)
            style('S$i', kind.type(element)),
        ];
        Future<String>? generated;
        Future<String> generate() => generated ??= _generate(
          '$config\n${[for (final s in styled) '@Component() ${s.source}'].join('\n')}',
        );
        for (final (i, kind) in _kinds.indexed) {
          test('${kind.label} of $element', () async {
            final point = styled[i].point;
            final definition = _definition(await generate(), 'S$i');
            expect(
              definition,
              _has(
                isConstructor
                    ? kind.constructor(element, point)
                    : kind.member(element, point),
              ),
            );
            // `name:` is the point's name for a single bean or a provider;
            // a collection takes every candidate, whatever the name is.
            final named = "name: r'$point'";
            if (kind.dependency case final dependency?) {
              expect(definition, isNot(_has(named)));
              expect(definition, _has('$dependency($element'));
            } else {
              expect(definition, _has(named));
            }
          });
        }
      }

      test('the generated code compiles', () async {
        String classes(String prefix, String element) => [
          for (final (i, kind) in _kinds.indexed)
            '@Component() ${style('$prefix$i', kind.type(element)).source}',
        ].join('\n');
        expect(
          await _compileErrors({
            'lib/src/greetings.dart':
                '${_elements['Greeting']}\n${classes('G', 'Greeting')}',
            'lib/src/strings.dart':
                '${_elements['String']}\n${classes('T', 'String')}',
          }),
          isEmpty,
        );
      });
    });
  }
}
