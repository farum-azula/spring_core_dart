import 'dart:convert';
import 'dart:io' as io;

import 'package:analyzer/dart/ast/ast.dart'
    show
        Comment,
        InstanceCreationExpression,
        ListLiteral,
        NamedArgument,
        SetOrMapLiteral,
        SimpleIdentifier,
        StringLiteral;
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
import 'package:spring_core_dart/core.dart' show SecretNames;
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_environment.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart';
import 'package:spring_core_dart_generator/src/core/builder/dart_format.dart';
import 'package:spring_core_dart_generator/src/core/builder/generated_path.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_directory.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/core/introspection/json_schemas/json_schema_module_parts.dart';
import 'package:spring_core_dart_generator/src/core/properties/dart_define_keys.dart';
import 'package:yaml/yaml.dart';

// Suffix of generated files; also used to skip them as scan inputs.

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

/// The build switch of each auto-configuration module of [package] that
/// has one (`@AutoConfigurationModule(build: ...)` in its
/// [autoConfigurationLibrary]), by the module's variable name, in the
/// order of the library: what a part of the module build that serves those
/// modules decides by, so it says what the modules say. Empty when
/// [buildStep] cannot read that library.
///
/// ```dart
/// final switches = await moduleBuildSwitches(
///   build.buildStep,
///   'spring_boot_starter_flutter_signals',
/// );
/// switches['springBootStarterFlutterSignalsDebugAutoConfiguration'];
/// // BuildSwitch('spring.flutter.signals.debug.enabled', parents: [...])
/// ```
Future<Map<String, BuildSwitch>> moduleBuildSwitches(
  BuildStep buildStep,
  String package,
) async {
  final id = AssetId(package, autoConfigurationLibrary);
  if (!await buildStep.canRead(id) || !await buildStep.resolver.isLibrary(id)) {
    return const {};
  }
  final library = await buildStep.resolver.libraryFor(id);
  return {
    for (final variable in library.topLevelVariables)
      if (autoConfigurationModuleChecker.firstAnnotationOf(variable)
          case final annotation?)
        if (ConstantReader(annotation).peek('build') case final build?
            when !build.isNull)
          variable.name!: BuildSwitch.fromAnnotation(build),
  };
}

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
/// of `lib/resources/` embedded (see [resources]).
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
/// // Output: lib/spring_gen/src/beans.spring.dart
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
  /// built to source, so it is at the asset path in the directory of the
  /// output's package, found through [packageDirectories] (also when
  /// `build_runner build --workspace` builds every package of a workspace
  /// from one directory). [packageDirectories] also finds the Flutter
  /// assets the build does not see (`@Value('asset:...')`). Tests pass
  /// their own function, or directories of their own, so they need no real
  /// files.
  ///
  /// ```dart
  /// // What `aop_proxies: interfaces` in build.yaml amounts to.
  /// final builder = SpringBuilder(proxyMode: ProxyMode.interfaces);
  /// ```
  SpringBuilder({
    this.proxyMode = ProxyMode.all,
    this.pruneProxies = true,
    this.deferProxies = false,
    this.dartDefinesExclude = const [],
    this.dartDefinesSecrets = const [],
    this.generations = const [],
    Future<String?> Function(AssetId output)? readExistingOutput,
    PackageDirectories? packageDirectories,
  }) : _packageDirectories = packageDirectories ?? PackageDirectories.current,
       _readExistingOutput =
           readExistingOutput ??
           (packageDirectories ?? PackageDirectories.current).read;

  /// The packages' parts of the module build (the builder factory passes
  /// the built-in ones, `packageGenerations`). A build starts those whose
  /// starter the package reaches ([reachablePackages]), every one when its
  /// dependencies cannot be read.
  final List<PackageGeneration> generations;

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

  /// Whether the `lib/` modules of this library package leave to the
  /// application the proxy classes only its aspects can match, as a
  /// starter's do (build option `aop_defer`, `false` by default). For a
  /// library without `lib/spring_auto_configuration.dart` whose modules a
  /// starter's auto-configuration imports (`spring_boot_actuator`'s
  /// properties): the application's build finds them through that import.
  /// Any other library keeps every proxy, since any module may import it.
  final bool deferProxies;

  /// The property name prefixes not offered to `--dart-define` (build
  /// option `dart_defines_exclude`, empty by default): neither the names
  /// under them nor their environment-variable forms are written into
  /// `springApplication.dartDefines`.
  final List<String> dartDefinesExclude;

  /// The property name prefixes whose secret-looking names a client build
  /// still offers to `--dart-define` (build option `dart_defines_secrets`,
  /// empty by default). A Flutter app's build leaves out of
  /// `springApplication.dartDefines` every name `SecretNames.looksSecret`
  /// flags (`spring.datasource.password`, `NEON_KEYCLOAK_SECRET`), but
  /// those of these prefixes and the public ones the parts declare
  /// ([PackageGeneration.publicDefines]), with a warning listing them: a
  /// define the code names is compiled into the app, where anyone can
  /// read it, and `--dart-define-from-file=.env` often holds a server's
  /// secrets too.
  final List<String> dartDefinesSecrets;

  final Future<String?> Function(AssetId output) _readExistingOutput;

  final PackageDirectories _packageDirectories;

  // The last generated content per output in this process (`watch` keeps
  // one builder); the file on disk is the source after a fresh start.
  final Map<AssetId, String> _lastGood = {};

  // Outputs whose syntax-error warning was logged and not yet followed by
  // a successful generation.
  final Set<AssetId> _warned = {};

  /// Every `.dart` input of `lib/`, `bin/`, `test/` and `example/` may
  /// produce a module in the `spring_gen/` folder of its root (most produce
  /// none): its `.spring.dart`, and beside it the files of what it holds
  /// by kind ([moduleFileExtensions]), each only when the module has some.
  @override
  Map<String, List<String>> get buildExtensions => {
    for (final root in generatedRoots) '^$root/{{}}.dart': moduleOutputs(root),
  };

  /// The outputs of a module of the source root [root], as `build.yaml`
  /// declares them: `<root>/spring_gen/{{}}.spring.dart` and its files.
  static List<String> moduleOutputs(String root) => [
    '$root/spring_gen/{{}}.spring.dart',
    for (final extension in moduleFileExtensions)
      '$root/spring_gen/{{}}$extension',
  ];

  /// Writes the `.spring.dart` of the input (see [generatedPath]) when
  /// [buildStep]'s input declares a `@ComponentScan` variable or a
  /// `@SpringBootApplication` function. Any other input is skipped after a
  /// cheap text check, without resolving it.
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
  /// disk in the directory of the output's package (in a workspace build
  /// too: never another package's file). Otherwise `build_runner watch`
  /// would delete and regenerate the file on every keystroke. While a
  /// scanned library has syntax errors the existing file is written again
  /// unchanged, and one warning is logged until the next successful
  /// generation. A validation error keeps the file too, and is reported as
  /// the build error. Without an existing output (a cold build) both
  /// errors fail the build.
  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (isGeneratedSource(input.path) || !hasGeneratedRoot(input.path)) {
      return;
    }
    // Cheap text check before resolving every library in the package.
    final text = await buildStep.readAsString(input);
    if (!text.contains('ComponentScan') &&
        !text.contains('SpringBootApplication')) {
      return;
    }
    final output = generatedId(input);
    ModuleSources? sources;
    try {
      sources = await _generate(buildStep, output);
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
      await _keep(buildStep, output, existing);
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
      await _keep(buildStep, output, existing);
      return;
    }
    if (sources == null) {
      return;
    }
    _warned.remove(output);
    final formatted = sources.formatted(
      await DartFormat.forOutput(
        buildStep,
        output,
        directories: _packageDirectories,
      ),
    );
    final files = {
      output: formatted.module,
      moduleFileId(output, introspectionExtension): formatted.introspection,
      moduleFileId(output, propertiesExtension): formatted.properties,
      moduleFileId(output, proxiesExtension): formatted.proxies,
      for (final extension in [
        ...packagePartExtensions,
        ...applicationPartExtensions,
      ])
        moduleFileId(output, extension): formatted.parts[extension],
    };
    for (final MapEntry(key: id, value: source) in files.entries) {
      if (source == null) {
        // Not written, so build_runner deletes the file of a former build.
        _lastGood.remove(id);
        continue;
      }
      _lastGood[id] = source;
      await buildStep.writeAsString(id, source);
    }
  }

  // Writes [existing], the module's library [output] as it is, again, with
  // its files that exist ([moduleFileExtensions]), so none is deleted.
  Future<void> _keep(
    BuildStep buildStep,
    AssetId output,
    String existing,
  ) async {
    await buildStep.writeAsString(output, existing);
    for (final extension in moduleFileExtensions) {
      final id = moduleFileId(output, extension);
      if (await _existingOutput(id) case final kept?) {
        await buildStep.writeAsString(id, kept);
      }
    }
  }

  /// The content of [output] to keep when generation fails: the last one
  /// this process generated, else the file read by [_readExistingOutput].
  /// `null` when there is none (a cold build).
  Future<String?> _existingOutput(AssetId output) async =>
      _lastGood[output] ?? await _readExistingOutput(output);

  /// Scans and emits the sources of the module [output] (with its files)
  /// for [buildStep]'s input.
  ///
  /// Returns `null` when the input is not a library or declares neither a
  /// `@ComponentScan` variable nor a `@SpringBootApplication` function.
  /// Throws the build errors listed on [build].
  Future<ModuleSources?> _generate(BuildStep buildStep, AssetId output) async {
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

    final resources = await SpringBuilder.resources(buildStep);
    final (built: started, :conditions) = await _startedGenerations(
      buildStep,
      BuildKeys(() => _texts(resources)),
    );
    final packageParts = await _moduleParts(buildStep, started);
    final coreParts = await _coreParts(buildStep);
    final scanner = BeanScanner(
      module,
      proxyMode: proxyMode,
      scan: componentScanModel(
        componentScanChecker.firstAnnotationOf(scan)!,
        scan,
      ),
      generations: started,
    );
    final build = await _prepareModule(
      buildStep,
      scanner,
      output,
      resources,
      started,
    );
    await _scanLibraries(buildStep, scanner, assets);
    for (final generation in started) {
      generation.scanModule(build);
    }
    scanner.collectErrors(() => _checkUniqueNames(module.beans));
    await _checkModule(build, started);
    scanner.throwErrors();

    // In a library package any module may import this one, so its beans
    // may be advised by aspects the build cannot see: no proxy is pruned,
    // and the `lib/` modules leave to the application's build the proxies
    // only its aspects can match. In an application (`publish_to: none`)
    // nothing outside imports it: it is pruned knowing the advice of the
    // package's other libraries and of the auto-configurations, as the
    // @SpringBootApplication output.
    final dependencies = build.dependencies;
    final application = await _isApplication(buildStep);
    final prune = pruneProxies && application;
    // A starter's `lib/` modules (a package with an auto-configuration
    // library), and those of a library that says a starter imports them
    // ([deferProxies]): the application's build finds them through the
    // auto-configurations and its own imports ([_deferredProxies]).
    final defer =
        pruneProxies &&
        !application &&
        output.path.startsWith('lib/') &&
        (deferProxies ||
            await buildStep.canRead(
              AssetId(output.package, autoConfigurationLibrary),
            ));
    return ModuleEmitter(
      output,
      dependencies: dependencies,
      deferProxies: defer,
      pruneProxies: prune,
      generations: started,
      generationConditions: conditions,
      // Pruning, and deferring, know the advice of the package's other
      // modules and of the auto-configurations.
      foreignAdvice: prune || defer
          ? await _foreignAdvice(
              buildStep,
              scanner,
              await _otherLibraries(buildStep, assets),
              includeOwn: true,
            )
          : null,
    ).emit(
      moduleName: variableName,
      variableName: '\$$variableName',
      scannedDirectory: directory,
      module: module,
      resources: await embedded(buildStep, resources),
      packageParts: packageParts,
      coreParts: coreParts,
    );
  }

  /// The parts of [generations] whose starter the package of [buildStep]'s
  /// input reaches ([reachablePackages]), all of them when its
  /// dependencies cannot be read, less those their build keys leave out
  /// ([PackageGeneration.build], read from [keys]); with the condition the
  /// code of each one only in debug builds is under.
  Future<
    ({List<PackageGeneration> built, Map<PackageGeneration, String> conditions})
  >
  _startedGenerations(BuildStep buildStep, BuildKeys keys) async =>
      builtGenerations(
        startedGenerations(generations, await reachablePackages(buildStep)),
        keys,
      );

  /// The generated files of the [started] parts that are `part of` the
  /// output of [buildStep]'s input, with what comes with them (imports,
  /// introspections, resources), by part in the parts' order; a part
  /// without any is left out.
  static Future<Map<PackageGeneration, ModuleParts>> _moduleParts(
    BuildStep buildStep,
    List<PackageGeneration> started,
  ) async => {
    for (final generation in started)
      if (await generation.moduleParts(buildStep) case final parts
          when !identical(parts, ModuleParts.none))
        generation: parts,
  };

  /// The generated files of the core that are `part of` the output of
  /// [buildStep]'s input (the classes of `spring.json.schemas`), with what
  /// comes with them; written after the parts' ([_moduleParts]).
  static Future<List<ModuleParts>> _coreParts(BuildStep buildStep) async => [
    if (await jsonSchemaModuleParts(buildStep) case final parts
        when !identical(parts, ModuleParts.none))
      parts,
  ];

  /// What the [started] parts get of the module [scanner] fills for
  /// [output], with the module's [resources]; each prepares it
  /// ([PackageGeneration.prepareModule]) before the scan.
  Future<ModuleBuild> _prepareModule(
    BuildStep buildStep,
    BeanScanner scanner,
    AssetId output,
    Map<String, ({String? text, String? base64})> resources,
    List<PackageGeneration> started,
  ) async {
    final build = ModuleBuild(
      scanner,
      buildStep: buildStep,
      packageDirectories: _packageDirectories,
      resources: _texts(resources),
      dependencies: await _dependencies(buildStep),
      // A starter the package only reaches (the data starter, through the
      // Supabase starter) is imported all the same. Not in the `lib/` of a
      // published package, whose imports pub.dev checks against its
      // `dependencies`.
      importablePackages:
          await _isApplication(buildStep) || !output.path.startsWith('lib/')
          ? await reachablePackages(buildStep)
          : null,
    );
    for (final generation in started) {
      await generation.prepareModule(build);
    }
    return build;
  }

  /// The checks of the [started] parts of the module of [build], whose
  /// problems join the scan's.
  static Future<void> _checkModule(
    ModuleBuild build,
    List<PackageGeneration> started,
  ) async {
    for (final generation in started) {
      await generation.checkModule(build);
    }
  }

  /// The files of [resources] to embed: all of them but those of
  /// `spring.resources.embed.exclude` (globs below `lib/resources/`:
  /// `content/**`), which the app reads as Flutter assets instead, so they
  /// are not in its binary and the web downloads one when it is read. The
  /// configuration (`application*.yml`, `*.properties`, `config/`) is
  /// always embedded: the start reads it at once. A file left out that is
  /// no Flutter asset of `pubspec.yaml` is reported, with the lines to add
  /// (an asset directory has its own files only, not its subdirectories').
  ///
  /// A file that looks like a secret (a dotfile such as `.env`, a key or
  /// keystore: `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`,
  /// `id_rsa`, `credentials*.json`, `service-account*.json`) is left out
  /// too, also below `config/`, with a warning: the module is compiled into
  /// every build, a web or mobile one included, where anyone can read it.
  /// The globs of
  /// `spring.resources.embed.secrets` embed such files anyway.
  static Future<Map<String, ({String? text, String? base64})>> embedded(
    BuildStep buildStep,
    Map<String, ({String? text, String? base64})> resources,
  ) async {
    final withoutSecrets = _withoutSecrets(resources);
    final patterns = embedExclusions(_texts(withoutSecrets));
    if (patterns.isEmpty) {
      return withoutSecrets;
    }
    final globs = [for (final pattern in patterns) Glob(pattern)];
    final kept = <String, ({String? text, String? base64})>{};
    final left = <String>[];
    for (final MapEntry(key: path, :value) in withoutSecrets.entries) {
      if (_isConfiguration(path) || !globs.any((g) => g.matches(path))) {
        kept[path] = value;
      } else {
        left.add(path);
      }
    }
    final assets = await flutterAssets(buildStep);
    if (assets != null) {
      final missing = {
        for (final path in left)
          if (!assets.contains('lib/resources/$path') &&
              !assets.contains(
                '${p.url.dirname('lib/resources/$path')}/',
              ))
            '${p.url.dirname('lib/resources/$path')}/',
      }.toList()..sort();
      if (missing.isNotEmpty) {
        log.warning(
          'spring.resources.embed.exclude leaves ${missing.length} '
          'director${missing.length == 1 ? 'y' : 'ies'} out of the binary '
          'that are no Flutter assets, so resources: finds nothing there at '
          'run time. Add to pubspec.yaml, under flutter: assets: (a '
          'directory has its own files, not those of its subdirectories):\n'
          '${[for (final directory in missing) '    - $directory'].join('\n')}',
        );
      }
    }
    return kept;
  }

  // [resources] without the files that look like secrets, unless the
  // globs of `spring.resources.embed.secrets` name them; a warning lists
  // those left out.
  static Map<String, ({String? text, String? base64})> _withoutSecrets(
    Map<String, ({String? text, String? base64})> resources,
  ) {
    final secret = [
      for (final path in resources.keys)
        if (looksLikeSecretFile(path)) path,
    ];
    if (secret.isEmpty) {
      return resources;
    }
    final allowed = [
      for (final pattern in embedExclusions(
        _texts(resources),
        key: 'spring.resources.embed.secrets',
      ))
        Glob(pattern),
    ];
    final left = [
      for (final path in secret)
        if (!allowed.any((glob) => glob.matches(path))) path,
    ];
    if (left.isEmpty) {
      return resources;
    }
    log.warning(
      '${left.length} file${left.length == 1 ? '' : 's'} of lib/resources/ '
      'look${left.length == 1 ? 's' : ''} like a secret and '
      '${left.length == 1 ? 'is' : 'are'} not embedded (the module is '
      'compiled into every build, a web or mobile one too, where anyone '
      'can read it): ${left.join(', ')}. Keep secrets out of lib/resources/ '
      '(read them from the environment), or list the file under '
      'spring.resources.embed.secrets to embed it anyway.',
    );
    return {
      for (final MapEntry(:key, :value) in resources.entries)
        if (!left.contains(key)) key: value,
    };
  }

  /// Whether the resource at [path] (below `lib/resources/`) looks like a
  /// secret: a dotfile or a file in a dot directory (`.env`, `.git/`), a
  /// private key, a keystore or a credentials file.
  static bool looksLikeSecretFile(String path) {
    final segments = p.url.split(path);
    final name = segments.last.toLowerCase();
    return segments.any((segment) => segment.startsWith('.')) ||
        _secretFile.hasMatch(name);
  }

  static final _secretFile = RegExp(
    r'(\.(pem|key|p12|pfx|jks|keystore|ppk|asc|gpg)$)|'
    r'(^id_(rsa|dsa|ecdsa|ed25519)(\..*)?$)|'
    r'(^(credentials|secrets?|service[-_]account)[^/]*\.(json|ya?ml|properties)$)|'
    r'(\.env$)',
  );

  /// The globs of `spring.resources.embed.exclude` (or of [key]) in the
  /// configuration [texts] without a profile, as every build key is read
  /// (a list, or one text of comma-separated globs).
  static List<String> embedExclusions(
    Map<String, String> texts, {
    String key = 'spring.resources.embed.exclude',
  }) {
    if (!texts.values.any((text) => text.contains('embed'))) {
      return const [];
    }
    final String? Function(String key) property;
    try {
      property = readPlatformEnvironment(
        BuildKeys.baseConfiguration(texts).files,
        profiles: const [],
      ).getProperty;
    } on Object {
      return const [];
    }
    return [
      ...?property(key)
          ?.split(',')
          .map((String part) => part.trim())
          .where((String part) => part.isNotEmpty),
      for (var i = 0; property('$key[$i]') != null; i++)
        property('$key[$i]')!.trim(),
    ];
  }

  // The configuration the start reads at once: never left out.
  static bool _isConfiguration(String path) =>
      path.startsWith('config/') ||
      path.endsWith('.properties') ||
      RegExp(r'^application[^/]*\.(ya?ml|properties)$').hasMatch(path);

  /// The `flutter: assets:` of the package's pubspec.yaml (directories end
  /// with `/`); `null` when it is no Flutter package.
  static Future<Set<String>?> flutterAssets(BuildStep buildStep) async {
    final pubspec = AssetId(buildStep.inputId.package, 'pubspec.yaml');
    if (!await buildStep.canRead(pubspec)) {
      return null;
    }
    final Object? yaml;
    try {
      yaml = loadYaml(await buildStep.readAsString(pubspec));
    } on YamlException {
      return null;
    }
    if (yaml is! Map || yaml['flutter'] is! Map) {
      return null;
    }
    final list = (yaml['flutter'] as Map)['assets'];
    return {
      if (list is List)
        for (final entry in list)
          switch (entry) {
            final String path => path,
            final Map<Object?, Object?> map when map['path'] is String =>
              map['path']! as String,
            _ => '',
          },
    }..remove('');
  }

  // The text files among [resources], by path.
  static Map<String, String> _texts(
    Map<String, ({String? text, String? base64})> resources,
  ) => {
    for (final MapEntry(:key, :value) in resources.entries)
      if (value.text != null) key: value.text!,
  };

  /// The files under `lib/resources/`, keyed by their path below that
  /// directory, to embed in the generated module.
  ///
  /// They are the application's `resources:` resources (config files,
  /// templates, messages). Embedding them makes `resources:` work on every
  /// platform without declaring Flutter assets. Text files are kept as
  /// text, other files are base64-encoded, and files above
  /// [_maxEmbeddedBytes] are skipped, with a warning unless [warn] is
  /// `false` (another builder reading the same files, which the main
  /// builder already warns about).
  ///
  /// An application whose `main` is outside `lib/` (`example/`,
  /// `example/shop/bin/`, `tool/demo/`) also gets the `lib/resources/` of
  /// every directory from the package root down to its own (see
  /// [resourceDirectories]). The nearer to `main`, the higher the
  /// precedence: an example's `example/lib/resources/application.properties`
  /// wins over the package's, as an application's config wins over a
  /// library's.
  static Future<Map<String, ({String? text, String? base64})>> resources(
    BuildStep buildStep, {
    String? entryDirectory,
    bool warn = true,
  }) async {
    final result = <String, ({String? text, String? base64})>{};
    for (final directory in resourceDirectories(entryDirectory)) {
      final assets = await buildStep
          .findAssets(Glob('$directory**'))
          .where((asset) => !asset.path.endsWith('.dart'))
          // The search index the build writes: a Flutter asset only.
          .where((asset) => !asset.path.startsWith('${directory}spring_gen/'))
          .toList();
      assets.sort((a, b) => a.path.compareTo(b.path));
      await _embed(buildStep, assets, directory, result, warn: warn);
    }
    return result;
  }

  static Future<void> _embed(
    BuildStep buildStep,
    List<AssetId> assets,
    String directory,
    Map<String, ({String? text, String? base64})> result, {
    required bool warn,
  }) async {
    for (final asset in assets) {
      final bytes = await buildStep.readAsBytes(asset);
      final path = asset.path.substring(directory.length);
      if (bytes.length > _maxEmbeddedBytes) {
        if (!warn) {
          continue;
        }
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
  Future<ModuleSources> _buildApplication(
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

    final resources = await SpringBuilder.resources(
      buildStep,
      entryDirectory: directory,
    );
    final keys = BuildKeys(() => _texts(resources));
    final (built: started, :conditions) = await _startedGenerations(
      buildStep,
      keys,
    );
    // The parts' files, after the application's own (which win).
    for (final generation in started) {
      final files = await generation.applicationResources(buildStep);
      for (final MapEntry(key: path, value: text) in files.entries) {
        resources.putIfAbsent(path, () => (text: text, base64: null));
      }
    }
    final scanner = BeanScanner(
      module,
      proxyMode: proxyMode,
      generations: started,
    );
    final build = await _prepareModule(
      buildStep,
      scanner,
      output,
      resources,
      started,
    );
    await _scanLibraries(buildStep, scanner, assets);
    for (final generation in started) {
      generation.scanModule(build);
    }
    scanner.collectErrors(() => _checkUniqueNames(module.beans));
    await _checkModule(build, started);
    scanner.throwErrors();

    final (
      modules: autoConfigurations,
      proxies: proxyBuild,
      excluded: excludedModules,
    ) = await _autoConfigurations(
      buildStep,
      keys: keys,
      includeOwn: example,
    );
    // The beans of the auto-configurations' modules whose proxy class is
    // left to the application.
    if (proxyMode != ProxyMode.none) {
      for (final (:source, :beanName, :beanNames, :type)
          in await _deferredProxies(buildStep, assets, includeOwn: example)) {
        final build = proxyBuild[source];
        if (build != null && build.condition == null) {
          continue; // a bean only of modules the build leaves out
        }
        if (scanner.foreignProxyModel(type) case final proxy?) {
          module.foreignProxies.add(
            ForeignProxyModel(
              source: source,
              beanName: beanName,
              beanNames: beanNames,
              proxy: proxy,
              element: type.element,
              condition: build?.condition,
            ),
          );
        }
      }
    }
    final springApplication = refer('springApplication');
    final dependencies = build.dependencies;
    final emitter = ModuleEmitter(
      output,
      dependencies: dependencies,
      pruneProxies: pruneProxies,
      generations: started,
      generationConditions: conditions,
      foreignAdvice: pruneProxies
          ? await _foreignAdvice(
              buildStep,
              scanner,
              nested,
              // The package's own advisors too, whatever the entry point (a
              // starter's test applications use its auto-configuration):
              // knowing one more advisor only keeps more proxies.
              includeOwn: true,
              excluded: excludedModules,
            )
          : null,
    );
    final (exclude, excludeName) = _exclusions(emitter, boots.single);
    // The auto-configurations of debug builds only go into the debug part,
    // which the library spreads in only in debug builds.
    final debugModules = [
      for (final module in autoConfigurations)
        if (module.conditions.contains(debugOnlyCondition)) module,
    ];
    final releasedModules = [
      for (final module in autoConfigurations)
        if (!module.conditions.contains(debugOnlyCondition)) module,
    ];
    // The nested @ComponentScan modules are the application's too: a
    // placeholder of theirs is read as much as one of the scan's own.
    final ownDefines = await _dartDefineKeys(
      buildStep,
      [...assets, ...nested],
      resources,
    );
    final defines = await _clientDefines(
      buildStep,
      DartDefineKeys.without(
        (DartDefineKeys()
              ..addAll(ownDefines)
              ..addAll(await _metadataDefineNames(buildStep)))
            .keys,
        dartDefinesExclude,
      ),
      own: ownDefines.toSet(),
      _publicDefines([
        for (final generation in started) ...generation.publicDefines,
        ...dartDefinesSecrets,
      ], resources),
    );
    final packageParts = await _moduleParts(buildStep, started);
    final coreParts = await _coreParts(buildStep);
    final sources = emitter.emit(
      moduleName: 'application',
      variableName: r'$application',
      scannedDirectory: roots.map((r) => '$r/').join(' and '),
      module: module,
      resources: await embedded(buildStep, resources),
      packageParts: packageParts,
      coreParts: coreParts,
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
                        for (final module in releasedModules) module.entry(),
                        if (debugModules.isNotEmpty)
                          _inDebug(_debugAutoConfigurations),
                      ]),
                    if (autoConfigurations.any((m) => m.ordering != null))
                      'autoConfigurationMetadata': literalMap({
                        for (final module in releasedModules)
                          module.entry(): ?module.ordering,
                        if (debugModules.any((m) => m.ordering != null))
                          literalSpread(): const CodeExpression(
                            Code(
                              '$debugOnlyCondition '
                              '? $_debugAutoConfigurationMetadata : const {}',
                            ),
                          ),
                      }),
                    if (exclude.isNotEmpty) 'exclude': literalList(exclude),
                    if (excludeName.isNotEmpty)
                      'excludeName': literalList(excludeName),
                    if (defines.isNotEmpty) 'dartDefines': refer(_dartDefines),
                    // Read by a hot reload only; a profile or a release
                    // build leaves the debug part out.
                    'fingerprint': const CodeExpression(
                      Code('$debugOnlyCondition ? $_fingerprint : null'),
                    ),
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
      ],
      partDeclarations: {
        // What only a hot reload uses.
        debugExtension: [
          ..._debugAutoConfigurationDeclarations(debugModules),
          ..._debugDeclarations(springApplication),
        ],
        // The values of the `--dart-define`s, a constant the compiler
        // computes.
        environmentExtension: [
          if (defines.isNotEmpty)
            Field(
              (f) => f
                ..docs.add(
                  '/// The `--dart-define` values of the properties and '
                  'environment variables\n/// the application may read: '
                  'those given to the build\n'
                  '/// (`SpringApplication.dartDefines`).',
                )
                ..modifier = FieldModifier.constant
                ..name = _dartDefines
                ..type = refer('Map<String, String>')
                ..assignment = Code(
                  [
                    '{',
                    for (final key in defines) _dartDefineEntry(key),
                    '}',
                  ].join('\n'),
                ),
            ),
        ],
      },
    );
    return _withFingerprint(
      sources,
      nestedShapes: await _beanShapes(buildStep, nested),
    );
  }

  // What the wiring of the nested @ComponentScan modules depends on, from
  // their libraries ([nested]): each class's name, supertypes, annotations
  // and those of its members, and its members' and constructors'
  // signatures. Their generated code is another output of this builder, so
  // the application's hash takes this in its place: a bean added, an
  // injection or a condition changed in a nested module changes the hash
  // (a reload restarts the context), a method body does not.
  static Future<String> _beanShapes(
    BuildStep buildStep,
    List<AssetId> nested,
  ) async {
    if (nested.isEmpty) {
      return '';
    }
    final resolver = buildStep.resolver;
    final shapes = StringBuffer();
    String annotations(Element element) => [
      for (final annotation in element.metadata.annotations)
        annotation.toSource(),
    ].join();
    for (final asset in nested) {
      if (!await resolver.isLibrary(asset)) {
        continue;
      }
      final library = await resolver.libraryFor(asset);
      for (final element in [...library.classes, ...library.mixins]) {
        shapes
          ..write(element.name)
          ..write(annotations(element))
          ..write(element.allSupertypes.map((t) => t.getDisplayString()))
          ..write('{');
        for (final member in <Element>[
          ...element.constructors,
          ...element.fields,
          ...element.getters,
          ...element.setters,
          ...element.methods,
        ]) {
          shapes
            ..write(annotations(member))
            ..write(switch (member) {
              final ExecutableElement executable =>
                '${executable.displayName}'
                    '${executable.type.getDisplayString()}',
              final FieldElement field =>
                '${field.name}:${field.type.getDisplayString()}',
              _ => member.displayName,
            })
            ..write(';');
          if (member is ExecutableElement) {
            for (final parameter in member.formalParameters) {
              shapes.write(annotations(parameter));
            }
          }
        }
        shapes.write('}');
      }
      for (final variable in library.topLevelVariables) {
        shapes.write(annotations(variable));
      }
    }
    return '$shapes';
  }

  // The getters of the debug part with the auto-configurations a release
  // build leaves out ([debugModules], each under its other conditions) and
  // their orderings; none without such modules.
  static List<Spec> _debugAutoConfigurationDeclarations(
    List<_AutoConfiguration> debugModules,
  ) {
    if (debugModules.isEmpty) {
      return const [];
    }
    final ordered = [
      for (final module in debugModules)
        if (module.ordering != null) module,
    ];
    return [
      Method(
        (m) => m
          ..docs.add(
            '/// The auto-configurations only debug builds have (their build '
            'key leaves\n/// them out of a profile or a release build), '
            'which `springApplication` adds\n/// to its own in debug '
            'builds.',
          )
          ..type = MethodType.getter
          ..returns = TypeReference(
            (t) => t
              ..symbol = 'List'
              ..types.add(refer('BeanModule', _bootUrl)),
          )
          ..name = _debugAutoConfigurations
          ..lambda = true
          ..body = literalList([
            for (final module in debugModules)
              module.entry(except: debugOnlyCondition),
          ]).code,
      ),
      if (ordered.isNotEmpty)
        Method(
          (m) => m
            ..docs.add(
              '/// The orderings of [$_debugAutoConfigurations] '
              '(`AutoConfigurationModule`).',
            )
            ..type = MethodType.getter
            ..returns = TypeReference(
              (t) => t
                ..symbol = 'Map'
                ..types.addAll([
                  refer('BeanModule', _bootUrl),
                  refer('AutoConfigurationModule', _bootUrl),
                ]),
            )
            ..name = _debugAutoConfigurationMetadata
            ..lambda = true
            ..body = literalMap({
              for (final module in ordered)
                module.entry(except: debugOnlyCondition): module.ordering,
            }).code,
        ),
    ];
  }

  // [getter] of the debug part spread into a list in debug builds only.
  static Expression _inDebug(String getter) =>
      CodeExpression(Code('if ($debugOnlyCondition) ...$getter'));

  // The getters of the debug part with the auto-configurations a release
  // build leaves out, and their orderings.
  static const _debugAutoConfigurations = r'_$debugAutoConfigurations';
  static const _debugAutoConfigurationMetadata =
      r'_$debugAutoConfigurationMetadata';

  // What only a hot reload uses, in the part `.spring.debug.dart`: the
  // fingerprint of the generated code and the reload functions of
  // [springApplication].
  static List<Spec> _debugDeclarations(Expression springApplication) => [
    Field(
      (f) => f
        ..docs.add(
          '/// The hash of the generated code, which a hot reload '
          'compares to restart\n'
          '/// the application only when its beans changed '
          '(`SpringApplication.reload`).',
        )
        ..modifier = FieldModifier.constant
        ..name = _fingerprint
        ..assignment = literalString(_fingerprintPlaceholder).code,
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
  ];

  // [sources] with the hash of the generated code (the library and its
  // files: a description changed is new code too, and so is a key the
  // application may now read from a `--dart-define` or a debug
  // auto-configuration) in place of the
  // placeholder of the debug part; same length, so the formatting is
  // unchanged.
  static ModuleSources _withFingerprint(
    ModuleSources sources, {
    String nestedShapes = '',
  }) {
    const declaration = "$_fingerprint = '$_fingerprintPlaceholder'";
    final code = [
      nestedShapes,
      sources.module,
      ?sources.introspection,
      ?sources.properties,
      ?sources.proxies,
      ?sources.parts[environmentExtension],
      // With the placeholder still in it: the debug auto-configurations.
      ?sources.parts[debugExtension],
    ].join();
    return ModuleSources(
      sources.module,
      introspection: sources.introspection,
      properties: sources.properties,
      proxies: sources.proxies,
      parts: {
        ...sources.parts,
        if (sources.parts[debugExtension] case final debug?)
          debugExtension: debug.replaceFirst(
            declaration,
            "$_fingerprint = '${_fnv1a(code)}'",
          ),
      },
    );
  }

  // The constant of the debug part with the hash of the generated code.
  static const _fingerprint = r'_$fingerprint';

  static const _fingerprintPlaceholder = '00000000';

  // The constant of the part `.spring.env.dart` with the values of the
  // `--dart-define`s.
  static const _dartDefines = r'_$dartDefines';

  // The entry of [key] in the constant [_dartDefines]: there when the
  // define is given.
  static String _dartDefineEntry(String key) =>
      "if (bool.hasEnvironment('$key')) "
      "'$key': String.fromEnvironment('$key'),";

  // [prefixes] and the placeholders the configuration gives their
  // properties (`anon-key: ${SUPABASE_ANON_KEY}`), as public as they are.
  static List<String> _publicDefines(
    List<String> prefixes,
    Map<String, ({String? text, String? base64})> resources,
  ) => [
    ...prefixes,
    for (final MapEntry(key: path, value: (:text, base64: _))
        in resources.entries)
      if (text != null)
        ...DartDefineKeys.placeholdersUnder(path, text, prefixes),
  ];

  // [keys] for the application of [buildStep]: in a client app (a Flutter
  // package) without the names that look like a secret, but those under
  // [kept]; a warning lists the names left out.
  static Future<List<String>> _clientDefines(
    BuildStep buildStep,
    List<String> keys,
    List<String> kept, {
    Set<String> own = const {},
  }) async {
    if (await flutterAssets(buildStep) == null) {
      return keys;
    }
    final public = DartDefineKeys.without(keys, kept).toSet();
    final left = [
      for (final key in keys)
        if (public.contains(key) && SecretNames.looksSecret(key)) key,
    ];
    if (left.isEmpty) {
      return keys;
    }
    // Only the application's own names are worth a word: the starters'
    // (`spring.datasource.password` of a reachable data starter) are left
    // out quietly.
    final named = [
      for (final key in left)
        if (own.contains(key)) key,
    ];
    final dropped = left.toSet();
    final kept0 = [
      for (final key in keys)
        if (!dropped.contains(key)) key,
    ];
    if (named.isEmpty) {
      return kept0;
    }
    left
      ..clear()
      ..addAll(named);
    log.warning(
      '${left.length} name${left.length == 1 ? '' : 's'} that look like a '
      'secret ${left.length == 1 ? 'is' : 'are'} not offered to '
      '--dart-define in this client app: a define the code names is '
      'compiled into the app, where anyone can read it '
      '(${left.take(8).join(', ')}${left.length > 8 ? ', ...' : ''}). '
      'A client cannot keep a secret; read it on a server. To offer such '
      'a name anyway (a public key), list its prefix under the builder '
      'option dart_defines_secrets; dart_defines_exclude leaves out others.',
    );
    return kept0;
  }

  // The properties of every package the application reaches, from their
  // `spring_metadata.json` (written for the editors): a `--dart-define`
  // may set any of them, as an environment variable may in Spring Boot,
  // not only those the application's own files name.
  static Future<List<String>> _metadataDefineNames(BuildStep buildStep) async {
    final packages = await reachablePackages(buildStep);
    if (packages == null) {
      return const [];
    }
    final names = <String>[];
    for (final package in packages.toList()..sort()) {
      final id = AssetId(package, 'lib/spring_gen/spring_metadata.json');
      if (!await buildStep.canRead(id)) {
        continue;
      }
      try {
        final json = jsonDecode(await buildStep.readAsString(id));
        if (json case {'properties': final List<Object?> properties}) {
          for (final property in properties) {
            if (property case {'name': final String name}) {
              names.add(name);
            }
          }
        }
      } on FormatException {
        continue;
      }
    }
    return names;
  }

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
    return keys.names;
  }

  // Runs [visitor] over the resolved declarations of [library]; `false`
  // when one cannot be resolved.
  // The advisors of the modules left out of the build ([excluded]: their
  // `library#name`) are not visited: they put no advice into the app.
  static Future<bool> _visitDeclarations(
    Resolver resolver,
    LibraryElement library,
    _AdvisorCreations visitor, {
    Set<String> excluded = const {},
  }) async {
    final declarations = <Element>[
      for (final variable in library.topLevelVariables)
        if (!excluded.contains('${library.uri}#${variable.name}')) variable,
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
    Set<String> excluded = const {},
  }) async {
    final foreign = ForeignAdvice();
    final resolver = buildStep.resolver;
    for (final asset in nested) {
      if (await resolver.isLibrary(asset)) {
        final library = await resolver.libraryFor(asset);
        // The bodies of their `@Bean` methods, to read the pointcuts of
        // advisor beans.
        await scanner.resolveBeanMethods(
          library,
          (fragment) => resolver.astNodeFor(fragment, resolve: true),
        );
        scanner.collectAdvice(library, foreign);
      }
    }
    final root = buildStep.inputId.package;
    final config = await buildStep.packageConfig;
    final reachable = await reachablePackages(buildStep);
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
        final asset = AssetId.resolve(library.uri);
        // The package's generated modules (and the libraries of their
        // descriptions), when its own are built in this phase (a starter's,
        // whose auto-configuration imports them): the advisors of the
        // libraries they come from are in [nested].
        if (package.name == root &&
            isGeneratedSource(asset.path) &&
            !await buildStep.canRead(asset)) {
          continue;
        }
        final source = await buildStep.readAsString(asset);
        if (source.contains('AspectMetadata')) {
          foreign.unknown = true;
        }
        if (source.contains('Advisor') &&
            !await _visitDeclarations(
              resolver,
              library,
              advisors,
              excluded: excluded,
            )) {
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
      foreign.advisedAnnotations.addAll(advisors.annotations);
      if (advisors.undeclared) {
        foreign.undeclaredAnnotations = true;
      }
      // Its advisors are read: the hand-written definitions of an
      // auto-configuration name their source after the package.
      foreign.knownSources.add('package:${package.name}');
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
          literalString(ConstantReader(name).stringValue, raw: true),
      ],
    );
  }

  // Auto-configuration modules of every dependency (direct or transitive):
  // top-level variables annotated `@AutoConfigurationModule` in
  // `lib/spring_auto_configuration.dart`, with an expression for their
  // `order` / `before` / `after` when set. `SpringApplication` sorts them
  // (Boot's AutoConfigurationSorter); here they are by package, then name.
  // With [includeOwn] (an example), the package's own too.
  //
  // A module with `build: AutoConfigurationBuild(property)` is decided by
  // that property of the application's configuration ([keys]): in, out (no
  // code at all), or in under [debugOnlyCondition], which a profile or a
  // release build compiles away with everything only the module reaches.
  // A module with a `platform` is in under that platform's constant the
  // same way.
  // [proxies]: the build of the beans (by source) with a deferred proxy
  // that are only in such modules, so their proxies leave with them;
  // walked only when a module is decided so.
  static Future<
    ({
      List<_AutoConfiguration> modules,
      Map<String, _ProxyBuild> proxies,
      Set<String> excluded,
    })
  >
  _autoConfigurations(
    BuildStep buildStep, {
    required BuildKeys keys,
    bool includeOwn = false,
  }) async {
    final root = buildStep.inputId.package;
    final found = <(Expression?, String, String, String, List<String>)>[];
    // Each module with the conditions it is in the build under: `null`
    // when it is left out, none when it is always in.
    final decided = <(TopLevelVariableElement, List<String>?)>[];
    final config = await buildStep.packageConfig;
    final reachable = await reachablePackages(buildStep);
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
          final choice = _buildChoice(
            ConstantReader(annotation).peek('build'),
            keys,
            '${package.name}.${variable.name}',
          );
          if (choice == BuildInclusion.never) {
            decided.add((variable, null));
            continue;
          }
          final conditions = [
            if (choice == BuildInclusion.debugOnly) debugOnlyCondition,
            ?_platformCondition(ConstantReader(annotation).peek('platform')),
          ];
          decided.add((variable, conditions));
          found.add((
            _orderingOf(ConstantReader(annotation)),
            package.name,
            variable.name!,
            'package:${package.name}/spring_auto_configuration.dart',
            conditions,
          ));
        }
      }
    }
    found.sort((a, b) {
      final byPackage = a.$2.compareTo(b.$2);
      return byPackage != 0 ? byPackage : a.$3.compareTo(b.$3);
    });
    final modules = [
      for (final (ordering, _, name, url, conditions) in found)
        _AutoConfiguration(refer(name, url), conditions, ordering),
    ];
    return (
      modules: modules,
      proxies: await _proxyBuild(buildStep.resolver, decided),
      excluded: {
        for (final (variable, conditions) in decided)
          if (conditions == null) '${variable.library.uri}#${variable.name}',
      },
    );
  }

  // `AutoConfigurationModule.platform` as the constants the compilers know:
  // true where the module works, so the other platform's build drops the
  // module and all only it reaches. A server is native without Flutter
  // (`dart.library.ui`), so a Flutter app on a phone or a desktop drops it
  // too.
  static String? _platformCondition(ConstantReader? platform) {
    if (platform == null || platform.isNull) {
      return null;
    }
    const io = "const bool.fromEnvironment('dart.library.io')";
    final condition = switch (platform.objectValue.variable?.name) {
      'native' => io,
      'web' => "const bool.fromEnvironment('dart.library.js_interop')",
      'server' => "($io && !const bool.fromEnvironment('dart.library.ui'))",
      _ => null,
    };
    if (condition == null) {
      return null;
    }
    // A program that runs such a module on the other platform on purpose
    // (server code checked as minified JavaScript under Node) is compiled
    // with `-DSPRING_ALL_PLATFORMS=true`.
    return '($condition || '
        "const bool.fromEnvironment('$allPlatformsDefine'))";
  }

  // The beans with a deferred proxy that only modules left out of the
  // build, or in it under a condition (not in a release, one platform),
  // define, by source: left out, or the condition its proxy is under. A
  // bean also in a module always built keeps its proxy as it is.
  static Future<Map<String, _ProxyBuild>> _proxyBuild(
    Resolver resolver,
    List<(TopLevelVariableElement, List<String>?)> decided,
  ) async {
    if (decided.every((entry) => entry.$2?.isEmpty ?? false)) {
      return const {};
    }
    final walker = _ModuleProxies(resolver);
    // By source: the conditions of each module that defines the bean.
    final builds = <String, List<List<String>?>>{};
    for (final (module, conditions) in decided) {
      for (final source in await walker.of(module)) {
        (builds[source] ??= []).add(conditions);
      }
    }
    final result = <String, _ProxyBuild>{};
    for (final MapEntry(key: source, value: all) in builds.entries) {
      final built = [for (final conditions in all) ?conditions];
      if (built.isEmpty) {
        result[source] = const _ProxyBuild.never();
      } else if (!built.any((conditions) => conditions.isEmpty)) {
        final alternatives = {
          for (final conditions in built) conditions.join(' && '),
        };
        result[source] = _ProxyBuild(
          alternatives.length == 1
              ? alternatives.single
              : alternatives.map((one) => '($one)').join(' || '),
        );
      }
    }
    return result;
  }

  // `AutoConfigurationModule.build` against the application's
  // configuration ([keys]), its parents' switches included; a module
  // without one is always built.
  static BuildInclusion _buildChoice(
    ConstantReader? build,
    BuildKeys keys,
    String module,
  ) {
    if (build == null || build.isNull) {
      return BuildInclusion.always;
    }
    return keys.decideSwitch(
      BuildSwitch.fromAnnotation(build),
      subject: module,
    );
  }

  // The beans whose module left their proxy class to the application
  // (`AopProxyFactory.deferred`), in the generated modules of the library
  // packages: those the auto-configuration libraries reach and those the
  // application's [assets] import, through the libraries they import or
  // export, in their own package or another one (a starter's
  // auto-configuration importing a library without one, such as
  // spring_boot_actuator, whose main library exports its module).
  static Future<List<_DeferredProxy>> _deferredProxies(
    BuildStep buildStep,
    List<AssetId> assets, {
    bool includeOwn = false,
  }) async {
    final root = buildStep.inputId.package;
    final resolver = buildStep.resolver;
    final config = await buildStep.packageConfig;
    final reachable = await reachablePackages(buildStep);
    bool searched(LibraryElement library) {
      final uri = library.uri;
      if (uri.scheme != 'package') {
        return false;
      }
      final package = uri.pathSegments.first;
      return (package != root || includeOwn) &&
          (reachable == null || reachable.contains(package));
    }

    Iterable<LibraryElement> next(LibraryElement library) => [
      for (final fragment in library.fragments)
        ...fragment.importedLibraries.where(searched),
      ...library.exportedLibraries.where(searched),
    ];

    final pending = <LibraryElement>[];
    // The libraries the application imports.
    for (final asset in assets) {
      if (await resolver.isLibrary(asset)) {
        pending.addAll(next(await resolver.libraryFor(asset)));
      }
    }
    // Every auto-configuration library.
    for (final package in config.packages) {
      if ((package.name == root && !includeOwn) ||
          (reachable != null && !reachable.contains(package.name))) {
        continue;
      }
      final id = AssetId(package.name, autoConfigurationLibrary);
      if (await buildStep.canRead(id) && await resolver.isLibrary(id)) {
        pending.add(await resolver.libraryFor(id));
      }
    }
    final found = <_DeferredProxy>[];
    final sources = <String>{};
    final seen = <Uri>{};
    while (pending.isNotEmpty) {
      final library = pending.removeLast();
      if (!seen.add(library.uri)) {
        continue;
      }
      pending.addAll(next(library));
      if (!library.uri.path.endsWith('.spring.dart')) {
        continue;
      }
      final text = await buildStep.readAsString(AssetId.resolve(library.uri));
      if (!text.contains('AopProxyFactory.deferred')) {
        continue;
      }
      final visitor = _DeferredProxies();
      for (final getter in library.getters) {
        (await resolver.astNodeFor(
          getter.firstFragment,
          resolve: true,
        ))?.accept(visitor);
      }
      for (final entry in visitor.found) {
        if (sources.add(entry.source)) {
          found.add(entry);
        }
      }
    }
    return found;
  }

  // `const AutoConfigurationModule(order:, before:, after:)` with the
  // values the annotation sets; `null` when it sets none.
  // What `SpringApplication` needs of the annotation at run time: its
  // ordering and its factories.
  static Expression? _orderingOf(ConstantReader annotation) {
    final order = annotation.peek('order')?.intValue ?? 0;
    final before = annotation.peek('before')?.listValue ?? const [];
    final after = annotation.peek('after')?.listValue ?? const [];
    final factories = annotation.peek('factories')?.listValue ?? const [];
    if (order == 0 && before.isEmpty && after.isEmpty && factories.isEmpty) {
      return null;
    }
    List<Expression> names(List<DartObject> values) => [
      for (final value in values)
        literalString(ConstantReader(value).stringValue, raw: true),
    ];
    return refer('AutoConfigurationModule', _bootUrl).constInstance([], {
      if (order != 0) 'order': literalNum(order),
      if (before.isNotEmpty) 'before': literalList(names(before)),
      if (after.isNotEmpty) 'after': literalList(names(after)),
      if (factories.isNotEmpty)
        'factories': literalList([
          for (final factory in factories) _factory(factory),
        ]),
    });
  }

  // One of `AutoConfigurationModule.factories` as the constant it was
  // written as: a top-level or static constant by its name, else the
  // call of its const constructor.
  static Expression _factory(DartObject factory) {
    final reader = ConstantReader(factory);
    final Revivable revivable;
    try {
      revivable = reader.revive();
    } on Object {
      throw InvalidGenerationSource(_factoryForms(factory));
    }
    // A library under `lib/` is an `asset:` URI here: its `package:` one.
    final source = revivable.source.removeFragment();
    final library = switch (source) {
      Uri(
        scheme: 'asset',
        pathSegments: [final package, 'lib', ...final rest],
      ) =>
        'package:$package/${rest.join('/')}',
      Uri(scheme: 'package' || 'dart') => '$source',
      _ => '',
    };
    final type = revivable.source.fragment;
    if (revivable.isPrivate || library.isEmpty) {
      throw InvalidGenerationSource(_factoryForms(factory));
    }
    if (type.isEmpty) {
      return refer(revivable.accessor, library);
    }
    final declared = factory.type?.element;
    if (revivable.accessor.isNotEmpty &&
        declared is InterfaceElement &&
        declared.getField(revivable.accessor)?.isStatic == true) {
      return refer(type, library).property(revivable.accessor);
    }
    Expression argument(DartObject value) {
      final constant = ConstantReader(value);
      if (constant.isString) {
        return stringLiteral(constant.stringValue);
      }
      return constant.isNull ||
              constant.isBool ||
              constant.isInt ||
              constant.isDouble
          ? literal(constant.literalValue)
          : _factory(value);
    }

    final positional = [
      for (final value in revivable.positionalArguments) argument(value),
    ];
    final named = {
      for (final MapEntry(:key, :value) in revivable.namedArguments.entries)
        key: argument(value),
    };
    return revivable.accessor.isEmpty
        ? refer(type, library).constInstance(positional, named)
        : refer(
            type,
            library,
          ).constInstanceNamed(revivable.accessor, positional, named);
  }

  /// [value] as a Dart string literal that reads back as written: `\`,
  /// `$` and the line breaks are escaped (a `$` would otherwise start an
  /// interpolation in the generated code).
  static Expression stringLiteral(String value) {
    return literalString(
      value
          .replaceAll(r'\', r'\\')
          .replaceAll(r'$', r'\$')
          .replaceAll('\r', r'\r'),
    );
  }

  static String _factoryForms(DartObject factory) =>
      'AutoConfigurationModule.factories: '
      "${factory.type?.getDisplayString() ?? 'a value'} cannot be written "
      'into the generated application. A factory is a public constant: a '
      'const constructor call with literal arguments, a top-level const '
      'variable or a static const field.';

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
            .where((asset) => !isGeneratedSource(asset.path))
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
  static Future<Set<String>?> reachablePackages(BuildStep buildStep) async {
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
  // Whether the package is an application: `publish_to: none` in its
  // pubspec (nothing outside it imports its modules).
  static Future<bool> _isApplication(BuildStep buildStep) async {
    final pubspec = AssetId(buildStep.inputId.package, 'pubspec.yaml');
    if (!await buildStep.canRead(pubspec)) {
      return false;
    }
    try {
      final yaml = loadYaml(await buildStep.readAsString(pubspec));
      return yaml is Map && '${yaml['publish_to']}' == 'none';
    } on YamlException {
      return false;
    }
  }

  // The Dart files of the package's lib/ and bin/ outside [scanned] (the
  // module's own), generated files excluded: where other aspects and
  // advisors of the application live.
  static Future<List<AssetId>> _otherLibraries(
    BuildStep buildStep,
    Iterable<AssetId> scanned,
  ) async {
    final own = scanned.toSet();
    return [
      for (final directory in const ['lib', 'bin'])
        ...await buildStep
            .findAssets(Glob('$directory/**.dart'))
            .where(
              (asset) => !isGeneratedSource(asset.path) && !own.contains(asset),
            )
            .toList(),
    ];
  }

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
    scanner.checkAnnotationValues([
      for (final asset in assets)
        if (await resolver.isLibrary(asset)) await resolver.libraryFor(asset),
    ]);
    if (scanner.hasUnreadableValues) {
      scanner.throwErrors();
    }
    await for (final asset in buildStep.findAssets(Glob('lib/*.dart'))) {
      if (await resolver.isLibrary(asset)) {
        final library = await resolver.libraryFor(asset);
        scanner.exportedClasses.addAll(
          library.exportNamespace.definedNames2.values
              .whereType<InterfaceElement>(),
        );
      }
    }
    for (final asset in assets) {
      if (await resolver.isLibrary(asset)) {
        final library = await resolver.libraryFor(asset);
        await scanner.resolveBeanMethods(
          library,
          (fragment) => resolver.astNodeFor(fragment, resolve: true),
        );
        await scanner.introspection.resolveFieldInitializers(
          library,
          (fragment) => resolver.astNodeFor(fragment, resolve: true),
        );
        await scanner.introspection.resolveMapperCalls(
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
    final byName = <String, BeanModel>{};
    for (final bean in beans) {
      if (bean.conditions.isNotEmpty) {
        continue;
      }
      for (final name in [bean.name, ...bean.aliases]) {
        final previous = byName[name];
        if (previous != null) {
          throw InvalidGenerationSource(
            "Bean name '$name' is used by both ${_declaration(previous)} and "
            '${_declaration(bean)}. Rename one (@Bean(name: ...), '
            "@Component('...')), or give them conditions that exclude each "
            'other.',
            element: bean.element,
          );
        }
        byName[name] = bean;
      }
    }
  }

  // Where [bean] is declared, for messages: `the @Bean method
  // ConfigA.pool of package:app/src/a.dart`, `the class Pool of ...`.
  static String _declaration(BeanModel bean) {
    final element = bean.element;
    final library = element.library?.uri;
    final where = library == null ? '' : ' of $library';
    return switch (element) {
      MethodElement(:final enclosingElement?) =>
        'the @Bean method ${enclosingElement.displayName}.'
            '${element.displayName}$where',
      _ => 'the class ${element.displayName}$where',
    };
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

// A bean whose module left its proxy class to the application: the
// `source` of its definition, its name, its aliases and qualifiers (for
// `bean(...)` pointcuts) and its class.
typedef _DeferredProxy = ({
  String source,
  String beanName,
  List<String> beanNames,
  InterfaceType type,
});

// The `BeanDefinition<T>(name:, source:, aliases:, qualifiers:, aopProxy:
// AopProxyFactory.deferred(...))` of a generated module.
class _DeferredProxies extends RecursiveAstVisitor<void> {
  final found = <_DeferredProxy>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    super.visitInstanceCreationExpression(node);
    final type = node.staticType;
    if (type is! InterfaceType ||
        type.element.name != 'BeanDefinition' ||
        type.typeArguments.length != 1) {
      return;
    }
    final arguments = {
      for (final argument in node.argumentList.arguments)
        if (argument is NamedArgument)
          argument.name.lexeme: argument.argumentExpression,
    };
    final proxy = arguments['aopProxy'];
    final bean = type.typeArguments.single;
    if (proxy is! InstanceCreationExpression ||
        proxy.constructorName.name?.name != 'deferred' ||
        bean is! InterfaceType) {
      return;
    }
    final source = arguments['source'];
    final name = arguments['name'];
    if (source is StringLiteral && name is StringLiteral) {
      if ((source.stringValue, name.stringValue) case (
        final source?,
        final name?,
      )) {
        found.add((
          source: source,
          beanName: name,
          beanNames: [
            ..._strings(arguments['aliases']),
            ..._strings(arguments['qualifiers']),
          ],
          type: bean,
        ));
      }
    }
  }

  // The strings of a `const [...]` or `const {...}` literal of strings.
  static Iterable<String> _strings(Object? literal) => [
    for (final element in switch (literal) {
      ListLiteral(:final elements) => elements,
      SetOrMapLiteral(:final elements) => elements,
      _ => const [],
    })
      if (element case StringLiteral(:final stringValue?)) stringValue,
  ];
}

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
      } else if (!_declaredAnnotations(pointcut, annotations) &&
          !_declaredAnnotations(type, annotations)) {
        undeclared = true;
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  /// The annotations the annotation-driven advisors match, by
  /// `library#Name` (see [ForeignAdvice.advisedAnnotations]).
  final annotations = <String>{};

  /// Whether one of them does not declare its annotations.
  bool undeclared = false;

  // Adds to [into] the annotations [type] declares it matches: the `A` of
  // `AnnotationMatchingPointcut<A>`, or the `static const annotationTypes`
  // list of the pointcut's (or advisor's) class. False when it declares
  // none.
  static bool _declaredAnnotations(DartType? type, Set<String> into) {
    if (type is! InterfaceType) {
      return false;
    }
    if (_annotationMatchingPointcutChecker.isExactlyType(type)) {
      final annotation = type.typeArguments.single;
      if (annotation is InterfaceType) {
        into.add(_qualified(annotation));
        return true;
      }
      return false;
    }
    final field = type.element.getField('annotationTypes');
    if (field == null || !field.isStatic || !field.isConst) {
      return false;
    }
    final values = field.computeConstantValue()?.toListValue();
    if (values == null) {
      return false;
    }
    for (final value in values) {
      if (value.toTypeValue() case final InterfaceType annotation) {
        into.add(_qualified(annotation));
      }
    }
    return true;
  }

  static String _qualified(InterfaceType type) =>
      '${type.element.library.uri}#${type.element.name}';

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

/// The main builder, for the `lib/` of a package whose own code imports
/// what it writes.
///
/// A hand-written starter binds its `@ConfigurationProperties` classes
/// through a `@ComponentScan` library, and its `lib/` imports the result.
/// The package's example (written by [SpringBuilder]) imports that `lib/`,
/// and a builder cannot read what another input of its own phase writes.
/// This builder (`spring_properties` in `build.yaml`, off unless a package
/// turns it on, and then the main builder is limited to the example)
/// runs in an earlier phase, so the example sees the files.
class SpringPropertiesBuilder extends SpringBuilder {
  /// A builder with the options of [SpringBuilder].
  SpringPropertiesBuilder({
    super.proxyMode,
    super.pruneProxies,
    super.deferProxies,
    super.dartDefinesExclude,
    super.generations,
  });

  @override
  Map<String, List<String>> get buildExtensions => {
    '^lib/{{}}.dart': SpringBuilder.moduleOutputs('lib'),
  };
}

// Where the build puts an auto-configuration module.
/// The compile-time define that keeps every module of
/// `AutoConfigurationModule(platform:)` whatever the platform:
/// `dart compile js -DSPRING_ALL_PLATFORMS=true`.
const allPlatformsDefine = 'SPRING_ALL_PLATFORMS';

// How the proxy of a bean only conditional modules define is built: under
// [condition], or not at all (`null`).
final class _ProxyBuild {
  const _ProxyBuild(String this.condition);
  const _ProxyBuild.never() : condition = null;

  final String? condition;
}

// The sources of the beans with a deferred proxy a module defines: those
// of its initializer and of the top-level getters and variables it reads,
// through every package library.
final class _ModuleProxies {
  _ModuleProxies(this.resolver);

  final Resolver resolver;

  // What each declaration has itself; what it reaches is put together at
  // every call, so declarations that read each other give the same set
  // whichever is asked first.
  final _own = <Element, ({Set<String> proxies, Set<Element> reads})>{};

  Future<Set<String>> of(Element element) async {
    final found = <String>{};
    final seen = <Element>{};
    final pending = [element];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (!seen.add(next)) {
        continue;
      }
      final (:proxies, :reads) = _own[next] ??= await _read(next);
      found.addAll(proxies);
      pending.addAll(reads);
    }
    return found;
  }

  Future<({Set<String> proxies, Set<Element> reads})> _read(
    Element element,
  ) async {
    const none = (proxies: <String>{}, reads: <Element>{});
    final fragment = switch (element) {
      GetterElement(isOriginDeclaration: true) => element.firstFragment,
      GetterElement(:final variable) => variable.firstFragment,
      TopLevelVariableElement() => element.firstFragment,
      _ => null,
    };
    if (fragment == null || element.library?.uri.scheme != 'package') {
      return none;
    }
    final node = await resolver.astNodeFor(fragment, resolve: true);
    if (node == null) {
      return none;
    }
    final visitor = _ModuleReferences();
    node.accept(visitor);
    return (
      proxies: {for (final proxy in visitor.found) proxy.source},
      reads: visitor.reads,
    );
  }
}

// The deferred proxies of a declaration, and the top-level getters and
// variables it reads.
class _ModuleReferences extends _DeferredProxies {
  final reads = <Element>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    final element = node.element;
    if ((element is GetterElement || element is TopLevelVariableElement) &&
        element!.enclosingElement is LibraryElement) {
      reads.add(element);
    }
  }
}

// An auto-configuration module the build includes: [module], under
// [conditions] (the constants a build or a platform keeps it under; none
// when it is in every build), with its [ordering] (its
// `AutoConfigurationModule`, `null` without one).
final class _AutoConfiguration {
  _AutoConfiguration(this.module, this.conditions, this.ordering);

  final Reference module;
  final List<String> conditions;
  final Expression? ordering;

  // The module as an element of a list or a key of a map: a collection `if`
  // under its conditions, but [except].
  Expression entry({String? except}) {
    final kept = [
      for (final condition in conditions)
        if (condition != except) condition,
    ];
    return kept.isEmpty
        ? module
        : CodeExpression(
            Code.scope(
              (allocate) => 'if (${kept.join(' && ')}) ${allocate(module)}',
            ),
          );
  }
}
