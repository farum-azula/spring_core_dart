import 'dart:convert';
import 'dart:io' as io;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/module_emitter.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_gen/source_gen.dart';
import 'package:yaml/yaml.dart';

// Suffix of generated files; also used to skip them as scan inputs.
const _outputExtension = '.spring.dart';

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
/// directory recursively and writes `<file>.spring.dart` with a `BeanModule`.
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
/// // Output: lib/src/beans.spring.dart
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
  /// [readExistingOutput] returns the current content of a generated file
  /// (`null` when there is none); by default the file is read from disk
  /// (outputs are built to source, so it is at the asset path relative to
  /// the package directory the build runs in). Tests inject it so they need
  /// no real files.
  ///
  /// ```dart
  /// final builder = SpringBuilder(proxyMode: ProxyMode.interfaces);
  /// ```
  SpringBuilder({
    this.proxyMode = ProxyMode.all,
    this.pruneProxies = true,
    Future<String?> Function(AssetId output)? readExistingOutput,
  }) : _readExistingOutput = readExistingOutput ?? _readOutputFile;

  /// Which beans get generated AOP proxies (build option `aop_proxies`:
  /// `all`, `interfaces` or `none`).
  final ProxyMode proxyMode;

  /// Whether `aop_proxies: all` skips the proxy classes of beans no
  /// pointcut of the module can match (build option `aop_prune`, `true` by
  /// default).
  final bool pruneProxies;

  final Future<String?> Function(AssetId output) _readExistingOutput;

  // The last generated content per output in this process (`watch` keeps
  // one builder); the file on disk is the source after a fresh start.
  final Map<AssetId, String> _lastGood = {};

  // Outputs whose syntax-error warning was logged and not yet followed by
  // a successful generation.
  final Set<AssetId> _warned = {};

  /// Every `.dart` input may produce a `.spring.dart` output next to it.
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': [_outputExtension],
  };

  /// Generates `<input>.spring.dart` when [buildStep]'s input declares a
  /// `@ComponentScan` variable; does nothing for any other input.
  ///
  /// Throws `InvalidGenerationSource` when a file has more than one
  /// `@ComponentScan`, when the scan variable is private or starts with
  /// `$`, when a scanned class is invalid (see [BeanScanner]) or when two
  /// beans share a name or alias.
  ///
  /// An error in the sources never removes or changes an output that
  /// already exists (from this process or on disk): while a scanned library
  /// has syntax errors (`build_runner watch` while typing) the existing
  /// file is written again unchanged and one warning is logged until the
  /// next successful generation; a validation error keeps the file too and
  /// is reported as the build error. Without an existing output (a cold
  /// build) both fail the build as before.
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
    final output = input.changeExtension(_outputExtension);
    String? source;
    try {
      source = await _generate(buildStep, output);
    } on SyntaxErrorInAssetException catch (error) {
      // build_runner deletes an output its step does not write, so the
      // existing content is written again: the build stays green and the
      // generated file does not flicker on every keystroke.
      final existing = await _existingOutput(output);
      if (existing == null) {
        rethrow;
      }
      if (_warned.add(output)) {
        log.warning(
          '${output.path} is kept unchanged until the sources parse again; '
          '${error.assetId.path} has syntax errors:\n$error',
        );
      }
      await buildStep.writeAsString(output, existing);
      return;
    } catch (error, stackTrace) {
      // A validation error, or a crash on the element model of a library
      // with errors: the existing file stays too, the error is reported.
      final existing = await _existingOutput(output);
      if (existing == null) {
        rethrow;
      }
      log.severe(
        '${output.path} is kept unchanged until this error is fixed:',
        error,
        stackTrace,
      );
      await buildStep.writeAsString(output, existing);
      return;
    }
    if (source == null) {
      return;
    }
    _warned.remove(output);
    _lastGood[output] = source;
    await buildStep.writeAsString(output, source);
  }

  /// The content of [output] from its last generation in this process, else
  /// from [_readExistingOutput]; `null` when there is none (a cold build).
  Future<String?> _existingOutput(AssetId output) async =>
      _lastGood[output] ?? await _readExistingOutput(output);

  // Outputs are built to source (`build_to: source`), so the file is at the
  // asset path relative to the package directory the build runs in.
  static Future<String?> _readOutputFile(AssetId output) async {
    final file = io.File(output.path);
    return await file.exists() ? file.readAsString() : null;
  }

  /// The source of [output] for [buildStep]'s input, or `null` when the
  /// input declares neither a `@ComponentScan` variable nor a
  /// `@SpringBootApplication` function.
  Future<String?> _generate(BuildStep buildStep, AssetId output) async {
    final input = buildStep.inputId;
    final resolver = buildStep.resolver;
    if (!await resolver.isLibrary(input)) {
      return null;
    }
    final library = await resolver.libraryFor(input);
    _rejectMisplacedScans(library);
    final boots = [
      for (final function in library.topLevelFunctions)
        if (springBootApplicationChecker.hasAnnotationOf(function)) function,
    ];
    if (boots.isNotEmpty) {
      return _buildApplication(buildStep, boots, output);
    }
    final scans = [
      for (final variable in library.topLevelVariables)
        if (componentScanChecker.hasAnnotationOf(variable)) variable,
    ];
    if (scans.isEmpty) {
      return null;
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
    // below it (recursively) is scanned, generated files excluded. A
    // subdirectory with its own @ComponentScan is left to that scan, whose
    // module is imported instead.
    final directory = p.url.dirname(input.path);
    final module = ModuleModel();
    final assets = await _scannedAssets(
      buildStep,
      {directory},
      module,
      scanRoot: directory,
    );

    final scanner = BeanScanner(
      module,
      proxyMode: proxyMode,
      scan: componentScanModel(
        componentScanChecker.firstAnnotationOf(scan)!,
        scan,
      ),
    );
    await _scanLibraries(buildStep, scanner, assets);
    scanner.collectErrors(() => _checkUniqueNames(module.beans));
    scanner.throwErrors();

    return ModuleEmitter(
      output,
      dependencies: await _dependencies(buildStep),
      pruneProxies: pruneProxies,
    ).emit(
      moduleName: variableName,
      variableName: '\$$variableName',
      scannedDirectory: directory,
      module: module,
      resources: await _resources(buildStep),
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
  Future<String> _buildApplication(
    BuildStep buildStep,
    List<TopLevelFunctionElement> boots,
    AssetId output,
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
    final module = ModuleModel();
    final assets = await _scannedAssets(buildStep, roots, module);

    final scanner = BeanScanner(module, proxyMode: proxyMode);
    await _scanLibraries(buildStep, scanner, assets);
    scanner.collectErrors(() => _checkUniqueNames(module.beans));
    scanner.throwErrors();

    final autoConfigurations = await _autoConfigurations(buildStep);
    final springApplication = refer('springApplication');
    final emitter = ModuleEmitter(
      output,
      dependencies: await _dependencies(buildStep),
      pruneProxies: pruneProxies,
    );
    final (exclude, excludeName) = _exclusions(emitter, boots.single);
    final source = emitter.emit(
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
                      'autoConfigurations': literalList([
                        for (final (module, _) in autoConfigurations) module,
                      ]),
                    if (autoConfigurations.any((entry) => entry.$2 != null))
                      'autoConfigurationMetadata': literalMap({
                        for (final (module, metadata) in autoConfigurations)
                          module: ?metadata,
                      }),
                    if (exclude.isNotEmpty) 'exclude': literalList(exclude),
                    if (excludeName.isNotEmpty)
                      'excludeName': literalList(excludeName),
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
    return source.replaceFirst(_fingerprintPlaceholder, _fnv1a(source));
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

  // `exclude` / `excludeName` of `@SpringBootApplication` on [main], as
  // expressions for `SpringApplication`.
  static (List<Expression>, List<Expression>) _exclusions(
    ModuleEmitter emitter,
    TopLevelFunctionElement main,
  ) {
    final annotation = ConstantReader(
      springBootApplicationChecker.firstAnnotationOf(main),
    );
    return (
      [
        for (final type
            in annotation.peek('exclude')?.listValue ?? const <DartObject>[])
          emitter.classReference(
            ConstantReader(type).typeValue as InterfaceType,
            main,
          ),
      ],
      [
        for (final name
            in annotation.peek('excludeName')?.listValue ??
                const <DartObject>[])
          literalString(ConstantReader(name).stringValue),
      ],
    );
  }

  // Auto-configuration modules of every dependency (direct or transitive):
  // top-level variables annotated `@AutoConfigurationModule` in
  // `lib/spring_auto_configuration.dart`, with an expression for their
  // `order` / `before` / `after` when set. `SpringApplication` sorts them
  // (Boot's AutoConfigurationSorter); here they are by package, then name.
  static Future<List<(Expression, Expression?)>> _autoConfigurations(
    BuildStep buildStep,
  ) async {
    final root = buildStep.inputId.package;
    final found = <(Expression?, String, String, String)>[];
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
            _orderingOf(ConstantReader(annotation)),
            package.name,
            variable.name!,
            'package:${package.name}/spring_auto_configuration.dart',
          ));
        }
      }
    }
    found.sort((a, b) {
      final byPackage = a.$2.compareTo(b.$2);
      return byPackage != 0 ? byPackage : a.$3.compareTo(b.$3);
    });
    return [
      for (final (ordering, _, name, url) in found)
        (refer(name, url), ordering),
    ];
  }

  // `const AutoConfigurationModule(order:, before:, after:)` with the
  // values the annotation sets; `null` when it sets none.
  static Expression? _orderingOf(ConstantReader annotation) {
    final order = annotation.peek('order')?.intValue ?? 0;
    final before = annotation.peek('before')?.listValue ?? const [];
    final after = annotation.peek('after')?.listValue ?? const [];
    if (order == 0 && before.isEmpty && after.isEmpty) {
      return null;
    }
    List<Expression> names(List<DartObject> values) => [
      for (final value in values)
        literalString(ConstantReader(value).stringValue),
    ];
    return refer('AutoConfigurationModule', _bootUrl).constInstance([], {
      if (order != 0) 'order': literalNum(order),
      if (before.isNotEmpty) 'before': literalList(names(before)),
      if (after.isNotEmpty) 'after': literalList(names(after)),
    });
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

  /// The `.dart` files below [roots] (glob characters in directory names
  /// are escaped), sorted by path, generated files excluded.
  ///
  /// A `@ComponentScan` file below them other than the input owns its
  /// directory: its files are left out and its module variable is added to
  /// [module]'s imports (the outermost ones only), so a bean is registered
  /// once even when both modules are used (Spring skips candidates that
  /// an overlapping scan already registered). Two `@ComponentScan` files in
  /// one directory ([scanRoot], the input's for a `@ComponentScan`) fail
  /// the build.
  Future<List<AssetId>> _scannedAssets(
    BuildStep buildStep,
    Set<String> roots,
    ModuleModel module, {
    String? scanRoot,
  }) async {
    final input = buildStep.inputId;
    final all = <AssetId>{
      for (final root in roots)
        ...await buildStep
            .findAssets(Glob('${Glob.quote(root)}/**.dart'))
            .where((asset) => !asset.path.endsWith(_outputExtension))
            .toList(),
    }.toList()..sort((a, b) => a.path.compareTo(b.path));

    final nested = <String, TopLevelVariableElement>{};
    for (final asset in all) {
      if (asset == input ||
          !(await buildStep.readAsString(asset)).contains('ComponentScan') ||
          !await buildStep.resolver.isLibrary(asset)) {
        continue;
      }
      final library = await buildStep.resolver.libraryFor(asset);
      final scan = library.topLevelVariables
          .where(componentScanChecker.hasAnnotationOf)
          .firstOrNull;
      if (scan == null) {
        continue;
      }
      final directory = p.url.dirname(asset.path);
      if (directory == scanRoot) {
        throw InvalidGenerationSource(
          'Two @ComponentScan roots in $directory/: ${input.path} and '
          '${asset.path}. A directory has one scan root; remove one, or move '
          'it into a subdirectory (which the other then imports).',
          element: scan,
        );
      }
      nested.putIfAbsent(directory, () => scan);
    }
    bool owned(String path) =>
        nested.keys.any((directory) => p.url.isWithin(directory, path));
    for (final MapEntry(key: directory, value: scan) in nested.entries) {
      if (!owned(directory)) {
        module.imports.add(scan);
      }
    }
    return [
      for (final asset in all)
        if (!owned(asset.path)) asset,
    ];
  }

  /// The direct dependencies of the root package (with itself) that the
  /// input's directory may import, from its `pubspec.yaml` (dev
  /// dependencies only outside `lib/` and `bin/`, as the
  /// `depend_on_referenced_packages` lint checks); `null` when it cannot be
  /// read.
  static Future<Set<String>?> _dependencies(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final pubspec = AssetId(package, 'pubspec.yaml');
    if (!await buildStep.canRead(pubspec)) {
      return null;
    }
    final Object? yaml;
    try {
      yaml = loadYaml(await buildStep.readAsString(pubspec));
    } on YamlException {
      return null;
    }
    if (yaml is! Map) {
      return null;
    }
    return {
      package,
      for (final section in [
        'dependencies',
        if (!const {
          'lib',
          'bin',
        }.contains(buildStep.inputId.pathSegments.first))
          'dev_dependencies',
      ])
        if (yaml[section] case final Map<Object?, Object?> entries)
          for (final name in entries.keys) '$name',
    };
  }

  // `@ComponentScan` belongs on a top-level variable; anywhere else it
  // would be ignored silently.
  static void _rejectMisplacedScans(LibraryElement library) {
    final misplaced = <(Element, String)>[
      for (final element in library.classes) (element, 'class'),
      for (final element in library.mixins) (element, 'mixin'),
      for (final element in library.enums) (element, 'enum'),
      for (final element in library.extensions) (element, 'extension'),
      for (final element in library.extensionTypes) (element, 'extension type'),
      for (final element in library.topLevelFunctions) (element, 'function'),
      for (final element in library.getters)
        if (element.isOriginDeclaration) (element, 'getter'),
      for (final container in [
        ...library.classes,
        ...library.mixins,
        ...library.enums,
        ...library.extensions,
        ...library.extensionTypes,
      ]) ...[
        for (final field in container.fields)
          if (field.isOriginDeclaration) (field, 'field'),
        for (final method in container.methods) (method, 'method'),
      ],
    ];
    for (final (element, kind) in misplaced) {
      if (componentScanChecker.hasAnnotationOf(element)) {
        throw InvalidGenerationSource(
          '@ComponentScan on $kind ${element.displayName} of '
          '${library.uri}: put it on a top-level variable holding the '
          'generated module, e.g.\n'
          '  @ComponentScan()\n'
          '  final BeanModule appBeans = \$appBeans;',
          element: element,
        );
      }
    }
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
