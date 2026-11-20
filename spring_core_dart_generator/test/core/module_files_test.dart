// A module's generated code by kind, each in a file beside its
// `.spring.dart` only when the module has some: the descriptions
// (`.spring.introspection.dart`, a library), the binding of the
// `@ConfigurationProperties` classes (`.spring.properties.dart`, a library) and
// the proxies (`.spring.proxies.dart`, a part of the module's library).
@Timeout(Duration(minutes: 5))
library;

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:test/test.dart';

import '../support/spring_builder.dart';

final _module = AssetId('pkg', 'lib/spring_gen/src/beans.spring.dart');
final _introspection = AssetId(
  'pkg',
  'lib/spring_gen/src/beans.spring.introspection.dart',
);
final _properties = AssetId(
  'pkg',
  'lib/spring_gen/src/beans.spring.properties.dart',
);
final _proxies = AssetId('pkg', 'lib/spring_gen/src/beans.spring.proxies.dart');

Future<TestBuilderResult> _build(
  String beans, {
  ProxyMode proxyMode = ProxyMode.none,
}) async {
  final result = await buildPackage({
    'lib/src/beans.dart': scanRoot,
    'lib/src/service.dart': '$coreImport$beans',
  }, proxyMode: proxyMode);
  expect(result.errors, isEmpty);
  return result;
}

String _read(TestBuilderResult result, AssetId id) =>
    normalize(result.readerWriter.testing.readString(id));

const _greeter = '@Service()\nclass Greeter {}\n';

const _shop = '''
@ConfigurationProperties('shop')
class ShopProperties {
  String name = '';
  Limits limits = Limits();
}

class Limits {
  int max = 1;
}
''';

void main() {
  test(
    'a module with nothing to describe or proxy: its library only',
    () async {
      final result = await _build(_greeter);
      expect(result.outputs, [_module]);
      expect(_read(result, _module), isNot(contains('introspections:')));
    },
  );

  test('the descriptions: a library the module imports and spreads', () async {
    final result = await _build('''
$_greeter
@Introspected()
class Book {
  String title = '';
}
''');
    expect(result.outputs, unorderedEquals([_module, _introspection]));
    final descriptions = _read(result, _introspection);
    expect(descriptions, isNot(contains('partof')));
    expect(
      descriptions,
      hasCode(
        r'List<Introspection<Object>> get $pkgBeansIntrospections => [',
      ),
    );
    expect(descriptions, hasCode('Introspection<Book>('));
    final module = _read(result, _module);
    expect(module, contains("import'beans.spring.introspection.dart'"));
    expect(module, hasCode(r'introspections: [...$pkgBeansIntrospections]'));
    expect(module, isNot(hasCode('Introspection<Book>(')));
  });

  test('the binding of a @ConfigurationProperties class and of the classes '
      'it is made of: a library of its own', () async {
    final result = await _build(_shop);
    expect(result.outputs, unorderedEquals([_module, _properties]));
    final binding = _read(result, _properties);
    expect(
      binding,
      hasCode(
        r'List<Introspection<Object>> get $pkgBeansPropertiesIntrospections',
      ),
    );
    expect(binding, hasCode('Introspection<ShopProperties>('));
    expect(binding, hasCode('Introspection<Limits>('));
    expect(
      _read(result, _module),
      hasCode(r'introspections: [...$pkgBeansPropertiesIntrospections]'),
    );
  });

  test('a class the binder and another use share stays with the '
      'descriptions; each file numbers its own functions', () async {
    final result = await _build('''
$_shop
@Introspected()
class Report {
  Limits limits = Limits();
}
''');
    expect(
      result.outputs,
      unorderedEquals([_module, _introspection, _properties]),
    );
    final descriptions = _read(result, _introspection);
    final binding = _read(result, _properties);
    expect(descriptions, hasCode('Introspection<Report>('));
    expect(descriptions, hasCode('Introspection<Limits>('));
    expect(binding, hasCode('Introspection<ShopProperties>('));
    expect(binding, isNot(hasCode('Introspection<Limits>(')));
    expect(descriptions, contains(r'_$get0('));
    expect(binding, contains(r'_$get0('));
    expect(
      _read(result, _module),
      hasCode(
        r'introspections: [...$pkgBeansIntrospections, '
        r'...$pkgBeansPropertiesIntrospections]',
      ),
    );
  });

  test('the proxies: a part of the module', () async {
    final result = await _build(_greeter, proxyMode: ProxyMode.all);
    expect(result.outputs, unorderedEquals([_module, _proxies]));
    final proxies = _read(result, _proxies);
    expect(proxies, contains("partof'beans.spring.dart';"));
    expect(proxies, contains(r'class_$GreeterProxy'));
    final module = _read(result, _module);
    expect(module, contains("part'beans.spring.proxies.dart';"));
    expect(module, isNot(contains(r'class_$GreeterProxy')));
    expect(module, contains(r'_$GreeterProxy('));
  });

  test('the files compile together', () async {
    expect(
      await compileErrors({
        'lib/src/service.dart':
            '''
$_greeter
$_shop
@Introspected()
class Report {
  Limits limits = Limits();
}
''',
      }),
      isEmpty,
    );
  });
}
