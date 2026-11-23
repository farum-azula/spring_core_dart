// `@Target` of package:meta on any annotation class, and the values a
// composed annotation gives through a getter: build errors naming the
// annotation and what to change, before any other message of that place.
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:test/test.dart';

import '../support/placements.dart';
import '../support/spring_builder.dart';

const _meta = "import 'package:meta/meta_meta.dart';\n";

Future<({bool ok, String errors})> _build(String source) async {
  final result = await buildPackage({
    'lib/src/beans.dart': scanRoot,
    'lib/src/service.dart': '$coreImport$_meta$source',
  }, proxyMode: ProxyMode.all);
  return (ok: result.succeeded, errors: result.errors.join('\n'));
}

String _only(String kinds) =>
    '@Target({$kinds}) class Mark { const Mark(); }\n';

void main() {
  group('@Target', () {
    test('a composed annotation: its message, not "no bean"', () async {
      final result = await _build('''
@Target({TargetKind.method})
class DevBean extends Bean implements Profile {
  const DevBean(this.value);
  @override
  final List<String> value;
}
@DevBean(['dev']) class Orders {}
''');
      expect(result.ok, isFalse);
      expect(
        result.errors,
        contains('@DevBean on class Orders: it can only be used on methods.'),
      );
      expect(result.errors, isNot(contains('Add @Component()')));
    });

    test('inherited by a class with no @Target of its own', () async {
      final result = await _build('''
@Target({TargetKind.method}) class Base { const Base(); }
class Sub extends Base { const Sub(); }
@Sub() class Orders {}
''');
      expect(
        result.errors,
        contains('@Sub on class Orders: it can only be used on methods.'),
      );
    });

    test('its own @Target replaces the inherited one', () async {
      final result = await _build('''
@Target({TargetKind.method}) class Base { const Base(); }
@Target({TargetKind.classType}) class Sub extends Base { const Sub(); }
@Sub() class Orders {}
''');
      expect(result.errors, isEmpty);
    });

    test('parents without a common place', () async {
      final result = await _build('''
@Target({TargetKind.method}) class A { const A(); }
@Target({TargetKind.field}) class B { const B(); }
class C implements A, B { const C(); }
@C() class Orders {}
''');
      expect(result.errors, contains('have no place in common'));
    });

    final wrong = <String, (String, String, String)>{
      'classType': ('TargetKind.method', '@Mark() class A {}', 'class A'),
      'mixin': ('TargetKind.classType', '@Mark() mixin M {}', 'mixin M'),
      'enum': ('TargetKind.classType', '@Mark() enum E { a }', 'enum E'),
      'extension': (
        'TargetKind.classType',
        '@Mark() extension X on int {}',
        'extension X',
      ),
      'extension type': (
        'TargetKind.classType',
        '@Mark() extension type T(int v) {}',
        'extension type T',
      ),
      'function': ('TargetKind.method', '@Mark() void f() {}', 'f, in'),
      'top-level variable': (
        'TargetKind.field',
        '@Mark() int v = 0;',
        'v, in',
      ),
      'method': (
        'TargetKind.function',
        'class A { @Mark() void m() {} }',
        'A.m',
      ),
      'getter': (
        'TargetKind.setter',
        'class A { @Mark() int get g => 0; }',
        'the getter A.g',
      ),
      'setter': (
        'TargetKind.getter',
        'class A { @Mark() set s(int v) {} }',
        'the setter A.s',
      ),
      'field': (
        'TargetKind.getter',
        'class A { @Mark() int f = 0; }',
        'the field A.f',
      ),
      'parameter': (
        'TargetKind.field',
        'class A { void m(@Mark() int p) {} }',
        'parameter p of A.m',
      ),
      'required parameter is no optionalParameter': (
        'TargetKind.optionalParameter',
        'class A { void m(@Mark() int p) {} }',
        'parameter p of A.m',
      ),
      'constructor': (
        'TargetKind.method',
        'class A { @Mark() A(); }',
        'the constructor A',
      ),
      'enum value': (
        'TargetKind.enumType',
        'enum E { @Mark() a }',
        'the enum value E.a',
      ),
      'typedef': (
        'TargetKind.classType',
        '@Mark() typedef F = int;',
        'typedef F',
      ),
      'type parameter': (
        'TargetKind.classType',
        'class A<@Mark() T> {}',
        'type parameter T',
      ),
      'static member is not overridable': (
        'TargetKind.overridableMember',
        'class A { @Mark() static void m() {} }',
        'A.m',
      ),
    };
    for (final MapEntry(key: name, value: (kinds, code, place))
        in wrong.entries) {
      test('refused: $name', () async {
        final result = await _build('${_only(kinds)}$code');
        expect(result.ok, isFalse, reason: code);
        expect(result.errors, contains('@Mark on $place'));
        expect(result.errors, contains('it can only be used on'));
      });
    }

    final right = <String, (String, String)>{
      'classType': ('TargetKind.classType', '@Mark() class A {}'),
      'type on a class': ('TargetKind.type', '@Mark() class A {}'),
      'type on a mixin': ('TargetKind.type', '@Mark() mixin M {}'),
      'type on an enum': ('TargetKind.type', '@Mark() enum E { a }'),
      'type on a typedef': ('TargetKind.type', '@Mark() typedef F = int;'),
      'mixinType': ('TargetKind.mixinType', '@Mark() mixin M {}'),
      'enumType': ('TargetKind.enumType', '@Mark() enum E { a }'),
      'enumValue': ('TargetKind.enumValue', 'enum E { @Mark() a }'),
      'extension': ('TargetKind.extension', '@Mark() extension X on int {}'),
      'extensionType': (
        'TargetKind.extensionType',
        '@Mark() extension type T(int v) {}',
      ),
      'function': ('TargetKind.function', '@Mark() void f() {}'),
      'top-level getter': ('TargetKind.getter', '@Mark() int get g => 0;'),
      'top-level setter': ('TargetKind.setter', '@Mark() set s(int v) {}'),
      'topLevelVariable': ('TargetKind.topLevelVariable', '@Mark() int v = 0;'),
      'method': ('TargetKind.method', 'class A { @Mark() void m() {} }'),
      'static method': (
        'TargetKind.method',
        'class A { @Mark() static void m() {} }',
      ),
      'getter': ('TargetKind.getter', 'class A { @Mark() int get g => 0; }'),
      'setter': ('TargetKind.setter', 'class A { @Mark() set s(int v) {} }'),
      'field': ('TargetKind.field', 'class A { @Mark() int f = 0; }'),
      'late field': (
        'TargetKind.field',
        'class A { @Mark() late final int f; }',
      ),
      'parameter': (
        'TargetKind.parameter',
        'class A { void m(@Mark() int p) {} }',
      ),
      'optionalParameter': (
        'TargetKind.optionalParameter',
        'class A { void m([@Mark() int? p]) {} }',
      ),
      'constructor': ('TargetKind.constructor', 'class A { @Mark() A(); }'),
      'typedefType': ('TargetKind.typedefType', '@Mark() typedef F = int;'),
      'typeParameter': ('TargetKind.typeParameter', 'class A<@Mark() T> {}'),
      'overridableMember': (
        'TargetKind.overridableMember',
        'class A { @Mark() void m() {} }',
      ),
      'declaring parameter as a field': (
        'TargetKind.field',
        'class A(@Mark() final int v);',
      ),
      'declaring parameter as a parameter': (
        'TargetKind.parameter',
        'class A(@Mark() final int v);',
      ),
    };
    for (final MapEntry(key: name, value: (kinds, code)) in right.entries) {
      test('accepted: $name', () async {
        final result = await _build('${_only(kinds)}$code');
        expect(result.errors, isEmpty, reason: code);
      });
    }

    test("the analyzer's ignore comment is honoured", () async {
      final result = await _build('''
${_only('TargetKind.field')}
class A {
  // ignore: invalid_annotation_target
  void m(@Mark() int p) {}
}
''');
      expect(result.errors, isEmpty);
    });

    test('the ignore of one declaration covers no other', () async {
      final result = await _build('''
${_only('TargetKind.field')}
class A {
  // ignore: invalid_annotation_target
  @Mark() void one() {}

  @Mark() void two() {}
}
''');
      expect(result.errors, contains('@Mark on A.two'));
      expect(result.errors, isNot(contains('@Mark on A.one')));
    });

    final misuse = <String, (String, String)>{
      'a non-bean class': ('@Mark() class Plain {}', 'class Plain'),
      'a scoped bean': (
        "@Mark() @Scope('prototype') @Component() class Scoped {}",
        'class Scoped',
      ),
      'a late field of a bean': (
        '@Component() class A { @Mark() late final int f; void m() {} }',
        'the field A.f',
      ),
      'a client': (
        "@Mark() @FeignClient('svc', url: 'http://x') "
            'abstract interface class Api {}',
        'class Api',
      ),
      'a repository': (
        '@Mark() @Repository() abstract class Orders {}',
        'class Orders',
      ),
    };
    for (final MapEntry(key: name, value: (code, place)) in misuse.entries) {
      test('refused on $name', () async {
        final result = await buildWithStarters(
          "import 'package:meta/meta_meta.dart';\n"
          '@Target({TargetKind.getter}) class Mark { const Mark(); }\n$code',
        );
        expect(result.succeeded, isFalse);
        expect(
          result.errors,
          contains('@Mark on $place: it can only be used on getters.'),
        );
      });
    }
  });

  group('a value given through a getter', () {
    test('names the annotation, the member and the field', () async {
      final result = await _build('''
class Dev extends Component implements Profile {
  const Dev([super.name]);
  @override
  List<String> get value => const ['dev'];
}
@Dev() class Orders {}
''');
      expect(result.ok, isFalse);
      expect(result.errors, contains('@Dev on class Orders'));
      expect(result.errors, contains('Profile.value'));
      expect(
        result.errors,
        contains("final List<String> value = const ['dev'];"),
      );
      expect(result.errors, isNot(contains('FormatException')));
    });

    test('an optional value too, which would be ignored', () async {
      final result = await _build('''
class Named extends Component {
  const Named();
  @override
  String? get name => 'orders';
}
@Named() class Orders {}
''');
      expect(result.errors, contains('Component.name'));
      expect(result.errors, contains("final String? name = 'orders';"));
    });

    test('from a base class of another library', () async {
      final result = await buildPackage({
        'lib/src/beans.dart': scanRoot,
        'lib/src/a.dart':
            "$coreImport import 'b.dart';\n@Dev() class Orders {}",
        'lib/src/b.dart':
            '$coreImport class Dev extends Component implements Profile {'
            ' const Dev(); @override List<String> get value => const []; }',
      });
      expect(result.errors.join('\n'), contains('Profile.value'));
    });

    test('a field builds and is read', () async {
      final module = await generateModule('''
class Dev extends Component implements Profile {
  const Dev([super.name]);
  @override
  final List<String> value = const ['dev'];
}
@Dev() class Orders {}
''');
      expect(module, contains("'dev'"));
    });

    test('a getter of its own, no framework value, builds', () async {
      final result = await _build('''
class Dev extends Component {
  const Dev();
  String get label => 'dev';
}
@Dev() class Orders {}
''');
      expect(result.errors, isEmpty);
    });
  });
}
