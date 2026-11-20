// The generated object methods run: the generator output for a package is
// written next to its sources and run in a separate process, so equality,
// hashing, the text of toString() and copyWith are those the generated
// code really has, through IntrospectedObject and the
// descriptions of lib/spring_gen/src/beans.spring.introspection.dart.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _app = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.introspection.dart';

part 'parted.dart';

@EqualsAndHashCode()
@ToString(mask: ['isbn'])
@CopyWith()
class Book with IntrospectedObject {
  const Book(
    this.title, {
    required this.pages,
    this.tags = const [],
    this.meta = const {},
    this.password,
    this.subtitle,
    this.isbn = '',
  });

  final String title;
  final int pages;
  final List<String> tags;
  final Map<String, List<int>> meta;
  final String? password;
  final String? subtitle;
  final String isbn;
}

class Novel extends Book {
  const Novel(super.title, {required super.pages});
}

@ToString(includeNames: false, exclude: ['y'])
class Point with IntrospectedObject {
  const Point(this.x, this.y);

  final int x;
  final int y;
}

@EqualsAndHashCode()
@ToString(reveal: ['token'])
class Base with IntrospectedObject {
  const Base(this.id, {this.token = 't'});

  final int id;
  final String token;
}

@EqualsAndHashCode(callSuper: true)
@ToString(callSuper: true)
class Child extends Base {
  const Child(super.id, this.name);

  final String name;
}

@EqualsAndHashCode()
class Plain extends Base {
  const Plain(super.id, this.name);

  final String name;
}

@ToString()
class Signed extends Base {
  const Signed(super.id, this.signature);

  final String signature;
}

class Legacy {
  const Legacy(this.code);

  final int code;

  @override
  bool operator ==(Object other) => other is Legacy && other.code == code;

  @override
  int get hashCode => code;

  @override
  String toString() => 'Legacy#$code';
}

@EqualsAndHashCode(callSuper: true)
@ToString(callSuper: true)
class Modern extends Legacy with IntrospectedObject {
  const Modern(super.code, this.name);

  final String name;
}

@CopyWith()
class Page<T> {
  const Page(this.items, {this.number = 0, this.parent});

  final List<T> items;
  final int number;
  final Page<T>? parent;
}

@CopyWith(exclude: ['id'], constructor: 'create')
class Purchase {
  const Purchase.create(this.id, this.note);

  final int id;
  final String note;
}

@ToString()
class Own with IntrospectedObject {
  const Own(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is Own && other.id % 10 == id % 10;

  @override
  int get hashCode => id % 10;
}

@ToString()
class Deferred with IntrospectedObject {
  late final String value;
}

@Component()
@EqualsAndHashCode()
@ToString()
class Shelf with IntrospectedObject {
  final String name = 'main';
}

@Configuration()
class Shop {
  @Bean()
  Point origin() => const Point(0, 0);
}

@EqualsAndHashCode()
class Holder<T> with IntrospectedObject {
  const Holder(this.value);

  final T value;
}

@EqualsAndHashCode()
@ToString()
class Wide with IntrospectedObject {
  const Wide(this.a1, this.a2, this.a3, this.a4, this.a5, this.a6, this.a7,
      this.a8, this.a9, this.a10, this.a11, this.a12, this.a13, this.a14,
      this.a15, this.a16, this.a17, this.a18, this.a19, this.a20, this.a21);

  final int a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14,
      a15, a16, a17, a18, a19, a20, a21;
}
''';

const _parted = '''
part of 'app.dart';

@ToString()
class Parted with IntrospectedObject {
  const Parted(this.id);

