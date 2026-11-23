// `@EqualsAndHashCode`, `@ToString` and `@CopyWith`: the object methods of a
// class's description and the copyWith of <library>.spring.introspection.dart,
// the build errors of every misuse, and the warnings. The output is compiled
// with the scanned libraries.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header = '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.introspection.dart';
''';

const _introspection = 'lib/spring_gen/src/beans.spring.introspection.dart';

// The scanned libraries: lib/src/app.dart with [app], and [others] by path
// (with the header unless they start with `part of`).
Map<String, String> _sources(String app, Map<String, String> others) => {
  'pkg|lib/src/beans.dart': _scan,
  'pkg|lib/src/app.dart': '$_header$app',
  for (final MapEntry(:key, :value) in others.entries)
    'pkg|$key': value.startsWith('part of') ? value : '$_header$value',
};

Future<(TestBuilderResult, List<String>)> _build(
  String app, {
  Map<String, String> others = const {},
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final logs = <String>[];
  final result = await testBuilder(
    SpringBuilder(generations: packageGenerations),
    _sources(app, others),
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      if (record.level.name == 'WARNING') {
        // Without the builder's `SpringBuilder on lib/src/beans.dart:`.
        logs.add(record.message.split('\n').skip(1).join('\n'));
      }
    },
  );
  return (result, logs);
}

String _normalize(String code) =>
    code.replaceAll(RegExp(r'\b_i\d+\.'), '').replaceAll(RegExp(r'\s'), '');

/// The generated `<library>.spring.introspection.dart` (normalized unless
/// [raw]), the build's warnings, and the diagnostics of the libraries of
/// [diagnosed] (paths of [others]), after checking that the outputs and the
/// other scanned libraries compile.
Future<(String, List<String>, List<String>)> _generate(
  String app, {
  Map<String, String> others = const {},
  Set<String> diagnosed = const {},
  bool raw = false,
}) async {
  final (result, warnings) = await _build(app, others: others);
  expect(result.errors, isEmpty);
  final outputs = {
    for (final output in result.outputs)
      'pkg|${output.path}': result.readerWriter.testing.readString(output),
  };
  final introspection = outputs['pkg|$_introspection']!;
  final (
    errors,
    diagnostics,
  ) = await resolveSources<(List<String>, List<String>)>(
    {..._sources(app, others), ...outputs},
    (resolver) async {
      final errors = <String>[];
      final expected = <String>[];
      for (final library in [
        'lib/src/app.dart',
        for (final MapEntry(:key, :value) in others.entries)
          if (!value.startsWith('part of')) key,
        for (final output in result.outputs)
          if (!outputs['pkg|${output.path}']!.contains('\npart of '))
            output.path,
      ]) {
        final element = await resolver.libraryFor(AssetId('pkg', library));
        for (final fragment in element.fragments) {
          final result = await element.session.getErrors(
            fragment.source.fullName,
          );
          if (result case ErrorsResult(:final diagnostics)) {
            for (final diagnostic in diagnostics) {
              // The header imports the generated file in every library.
              if (diagnostic.severity == Severity.info ||
                  diagnostic.message.startsWith('Unused import')) {
                continue;
              }
              final line =
                  '${fragment.source.shortName}: ${diagnostic.message}';
              if (diagnosed.contains(library)) {
                expected.add(line);
              } else {
                errors.add(line);
              }
            }
          }
        }
      }
      return (errors, expected);
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|$_introspection',
    readAllSourcesFromFilesystem: true,
  );
  expect(errors, isEmpty, reason: introspection);
  return (
    raw ? introspection : _normalize(introspection),
    warnings,
    diagnostics,
  );
}

Future<String> _errors(
  String app, {
  Map<String, String> others = const {},
}) async {
  final (result, _) = await _build(app, others: others);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

void main() {
  test('the description gets the typed object methods; the file gets the '
      'copyWith type and extension; a masked field is never read', () async {
    final (output, warnings, _) = await _generate('''
