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
import 'package:spring_core_dart_generator/src/asset_check.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/dart_define_keys.dart';
import 'package:spring_core_dart_generator/src/driver_glue.dart';
import 'package:spring_core_dart_generator/src/flutter_scanning.dart';
import 'package:spring_core_dart_generator/src/generated_path.dart';
import 'package:spring_core_dart_generator/src/json_schema_classes.dart';
import 'package:spring_core_dart_generator/src/module_emitter.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart'
    show KeysDiagnostics;
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart'
    show readPlatformEnvironment;
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
    Future<String?> Function(AssetId output)? readExistingOutput,
    PackageDirectories? packageDirectories,
  }) : _packageDirectories = packageDirectories ?? PackageDirectories.current,
       _readExistingOutput =
           readExistingOutput ??
           (packageDirectories ?? PackageDirectories.current).read;

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

  final Future<String?> Function(AssetId output) _readExistingOutput;

  final PackageDirectories _packageDirectories;

  // The last generated content per output in this process (`watch` keeps
  // one builder); the file on disk is the source after a fresh start.
  final Map<AssetId, String> _lastGood = {};

  // Outputs whose syntax-error warning was logged and not yet followed by
  // a successful generation.
  final Set<AssetId> _warned = {};

  /// Every `.dart` input of `lib/`, `bin/`, `test/` and `example/` may
  /// produce a `.spring.dart` output in the `spring_gen/` folder of its
  /// root (most produce none).
  @override
  Map<String, List<String>> get buildExtensions => const {
    '^lib/{{}}.dart': ['lib/spring_gen/{{}}.spring.dart'],
    '^bin/{{}}.dart': ['bin/spring_gen/{{}}.spring.dart'],
    '^test/{{}}.dart': ['test/spring_gen/{{}}.spring.dart'],
    '^example/{{}}.dart': ['example/spring_gen/{{}}.spring.dart'],
  };

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
    if (input.path.endsWith(_outputExtension) ||
        !hasGeneratedRoot(input.path)) {
      return;
    }
    // Cheap text check before resolving every library in the package.
    final text = await buildStep.readAsString(input);
    if (!text.contains('ComponentScan') &&
        !text.contains('SpringBootApplication')) {
      return;
    }
    final output = generatedId(input);
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

    final resources = await SpringBuilder.resources(buildStep);
    final keyParts = await _keyParts(buildStep);
    final json = await _jsonSchemaPart(buildStep);
    final scanner = BeanScanner(
      module,
      proxyMode: proxyMode,
      scan: componentScanModel(
        componentScanChecker.firstAnnotationOf(scan)!,
        scan,
      ),
      sqlResources: _texts(resources),
    );
    await _scanLibraries(buildStep, scanner, assets);
    scanner.collectErrors(() => _checkUniqueNames(module.beans));
    scanBuildContextAccess(module, scanner.collectErrors);
    await checkAssetValues(
      buildStep,
      module,
      scanner.collectErrors,
      packageDirectories: _packageDirectories,
    );
    scanner.throwErrors();

    // In a library package any module may import this one, so its beans
    // may be advised by aspects the build cannot see: no proxy is pruned,
    // and the `lib/` modules leave to the application's build the proxies
    // only its aspects can match. In an application (`publish_to: none`)
    // nothing outside imports it: it is pruned knowing the advice of the
    // package's other libraries and of the auto-configurations, as the
    // @SpringBootApplication output.
    final dependencies = await _dependencies(buildStep);
    final glue = await driverGlueFor(buildStep, dependencies);
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
      extra: [for (final output in glue) output.code],
      extraDefinitions: [for (final output in glue) output.definition],
      resources: {
        ...await embedded(buildStep, resources),
        ...json.resources,
      },
      parts: [...keyParts, ...json.parts],
      partImports: [
        if (keyParts.isNotEmpty) ...SpringKeyFiles.imports,
        ...json.imports,
      ],
      extraIntrospections: json.introspections,
    );
  }

  /// The generated key files (`theme.spring.dart`, `messages.spring.dart`)
  /// that are `part of` the output of the input: when the package uses the
  /// Flutter starter, the input is the parent library
  /// ([SpringKeyFiles.parentLibrary]), and
  /// the keys builder writes them (it decides with the same
  /// [SpringKeyFiles.generate]).
  Future<List<String>> _keyParts(BuildStep buildStep) async {
    if (!await SpringKeyFiles.usesFlutterStarter(buildStep)) {
      return const [];
    }
    final scans = await SpringKeyFiles.scanLibraries(buildStep);
    // The same choice as the keys builder. That builder may be disabled,
    // and a part cannot be probed with canRead: the keys builder writes to
    // source in its own phase, so the file is not readable from this one.
    // The parts are therefore decided by the shared computation.
    if (SpringKeyFiles.parentLibrary(scans).parent != buildStep.inputId) {
      return const [];
    }
    // Read as the keys builder reads them, whatever the entry point.
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final parts = SpringKeyFiles.generate(
      await SpringKeyFiles.withImports(buildStep, _texts(resources)),
      KeysDiagnostics(),
      loaderKinds: await SpringKeyFiles.loaderKinds(buildStep),
    );
    final parent = SpringKeyFiles.parentOf(buildStep.inputId);
    return [
      if (parts.theme != null)
        SpringKeyFiles.partPath(parent, SpringKeyFiles.themeFile),
      if (parts.messages != null)
        SpringKeyFiles.partPath(parent, SpringKeyFiles.messagesFile),
    ];
  }

  /// The classes of `spring.json.schemas` (`json_schemas.spring.dart`)
  /// when the input is the library their part belongs to: the part, the
  /// import it needs, its list of introspections, and the downloaded
  /// schemas as resources of the app (`JsonSchemaLocations.resourceOf`).
  /// The classes builder writes the part from the same computation.
  Future<JsonSchemaPart> _jsonSchemaPart(BuildStep buildStep) async {
    final part = await JsonSchemaPart.of(buildStep);
    if (part == null || part.parent != buildStep.inputId) {
      return JsonSchemaPart.none;
    }
    return part;
  }

  /// The files of [resources] to embed: all of them but those of
  /// `spring.resources.embed.exclude` (globs below `lib/resources/`:
  /// `content/**`), which the app reads as Flutter assets instead, so they
  /// are not in its binary and the web downloads one when it is read. The
  /// configuration (`application*.yml`, `*.properties`, `config/`) is
  /// always embedded: the start reads it at once. A file left out that is
  /// no Flutter asset of `pubspec.yaml` is reported, with the lines to add
  /// (an asset directory has its own files only, not its subdirectories').
  static Future<Map<String, ({String? text, String? base64})>> embedded(
    BuildStep buildStep,
    Map<String, ({String? text, String? base64})> resources,
  ) async {
    final patterns = embedExclusions(_texts(resources));
    if (patterns.isEmpty) {
      return resources;
    }
    final globs = [for (final pattern in patterns) Glob(pattern)];
    final kept = <String, ({String? text, String? base64})>{};
    final left = <String>[];
    for (final MapEntry(key: path, :value) in resources.entries) {
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

  /// The globs of `spring.resources.embed.exclude` in the configuration
  /// [texts] (a list, or one text of comma-separated globs).
  static List<String> embedExclusions(Map<String, String> texts) {
    if (!texts.values.any((text) => text.contains('embed'))) {
      return const [];
    }
    final String? Function(String key) property;
    try {
      property = readPlatformEnvironment(
        texts,
        profiles: const [],
      ).getProperty;
    } on Object {
      return const [];
    }
    const key = 'spring.resources.embed.exclude';
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

  // `build-info.properties` (Spring Boot's `META-INF/build-info.properties`)
  // for an application with the actuator, which its `info` endpoint shows:
  // the name and version of `pubspec.yaml`. Only for an application
  // (`publish_to: none`): the example of a published package would change
  // with every release of the family. No build time, so the generated code
  // stays the same from one build to the next; an app that wants it writes
  // the file itself (`lib/resources/build-info.properties`).
  static Future<String?> _buildInfo(BuildStep buildStep) async {
    final id = AssetId(buildStep.inputId.package, 'pubspec.yaml');
    if (!await buildStep.canRead(id)) {
      return null;
    }
    final Object? pubspec;
    try {
      pubspec = loadYaml(await buildStep.readAsString(id));
    } on YamlException {
      return null;
    }
    if (pubspec is! YamlMap || '${pubspec['publish_to']}' != 'none') {
      return null;
    }
    final dependencies = pubspec['dependencies'];
    final actuator =
        dependencies is YamlMap &&
        dependencies.keys.any(
          (name) =>
              name == 'spring_boot_actuator' ||
              name == 'spring_boot_starter_actuator',
        );
    if (!actuator) {
      return null;
    }
    final name = '${pubspec['name'] ?? ''}';
    final version = pubspec['version'];
    return [
      'build.artifact=$name',
      'build.name=$name',
      if (version != null) 'build.version=$version',
      '',
    ].join('\n');
  }

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

    final resources = await SpringBuilder.resources(
      buildStep,
      entryDirectory: directory,
    );
    if (await _buildInfo(buildStep) case final info?
        when !resources.containsKey('build-info.properties')) {
      resources['build-info.properties'] = (text: info, base64: null);
    }
    final scanner = BeanScanner(
      module,
      proxyMode: proxyMode,
      sqlResources: _texts(resources),
    );
    await _scanLibraries(buildStep, scanner, assets);
    scanner.collectErrors(() => _checkUniqueNames(module.beans));
    scanBuildContextAccess(module, scanner.collectErrors);
    await checkAssetValues(
      buildStep,
      module,
      scanner.collectErrors,
      packageDirectories: _packageDirectories,
    );
    scanner.throwErrors();

    final (
      modules: autoConfigurations,
      proxies: proxyBuild,
      excluded: excludedModules,
    ) = await _autoConfigurations(
      buildStep,
      includeOwn: example,
      configuration: _texts(resources),
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
    final dependencies = await _dependencies(buildStep);
    final glue = await driverGlueFor(buildStep, dependencies);
    final emitter = ModuleEmitter(
      output,
      dependencies: dependencies,
      pruneProxies: pruneProxies,
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
    final defines = DartDefineKeys.without(
      // The nested @ComponentScan modules are the application's too: a
      // placeholder of theirs is read as much as one of the scan's own.
      await _dartDefineKeys(buildStep, [...assets, ...nested], resources),
      dartDefinesExclude,
    );
    final keyParts = await _keyParts(buildStep);
    final json = await _jsonSchemaPart(buildStep);
    final source = emitter.emit(
      moduleName: 'application',
      variableName: r'$application',
      scannedDirectory: roots.map((r) => '$r/').join(' and '),
      module: module,
      resources: {
        ...await embedded(buildStep, resources),
        ...json.resources,
      },
      parts: [...keyParts, ...json.parts],
      partImports: [
        if (keyParts.isNotEmpty) ...SpringKeyFiles.imports,
        ...json.imports,
      ],
      extraIntrospections: json.introspections,
      extraDefinitions: [for (final output in glue) output.definition],
      extra: [
        for (final output in glue) output.code,
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
        final asset = AssetId.resolve(library.uri);
        // The package's generated modules, when its own are built in this
        // phase (a starter's, whose auto-configuration imports them): the
        // advisors of the libraries they come from are in [nested].
        if (package.name == root &&
            asset.path.endsWith('.spring.dart') &&
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
  //
  // A module with `build: AutoConfigurationBuild(property)` is decided by
  // that property of the application's [configuration]: in, out (no code
  // at all), or in under `!dart.vm.product`, which a release build
  // compiles away with everything only the module reaches. A module with
  // a `platform` is in under that platform's constant the same way.
  // [proxies]: the build of the beans (by source) with a deferred proxy
  // that are only in such modules, so their proxies leave with them;
  // walked only when a module is decided so.
  static Future<
    ({
      List<(Expression, Expression?)> modules,
      Map<String, _ProxyBuild> proxies,
      Set<String> excluded,
    })
  >
  _autoConfigurations(
    BuildStep buildStep, {
    bool includeOwn = false,
    Map<String, String> configuration = const {},
  }) async {
    final root = buildStep.inputId.package;
    final found = <(Expression?, String, String, String, List<String>)>[];
    // Each module with the conditions it is in the build under: `null`
    // when it is left out, none when it is always in.
    final decided = <(TopLevelVariableElement, List<String>?)>[];
    String? Function(String key)? lookup;
    String? property(String key) {
      lookup ??= readPlatformEnvironment(
        configuration,
        profiles: const [],
      ).getProperty;
      return lookup!(key)?.trim().toLowerCase();
    }

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
          final choice = _buildChoice(
            ConstantReader(annotation).peek('build'),
            property,
            '${package.name}.${variable.name}',
            profiled: (key) => _profileSetting(configuration, key),
          );
          if (choice == _BuildChoice.never) {
            decided.add((variable, null));
            continue;
          }
          final conditions = [
            if (choice == _BuildChoice.notInRelease)
              "!const bool.fromEnvironment('dart.vm.product')",
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
    // A module under a condition is a collection `if` in the list, and in
    // the map of the orderings too (`if (...) module: ordering`).
    final modules = [
      for (final (ordering, _, name, url, conditions) in found)
        (
          conditions.isEmpty
              ? refer(name, url)
              : CodeExpression(
                  Code.scope(
                    (allocate) =>
                        'if (${conditions.join(' && ')}) '
                        '${allocate(refer(name, url))}',
                  ),
                ),
          ordering,
        ),
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

  // `AutoConfigurationModule.platform` as the constant the compilers know:
  // true where the module works, so the other platform's build drops the
  // module and all only it reaches.
  static String? _platformCondition(ConstantReader? platform) {
    if (platform == null || platform.isNull) {
      return null;
    }
    return switch (platform.objectValue.variable?.name) {
      'native' => "const bool.fromEnvironment('dart.library.io')",
      'web' => "const bool.fromEnvironment('dart.library.js_interop')",
      _ => null,
    };
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

  // The profile's configuration file (`application-web.yml`) that sets
  // [key], which the build does not read; `null` when none does.
  static String? _profileSetting(Map<String, String> files, String key) {
    final parts = key.split('.');
    bool sets(Object? node, List<String> rest) {
      if (rest.isEmpty) {
        return node != null;
      }
      if (node is! Map) {
        return false;
      }
      for (var i = 1; i <= rest.length; i++) {
        final name = rest.take(i).join('.');
        if (node.containsKey(name) && sets(node[name], rest.sublist(i))) {
          return true;
        }
      }
      return false;
    }

    for (final MapEntry(key: path, value: text) in files.entries) {
      final name = p.basename(path);
      if (!RegExp(r'^application-[^.]+\.(ya?ml|properties)$').hasMatch(name)) {
        continue;
      }
      try {
        final set = name.endsWith('.properties')
            ? LineSplitter.split(text).any(
                (line) => RegExp(
                  '^\\s*${RegExp.escape(key)}\\s*[=:]',
                ).hasMatch(line),
              )
            : loadYamlDocuments(text).any((doc) => sets(doc.contents, parts));
        if (set) {
          return name;
        }
      } on Object {
        continue; // the configuration's own reading reports a broken file
      }
    }
    return null;
  }

  // `AutoConfigurationModule.build` against the application's property.
  static _BuildChoice _buildChoice(
    ConstantReader? build,
    String? Function(String key) property,
    String module, {
    String? Function(String key)? profiled,
  }) {
    if (build == null || build.isNull) {
      return _BuildChoice.always;
    }
    final key = build.read('property').stringValue;
    final String? value;
    try {
      value = property(key);
    } on Object catch (error) {
      throw InvalidGenerationSourceError(
        '$module: the build reads $key to decide whether the module is '
        'built, and could not: $error',
        todo:
            'Give $key a value the build can read in application.yml or '
            'application.properties, or a placeholder with a default '
            r'(${FLAG:true}): '
            'environment variables and --dart-define values do not exist '
            'at build time.',
      );
    }
    switch (value) {
      case 'true':
        return _BuildChoice.always;
      case 'false':
        return _BuildChoice.never;
      case null || '':
        if (profiled?.call(key) case final file?) {
          log.warning(
            '$module: $key is set only in $file, which the build does not '
            'read: it decides by application.yml or application.properties '
            'without a profile. The module is built as when it is not set.',
          );
        }
        final missing = build.read('whenMissing').objectValue;
        final name = missing.variable?.name ?? 'notInRelease';
        return switch (name) {
          'always' => _BuildChoice.always,
          'never' => _BuildChoice.never,
          _ => _BuildChoice.notInRelease,
        };
      default:
        log.warning(
          "$module: $key is '$value', not true or false; the module is "
          'built as when it is not set.',
        );
        return _buildChoice(build, (_) => null, module);
    }
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
    final reachable = await _reachablePackages(buildStep);
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
              (asset) =>
                  !asset.path.endsWith('.spring.dart') && !own.contains(asset),
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
    for (final asset in assets) {
      if (await resolver.isLibrary(asset)) {
        final library = await resolver.libraryFor(asset);
        await scanner.resolveBeanMethods(
          library,
          (fragment) => resolver.astNodeFor(fragment, resolve: true),
        );
        await scanner.resolveFieldInitializers(
          library,
          (fragment) => resolver.astNodeFor(fragment, resolve: true),
        );
        await scanner.resolveMapperCalls(
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
  });

  @override
  Map<String, List<String>> get buildExtensions => const {
    '^lib/{{}}.dart': ['lib/spring_gen/{{}}.spring.dart'],
  };
}

// Where the build puts an auto-configuration module.
enum _BuildChoice { always, notInRelease, never }

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
  final _seen = <Element, Set<String>>{};

  Future<Set<String>> of(Element element) async {
    if (_seen[element] case final found?) {
      return found; // done, or being walked (a cycle)
    }
    final found = _seen[element] = <String>{};
    final fragment = switch (element) {
      GetterElement(isOriginDeclaration: true) => element.firstFragment,
      GetterElement(:final variable) => variable.firstFragment,
      TopLevelVariableElement() => element.firstFragment,
      _ => null,
    };
    if (fragment == null || element.library?.uri.scheme != 'package') {
      return found;
    }
    final node = await resolver.astNodeFor(fragment, resolve: true);
    if (node == null) {
      return found;
    }
    final visitor = _ModuleReferences();
    node.accept(visitor);
    found.addAll([for (final proxy in visitor.found) proxy.source]);
    for (final read in visitor.reads) {
      found.addAll(await of(read));
    }
    return found;
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
