import 'package:analyzer/dart/element/element.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/module_emitter.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';

// Suffix of generated files; also used to skip them as scan inputs.
const _outputExtension = '.beans.dart';

/// For every library with a `@ComponentScan` variable, scans the library's
/// directory recursively and writes `<file>.beans.dart` with a `BeanModule`.
///
/// The builder runs on every `.dart` input, but only does real work for a
/// library with exactly one public top-level variable annotated with
/// `@ComponentScan()`. It then resolves every library under that file's
/// directory (sorted by path, so output is deterministic), feeds them to a
/// [BeanScanner], checks that bean names and aliases are unique, and
/// writes the module with a [ModuleEmitter]. The generated variable is the
/// scan variable's name prefixed with `$`.
///
/// Example (generated code uses import prefixes such as `_i1.`; they are
/// omitted here):
///
/// ```dart
/// // Input: lib/src/beans.dart
/// @ComponentScan()
/// final BeanModule appBeans = $appBeans;
///
/// // Input: lib/src/greeting/greeter.dart
/// @Service()
/// class Greeter {
///   Greeter(this.clock);
///   final Clock clock;
/// }
///
/// // Output: lib/src/beans.beans.dart
/// /// Beans found by `@ComponentScan` in `lib/src/`.
/// final BeanModule $appBeans = BeanModule(r'appBeans', [
///   BeanDefinition<Greeter>(
///     name: r'greeter',
///     source: r'package:app/src/greeting/greeter.dart#Greeter',
///     types: const [Greeter],
///     dependencies: const [Dependency(Clock, name: r'clock')],
///     create: (r) => Greeter(r.dependency<Clock>(name: r'clock')),
///   ),
///   // ...
/// ]);
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring scans the classpath when the context starts, not at build
/// // time; the closest equivalent of one SpringBuilder run is:
/// @Configuration
/// @ComponentScan("com.example.app")
/// class AppConfig {}
///
/// var registry = new DefaultListableBeanFactory();
/// new ClassPathBeanDefinitionScanner(registry).scan("com.example.app");
/// // Duplicate names fail with ConflictingBeanDefinitionException
/// // (here: InvalidGenerationSource during the build).
/// ```
class SpringBuilder implements Builder {
  /// Creates the builder; [proxyMode] defaults to [ProxyMode.all].
  ///
  /// ```dart
  /// const builder = SpringBuilder(proxyMode: ProxyMode.interfaces);
  /// ```
  const SpringBuilder({this.proxyMode = ProxyMode.all});

  /// Which beans get generated AOP proxies (build option `aop_proxies`:
  /// `all`, `interfaces` or `none`).
  final ProxyMode proxyMode;

  /// Every `.dart` input may produce a `.beans.dart` output next to it.
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': [_outputExtension],
  };

  /// Generates `<input>.beans.dart` when [buildStep]'s input declares a
  /// `@ComponentScan` variable; does nothing for any other input.
  ///
  /// Throws `InvalidGenerationSource` when a file has more than one
  /// `@ComponentScan`, when the scan variable is private or starts with
  /// `$`, when a scanned class is invalid (see [BeanScanner]) or when two
  /// beans share a name or alias.
  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (input.path.endsWith(_outputExtension)) {
      return;
    }
    // Cheap text check before resolving every library in the package.
    if (!(await buildStep.readAsString(input)).contains('ComponentScan')) {
      return;
    }
    final resolver = buildStep.resolver;
    if (!await resolver.isLibrary(input)) {
      return;
    }
    final library = await resolver.libraryFor(input);
    final scans = [
      for (final variable in library.topLevelVariables)
        if (componentScanChecker.hasAnnotationOf(variable)) variable,
    ];
    if (scans.isEmpty) {
      return;
    }
    if (scans.length > 1) {
      throw InvalidGenerationSource(
        'Only one @ComponentScan is allowed per file.',
        element: scans[1],
      );
    }
    final scan = scans.single;
    final variableName = scan.name!;
    if (variableName.startsWith(r'$') || variableName.startsWith('_')) {
      throw InvalidGenerationSource(
        r'@ComponentScan variable must be public and must not start with $.',
        element: scan,
      );
    }

    // The scan root is the directory of the annotated file; every library
    // below it (recursively) is scanned, generated files excluded.
    final directory = p.url.dirname(input.path);
    final assets = await buildStep
        .findAssets(Glob('$directory/**.dart'))
        .where((asset) => !asset.path.endsWith(_outputExtension))
        .toList();
    assets.sort((a, b) => a.path.compareTo(b.path));

    final module = ModuleModel();
    final scanner = BeanScanner(module, proxyMode: proxyMode);
    for (final asset in assets) {
      if (await resolver.isLibrary(asset)) {
        scanner.scanLibrary(await resolver.libraryFor(asset));
      }
    }
    _checkUniqueNames(module.beans);

    final output = input.changeExtension(_outputExtension);
    await buildStep.writeAsString(
      output,
      ModuleEmitter(output).emit(
        moduleName: variableName,
        variableName: '\$$variableName',
        scannedDirectory: directory,
        module: module,
      ),
    );
  }

  // Bean names and aliases share one namespace (like Spring's registry,
  // which forbids overriding by default), so a clash is a build error that
  // names both declarations.
  void _checkUniqueNames(List<BeanModel> beans) {
    final byName = <String, Element>{};
    for (final bean in beans) {
      for (final name in [bean.name, ...bean.aliases]) {
        final previous = byName[name];
        if (previous != null) {
          throw InvalidGenerationSource(
            "Bean name '$name' is used by both "
            '${previous.displayName} and ${bean.element.displayName}.',
            element: bean.element,
          );
        }
        byName[name] = bean.element;
      }
    }
  }
}