@EqualsAndHashCode()
@ToString(mask: ['isbn'])
@CopyWith()
class Book with IntrospectedObject {
  const Book(
    this.title, {
    required this.pages,
    this.tags = const [],
    this.password,
    this.isbn = '',
  });

  final String title;
  final int pages;
  final List<String> tags;
  final String? password;
  final String isbn;
}
''');
    expect(warnings, isEmpty);
    void has(String code) => expect(output, contains(_normalize(code)));
    has(r'''
bool _$equals0(Book a, Book b) => a.title == b.title && a.pages == b.pages &&
    deepEquals(a.tags, b.tags) && a.password == b.password &&
    a.isbn == b.isbn;
int _$hashCode1(Book object) => Object.hash(object.title, object.pages,
    deepHash(object.tags), object.password, object.isbn,);
String _$toString2(Book object) => 'Book(title: ${object.title}, pages: ${object.pages}, tags: ${object.tags}, password: ******, isbn: ******)';
''');
    has(r'''
const Introspection<Book>(
  className: r'Book',
  properties: [],
  library: r'package:pkg/src/app.dart',
  parts: {},
  objectMethods: ObjectMethods<Book>(
    equals: _$equals0,
    hashCode: _$hashCode1,
    toString: _$toString2,
  ),
),
''');
    has(
      'typedef BookCopyWith = Book Function({String title, int pages, '
      'List<String> tags, String? password, String isbn,});',
    );
    has(r'''
extension $Book on Book {
  BookCopyWith get copyWith => ({
    Object? title = const _$Keep(),
    Object? pages = const _$Keep(),
    Object? tags = const _$Keep(),
    Object? password = const _$Keep(),
    Object? isbn = const _$Keep(),
  }) => Book(
    title is _$Keep ? this.title : (title as String),
    pages: pages is _$Keep ? this.pages : (pages as int),
    tags: tags is _$Keep ? this.tags : (tags as List<String>),
    password: password is _$Keep ? this.password : (password as String?),
    isbn: isbn is _$Keep ? this.isbn : (isbn as String),
  );
}
''');
    has(r'''
final class _$Keep {
  const _$Keep();
}
''');
  });

  test('where they are used: one import; copyWith(x: null) clears, a value '
      'of the wrong type does not compile', () async {
    final (_, _, diagnostics) = await _generate(
      '''
@CopyWith()
class Book {
  const Book(this.title, {this.subtitle});

  final String title;
  final String? subtitle;
}
''',
      others: {
        'lib/src/use.dart': '''
import 'package:pkg/src/app.dart';

Book cleared(Book book) => book.copyWith(subtitle: null);
''',
        'lib/src/wrong.dart': '''
import 'package:pkg/src/app.dart';

Book wrong(Book book) => book.copyWith(title: 3);
''',
      },
      diagnosed: {'lib/src/wrong.dart'},
    );
    expect(
      diagnostics.single,
      "wrong.dart: The argument type 'int' can't be assigned to the parameter "
      "type 'String'. ",
    );
  });

  test('allowed: a bean, @ConfigurationProperties, generics, const and late '
      'final fields, an annotation through a typedef; names nobody writes '
      'made unique', () async {
    final (output, warnings, _) = await _generate(
      '''
@Component()
@EqualsAndHashCode()
@ToString()
class Shelf with IntrospectedObject {
  final String name = 'main';
}

@ConfigurationProperties('shop')
@ToString()
class ShopProperties with IntrospectedObject {
  String name = 'shop';
  String apiKey = '';
}

@EqualsAndHashCode()
@CopyWith()
class Page<T extends Object> with IntrospectedObject {
  const Page(this.items, {this.number = 0});

  final List<T> items;
  final int number;
}

@ToString()
class Deferred with IntrospectedObject {
  late final String value;
}

typedef Copied = CopyWith;

@Copied()
class Filter {
  const Filter({required this.query, this.page = 0});

  final String query;
  final int page;
}

@CopyWith()
class Book {
  const Book(this.title);

  final String title;
}
''',
      others: {
        'lib/src/archive/book.dart': '''
