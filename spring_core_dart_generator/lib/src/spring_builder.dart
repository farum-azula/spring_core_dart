import 'dart:convert';
import 'dart:io' as io;

import 'package:analyzer/dart/ast/ast.dart'
    show Comment, InstanceCreationExpression, SimpleIdentifier;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/asset_check.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/dart_define_keys.dart';
import 'package:spring_core_dart_generator/src/flutter_scanning.dart';
import 'package:spring_core_dart_generator/src/module_emitter.dart';
import 'package:yaml/yaml.dart';

// Suffix of generated files; also used to skip them as scan inputs.
const _outputExtension = '.spring.dart';

const _bootUrl = 'package:spring_boot_dart/spring_boot_dart.dart';

/// Recognises `@SpringBootApplication` from `spring_boot_dart`, which marks
/// the `main` whose output scans the whole package.
///
/// It is matched by URL, so the generator does not depend on that package.
const springBootApplicationChecker = TypeChecker.fromUrl(
  'package:spring_boot_dart/src/annotations.dart#SpringBootApplication',
);

/// Recognises `@AutoConfigurationModule` from `spring_boot_dart`: the
/// annotation a starter puts on the module variables it contributes to
/// every application that depends on it (matched by URL).
const autoConfigurationModuleChecker = TypeChecker.fromUrl(
  'package:spring_boot_dart/src/annotations.dart#AutoConfigurationModule',
);

/// The library, relative to a package root, where a starter lists its
/// auto-configuration modules.
///
/// When an application is built, this file is read in every package it
/// depends on, and the `@AutoConfigurationModule` variables found there are
/// passed to its `SpringApplication`. Spring Boot reads
/// `META-INF/spring/...AutoConfiguration.imports` for the same purpose.
const autoConfigurationLibrary = 'lib/spring_auto_configuration.dart';

