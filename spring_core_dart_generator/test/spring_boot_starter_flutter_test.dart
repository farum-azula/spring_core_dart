// spring_boot_starter_flutter support: `@BuildContextAccess` beans get generated
// `BuildContext` getters, and `SpringStatelessWidget<(...)>` classes get a
// `SpringWidgetBindings` bean that fills their bean records. Built next to
// stub `flutter` and `spring_boot_starter_flutter` packages (only the declarations the
// generator and the generated code look at); the output is compiled
// against them.
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _stubs = {
  'flutter|lib/widgets.dart': '''
abstract class BuildContext {
  Object get widget;
}

abstract class Widget {
  const Widget({Object? key});
}

abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});
  State<StatefulWidget> createState();
}

abstract class State<T extends StatefulWidget> {
  BuildContext get context => throw UnimplementedError();
  Widget build(BuildContext context);
}
''',
  'flutter|lib/foundation.dart': '''
export 'src/foundation/change_notifier.dart';
''',
  'flutter|lib/src/foundation/change_notifier.dart': '''
abstract class Listenable {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}

mixin class ChangeNotifier implements Listenable {
  final _listeners = <void Function()>[];
  @override
  void addListener(void Function() listener) => _listeners.add(listener);
  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);
  bool get hasListeners => _listeners.isNotEmpty;
  void notifyListeners() {
    for (final listener in [..._listeners]) {
      listener();
    }
  }
  void dispose() {}
}
''',
  'spring_boot_starter_flutter|lib/src/notify_listeners.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

class NotifyListeners {
  const NotifyListeners({this.exclude = const []});
  final List<String> exclude;
}

class ChangeNotifierComponent extends Component {
  const ChangeNotifierComponent({String? name, this.exclude = const []})
    : super(name);
  final List<String> exclude;
}
''',
  'spring_boot_starter_flutter|lib/spring_boot_starter_flutter.dart': '''
export 'src/annotations.dart';
export 'src/notify_listeners.dart';
export 'src/spring_scope.dart';
export 'src/spring_widgets.dart';
''',
  'spring_boot_starter_flutter|lib/src/annotations.dart': '''
class BuildContextAccess {
  const BuildContextAccess({this.name});
  final String? name;
}
''',
  'spring_boot_starter_flutter|lib/src/spring_scope.dart': '''
import 'package:flutter/widgets.dart';

class SpringScope {
  static T beanOf<T extends Object>(BuildContext context, {String? qualifier}) =>
      throw UnimplementedError();
}
''',
  'spring_boot_starter_flutter|lib/src/spring_widgets.dart': '''
import 'package:flutter/widgets.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

abstract class SpringStatelessWidget<B extends Record> extends Widget {
  const SpringStatelessWidget({super.key});
  Widget build(BuildContext context, B beans);
}

abstract class SpringStatefulWidget<B extends Record> extends StatefulWidget {
  const SpringStatefulWidget({super.key});
}

abstract class SpringState<W extends SpringStatefulWidget<B>, B extends Record>
    extends State<W> {
  B get beans => throw UnimplementedError();
}

final class SpringWidgetBinding {
  const SpringWidgetBinding({
    required this.widget,
    required this.beans,
    required this.types,
    required this.resolve,
    this.values,
  });
  final String widget;
  final Type beans;
  final List<Type> types;
  final List<Object?> Function(Record beans)? values;
  final Record Function(BeanFactory factory) resolve;
  static T bean<T extends Object>(BeanFactory factory, [String? name]) =>
      factory.getBean<T>(qualifier: name);
}

final class SpringWidgetBindings {
  const SpringWidgetBindings(this.bindings);
  final List<SpringWidgetBinding> bindings;
}
''',
};

const _header = '''
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
''';

Future<PackageConfig> _packageConfig() async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  return PackageConfig([
    for (final package in isolateConfig.packages)
      if (package.name != 'flutter' &&
          package.name != 'spring_boot_starter_flutter')
        package,
    for (final name in ['flutter', 'spring_boot_starter_flutter'])
      Package(
        name,
        Uri.parse('file:///$name/'),
        packageUriRoot: Uri.parse('file:///$name/lib/'),
      ),
  ]);
}

/// Builds [beans] (a library of `pkg` under the scan).
Future<TestBuilderResult> _build(String beans) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return testBuilder(
    SpringBuilder(proxyMode: ProxyMode.all),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$beans',
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

/// The generated module of [beans] (normalized), after checking that it
/// compiles against the stubs.
Future<String> _generate(String beans) async {
  final result = await _build(beans);
  expect(result.errors, isEmpty);
  const path = 'lib/src/beans.spring.dart';
  final output = result.readerWriter.testing.readString(
    result.outputs.singleWhere((o) => o.path == path),
  );
  final errors = await resolveSources<List<String>>(
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$beans',
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

/// The build errors of [beans].
Future<String> _errors(String beans) async {
  final result = await _build(beans);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

void main() {
  group('@BuildContextAccess', () {
    test('a getter per marked bean, named after the bean or name:', () async {
      final output = await _generate('''
@Component()
@BuildContextAccess()
class Basket {}

@Service()
@BuildContextAccess(name: 'search')
class BookSearch {}

@Component()
class NotMarked {}

typedef Clock = DateTime Function();

abstract interface class Store {}

class MemoryStore implements Store {}

@Configuration()
class AppConfig {
  @Bean()
  @BuildContextAccess()
  Store store() => MemoryStore();

  @Bean()
  @BuildContextAccess()
  Clock clock() => DateTime.now;
}
''');
      expect(
        output,
        _has(
          'extension SpringBeans on BuildContext {'
          "  /// The bean 'basket'.\n"
          "  Basket get basket => SpringScope.beanOf<Basket>(this, qualifier: r'basket');",
        ),
      );
      expect(
        output,
        _has(
          "BookSearch get search => SpringScope.beanOf<BookSearch>(this, qualifier: r'bookSearch');",
        ),
      );
      expect(
        output,
        _has(
          "Store get store => SpringScope.beanOf<Store>(this, qualifier: r'store');",
        ),
      );
      expect(
        output,
        _has(
          'DateTime Function() get clock => '
          "SpringScope.beanOf<DateTime Function()>(this, qualifier: r'clock');",
        ),
      );
      expect(output, isNot(contains('getnotMarked')));
    });

    test('nothing Flutter in a module without @BuildContextAccess or '
        'SpringStatelessWidget', () async {
      final output = await _generate('''
@Component()
class Basket {}
''');
      expect(output, isNot(contains('BuildContext')));
      expect(output, isNot(contains('flutter')));
      expect(output, isNot(contains('SpringStatelessWidget')));
    });

    test('an invalid getter name fails the build', () async {
      expect(
        await _errors('''
@Component('my-basket')
@BuildContextAccess()
class Basket {}
'''),
        contains(
          "@BuildContextAccess on bean 'my-basket' (package:pkg/src/app.dart#Basket)"
          ": 'my-basket' is not a valid Dart identifier for a getter. Give the "
          "getter a name: @BuildContextAccess(name: 'myGetter').",
        ),
      );
      expect(
        await _errors('''
@Component()
@BuildContextAccess(name: '_basket')
class Basket {}
'''),
        contains("'_basket' is private"),
      );
      expect(
        await _errors('''
@Component('switch')
@BuildContextAccess()
class Basket {}
'''),
        contains("'switch' is a reserved word."),
      );
    });

    test('a getter clashing with BuildContext, Object or spring_boot_starter_flutter '
        'fails the build', () async {
      for (final (name, owner) in [
        ('widget', 'BuildContext'),
        ('size', 'BuildContext'),
        ('findRenderObject', 'BuildContext'),
        ('hashCode', 'Object'),
        ('bean', 'SpringBuildContext'),
        ('message', 'SpringBuildContext'),
      ]) {
        expect(
          await _errors('''
@Component()
@BuildContextAccess(name: '$name')
class Basket {}
'''),
          contains(
            "@BuildContextAccess(name: '$name') on package:pkg/src/app.dart#Basket: "
            "'$name' clashes with $owner.$name, which a generated getter "
            'cannot replace. Choose another name.',
          ),
        );
      }
    });

    test('two beans with the same getter fail the build', () async {
      expect(
        await _errors('''
@Component()
@BuildContextAccess(name: 'cart')
class Basket {}

@Component()
@BuildContextAccess(name: 'cart')
class WishList {}
'''),
        contains(
          "the getter 'cart' is already generated for bean 'basket' "
          '(package:pkg/src/app.dart#Basket)',
        ),
      );
    });

    test('@BuildContextAccess on a class that is no bean fails the build', () async {
      expect(
        await _errors('''
@BuildContextAccess()
class Basket {}
'''),
        contains(
          '@BuildContextAccess on Basket, which is no bean of this application',
        ),
      );
    });
  });

  test('@SpringBootApplication: getters after the run and reload functions, '
      'bindings named after the application module', () async {
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    await readerWriter.testing.loadIsolateSources();
    final result = await testBuilder(
      SpringBuilder(proxyMode: ProxyMode.all),
      {
        'pkg|lib/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''',
        'pkg|lib/src/app.dart':
            '''
$_header
@Component()
@BuildContextAccess()
class Basket {}

class Badge extends SpringStatelessWidget<(Basket,)> {
  const Badge();
  @override
  Widget build(BuildContext context, (Basket,) beans) => this;
}
''',
        ..._stubs,
      },
      rootPackage: 'pkg',
      readerWriter: readerWriter,
      packageConfig: await _packageConfig(),
      flattenOutput: true,
    );
    expect(result.errors, isEmpty);
    final output = _normalize(
      result.readerWriter.testing.readString(
        result.outputs.singleWhere((o) => o.path == 'lib/main.spring.dart'),
      ),
    );
    expect(output, _has("name: r'flutterSpringWidgetBindings#application'"));
    expect(
      output.indexOf('extensionSpringBeansonBuildContext'),
      greaterThan(output.indexOf('reloadApplicationAsync(')),
    );
  });

  group('SpringStatelessWidget', () {
    test('one SpringWidgetBindings bean with a binding per record type', () async {
      final output = await _generate('''
@Component()
class Basket {}

abstract interface class Navigator {}

@Component()
class AppNavigator implements Navigator {}

@Component()
class Clock {}

class Analytics {}

typedef BadgeBeans = (Basket, Navigator);

class BasketBadge extends SpringStatelessWidget<BadgeBeans> {
  const BasketBadge({super.key});
  @override
  Widget build(BuildContext context, BadgeBeans beans) => this;
}

// The same record: the first widget names the binding.
class BasketBadge2 extends SpringStatelessWidget<(Basket, Navigator)> {
  const BasketBadge2({super.key});
  @override
  Widget build(BuildContext context, (Basket, Navigator) beans) => this;
}

class _Header extends SpringStatelessWidget<({Basket basket, Clock clock, Analytics? analytics})> {
  const _Header();
  @override
  Widget build(BuildContext context, ({Basket basket, Clock clock, Analytics? analytics}) beans) => this;
}

class Single extends SpringStatelessWidget<(Clock,)> {
  const Single({super.key});
  @override
  Widget build(BuildContext context, (Clock,) beans) => this;
}

// A base class: its record is still a type parameter.
abstract class Page<B extends Record> extends SpringStatelessWidget<B> {
  const Page({super.key});
}

class ClockPage extends Page<(Clock,)> {
  const ClockPage({super.key});
  @override
  Widget build(BuildContext context, (Clock,) beans) => this;
}

Widget unused() => const _Header();
''');
      expect(
        output,
        _has(
          'BeanDefinition<SpringWidgetBindings>('
          "  name: r'flutterSpringWidgetBindings#pkgBeans',"
          "  source: r'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart#SpringWidgetBindings',"
          '  types: const [SpringWidgetBindings],'
          '  autowireCandidate: false,'
          '  create: (r) => SpringWidgetBindings([',
        ),
      );
      expect(
        output,
        _has(
          'SpringWidgetBinding('
          "  widget: r'package:pkg/src/app.dart#BasketBadge',"
          '  beans: BadgeBeans,'
          '  types: const [Basket, Navigator],'
          '  resolve: (f) => (SpringWidgetBinding.bean<Basket>(f), '
          'SpringWidgetBinding.bean<Navigator>(f)),'
          r'values: (r) { final v = (r as (Basket, Navigator)); '
          r'return [v.$1, v.$2]; })',
        ),
      );
      expect(output, isNot(contains('app.dart#BasketBadge2')));
      expect(
        output,
        _has(
          'SpringWidgetBinding('
          "  widget: r'package:pkg/src/app.dart#_Header',"
          '  beans: _\$typeOf<({Analytics? analytics, Basket basket, Clock clock})>(),'
          '  types: const [Basket, Clock],'
          '  resolve: (f) => ('
          '    analytics: f.findBean<Analytics>(),'
          "    basket: SpringWidgetBinding.bean<Basket>(f, r'basket'),"
          "    clock: SpringWidgetBinding.bean<Clock>(f, r'clock'),"
          '  ),'
          'values: (r) { final v = (r as ({Analytics? analytics, Basket '
          'basket, Clock clock})); return [v.analytics, v.basket, v.clock]; })',
        ),
      );
      expect(
        output,
        _has(
          "widget: r'package:pkg/src/app.dart#Single',"
          // Normalized: the one-field record's comma is dropped here; the
          // compile check above proves it is written.
          '  beans: _\$typeOf<(Clock)>(),'
          '  types: const [Clock],'
          '  resolve: (f) => (SpringWidgetBinding.bean<Clock>(f))',
        ),
      );
      expect(output, isNot(contains('app.dart#ClockPage')));
      expect(output, isNot(contains('app.dart#Page')));
      expect(output, _has(r'Type _$typeOf<T>() => T;'));
    });

    test('a SpringState gets a binding like a SpringStatelessWidget', () async {
      final output = await _generate('''
@Component()
class Basket {}

@Component()
class Clock {}

class BasketPage extends SpringStatefulWidget<(Basket, Clock)> {
  const BasketPage({super.key});
  @override
  State<BasketPage> createState() => _BasketPageState();
}

class _BasketPageState extends SpringState<BasketPage, (Basket, Clock)> {
  @override
  Widget build(BuildContext context) => const BasketPage();
}

// A base state: its record is still a type parameter.
abstract class PageState<W extends SpringStatefulWidget<B>, B extends Record>
    extends SpringState<W, B> {}
''');
      expect(
        output,
        _has(
          'SpringWidgetBinding('
          "  widget: r'package:pkg/src/app.dart#_BasketPageState',"
          '  beans: _\$typeOf<(Basket, Clock)>(),'
          '  types: const [Basket, Clock],'
          '  resolve: (f) => (SpringWidgetBinding.bean<Basket>(f), '
          'SpringWidgetBinding.bean<Clock>(f)),'
          r'values: (r) { final v = (r as (Basket, Clock)); '
          r'return [v.$1, v.$2]; })',
        ),
      );
      expect(output, isNot(contains('app.dart#PageState')));
      expect(
        await _errors('''
class Page extends SpringStatefulWidget<(Object,)> {
  const Page();
  @override
  State<Page> createState() => _PageState();
}

class _PageState extends SpringState<Page, (Object,)> {
  @override
  Widget build(BuildContext context) => const Page();
}
'''),
        contains('SpringState _PageState: Object ('),
      );
    });

    test('a record field that is no bean type fails the build', () async {
      for (final (type, shown) in [
        ('(Basket, dynamic)', 'dynamic'),
        ('(Basket, void Function())', 'void Function()'),
        ('(Basket, Object)', 'Object'),
        ('({(int, int) pair})', '(int, int)'),
      ]) {
        expect(
          await _errors('''
@Component()
class Basket {}

class Bad extends SpringStatelessWidget<$type> {
  const Bad();
  @override
  Widget build(BuildContext context, $type beans) => this;
}
'''),
          contains('SpringStatelessWidget Bad: $shown ('),
          reason: type,
        );
      }
    });

    test('a record type parameter on a concrete widget fails the build', () async {
      expect(
        await _errors('''
class Generic<B extends Record> extends SpringStatelessWidget<B> {
  const Generic();
  @override
  Widget build(BuildContext context, B beans) => this;
}
'''),
        contains(
          'SpringStatelessWidget Generic: its beans must be a record of bean types, '
          'like SpringStatelessWidget<(Basket, AppNavigator)>, not B.',
        ),
      );
      expect(
        await _errors('''
class Any extends SpringStatelessWidget<Record> {
  const Any();
  @override
  Widget build(BuildContext context, Record beans) => this;
}
'''),
        contains(
          'SpringStatelessWidget Any: its beans must be a record of bean types',
        ),
      );
    });
  });

  group('@ChangeNotifierComponent', () {
    test('its proxy mixes ChangeNotifier in: subclass and delegating '
        'proxies; not when the class is one already', () async {
      final output = await _generate('''
@ChangeNotifierComponent()
class Counter {
  int _value = 0;
  int get value => _value;
  void increment() => _value++;
}

@ChangeNotifierComponent(exclude: ['peek'])
class Basket {
  int count = 0;
  void add() => count++;
  int peek() => count;
}

@ChangeNotifierComponent()
class Cart extends ChangeNotifier {
  int items = 0;
  void add() => items++;
}
''');
      expect(
        output,
        _has(r'class _$CounterProxy extends Counter with ChangeNotifier'),
      );
      expect(
        output,
        _has(r'class _$BasketProxy with ChangeNotifier implements Basket'),
      );
      expect(
        output,
        isNot(contains(_normalize(r'_$CartProxy extends Cart with'))),
      );
      expect(output, isNot(contains(_normalize(r'_$CartProxy with'))));
    });

    test('exclude names a member of the class', () async {
      expect(
        await _errors('''
@ChangeNotifierComponent(exclude: ['reset'])
class Counter {
  int value = 0;
  void increment() => value++;
}
'''),
        contains(
          '@ChangeNotifierComponent on Counter: exclude names reset, which is '
          'no public method, setter or field of Counter.',
        ),
      );
      expect(
        await _errors('''
@Component()
@NotifyListeners(exclude: ['nope'])
class Basket extends ChangeNotifier {
  void add() {}
}
'''),
        contains('@NotifyListeners on Basket: exclude names nope'),
      );
    });

    test("ChangeNotifier's members on a class that is no ChangeNotifier "
        'fail the build', () async {
      expect(
        await _errors('''
@ChangeNotifierComponent()
class Player {
  void dispose() {}
  void play() {}
}
'''),
        contains(
          '@ChangeNotifierComponent on Player: dispose would clash with the '
          'ChangeNotifier its proxy mixes in',
        ),
      );
    });
  });

  test('bindings list the beans of a record for the widgets', () async {
    final output = await _generate('''
@Component()
class Basket {}

@Component()
class Clock {}

class Badge extends SpringStatelessWidget<(Basket, {Clock clock})> {
  const Badge();
  @override
  Widget build(BuildContext context, (Basket, {Clock clock}) beans) => this;
}
''');
    expect(
      output,
      _has(
        'values: (r) { final v = (r as (Basket, {Clock clock})); '
        r'return [v.$1, v.clock]; }',
      ),
    );
  });
}