@CopyWith()
class Book {
  const Book(this.title);

  final String title;
}
''',
      },
    );
    expect(warnings, isEmpty);
    void has(String code) => expect(output, contains(_normalize(code)));
    has(
      r"(ShopProperties object) => 'ShopProperties(name: ${object.name}, "
      "apiKey: ******)';",
    );
    has(
      'typedef PageCopyWith<T extends Object> = Page<T> Function( '
      '{List<T> items, int number,});',
    );
    has('(Page<Object> a, Page<Object> b) => deepEquals(a.items, b.items)');
    has(r'extension $Page<T extends Object> on Page<T> {');
    has('typedef BookCopyWithApp = Book Function({String title});');
    has('typedef BookCopyWithArchiveBook = Book Function({String title});');
    has(r'extension $BookApp on Book {');
    has(r'extension $BookArchiveBook on Book {');
    has('typedef FilterCopyWith = Filter Function({String query, int page});');
  });

  test('warnings: a private field left out unless excluded, a field of '
      'hashCode that is not final unless excluded', () async {
    final (_, warnings, _) = await _generate('''
@EqualsAndHashCode()
@ToString(exclude: ['_cache'])
class Counter with IntrospectedObject {
  Counter(this.name);

  final String name;
  int count = 0;
  final _cache = <String>[];

  List<String> get cache => _cache;
}

@EqualsAndHashCode(exclude: ['count', '_cache'])
class Quiet with IntrospectedObject {
  Quiet(this.name);

  final String name;
  int count = 0;
  final _cache = <String>[];

  List<String> get cache => _cache;
}
''');
    expect(warnings, hasLength(2), reason: warnings.join('\n'));
    expect(
      warnings,
      contains(
        '@EqualsAndHashCode on Counter leaves out the private field _cache: '
        'the generated code (another library) cannot read it. Exclude it '
        "(exclude: ['_cache']) to say so, or make it public.",
      ),
    );
    expect(
      warnings,
      contains(
        '@EqualsAndHashCode on Counter: the field count of hashCode is not '
        'final, so a Counter in a Set or as a Map key is lost when it '
        "changes. Make it final, or exclude it (exclude: ['count']).",
      ),
    );
  });

  test('build errors of the target and of the options', () async {
    final errors = await _errors('''
@ToString()
class Missing {
  const Missing(this.id);

  final int id;
}

@EqualsAndHashCode()
class OwnEquals with IntrospectedObject {
  @override
  bool operator ==(Object other) => true;

  @override
  int get hashCode => 0;
}

mixin Loud {
  @override
  String toString() => 'loud';
}

@ToString()
class LoudLast with IntrospectedObject, Loud {}

class Overriding with IntrospectedObject {
  @override
  String toString() => 'mine';
}

@ToString()
class Below extends Overriding {}

@ToString()
abstract class Shape {}

@ToString()
interface class Named {}

@ToString()
sealed class Result {}

@EqualsAndHashCode()
mixin class Mixable {}

@ToString()
class _Hidden with IntrospectedObject {}

@ToString(include: ['id'], exclude: ['id'])
class Both with IntrospectedObject {
  final int id = 0;
}

@ToString(include: ['titel'])
class Typo with IntrospectedObject {
  final String title = '';
}

@ToString(exclude: ['count'])
class Static with IntrospectedObject {
  static int count = 0;
  final int id = 0;
}

@ToString(include: ['_secret'])
class PrivateInclude with IntrospectedObject {
  final _secret = '';
}

@ToString(mask: ['card'], exclude: ['card'])
class MaskExcluded with IntrospectedObject {
  final String card = '';
}

@ToString(mask: ['token'], reveal: ['token'])
class MaskRevealed with IntrospectedObject {
  final String token = '';
}

@ToString(mask: ['crad'])
class MaskTypo with IntrospectedObject {
  final String card = '';
}

@ToString(reveal: ['title'])
class RevealPlain with IntrospectedObject {
  final String title = '';
}

@ToString(callSuper: true)
class NoParent with IntrospectedObject {}

class Plain {}

