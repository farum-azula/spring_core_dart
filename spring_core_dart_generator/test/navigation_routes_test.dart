// spring_boot_starter_flutter_navigation support: `@ScreenRoute` and
// `@RouteShell` widgets become the module's `ScreenRoutes` bean, and each
// screen gets its constants (`extension BookPageRoute on BookPage`). Built
// next to stub `flutter` and `spring_boot_starter_flutter_navigation`
// packages (only what the generator and the generated code look at); the
// output is compiled against them.
import 'dart:convert';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/spring_metadata_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header = '''
import 'package:flutter/widgets.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

''';

const _stubs = {
  'flutter|lib/widgets.dart': '''
export 'src/widgets/framework.dart';
''',
  'flutter|lib/src/widgets/framework.dart': '''
abstract class BuildContext {}

abstract class Widget {
  const Widget({Object? key});
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget({super.key});
  Widget build(BuildContext context);
}
''',
  'spring_boot_starter_flutter_navigation|lib/spring_boot_starter_flutter_navigation.dart':
      '''
export 'src/annotations.dart';
export 'src/shell_state.dart';
export 'src/routes.dart';
''',
  'spring_boot_starter_flutter_navigation|lib/src/annotations.dart': '''
enum PageTransition { theme, platform, fadeUpwards, zoom, cupertino, fade, none }

class ScreenRoute {
  const ScreenRoute(this.path, {this.title, this.name, this.params = const {},
      this.extra, this.shell, this.branch,
      this.transition = PageTransition.theme, this.content})
      : notFound = false;
  const ScreenRoute.notFound() : path = '', title = null, name = null,
      params = const {}, extra = null, shell = null, branch = null,
      transition = PageTransition.theme, content = null, notFound = true;
  final String? branch;
  final PageTransition transition;
  final String path;
  final String? title;
  final String? name;
  final Map<String, Type> params;
  final Type? extra;
  final Type? shell;
  final String? content;
  final bool notFound;
}

class RouteShell {
  const RouteShell({required this.branches});
  final List<String> branches;
}

class RouteInfo {
  const RouteInfo({this.description, this.image, this.index = true,
      this.paths = const [], this.link = true});
  final String? description;
  final String? image;
  final bool index;
  final List<String> paths;
  final bool link;
}
''',
  'spring_boot_starter_flutter_navigation|lib/src/shell_state.dart': '''
import 'package:flutter/widgets.dart';

abstract interface class ShellState {
  Widget get child;
}
''',
  'spring_boot_starter_flutter_navigation|lib/src/routes.dart': '''
import 'package:flutter/widgets.dart';
import 'shell_state.dart';

abstract final class RouteAttributes {
  static const preAuthorize = 'preAuthorize';
}

class RouteState {}

class ScreenRoutes {
  static ScreenRoutesBuilder route({String? source}) => ScreenRoutesBuilder();
}

class ScreenRoutesBuilder {
  ScreenRoutesBuilder screen(String path, Widget Function(RouteState) builder,
      {String? name, String? title, Map<String, Type> params = const {},
      Type? extra, Object? shell, String? branch,
      PageTransition transition = PageTransition.theme,
      String? content, String? source,
      Map<String, Object?> attributes = const {}, bool link = true}) => this;
  ScreenRoutesBuilder shell(Widget Function(ShellState) builder,
      void Function(ShellBranchesBuilder) branches,
      {Object? key, String? source}) => this;
  ScreenRoutesBuilder notFound(Widget Function(RouteState) builder) => this;
  ScreenRoutes build() => ScreenRoutes();
}

class ShellBranchesBuilder {
  ShellBranchesBuilder branch(String path,
      void Function(ScreenRoutesBuilder) screens) => this;
}

class RouteLocation {
  RouteLocation.expand(String pattern, {Map<String, Object?> pathVariables
      = const {}, Map<String, Object?> params = const {}, Object? extra});
}

sealed class RouteKey<T> { const RouteKey(); }
final class RouteVar<T> extends RouteKey<T> {
  const RouteVar(this.name);
  final String name;
}
final class RouteParam<T> extends RouteKey<T?> {
  const RouteParam(this.name);
  final String name;
}
final class RouteExtra<T> extends RouteKey<T?> {
  const RouteExtra();
}
''',
};

const _stubPackages = ['flutter', 'spring_boot_starter_flutter_navigation'];

Future<PackageConfig> _packageConfig() async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  return PackageConfig([
    for (final package in isolateConfig.packages)
      if (!_stubPackages.contains(package.name)) package,
    for (final name in _stubPackages)
      Package(
        name,
        Uri.parse('file:///$name/'),
        packageUriRoot: Uri.parse('file:///$name/lib/'),
      ),
  ]);
}

Future<TestBuilderResult> _build(String code) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$code',
      ..._stubs,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: await _packageConfig(),
    flattenOutput: true,
  );
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