/// The builder that writes `<file>.spring.dart`: the bean module of a
/// `@ComponentScan()` variable, or the whole application of a
/// `@SpringBootApplication()` `main`.
///
/// It is what `dart run build_runner build` runs for an application;
/// `springCoreDartBuilder` creates it from the `build.yaml` options.
/// It runs on every `.dart` input but only does work for two kinds of
/// library:
///
/// - One with a public top-level variable annotated `@ComponentScan()` (at
///   most one per file). Every library under that file's directory is
///   resolved, in path order so the output is deterministic. A
///   subdirectory with its own `@ComponentScan` is left to that scan, and
///   its module is imported instead. The generated getter is named after
///   the scan variable, prefixed with `$`.
/// - One with a `main` annotated `@SpringBootApplication()`. Then `lib/`
///   and the directory of `main` are scanned (only `example/` for an entry
///   point under `example/`). The output also declares
///   `springApplication`, `runApplication` and the hot-reload functions,
///   with the auto-configuration modules of every dependency and the
///   `--dart-define` keys the application reads.
///
/// The libraries go through a [BeanScanner]. Bean names and aliases must be
/// unique, and the module is written by a [ModuleEmitter], with the files
/// of `lib/resources/` embedded (see [_resources]).
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
/// BeanModule get $appBeans => BeanModule(r'appBeans', [
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
  /// Creates the builder with the `aop_proxies` ([proxyMode], default
  /// [ProxyMode.all]) and `aop_prune` ([pruneProxies], default `true`)
  /// options.
  ///
  /// [readExistingOutput] returns the current content of a generated file,
  /// or `null` when there is none. The builder keeps that content when the
  /// sources have errors. By default the file is read from disk: outputs are
  /// built to source, so it is at the asset path relative to the package
  /// directory the build runs in. Tests pass their own function so they
  /// need no real files.
  ///
  /// ```dart
  /// // What `aop_proxies: interfaces` in build.yaml amounts to.
  /// final builder = SpringBuilder(proxyMode: ProxyMode.interfaces);
  /// ```
  SpringBuilder({
    this.proxyMode = ProxyMode.all,
    this.pruneProxies = true,
    Future<String?> Function(AssetId output)? readExistingOutput,
  }) : _readExistingOutput = readExistingOutput ?? _readOutputFile;

  /// Which beans get a generated AOP proxy class (build option
  /// `aop_proxies`: `all`, `interfaces` or `none`).
  final ProxyMode proxyMode;

  /// Whether the `@SpringBootApplication` output leaves out the proxy
  /// classes of beans that no pointcut of the application can match (build
  /// option `aop_prune`, `true` by default).
  ///
  /// Only that output prunes: it knows every module of the application.
  /// `@ComponentScan` outputs keep every proxy.
  final bool pruneProxies;

  final Future<String?> Function(AssetId output) _readExistingOutput;

  // The last generated content per output in this process (`watch` keeps
  // one builder); the file on disk is the source after a fresh start.
  final Map<AssetId, String> _lastGood = {};

  // Outputs whose syntax-error warning was logged and not yet followed by
  // a successful generation.
  final Set<AssetId> _warned = {};

  /// Every `.dart` input may produce a `.spring.dart` output next to it
  /// (most produce none).
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': [_outputExtension],
  };

  /// Writes `<input>.spring.dart` when [buildStep]'s input declares a
  /// `@ComponentScan` variable or a `@SpringBootApplication` function. Any
  /// other input is skipped after a cheap text check, without resolving it.
  ///
  /// Throws `InvalidGenerationSource` when a file has more than one
  /// `@ComponentScan` or `@SpringBootApplication`, when the scan variable is
  /// private or starts with `$`, when `@ComponentScan` is not on a top-level
  /// variable, when a scanned declaration is invalid (see [BeanScanner]) or
  /// when two unconditional beans share a name or alias. A starter whose
  /// `requires` range does not allow the `spring_boot_dart` version in use
  /// fails the build too.
  ///
  /// An error in the sources never removes or changes an output that
  /// already exists, whether it was generated by this process or is on
  /// disk. Otherwise `build_runner watch` would delete and regenerate the
  /// file on every keystroke. While a scanned library has syntax errors the
  /// existing file is written again unchanged, and one warning is logged
  /// until the next successful generation. A validation error keeps the
  /// file too, and is reported as the build error. Without an existing
  /// output (a cold build) both errors fail the build.
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

  /// The content of [output] to keep when generation fails: the last one
  /// this process generated, else the file read by [_readExistingOutput].
  /// `null` when there is none (a cold build).
  Future<String?> _existingOutput(AssetId output) async =>
      _lastGood[output] ?? await _readExistingOutput(output);

  // Outputs are built to source (`build_to: source`), so the file is at the
  // asset path relative to the package directory the build runs in.
  static Future<String?> _readOutputFile(AssetId output) async {
    final file = io.File(output.path);
    return file.existsSync() ? await file.readAsString() : null;
  }

  /// Scans and emits the source of [output] for [buildStep]'s input.
  ///
  /// Returns `null` when the input is not a library or declares neither a
  /// `@ComponentScan` variable nor a `@SpringBootApplication` function.
  /// Throws the build errors listed on [build].
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
      return await _buildApplication(buildStep, boots, output);
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
    scanBuildContextAccess(module, scanner.collectErrors);
    await checkAssetValues(buildStep, module, scanner.collectErrors);
    scanner.throwErrors();

    // Any module may import this one, so its beans may be advised by
    // aspects the build cannot see: no proxy is pruned (only the
    // @SpringBootApplication output, which knows every module, prunes).
    return ModuleEmitter(
      output,
      dependencies: await _dependencies(buildStep),
      pruneProxies: false,
    ).emit(
      moduleName: variableName,
      variableName: '\$$variableName',
      scannedDirectory: directory,
      module: module,
      resources: await _resources(buildStep),
    );
  }

  /// The files under `lib/resources/`, keyed by their path below that
  /// directory, to embed in the generated module.
  ///
  /// They are the application's `classpath:` resources (config files,
  /// templates, messages). Embedding them makes `classpath:` work on every
  /// platform without declaring Flutter assets. Text files are kept as
  /// text, other files are base64-encoded, and files above
  /// [_maxEmbeddedBytes] are skipped with a warning.
  ///
  /// An application whose `main` is outside `lib/` (`example/`,
  /// `example/shop/bin/`, `tool/demo/`) also gets the `lib/resources/` of
  /// every directory from the package root down to its own (see
  /// [resourceDirectories]). The nearer to `main`, the higher the
  /// precedence: an example's `example/lib/resources/application.properties`
  /// wins over the package's, as an application's config wins over a
  /// library's.
  static Future<Map<String, ({String? text, String? base64})>> _resources(
    BuildStep buildStep, {
    String? entryDirectory,
  }) async {
    final result = <String, ({String? text, String? base64})>{};
    for (final directory in resourceDirectories(entryDirectory)) {
      final assets = await buildStep
          .findAssets(Glob('$directory**'))
          .where((asset) => !asset.path.endsWith('.dart'))
          .toList();
      assets.sort((a, b) => a.path.compareTo(b.path));
      await _embed(buildStep, assets, directory, result);
    }
    return result;
  }

  static Future<void> _embed(
    BuildStep buildStep,
    List<AssetId> assets,
    String directory,
    Map<String, ({String? text, String? base64})> result,
  ) async {
    for (final asset in assets) {
      final bytes = await buildStep.readAsBytes(asset);
      final path = asset.path.substring(directory.length);
      if (bytes.length > _maxEmbeddedBytes) {
        log.warning(
          '$directory$path is larger than $_maxEmbeddedBytes bytes and '
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
  }

  static const int _maxEmbeddedBytes = 1024 * 1024;

  /// The directories whose files are embedded as resources for an
  /// application whose `main` is in [entryDirectory] (package-relative,
  /// `/`-separated), lowest precedence first.
  ///
  /// That is `lib/resources/`, then `<dir>/lib/resources/` for each
  /// directory from the top one down to [entryDirectory]. For an entry
  /// point inside `lib/`, or no entry point, it is only `lib/resources/`.
  ///
  /// ```dart
  /// SpringBuilder.resourceDirectories('example/shop/bin');
  /// // [lib/resources/, example/lib/resources/,
  /// //  example/shop/lib/resources/, example/shop/bin/lib/resources/]
  /// ```
  static List<String> resourceDirectories(String? entryDirectory) {
    final directories = ['lib/resources/'];
    if (entryDirectory == null ||
        entryDirectory == 'lib' ||
        p.url.isWithin('lib', entryDirectory)) {
      return directories;
    }
    final parts = p.url.split(p.url.normalize(entryDirectory));
    for (var i = 1; i <= parts.length; i++) {
      final directory = p.url.joinAll(parts.take(i));
      if (directory == '.' || directory.isEmpty) {
        continue;
      }
      directories.add('$directory/lib/resources/');
    }
    return directories;
  }

  // `() => springApplication`: the application as the code is after a hot
  // reload on the Dart VM (SpringHotReload restarts the context when its
  // generated code changed).
  static Expression _currentApplication(Expression springApplication) => Method(
    (m) => m
      ..lambda = true
      ..body = springApplication.code,
  ).closure;

  // `@SpringBootApplication` on `main`: like Spring Boot's component scan
  // from the application class, the whole package is scanned — `lib/` and
  // the directory of `main` (e.g. `bin/`) — and the output also declares
  // `springApplication` and `runApplication(args)`.
  //
  // An entry point under `example/` is the example of a library or
  // starter: only `example/` is scanned, and the package's own
  // auto-configuration is used (its `lib/` reaches the application that
  // way, as for any application depending on it).
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
    final example =
        directory == 'example' || p.url.isWithin('example', directory);
    final roots = example
        ? {'example'}
        : ({'lib', directory}..removeWhere(
            (root) => root != 'lib' && p.url.isWithin('lib', root),
          ));
    final module = ModuleModel();
    final nested = <AssetId>[];
    final assets = await _scannedAssets(
      buildStep,
      roots,
      module,
      nestedAssets: nested,
    );

    final scanner = BeanScanner(module, proxyMode: proxyMode);
    await _scanLibraries(buildStep, scanner, assets);
    scanner.collectErrors(() => _checkUniqueNames(module.beans));
    scanBuildContextAccess(module, scanner.collectErrors);
    await checkAssetValues(buildStep, module, scanner.collectErrors);
    scanner.throwErrors();

    final autoConfigurations = await _autoConfigurations(
      buildStep,
      includeOwn: example,
    );
    final springApplication = refer('springApplication');
    final emitter = ModuleEmitter(
      output,
      dependencies: await _dependencies(buildStep),
      pruneProxies: pruneProxies,
      foreignAdvice: pruneProxies
          ? await _foreignAdvice(
              buildStep,
              scanner,
              nested,
              includeOwn: example,
            )
          : null,
    );
    final (exclude, excludeName) = _exclusions(emitter, boots.single);
    final resources = await _resources(buildStep, entryDirectory: directory);
    final defines = await _dartDefineKeys(buildStep, assets, resources);
    final source = emitter.emit(
      moduleName: 'application',
      variableName: r'$application',
      scannedDirectory: roots.map((r) => '$r/').join(' and '),
      module: module,
      resources: resources,
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
                    if (defines.isNotEmpty)
                      'dartDefines': CodeExpression(
                        Code(
                          [
                            '{',
                            for (final key in defines) _dartDefineEntry(key),
                            '}',
                          ].join('\n'),
                        ),
                      ),
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
            ..body = springApplication
                .property('run')
                .call(
                  [refer('args')],
                  {'hotReload': _currentApplication(springApplication)},
                )
                .code,
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
            ..body = springApplication
                .property('runAsync')
                .call(
                  [refer('args')],
                  {'hotReload': _currentApplication(springApplication)},
                )
                .code,
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

  // The `dartDefines` entry of [key]: set when the define is given.
  static String _dartDefineEntry(String key) =>
      "if (const bool.hasEnvironment('$key')) "
      "'$key': const String.fromEnvironment('$key'),";

  // The keys a `--dart-define` may set (see DartDefineKeys): read from the
  // scanned libraries and the application's config files.
  static Future<List<String>> _dartDefineKeys(
    BuildStep buildStep,
    List<AssetId> assets,
    Map<String, ({String? text, String? base64})> resources,
  ) async {
    final keys = DartDefineKeys();
    final resolver = buildStep.resolver;
    for (final asset in assets) {
      if (await resolver.isLibrary(asset)) {
        keys.addLibrary(await resolver.libraryFor(asset));
      }
    }
    for (final MapEntry(key: path, value: (:text, base64: _))
        in resources.entries) {
      if (text != null) {
        keys.addConfigFile(path, text);
      }
    }
    return keys.keys;
  }

  // Runs [visitor] over the resolved declarations of [library]; `false`
  // when one cannot be resolved.
  static Future<bool> _visitDeclarations(
    Resolver resolver,
    LibraryElement library,
    _AdvisorCreations visitor,
  ) async {
    final declarations = <Element>[
      ...library.topLevelVariables,
      ...library.topLevelFunctions,
      ...library.classes,
    ];
    for (final declaration in declarations) {
      try {
        (await resolver.astNodeFor(
          declaration.firstFragment,
          resolve: true,
        ))?.accept(visitor);
      } on Object {
        return false;
      }
    }
    return true;
  }

  // The advice of the application's other modules, for proxy pruning: the
  // aspects and advisor beans of the nested @ComponentScan modules
  // ([nested]: their libraries), whether an auto-configuration may
  // declare aspects (its libraries mention `AspectMetadata`), which the
  // build cannot read, and whether it declares advisor beans whose
  // pointcut is not an `AnnotationPointcut` (beans with the annotations
  // such a pointcut matches are never pruned).
  Future<ForeignAdvice> _foreignAdvice(
    BuildStep buildStep,
    BeanScanner scanner,
    List<AssetId> nested, {
    bool includeOwn = false,
  }) async {
    final foreign = ForeignAdvice();
    final resolver = buildStep.resolver;
    for (final asset in nested) {
      if (await resolver.isLibrary(asset)) {
        scanner.collectAdvice(await resolver.libraryFor(asset), foreign);
      }
    }
    final root = buildStep.inputId.package;
    final config = await buildStep.packageConfig;
    final reachable = await _reachablePackages(buildStep);
    for (final package in config.packages) {
      final id = AssetId(package.name, autoConfigurationLibrary);
      if ((package.name == root && !includeOwn) ||
          (reachable != null && !reachable.contains(package.name)) ||
          !await buildStep.canRead(id) ||
          !await resolver.isLibrary(id)) {
        continue;
      }
      final pending = [await resolver.libraryFor(id)];
      final seen = <Uri>{};
      final advisors = _AdvisorCreations();
      while (pending.isNotEmpty && !foreign.unknown) {
        final library = pending.removeLast();
        if (!seen.add(library.uri)) {
          continue;
        }
        final source = await buildStep.readAsString(
          AssetId.resolve(library.uri),
        );
        if (source.contains('AspectMetadata')) {
          foreign.unknown = true;
        }
        if (source.contains('Advisor') &&
            !await _visitDeclarations(resolver, library, advisors)) {
          foreign.advisors = true;
        }
        for (final fragment in library.fragments) {
          for (final imported in fragment.importedLibraries) {
            final uri = imported.uri;
            if (uri.scheme == 'package' &&
                uri.pathSegments.first == package.name) {
              pending.add(imported);
            }
          }
        }
      }
      if (advisors.mentioned && !advisors.annotationDriven) {
        foreign.advisors = true;
      }
    }
    return foreign;
  }

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
  // With [includeOwn] (an example), the package's own too.
  static Future<List<(Expression, Expression?)>> _autoConfigurations(
    BuildStep buildStep, {
    bool includeOwn = false,
  }) async {
    final root = buildStep.inputId.package;
    final found = <(Expression?, String, String, String)>[];
    final config = await buildStep.packageConfig;
    final reachable = await _reachablePackages(buildStep);
    for (final package in config.packages) {
      if (package.name == root && !includeOwn) {
        continue;
      }
      if (reachable != null && !reachable.contains(package.name)) {
        continue; // a sibling of a pub workspace, not a dependency
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

  /// The `.dart` files this build scans: those below [roots], sorted by
  /// path, generated files excluded. Glob characters in directory names are
  /// escaped.
  ///
  /// A `@ComponentScan` file below them, other than the input, owns its
  /// directory. Its files are left out and its module variable is added to
  /// [module]'s imports (the outermost ones only). So a bean is registered
  /// once even when both modules are used; Spring likewise skips candidates
  /// that an overlapping scan already registered. Two `@ComponentScan`
  /// files in one directory fail the build when that directory is
  /// [scanRoot] (the input's directory, for a `@ComponentScan` input).
  ///
  /// [nestedAssets] receives the files left to the nested scans (proxy
  /// pruning reads their aspects).
  Future<List<AssetId>> _scannedAssets(
    BuildStep buildStep,
    Set<String> roots,
    ModuleModel module, {
    String? scanRoot,
    List<AssetId>? nestedAssets,
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
    nestedAssets?.addAll(all.where((asset) => owned(asset.path)));
    return [
      for (final asset in all)
        if (!owned(asset.path)) asset,
    ];
  }

  /// The packages the application of [buildStep]'s input depends on,
  /// directly or not: its own [_dependencies], then the `dependencies` of
  /// each, read from their `pubspec.yaml`.
  ///
  /// Auto-configurations are only taken from these packages. In a pub
  /// workspace the package config lists every member, so being in it does
  /// not make a package a dependency, and an app must not get the
  /// auto-configurations of its siblings. Returns `null` (no filtering)
  /// when a pubspec cannot be read.
  static Future<Set<String>?> _reachablePackages(BuildStep buildStep) async {
    final direct = await _dependencies(buildStep);
    if (direct == null) {
      return null;
    }
    final config = await buildStep.packageConfig;
    final byName = {
      for (final package in config.packages) package.name: package,
    };
    final reachable = <String>{};
    final pending = [...direct];
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (!reachable.add(name) || name == buildStep.inputId.package) {
        continue;
      }
      final package = byName[name];
      if (package != null) {
        final dependencies = await _pubspecDependencies(
          buildStep,
          package.name,
          package.root,
        );
        if (dependencies == null) {
          // Unknown: better every package of the config than a missing
          // auto-configuration.
          return null;
        }
        pending.addAll(dependencies);
      }
    }
    return reachable;
  }

  // The `dependencies` of package [name] (at [root]): its pubspec.yaml read
  // through the build, else from disk where the package config says it is;
  // `null` when neither works (the caller then filters nothing).
  static Future<List<String>?> _pubspecDependencies(
    BuildStep buildStep,
    String name,
    Uri root,
  ) async {
    String? text;
    final id = AssetId(name, 'pubspec.yaml');
    try {
      if (await buildStep.canRead(id)) {
        text = await buildStep.readAsString(id);
      }
    } on Object {
      // Not readable through the build.
    }
    if (text == null) {
      try {
        if (root.isScheme('file')) {
          final file = io.File.fromUri(root.resolve('pubspec.yaml'));
          if (file.existsSync()) {
            text = file.readAsStringSync();
          }
        }
      } on Object {
        // Unreadable.
      }
    }
    if (text == null) {
      return null;
    }
    try {
      final yaml = loadYaml(text);
      final dependencies = yaml is Map ? yaml['dependencies'] : null;
      if (dependencies is Map) {
        return [for (final name in dependencies.keys) '$name'];
      }
      return const [];
    } on YamlException {
      return null;
    }
  }

  /// The direct dependencies of the root package (with itself) that the
  /// input's directory may import, from its `pubspec.yaml`; `null` when it
  /// cannot be read.
  ///
  /// Dev dependencies count only outside `lib/` and `bin/`, as the
  /// `depend_on_referenced_packages` lint checks. The emitter imports a
  /// type through the public library of one of these packages, when the
  /// scanned library imports it that way, rather than through its `src/`
  /// file.
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
          r'  final BeanModule appBeans = $appBeans;',
          element: element,
        );
      }
    }
  }

  /// Scans the libraries among [assets] with [scanner].
  ///
  /// First it records where each public type is declared (the runtime's
  /// public library first, then the scanned files), so an error can name
  /// the import a library misses. The bodies of each library's `@Bean`
  /// methods are resolved before the library is scanned, because a
  /// `@Bean` method's bean type is inferred from what its body returns
  /// (`DataSource dataSource() => HikariDataSource(url)` registers a
  /// `HikariDataSource`).
  Future<void> _scanLibraries(
    BuildStep buildStep,
    BeanScanner scanner,
    List<AssetId> assets,
  ) async {
    final resolver = buildStep.resolver;
    // Where each public type is declared, to name the import a library
    // misses (the runtime's public library first, then scanned files).
    final runtime = AssetId('spring_core_dart', 'lib/spring_core_dart.dart');
    final libraries = [
      if (await buildStep.canRead(runtime) && await resolver.isLibrary(runtime))
        await resolver.libraryFor(runtime),
      for (final asset in assets)
        if (await resolver.isLibrary(asset)) await resolver.libraryFor(asset),
    ];
    for (final library in libraries) {
      for (final name in library.exportNamespace.definedNames2.keys) {
        if (!name.startsWith('_') && !name.endsWith('=')) {
          scanner.knownTypes.putIfAbsent(name, () => library.uri);
        }
      }
    }
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

const _advisorChecker = TypeChecker.fromUrl(
  'package:spring_core_dart/src/aop/advisor.dart#Advisor',
);
const _defaultPointcutAdvisorChecker = TypeChecker.fromUrl(
  'package:spring_core_dart/src/aop/advisor.dart#DefaultPointcutAdvisor',
);
const _annotationPointcutChecker = TypeChecker.fromUrl(
  'package:spring_core_dart/src/aop/aop_pointcut.dart#AnnotationPointcut',
);
const _annotationMatchingPointcutChecker = TypeChecker.fromUrl(
  'package:spring_core_dart/src/aop/aop_pointcut.dart'
  '#AnnotationMatchingPointcut',
);

// The advisors the libraries of a starter create (`DefaultPointcutAdvisor
// (p, ...)` or an `Advisor` class) or register (`Advisor` in the types of
// a bean definition), and whether all created ones have a pointcut whose
// static type is an `AnnotationPointcut` matching annotations from
// outside `package:spring_core_dart` (the annotations pruning keeps the
// beans of). Registered without a creation the build sees counts as not
// annotation-driven.
class _AdvisorCreations extends RecursiveAstVisitor<void> {
  bool mentioned = false;
  var _found = false;
  var _annotationDriven = true;

  bool get annotationDriven => _found && _annotationDriven;

  // Doc comments (`[Advisor]`) register nothing.
  @override
  void visitComment(Comment node) {}

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element case final InterfaceElement element
        when _advisorChecker.isAssignableFrom(element)) {
      mentioned = true;
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType;
    if (type is InterfaceType && _advisorChecker.isAssignableFromType(type)) {
      mentioned = true;
      _found = true;
      final pointcut = _defaultPointcutAdvisorChecker.isExactlyType(type)
          ? node
                .argumentList
                .arguments
                .firstOrNull
                ?.argumentExpression
                .staticType
          : type.lookUpGetter('pointcut', type.element.library)?.returnType;
      if (!_matchesByForeignAnnotation(pointcut)) {
        _annotationDriven = false;
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  static bool _matchesByForeignAnnotation(DartType? pointcut) {
    if (pointcut is! InterfaceType ||
        !_annotationPointcutChecker.isAssignableFromType(pointcut)) {
      return false;
    }
    // `AnnotationMatchingPointcut<A>` with a runtime annotation (not kept
    // by pruning) matches beans the build may prune.
    if (_annotationMatchingPointcutChecker.isExactlyType(pointcut)) {
      final annotation = pointcut.typeArguments.single;
      return annotation is InterfaceType &&
          !annotation.element.library.uri.toString().startsWith(
            'package:spring_core_dart/',
          );
    }
    return true;
  }
}