@EqualsAndHashCode(callSuper: true)
class IdentityParent extends Plain with IntrospectedObject {}

@ToString(callSuper: true)
class NamelessParent extends Plain with IntrospectedObject {}

@Configuration()
@ToString()
class AppConfig with IntrospectedObject {}

@Aspect()
@Component()
@ToString()
class Tracer with IntrospectedObject {}

@InterfaceProxy()
@ToString()
abstract interface class Client {}

@ToString()
enum Color { red }

@ToString()
mixin Labelled {}

@ToString()
extension Shout on String {}

@ToString()
extension type Id(int value) {}

@EqualsAndHashCode()
typedef Pair = (int, int);

class Fields {
  @ToString()
  final int id = 0;
}

class Unannotated with IntrospectedObject {}

@ToString()
void helper() {}

void use() => _Hidden();
''');
    void has(String message) => expect(errors, contains(message));
    has(
      '@ToString on Missing: Missing does not mix in IntrospectedObject, '
      'whose toString call the generated one. Declare the class as `class '
      'Missing with IntrospectedObject` (after its `extends`, before its '
      '`implements`); IntrospectedObject comes with the import of '
      "@ToString: import 'package:spring_core_dart/spring_core_dart.dart';",
    );
    has(
      '@EqualsAndHashCode on OwnEquals: OwnEquals declares == itself, which '
      "wins over IntrospectedObject's (the one that calls the generated ==); "
      'remove it or the annotation.',
    );
    has(
      '@ToString on LoudLast: the mixin Loud, applied after '
      'IntrospectedObject, declares toString, which wins over '
      "IntrospectedObject's",
    );
    has(
      '@ToString on Below: Below inherits toString from Overriding, which '
      'declares its own below IntrospectedObject',
    );
    has('@ToString on Shape: an abstract class has no instances of its own');
    has('@ToString on Named: an interface class is a type to implement');
    has('@ToString on Result: an abstract class');
    has(
      '@EqualsAndHashCode on Mixable: a mixin class cannot mix in '
      'IntrospectedObject',
    );
    has('@ToString on _Hidden: the class is private');
    has('@ToString on Both: include and exclude cannot be given together');
    has(
      '@ToString on Typo: include names "titel", which is not an instance '
      'field of Typo (did you mean "title"?). The fields: title.',
    );
    has(
      '@ToString on Static: exclude names "count", which is a static field, '
      'not an instance field of Static',
    );
    has('@ToString on PrivateInclude: include names the private field _secret');
    has(
      '@ToString on MaskExcluded: "card" is in both mask and exclude; a '
      'field that is not written needs no mask.',
    );
    has(
      '@ToString on MaskRevealed: "token" is in both mask and reveal; keep '
      'it in one of the two.',
    );
    has(
      '@ToString on MaskTypo: mask names "crad", which is not an instance '
      'field of MaskTypo (did you mean "card"?)',
    );
    has(
      '@ToString on RevealPlain: reveal names "title", whose name does not '
      'look secret',
    );
    has(
      '@ToString(callSuper: true) on NoParent: NoParent extends no class but '
      'Object',
    );
    has(
      '@EqualsAndHashCode(callSuper: true) on IdentityParent: no class above '
      "IdentityParent has an == of its own (Plain's is Object's: "
      'identity)',
    );
    has(
      '@ToString(callSuper: true) on NamelessParent: no class above '
      "NamelessParent has a toString() of its own (Plain's is Object's",
    );
    has('@ToString on AppConfig: a @Configuration class declares beans');
    has('@ToString on Tracer: an aspect holds advice, no data');
    has('@ToString on Client: an abstract class has no instances of its own');
    has(
      '@ToString on enum Color of package:pkg/src/app.dart: the values of an '
      'enum are constants',
    );
    has(
      '@ToString on mixin Labelled of package:pkg/src/app.dart: a mixin has '
      'no instances of its own',
    );
    has(
      '@ToString on extension Shout of package:pkg/src/app.dart: an '
      "extension cannot override Object's members",
    );
    has(
      '@ToString on extension type Id of package:pkg/src/app.dart: an '
      'extension type is its representation at run time',
    );
    has(
      '@EqualsAndHashCode on typedef Pair of package:pkg/src/app.dart: a '
      'typedef is no class',
    );
    has(
      '@ToString on the field Fields.id of package:pkg/src/app.dart: the '
      'annotation belongs on the class',
    );
    has(
      'Unannotated mixes in IntrospectedObject, but neither it nor a class '
      'above it has @EqualsAndHashCode or @ToString',
    );
    has(
      '@ToString on the function helper of package:pkg/src/app.dart: the '
      'annotation belongs on a class.',
    );
  });

  test('build errors of an overridden member IntrospectedObject cannot '
      'replace', () async {
    final errors = await _errors('''
