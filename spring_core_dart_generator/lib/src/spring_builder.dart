import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/module_emitter.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_gen/source_gen.dart';

// Suffix of generated files; also used to skip them as scan inputs.
const _outputExtension = '.beans.dart';

const _bootUrl = 'package:spring_boot_dart/spring_boot_dart.dart';

/// `@SpringBootApplication` from `spring_boot_dart` (matched by URL, so the
/// generator does not depend on that package).
const springBootApplicationChecker = TypeChecker.fromUrl(
  'package:spring_boot_dart/src/annotations.dart#SpringBootApplication',
);

/// `@AutoConfigurationModule` from `spring_boot_dart`.
const autoConfigurationModuleChecker = TypeChecker.fromUrl(
  'package:spring_boot_dart/src/annotations.dart#AutoConfigurationModule',
);

/// Where a library declares its auto-configuration modules (like Spring
/// Boot's `META-INF/spring/...AutoConfiguration.imports`).
const autoConfigurationLibrary = 'lib/spring_auto_configuration.dart';

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
    final text = await buildStep.readAsString(input);
    if (!text.contains('ComponentScan') &&
        !text.contains('SpringBootApplication')) {
      return;
    }
    final resolver = buildStep.resolver;
    if (!await resolver.isLibrary(input)) {
      return;
    }
    final library = await resolver.libraryFor(input);
    final boots = [
      for (final function in library.topLevelFunctions)
        if (springBootApplicationChecker.hasAnnotationOf(function)) function,
    ];
    if (boots.isNotEmpty) {
      await _buildApplication(buildStep, boots);
      return;
    }
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
    await _scanLibraries(buildStep, scanner, assets);
    _checkUniqueNames(module.beans);

    final output = input.changeExtension(_outputExtension);
    await buildStep.writeAsString(
      output,
      ModuleEmitter(output).emit(
        moduleName: variableName,
        variableName: '\$$variableName',
        scannedDirectory: directory,
        module: module,
        resources: await _resources(buildStep),
      ),
    );
  }

  /// Files under `lib/resources/` (Spring's classpath resources), embedded
  /// so `classpath:` works everywhere without Flutter asset declarations.
  /// Text files stay readable; other files are base64-encoded; files above
  /// [_maxEmbeddedBytes] are skipped with a warning.
  static Future<Map<String, ({String? text, String? base64})>> _resources(
    BuildStep buildStep,
  ) async {
    final assets = await buildStep
        .findAssets(Glob('lib/resources/**'))
        .where((asset) => !asset.path.endsWith('.dart'))
        .toList();
    assets.sort((a, b) => a.path.compareTo(b.path));
    final result = <String, ({String? text, String? base64})>{};
    for (final asset in assets) {
      final bytes = await buildStep.readAsBytes(asset);
      final path = asset.path.substring('lib/resources/'.length);
      if (bytes.length > _maxEmbeddedBytes) {
        log.warning(
          'lib/resources/$path is larger than $_maxEmbeddedBytes bytes and '
          'is not embedded; ship it as a Flutter asset or a file instead.',
        );
        continue;
      }
      try {
        result[path] = (text: const Utf8Decoder().convert(bytes), base64: null);
      } on FormatException {
        result[path] = (text: null, base64: base64Encode(bytes));
      }
    }
    return result;
  }

  static const _maxEmbeddedBytes = 1024 * 1024;

  // `@SpringBootApplication` on `main`: like Spring Boot's component scan
  // from the application class, the whole package is scanned — `lib/` and
  // the directory of `main` (e.g. `bin/`) — and the output also declares
  // `springApplication` and `runApplication(args)`.
  Future<void> _buildApplication(
    BuildStep buildStep,
    List<TopLevelFunctionElement> boots,
  ) async {
    if (boots.length > 1) {
      throw InvalidGenerationSource(
        'Only one @SpringBootApplication is allowed per file.',
        element: boots[1],
      );
    }
    final input = buildStep.inputId;
    final directory = p.url.dirname(input.path);
    final roots = {'lib', directory}
      ..removeWhere((root) => root != 'lib' && p.url.isWithin('lib', root));
    final assets = <AssetId>{
      for (final root in roots)
        ...await buildStep
            .findAssets(Glob('${Glob.quote(root)}/**.dart'))
            .where((asset) => !asset.path.endsWith(_outputExtension))
            .toList(),
    }.toList()..sort((a, b) => a.path.compareTo(b.path));

    final module = ModuleModel();
    final scanner = BeanScanner(module, proxyMode: proxyMode);
    await _scanLibraries(buildStep, scanner, assets);
    _checkUniqueNames(module.beans);

    final autoConfigurations = await _autoConfigurations(buildStep);
    final springApplication = refer('springApplication');
    final output = input.changeExtension(_outputExtension);
    final source = ModuleEmitter(output).emit(
      moduleName: 'application',
      variableName: r'$application',
      scannedDirectory: roots.map((r) => '$r/').join(' and '),
      module: module,
      resources: await _resources(buildStep),
      extra: [
        Method(
          (m) => m
            ..docs.add(
              '/// The `@SpringBootApplication` of the current code (a '
              'getter, so it is\n/// up to date after a hot reload).',
            )
            ..type = MethodType.getter
            ..returns = refer('SpringApplication', _bootUrl)
            ..name = 'springApplication'
            ..lambda = true
            ..body = refer('SpringApplication', _bootUrl)
                .newInstance(
                  [
                    literalList([refer(r'$application')]),
                  ],
                  {
                    if (autoConfigurations.isNotEmpty)
                      'autoConfigurations': literalList(autoConfigurations),
                    'fingerprint': literalString(_fingerprintPlaceholder),
                  },
                )
                .code,
        ),
        Method(
          (m) => m
            ..docs.add(
              '/// Starts the application: config files, environment, '
              'context, runners\n'
              '/// (asynchronous runners go on one after another after it '
              'returns;\n'
              '/// [runApplicationAsync] waits for them).',
            )
            ..returns = refer('ConfigurableApplicationContext', _bootUrl)
            ..name = 'runApplication'
            ..requiredParameters.add(
              Parameter(
                (p) => p
                  ..name = 'args'
                  ..type = refer('List<String>'),
              ),
            )
            ..lambda = true
            ..body = springApplication.property('run').call([
              refer('args'),
            ]).code,
        ),
        Method(
          (m) => m
            ..docs.add(
              '/// Like [runApplication], reading config files '
              'asynchronously (Flutter assets)\n'
              '/// and completing once every runner has finished.',
            )
            ..returns = TypeReference(
              (t) => t
                ..symbol = 'Future'
                ..types.add(refer('ConfigurableApplicationContext', _bootUrl)),
            )
            ..name = 'runApplicationAsync'
            ..requiredParameters.add(
              Parameter(
                (p) => p
                  ..name = 'args'
                  ..type = refer('List<String>'),
              ),
            )
            ..lambda = true
            ..body = springApplication.property('runAsync').call([
              refer('args'),
            ]).code,
        ),
        for (final (name, call, doc) in const [
          (
            'reloadApplication',
            'reload',
            '/// For hot reload: [running] if the generated code is '
                'unchanged, else a\n/// restarted application with the '
                'new beans and the same arguments;\n/// [runners]: whether '
                'ApplicationRunner / CommandLineRunner beans run again.',
          ),
          (
            'reloadApplicationAsync',
            'reloadAsync',
            '/// Like [reloadApplication], reading config files '
                'asynchronously.',
          ),
        ])
          Method(
            (m) => m
              ..docs.add(doc)
              ..returns = call == 'reload'
                  ? refer('ConfigurableApplicationContext', _bootUrl)
                  : TypeReference(
                      (t) => t
                        ..symbol = 'Future'
                        ..types.add(
                          refer('ConfigurableApplicationContext', _bootUrl),
                        ),
                    )
              ..name = name
              ..requiredParameters.add(
                Parameter(
                  (p) => p
                    ..name = 'running'
                    ..type = refer('ConfigurableApplicationContext', _bootUrl),
                ),
              )
              ..optionalParameters.add(
                Parameter(
                  (p) => p
                    ..name = 'runners'
                    ..type = refer('bool')
                    ..named = true
                    ..defaultTo = literalTrue.code,
                ),
              )
              ..lambda = true
              ..body = springApplication
                  .property(call)
                  .call([refer('running')], {'runners': refer('runners')})
                  .code,
          ),
      ],
    );
    // The hash of the generated code (with the placeholder in it) replaces
    // the placeholder; same length, so the formatting is unchanged.
    await buildStep.writeAsString(
      output,
      source.replaceFirst(_fingerprintPlaceholder, _fnv1a(source)),
    );
  }

  static const _fingerprintPlaceholder = '00000000';

  // FNV-1a (32 bit) as 8 hex digits: stable across runs and platforms,
  // unlike String.hashCode.
  static String _fnv1a(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // Auto-configuration modules of every dependency (direct or transitive):
  // top-level variables annotated `@AutoConfigurationModule` in
  // `lib/spring_auto_configuration.dart`, ordered by `order`, then package.
  static Future<List<Expression>> _autoConfigurations(
    BuildStep buildStep,
  ) async {
    final root = buildStep.inputId.package;
    final found = <(int, String, String, String)>[];
    final config = await buildStep.packageConfig;
    for (final package in config.packages) {
      if (package.name == root) {
        continue;
      }
      final id = AssetId(package.name, autoConfigurationLibrary);
      if (!await buildStep.canRead(id) ||
          !await buildStep.resolver.isLibrary(id)) {
        continue;
      }
      final library = await buildStep.resolver.libraryFor(id);
      for (final variable in library.topLevelVariables) {
        final annotation = autoConfigurationModuleChecker.firstAnnotationOf(
          variable,
        );
        if (annotation != null) {
          await _checkCompatibility(
            buildStep,
            package.name,
            ConstantReader(annotation).peek('requires')?.stringValue,
            variable,
          );
          found.add((
            ConstantReader(annotation).peek('order')?.intValue ?? 0,
            package.name,
            variable.name!,
            'package:${package.name}/spring_auto_configuration.dart',
          ));
        }
      }
    }
    found.sort((a, b) {
      final byOrder = a.$1.compareTo(b.$1);
      return byOrder != 0 ? byOrder : a.$2.compareTo(b.$2);
    });
    return [for (final (_, _, name, url) in found) refer(name, url)];
  }

  // A starter's `requires` range against the spring_boot_dart version in
  // use (`springBootVersion`); a mismatch stops the build with an
  // explanation instead of failing later in generated or runtime code.
  static Future<void> _checkCompatibility(
    BuildStep buildStep,
    String starter,
    String? requires,
    Element element,
  ) async {
    if (requires == null) {
      return;
    }
    final VersionConstraint constraint;
    try {
      constraint = VersionConstraint.parse(requires);
    } on FormatException catch (error) {
      throw InvalidGenerationSource(
        "$starter: invalid requires '$requires' (${error.message}).",
        element: element,
      );
    }
    final version = await _springBootVersion(buildStep);
    if (version == null) {
      throw InvalidGenerationSource(
        '$starter requires spring_boot_dart $requires, but spring_boot_dart '
        'is not a dependency of this application.',
        element: element,
      );
    }
    if (!constraint.allows(version)) {
      throw InvalidGenerationSource(
        'Incompatible starter: $starter requires spring_boot_dart $requires, '
        'but $version is used.\n'
        'Upgrade spring_boot_dart to a version in $requires, or use a '
        'version of $starter made for spring_boot_dart $version '
        '(see its CHANGELOG / pub.dev versions).',
        element: element,
      );
    }
  }

  static Future<Version?> _springBootVersion(BuildStep buildStep) async {
    final id = AssetId('spring_boot_dart', 'lib/src/version.dart');
    if (!await buildStep.canRead(id)) {
      return null;
    }
    final library = await buildStep.resolver.libraryFor(id);
    final value = library.topLevelVariables
        .where((v) => v.name == 'springBootVersion')
        .firstOrNull
        ?.computeConstantValue()
        ?.toStringValue();
    return value == null ? null : Version.parse(value);
  }

  /// Scans the libraries among [assets] with [scanner], resolving the
  /// bodies of their `@Bean` methods first (for the inferred bean types).
  Future<void> _scanLibraries(
    BuildStep buildStep,
    BeanScanner scanner,
    List<AssetId> assets,
  ) async {
    final resolver = buildStep.resolver;
    for (final asset in assets) {
      if (await resolver.isLibrary(asset)) {
        final library = await resolver.libraryFor(asset);
        await scanner.resolveBeanMethods(
          library,
          (fragment) => resolver.astNodeFor(fragment, resolve: true),
        );
        scanner.scanLibrary(library);
      }
    }
  }

  // Bean names and aliases share one namespace (like Spring's registry,
  // which forbids overriding by default), so a clash of two unconditional
  // declarations is a build error that names both. Declarations with
  // conditions (`@Profile('dev')` / `@Profile('prod')` both declaring
  // `dataSource`) may share a name: the container registers those whose
  // conditions match, and its override check reports a real clash at
  // refresh (BeanDefinitionOverrideException).
  void _checkUniqueNames(List<BeanModel> beans) {
    final byName = <String, Element>{};
    for (final bean in beans) {
      if (bean.conditions.isNotEmpty) {
        continue;
      }
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
