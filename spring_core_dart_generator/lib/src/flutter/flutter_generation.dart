// spring_boot_starter_flutter's part of the module build: its widgets,
// `@BuildContextAccess` beans and `@ThemeLoaderKind` classes, the
// `@Value('asset:...')` check, the typed keys as parts of the module's
// library, and its metadata. Its `@ChangeNotifierComponent` beans are a
// part of their own (change_notifier_generation.dart).
import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/metadata_locations.dart';
import 'package:spring_core_dart_generator/src/core/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/package_directory.dart';
import 'package:spring_core_dart_generator/src/core/spring_builder.dart';
import 'package:spring_core_dart_generator/src/core/spring_metadata.dart';
import 'package:spring_core_dart_generator/src/core/spring_metadata_builder.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';
import 'package:spring_core_dart_generator/src/flutter/asset_check.dart';
import 'package:spring_core_dart_generator/src/flutter/flutter_emitter.dart';
import 'package:spring_core_dart_generator/src/flutter/flutter_scanning.dart';
import 'package:spring_core_dart_generator/src/flutter/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/flutter/theme_references.dart';
import 'package:spring_core_dart_generator/src/flutter/typed_theme_keys.dart';

/// The part of `spring_boot_starter_flutter` in the module build.
///
/// - It scans the Spring widgets (`SpringStatelessWidget<R>`,
///   `SpringState<W, R>`) and `@ThemeLoaderKind` classes of each library.
/// - Once the module is scanned it reads the `@BuildContextAccess` beans,
///   checks the `@Value('asset:...')` assets against `pubspec.yaml` and
///   the props classes of the loader kinds.
/// - The typed keys (`theme.spring.keys.dart`,
///   `messages.spring.keys.dart`) are parts of the library the keys
///   builder chooses.
/// - The module gets the `SpringWidgetBindings` bean, registers its loader
///   kinds before it is built, and is followed by
///   `extension SpringBeans on BuildContext`.
/// - `spring_metadata.json` gets the `loaderKinds` of the package and,
///   for the starter itself, the theme's schema.
///
/// ```dart
/// // Output (in the module):
/// BeanModule get $application {
///   ThemeLoaderKinds.register<DoorsLoaderProps>('doors', ...);
///   return BeanModule(r'application', [
///     ...,
///     BeanDefinition<SpringWidgetBindings>(
///         name: r'flutterSpringWidgetBindings#application', ...),
///   ]);
/// }
///
/// extension SpringBeans on BuildContext {
///   Basket get basket => SpringScope.beanOf<Basket>(this, ...);
/// }
/// ```
final class FlutterGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const FlutterGeneration();

  /// Where the Flutter starter keeps the theme's schema, which its
  /// `spring_metadata.json` embeds.
  static const themePath = 'tool/theme_metadata.json';

  // The keys of a loader kind in spring_metadata.json, in their order.
  static const _loaderKindKeys = ['name', 'class', 'source', 'line', 'props'];

  @override
  String get package => 'spring_boot_starter_flutter';

  @override
  List<String> get markers => const ['@ThemeLoaderKind'];

  @override
  void scanClass(ClassElement element, ModuleScan scan) {
    final flutter = FlutterModuleModel.of(scan.module);
    // Widgets whose bean records the module fills.
    scan
      ..collectErrors(() => scanSpringWidget(element, flutter))
      ..collectErrors(() => scanThemeLoaderKind(element, flutter));
  }

  @override
  Future<void> checkModule(ModuleBuild build) async {
    scanBuildContextAccess(
      build.module,
      FlutterModuleModel.of(build.module),
      build.collectErrors,
    );
    await checkAssetValues(
      build.buildStep,
      build.module,
      build.collectErrors,
      packageDirectories: build.packageDirectories,
    );
    await _checkLoaderKinds(build);
  }

  /// Checks that the props class of every `@ThemeLoaderKind` of the module
  /// that takes one (`DoorsLoaderProps`) is a class the module can name:
  /// the keys builder writes it into `theme.spring.keys.dart`, a part of
  /// the output of [SpringKeyFiles.parentLibrary] only, for the kinds
  /// [SpringKeyFiles.loaderKinds] finds in the source text. A kind in
  /// another module (a nested `@ComponentScan`, a `bin/` application), or
  /// one the text does not show (a name that is no string literal), is a
  /// build error instead of generated code that does not compile.
  static Future<void> _checkLoaderKinds(ModuleBuild build) async {
    final typed = [
      for (final kind in FlutterModuleModel.of(build.module).loaderKinds)
        if (kind.typedProps) kind,
    ];
    if (typed.isEmpty) {
      return;
    }
    final buildStep = build.buildStep;
    final input = buildStep.inputId;
    final choice = SpringKeyFiles.parentLibrary(
      await SpringKeyFiles.scanLibraries(buildStep),
    );
    final known = (await SpringKeyFiles.loaderKinds(buildStep)).own;
    for (final kind in typed) {
      final props = LoaderKinds.propsClass(kind.name);
      final what =
          "@ThemeLoaderKind('${kind.name}') on ${kind.element.name ?? '?'}";
      build.collectErrors(() {
        if (choice.parent != input) {
          final where = switch (choice.parent) {
            final parent? =>
              'a part of the generated library of ${parent.path}, which '
                  'the module of ${input.path} cannot use: move the class '
                  'into the module of ${parent.path}',
            null =>
              'a part of the generated library of the '
                  "package's @SpringBootApplication in lib/ (else of its "
                  'outermost @ComponentScan there), and there is none '
                  '(${choice.error ?? 'no library of lib/ has either'}): '
                  'declare one over the class',
          };
          throw InvalidGenerationSource(
            '$what: its props class $props is written into '
            '${SpringKeyFiles.themeFile}, $where, or take LoaderValues.',
            element: kind.element,
          );
        }
        if (!known.containsKey(canonicalName(kind.name))) {
          throw InvalidGenerationSource(
            '$what: its props class $props is written from the annotation '
            'as the source has it, before anything is resolved, and no '
            'class there has this kind: write the name as a string literal '
            "(@ThemeLoaderKind('${kind.name}')), or take LoaderValues.",
            element: kind.element,
          );
        }
      });
    }
  }

  /// The generated key files (`theme.spring.keys.dart`,
  /// `messages.spring.keys.dart`) that are `part of` the output of the
  /// input: when the package uses the Flutter starter, the input is the
  /// parent library ([SpringKeyFiles.parentLibrary]), and the keys builder
  /// writes them (it decides with the same [SpringKeyFiles.generate]).
  @override
  Future<ModuleParts> moduleParts(BuildStep buildStep) async {
    if (!await SpringKeyFiles.usesFlutterStarter(buildStep)) {
      return ModuleParts.none;
    }
    final scans = await SpringKeyFiles.scanLibraries(buildStep);
    // The same choice as the keys builder. That builder may be disabled,
    // and a part cannot be probed with canRead: the keys builder writes to
    // source in its own phase, so the file is not readable from this one.
    // The parts are therefore decided by the shared computation.
    if (SpringKeyFiles.parentLibrary(scans).parent != buildStep.inputId) {
      return ModuleParts.none;
    }
    // Read as the keys builder reads them, whatever the entry point.
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final parts = SpringKeyFiles.generate(
      await SpringKeyFiles.withImports(buildStep, {
        for (final MapEntry(:key, value: (:text, base64: _))
            in resources.entries)
          key: ?text,
      }),
      KeysDiagnostics(),
      loaderKinds: await SpringKeyFiles.loaderKinds(buildStep),
    );
    final parent = SpringKeyFiles.parentOf(buildStep.inputId);
    final paths = [
      if (parts.theme != null)
        SpringKeyFiles.partPath(parent, SpringKeyFiles.themeFile),
      if (parts.messages != null)
        SpringKeyFiles.partPath(parent, SpringKeyFiles.messagesFile),
    ];
    return paths.isEmpty
        ? ModuleParts.none
        : ModuleParts(paths, SpringKeyFiles.imports);
  }

  @override
  Iterable<Expression> beanDefinitions(ModuleEmission emission) {
    final flutter = FlutterModuleModel.of(emission.module);
    return [
      if (flutter.springWidgets.isNotEmpty)
        FlutterEmitter(emission, flutter).springWidgetBindings(),
    ];
  }

  // The kinds are known before the themes are read.
  @override
  Iterable<Code> moduleStatements(ModuleEmission emission) => [
    for (final registration in FlutterEmitter(
      emission,
      FlutterModuleModel.of(emission.module),
    ).loaderKindRegistrations())
      registration.statement,
  ];

  @override
  Iterable<Spec> declarations(ModuleEmission emission) {
    final flutter = FlutterModuleModel.of(emission.module);
    return [
      if (flutter.buildContextAccess.isNotEmpty)
        FlutterEmitter(emission, flutter).contextAccessExtension(),
    ];
  }

  @override
  Future<Map<String, Object?>> metadata(MetadataBuild build) async {
    final kinds = await _loaderKinds(build.buildStep, [
      for (final MapEntry(key: asset, value: text) in build.libraries.entries)
        for (final kind in SpringKeyFiles.scanLoaderKinds(text))
          {
            'name': kind.name,
            'class': kind.className,
            'source': sourceOfUri(asset.uri),
            'line': kind.line,
          },
    ]);
    final theme = build.buildStep.inputId.package == package
        ? await _theme(build.buildStep, build.packageDirectories)
        : null;
    return {
      // `@ThemeLoaderKind` classes of the package.
      if (kinds.isNotEmpty)
        'loaderKinds': [
          for (final kind in SpringMetadata.byName(kinds, 'name'))
            SpringMetadata.ordered(kind, _loaderKindKeys, nullable: true),
        ],
      'theme': ?theme,
    };
  }

  // The keys each kind takes, as far as the package's own themes show them:
  // the top-level keys of its loaders, except `kind`, `phases` and `web`.
  static Future<List<Map<String, Object?>>> _loaderKinds(
    BuildStep buildStep,
    List<Map<String, Object?>> kinds,
  ) async {
    if (kinds.isEmpty) {
      return kinds;
    }
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final diagnostics = KeysDiagnostics();
    final set = ThemeSet.read(
      SpringKeyFiles.readProperties({
        for (final MapEntry(:key, value: (:text, base64: _))
            in resources.entries)
          key: ?text,
      }, diagnostics),
      diagnostics,
    );
    final keys = <String, Set<String>>{};
    if (set != null) {
      for (final name in set.names) {
        final loaders = set.scope(name).node(const ['loaders']);
        for (final loader in loaders?.children.values ?? const <ThemeNode>[]) {
          final kind = loader.children['kind']?.entry?.value.trim();
          if (kind == null) {
            continue;
          }
          keys.putIfAbsent(canonicalName(kind), () => {}).addAll([
            for (final MapEntry(:key, :value) in loader.children.entries)
              if (!loaderOwnKeys.contains(key)) value.spelling,
          ]);
        }
      }
    }
    return [
      for (final kind in kinds)
        {
          ...kind,
          if (keys['${kind['name']}'.toLowerCase().replaceAll(
                RegExp('[-_]'),
                '',
              )]
              case final found?)
            'props': found.toList()..sort(),
        },
    ];
  }

  // The `{types, properties}` of the theme schema, read when the build
  // runs (the file is the source of the theme docs too).
  static Future<Map<String, Object?>?> _theme(
    BuildStep buildStep,
    PackageDirectories directories,
  ) async {
    final json = await _readJson(buildStep, directories, themePath);
    if (json == null || json['types'] == null || json['properties'] == null) {
      log.warning(
        '$themePath has no `types` and `properties`: the theme is left out '
        'of ${SpringMetadataBuilder.outputPath}.',
      );
      return null;
    }
    return {'types': json['types'], 'properties': json['properties']};
  }

  // A JSON object file of the package: from the build when it sees it,
  // else from disk (the root files are not always build sources).
  static Future<Map<String, Object?>?> _readJson(
    BuildStep buildStep,
    PackageDirectories directories,
    String path,
  ) async {
    final id = AssetId(buildStep.inputId.package, path);
    final text = await buildStep.canRead(id)
        ? await buildStep.readAsString(id)
        : await directories.read(id);
    if (text == null) {
      return null;
    }
    final json = jsonDecode(text);
    return json is Map
        ? {for (final e in json.entries) '${e.key}': e.value}
        : null;
  }
}