import 'package:meta/meta.dart';

class Widgetish {
  const Widgetish();

  @nonVirtual
  @override
  bool operator ==(Object other) => super == other;

  @nonVirtual
  @override
  int get hashCode => super.hashCode;
}

@EqualsAndHashCode()
class Tile extends Widgetish with IntrospectedObject {}
''');
    expect(
      errors,
      contains(
        '@EqualsAndHashCode on Tile: Widgetish declares == @nonVirtual, so no '
        'subclass may override it',
      ),
    );
  });

  test('build errors of copyWith', () async {
    final errors = await _errors('''
@CopyWith()
class NoParameter {
  NoParameter(this.title);

  final String title;
  final created = DateTime(2026);
}

@CopyWith()
class Computed {
  Computed(String raw) : title = raw.trim();

  final String title;
}

@CopyWith(constructor: 'creat')
class Named {
  Named.create(this.id);

  final int id;
}

@CopyWith()
class OnlyNamed {
  OnlyNamed.of(this.id);

  final int id;
}

@CopyWith(constructor: '_')
class PrivateConstructor {
  PrivateConstructor._(this.id);

  final int id;
}

@CopyWith()
class PrivateField {
  PrivateField(this._clock, this.id);

  final int _clock;
  final int id;

  int get clock => _clock;
}

class _Kind {}

@CopyWith()
class PrivateType {
  PrivateType(this.kind);

  final _Kind kind;
}

@CopyWith()
class HasCopyWith {
  HasCopyWith(this.id);

  final int id;

  HasCopyWith copyWith() => this;
}

@CopyWith()
abstract class Repository {}

@CopyWith()
class CopiedMixer with IntrospectedObject {
  const CopiedMixer(this.id);

  final int id;
}

void use() => PrivateType(_Kind());
''');
    void has(String message) => expect(errors, contains(message));
    has(
      '@CopyWith on NoParameter: no parameter of NoParameter(...) sets the '
      'field created, so a copy could not take its value; add one '
      "(this.created), or exclude the field (exclude: ['created']).",
    );
    has(
      '@CopyWith on Computed: the required parameter raw of Computed(...) '
      'sets no field Computed has to read',
    );
    has(
      '@CopyWith on Named: Named has no constructor named "creat" (did you '
      'mean "create"?)',
    );
    has(
      '@CopyWith on OnlyNamed: OnlyNamed has no unnamed constructor; name the '
      "constructor that makes the copy with @CopyWith(constructor: '...')."
      ' Its constructors: OnlyNamed.of(...).',
    );
    has(
      '@CopyWith on PrivateConstructor: the constructor '
      'PrivateConstructor._(...) is private',
    );
    has(
      '@CopyWith on PrivateField: the parameter _clock of PrivateField(...) '
      'sets the private field _clock',
    );
    has(
      '@CopyWith on PrivateType: the field kind has the private type _Kind',
    );
    has('@CopyWith on HasCopyWith: HasCopyWith has a member named copyWith');
    has(
      '@CopyWith on Repository: an abstract class has no instances of its '
      'own',
    );
    has(
      'CopiedMixer mixes in IntrospectedObject, but neither it nor a class '
      'above it has @EqualsAndHashCode or @ToString',
    );
  });
}