// The generated module (normalized), after checking that it compiles.
Future<String> _generate(String code) async {
  final result = await _build(code);
  expect(result.errors, isEmpty);
  const path = 'lib/spring_gen/src/beans.spring.dart';
  final output = result.readerWriter.testing.readString(
    result.outputs.singleWhere((o) => o.path == path),
  );
  final errors = await resolveSources<List<String>>(
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$code',
      'pkg|$path': output,
      ..._stubs,
    },
    (resolver) async {
      final library = await resolver.libraryFor(AssetId('pkg', path));
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
    resolverFor: 'pkg|$path',
    packageConfig: await _packageConfig(),
    readAllSourcesFromFilesystem: true,
  );
  expect(errors, isEmpty, reason: output);
  return _normalize(output);
}

Future<String> _errors(String code) async {
  final result = await _build(code);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

const _app = '''
class BookSummary {}

@RouteShell(branches: ['/catalog', '/profile'])
class MainTabs extends StatelessWidget {
  const MainTabs(this.shell, {super.key});
  final ShellState shell;
  @override
  Widget build(BuildContext context) => shell.child;
}

@ScreenRoute('/catalog/books/{isbn}', title: 'Book',
    params: {'page': int, 'sort-by': String}, extra: BookSummary)
class BookPage extends StatelessWidget {
  const BookPage({super.key});
  @override
  Widget build(BuildContext context) => this;
}

@ScreenRoute('/docs/{*path}', content: 'resources:content/docs/')
@RouteInfo(link: false)
class DocPage extends StatelessWidget {
  DocPage({super.key});
  @override
  Widget build(BuildContext context) => this;
}

@ScreenRoute('/settings', shell: MainTabs, name: 'settings')
@PreAuthorize('isAuthenticated()')
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => this;
}

@ScreenRoute('/motion', branch: '/profile', transition: PageTransition.none)
class MotionPage extends StatelessWidget {
  const MotionPage({super.key});
  @override
  Widget build(BuildContext context) => this;
}

@ScreenRoute.notFound()
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});
  @override
  Widget build(BuildContext context) => this;
}
''';

void main() {
  test('the screens and shells make the module ScreenRoutes bean', () async {
    final code = await _generate(_app);
    expect(code, _has("name: r'screenRoutes#pkgBeans'"));
    // Its type is the definition's type argument, no `types:` (0.7.0).
    expect(code, _has('BeanDefinition<ScreenRoutes>('));
    expect(code, isNot(_has('types: const [ScreenRoutes]')));
    expect(
      code,
      _has(
        [
          "ScreenRoutes.route(source: r'pkgBeans')",
          ".shell((s) => MainTabs(s), (t) => t.branch(r'/catalog', (b) => b)",
          ".branch(r'/profile', (b) => b), key: MainTabs, ",
          "source: r'package:pkg/src/app.dart#MainTabs')",
        ].join(),
      ),
    );
    expect(
      code,
      _has(
        ".screen(r'/catalog/books/{isbn}', (r) => const BookPage(), "
        "name: r'book-page', title: r'Book', "
        "params: {r'page': int, r'sort-by': String}, extra: BookSummary, "
        "source: r'package:pkg/src/app.dart#BookPage')",
      ),
    );
    // Not const: the constructor is not.
    expect(code, _has('(r) => DocPage()'));
    expect(code, _has("content: r'resources:content/docs/'"));
    expect(
      code,
      _has("link: false, source: r'package:pkg/src/app.dart#DocPage'"),
    );
    expect(code, _has("name: r'settings', shell: MainTabs"));
    expect(
      code,
      _has(
        'attributes: const {RouteAttributes.preAuthorize: '
        "r'isAuthenticated()'}",
      ),
    );
    expect(code, _has('.notFound((r) => const NotFoundPage()).build()'));
    // A branch its path is not under, and a transition of its own; the
    // theme's (the default) is not written.
    expect(
      code,
      _has(
        ".screen(r'/motion', (r) => const MotionPage(), "
        "name: r'motion-page', branch: r'/profile', "
        'transition: PageTransition.none, '
        "source: r'package:pkg/src/app.dart#MotionPage')",
      ),
    );
    expect(code, isNot(_has('PageTransition.theme')));
  });

  test('each screen gets its constants and to()', () async {
    final code = await _generate(_app);
    expect(code, _has('extension BookPageRoute on BookPage {'));
    expect(code, _has("static const pattern = r'/catalog/books/{isbn}';"));
    expect(code, _has("static const routeName = r'book-page';"));
    expect(code, _has("static const isbn = RouteVar<String>(r'isbn');"));
    expect(code, _has("static const page = RouteParam<int>(r'page');"));
    expect(code, _has("static const sortBy = RouteParam<String>(r'sort-by');"));
    expect(code, _has('static const extra = RouteExtra<BookSummary>();'));
    expect(
      code,
      _has(
        'static RouteLocation to({required String isbn, int? page, '
        'String? sortBy, BookSummary? extra}) => RouteLocation.expand(pattern, '
        "pathVariables: {r'isbn': isbn}, "
        "params: {r'page': page, r'sort-by': sortBy}, extra: extra);",
      ),
    );
    // `{*path}` of the docs: the variable is `path`, the pattern `pattern`.
    expect(code, _has("static const path = RouteVar<String>(r'path');"));
    expect(code, _has("static const pattern = r'/docs/{*path}';"));
    expect(code, isNot(contains('extensionNotFoundPageRoute')));
  });

  group('build errors', () {
    test('a screen the router cannot make', () async {
      expect(
        await _errors('''
@ScreenRoute('/a')
class A extends StatelessWidget {
  const A(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context) => this;
}
'''),
        contains('needs an unnamed constructor without required parameters'),
      );
    });

    test('a shell that does not take its ShellState', () async {
      expect(
        await _errors('''
@RouteShell(branches: ['/a'])
class Tabs extends StatelessWidget {
  const Tabs({super.key});
  @override
  Widget build(BuildContext context) => this;
}
'''),
        contains('whose only required parameter is its ShellState'),
      );
    });

    test('a path two screens declare', () async {
      const screen = '''
@ScreenRoute('/same')
class %s extends StatelessWidget {
  const %s({super.key});
  @override
  Widget build(BuildContext context) => this;
}
''';
      expect(
        await _errors(
          screen.replaceAll('%s', 'One') + screen.replaceAll('%s', 'Two'),
        ),
        allOf(contains('declared twice'), contains('One'), contains('Two')),
      );
    });

    test('a value named like a reserved word or a private name', () async {
      for (final variable in ['class', '_page']) {
        expect(
          await _errors('''
@ScreenRoute('/docs/{$variable}')
class Doc extends StatelessWidget {
  const Doc({super.key});
  @override
  Widget build(BuildContext context) => this;
}
'''),
          contains('makes no Dart name'),
          reason: variable,
        );
      }
    });

    test('a value named like a constant of the extension', () async {
      expect(
        await _errors('''
@ScreenRoute('/docs/{*pattern}')
class Doc extends StatelessWidget {
  const Doc({super.key});
  @override
  Widget build(BuildContext context) => this;
}
'''),
        contains('clashes with the constant DocRoute.pattern'),
      );
    });

    test('a parameter named like a path variable', () async {
      expect(
        await _errors('''
@ScreenRoute('/books/{isbn}', params: {'isbn': int})
class Book extends StatelessWidget {
  const Book({super.key});
  @override
  Widget build(BuildContext context) => this;
}
'''),
        contains('also a path variable'),
      );
    });

    test('an annotated class that is no widget', () async {
      expect(
        await _errors('''
@ScreenRoute('/a')
class A {}
'''),
        contains('is not a widget'),
      );
    });

    test('a malformed path', () async {
      expect(
        await _errors('''
@ScreenRoute('/a/{*rest}/b')
class A extends StatelessWidget {
  const A({super.key});
  @override
  Widget build(BuildContext context) => this;
}
'''),
        contains('{*name} before its end'),
      );
    });
  });

  test('spring_metadata.json lists the routes and shells', () async {
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    await readerWriter.testing.loadIsolateSources();
    await testBuilder(
      SpringMetadataBuilder(packageDirectories: PackageDirectories()),
      {
        'pkg|lib/src/beans.dart': _scan,
        'pkg|lib/src/app.dart': '$_header$_app',
        ..._stubs,
      },
      rootPackage: 'pkg',
      readerWriter: readerWriter,
      packageConfig: await _packageConfig(),
      flattenOutput: true,
    );
    final json = jsonDecode(
      readerWriter.testing.readString(
        AssetId('pkg', 'lib/spring_gen/spring_metadata.json'),
      ),
    ) as Map<String, Object?>;
    final routes = [for (final r in json['routes']! as List) r as Map];
    final book = routes.firstWhere((r) => r['class'] == 'BookPage');
    expect(book, {
      'path': '/catalog/books/{isbn}',
      'name': 'book-page',
      'class': 'BookPage',
      'source': 'package:pkg/src/app.dart#BookPage',
      'title': 'Book',
      'params': {'page': 'int', 'sort-by': 'String'},
      'extra': 'BookSummary',
    });
    final docs = routes.firstWhere((r) => r['class'] == 'DocPage');
    expect(docs['content'], 'resources:content/docs/');
    expect(docs['link'], isFalse);
    final settings = routes.firstWhere((r) => r['class'] == 'SettingsPage');
    expect(settings['preAuthorize'], 'isAuthenticated()');
    expect(settings['shell'], 'MainTabs');
    expect(json['shells'], [
      {
        'class': 'MainTabs',
        'source': 'package:pkg/src/app.dart#MainTabs',
        'branches': ['/catalog', '/profile'],
      },
    ]);
  });
}