  final int id;
}
''';

const _main = r'''
import 'dart:convert';

import 'package:pkg/src/app.dart';
import 'package:pkg/spring_gen/src/beans.spring.introspection.dart';
import 'package:pkg/src/beans.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

void main() {
  final results = <String, Object?>{};
  void check(String name, Object? Function() value) {
    try {
      results[name] = value();
    } on Object catch (error) {
      results[name] = 'threw ${error.runtimeType}: $error';
    }
  }

  check('unregistered', () => '${const Point(1, 2)}');
  Introspector.shared.registerAll($pkgBeansIntrospections);

  const dune = Book(
    'Dune',
    pages: 412,
    tags: ['sf'],
    meta: {'editions': [1965, 2005]},
    password: 'spice',
    subtitle: 'Book one',
    isbn: '978',
  );
  final same = Book(
    'Dune',
    pages: 412,
    tags: ['sf'],
    meta: {'editions': [1965, 2005]},
    password: 'spice',
    subtitle: 'Book one',
    isbn: '978',
  );
  check('equal by content', () => dune == same);
  check('same hash', () => dune.hashCode == same.hashCode);
  check('found in a set', () => {dune}.contains(same));
  check('found as a map key', () => {dune: 1}[same]);
  check('other pages differ', () => dune == same.copyWith(pages: 1));
  check('other tags differ', () => dune == same.copyWith(tags: ['fantasy']));
  check('a subclass is no Book', () => const Book('Dune', pages: 412) ==
      const Novel('Dune', pages: 412));
  check('a subclass without annotations', () =>
      const Novel('Dune', pages: 412) == const Novel('Dune', pages: 412));
  check('text', () => '$dune');
  check('kept', () => dune.copyWith() == dune);
  check('set', () => '${dune.copyWith(pages: 896, title: 'Dune Messiah')}');
  // ignore: avoid_redundant_argument_values
  check('cleared', () => dune.copyWith(subtitle: null).subtitle);
  check('without names', () => '${const Point(1, 2)}');
  check('callSuper equal', () => const Child(1, 'a') == const Child(1, 'a'));
  check('callSuper compares the parent', () =>
      const Child(1, 'a') == const Child(2, 'a'));
  check('callSuper hash', () =>
      const Child(1, 'a').hashCode == const Child(1, 'a').hashCode);
  check('callSuper text', () => '${const Child(1, 'a')}');
  check('without callSuper the parent is not compared', () =>
      const Plain(1, 'a') == const Plain(2, 'a'));
  check('the parent text when not generated', () => '${const Plain(1, 'a')}');
  check('the parent equality when not generated', () =>
      const Signed(1, 'a') == const Signed(1, 'b'));
  check('callSuper of an own ==', () =>
      const Modern(1, 'a') == const Modern(1, 'a') &&
      const Modern(1, 'a') != const Modern(2, 'a'));
  check('callSuper of an own toString', () => '${const Modern(7, 'a')}');
  final page = const Page<String>(['a'], number: 1).copyWith(number: 2);
  check('generic copy keeps its type', () => page is Page<String>);
  check('generic copy', () => '${page.items} ${page.number}');
  check('generic copy clears', () =>
      Page<String>(['a'], parent: const Page(['b'])).copyWith(parent: null)
          .parent);
  final order = const Purchase.create(7, 'gift').copyWith(note: 'rush');
  check('named constructor, excluded kept', () => '${order.id} ${order.note}');
  check('own == with @ToString', () => const Own(1) == const Own(11));
  check('own == text', () => '${const Own(11)}');
  check('late field not set', () => '${Deferred()}');
  check('late field set', () => '${Deferred()..value = 'ready'}');
  check('part file', () => '${const Parted(3)}');
  check('const canonical', () => identical(const Point(1, 2), const Point(1, 2)));
  check('type parameter by content', () =>
      Holder(<int>[1, 2]) == Holder(<int>[1, 2]));
  check('more than 20 fields', () =>
      const Wide(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
          19, 20, 21) ==
      const Wide(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
          19, 20, 21));
  final context = ApplicationContext.run([pkgBeans]);
  check('bean text', () => '${context.getBean<Shelf>()}');
  check('a @Bean method result', () => '${context.getBean<Point>()}');
  context.close();
  print('RESULT ${jsonEncode(results)}');
}
''';

/// Builds the package of [_app] and runs [_main]; the map it prints after
/// `RESULT `.
Future<Map<String, Object?>> _run() async {
  final sources = {
    'lib/src/beans.dart': _scan,
    'lib/src/app.dart': _app,
    'lib/src/parted.dart': _parted,
    'bin/main.dart': _main,
  };
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(generations: packageGenerations),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final directory = await Directory.systemTemp.createTemp('spring_object_');
  addTearDown(() => directory.delete(recursive: true));
  final files = {
    ...sources,
    for (final output in result.outputs)
      output.path: readerWriter.testing.readString(output),
  };
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File('${directory.path}/$key');
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }
  final workspace = await loadPackageConfigUri((await Isolate.packageConfig)!);
  await savePackageConfig(
    PackageConfig([
      ...workspace.packages,
      Package(
        'pkg',
        directory.uri,
        packageUriRoot: directory.uri.resolve('lib/'),
      ),
    ]),
    directory,
  );
  final process = await Process.run(Platform.resolvedExecutable, [
    '--packages=${directory.path}/.dart_tool/package_config.json',
    '${directory.path}/bin/main.dart',
  ]);
  final output = '${process.stdout}';
  final line = LineSplitter.split(
    output,
  ).where((line) => line.startsWith('RESULT ')).firstOrNull;
  expect(line, isNotNull, reason: '$output\n${process.stderr}');
  return jsonDecode(line!.substring('RESULT '.length)) as Map<String, Object?>;
}

void main() {
  test(
    'equality, hashing, toString and copyWith of the generated code',
    () async {
      final results = await _run();
      expect(results, {
        'unregistered': startsWith(
          'threw StateError: Bad state: No description of Point is '
          'registered',
        ),
        'equal by content': true,
        'same hash': true,
        'found in a set': true,
        'found as a map key': 1,
        'other pages differ': false,
        'other tags differ': false,
        'a subclass is no Book': false,
        'a subclass without annotations': true,
        'text':
            'Book(title: Dune, pages: 412, tags: [sf], '
            'meta: {editions: [1965, 2005]}, password: ******, '
            'subtitle: Book one, isbn: ******)',
        'kept': true,
        'set':
            'Book(title: Dune Messiah, pages: 896, tags: [sf], '
            'meta: {editions: [1965, 2005]}, password: ******, '
            'subtitle: Book one, isbn: ******)',
        'cleared': null,
        'without names': 'Point(1)',
        'callSuper equal': true,
        'callSuper compares the parent': false,
        'callSuper hash': true,
        'callSuper text': 'Child(super: Base(id: 1, token: t), name: a)',
        'without callSuper the parent is not compared': true,
        'the parent text when not generated': 'Base(id: 1, token: t)',
        'the parent equality when not generated': true,
        'callSuper of an own ==': true,
        'callSuper of an own toString': 'Modern(super: Legacy#7, name: a)',
        'generic copy keeps its type': true,
        'generic copy': '[a] 2',
        'generic copy clears': null,
        'named constructor, excluded kept': '7 rush',
        'own == with @ToString': true,
        'own == text': 'Own(id: 11)',
        'late field not set': startsWith('threw LateError'),
        'late field set': 'Deferred(value: ready)',
        'part file': 'Parted(id: 3)',
        'const canonical': true,
        'type parameter by content': true,
        'more than 20 fields': true,
        'bean text': 'Shelf(name: main)',
        'a @Bean method result': 'Point(0)',
      });
    },
  );
}
