import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart' hide Resource;
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/metadata_beans.dart';
import 'package:spring_core_dart_generator/src/metadata_properties.dart';
import 'package:spring_core_dart_generator/src/metadata_read_keys.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_metadata.dart';

/// Writes `lib/spring_gen/spring_metadata.json`, what editors and tools
/// need to know about the Spring side of a package: its configuration
/// properties, beans, profiles, value hints and (for the Flutter starter)
/// the theme. See `roadmap/spring_metadata.md` for the format.
///
/// It runs for a package with Spring code: a `@ComponentScan`,
/// `@SpringBootApplication`, `@AutoConfigurationModule`,
/// `@ConfigurationProperties` or hand-written `BeanDefinition`s in `lib/` or
/// `bin/`. Everything is derived from the code: nothing is written by hand.
///
/// Like the main builder it keeps an existing file while the sources have
/// errors, so `build_runner watch` does not delete it on every keystroke.
///
/// Spring Boot: `spring-boot-configuration-processor` writes
/// `META-INF/spring-configuration-metadata.json`.
final class SpringMetadataBuilder implements Builder {
  /// Creates the builder; tests pass [packageDirectories] of their own.
  SpringMetadataBuilder({PackageDirectories? packageDirectories})
    : _directories = packageDirectories ?? PackageDirectories.current;

  final PackageDirectories _directories;

  /// The generated file.
  static const outputPath = 'lib/spring_gen/spring_metadata.json';

  /// Where the Flutter starter keeps the theme's schema.
  static const themePath = 'tool/theme_metadata.json';

  static const _markers = [
    'ComponentScan',
    'SpringBootApplication',
    'AutoConfigurationModule',
    'ConfigurationProperties',
    'BeanDefinition<',
    '@Component',
    '@Service',
    '@Configuration',
    '@Bean',
  ];

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': [outputPath],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final output = AssetId(package, outputPath);
    final assets = await _sources(buildStep);
    final texts = {
      for (final asset in assets) asset: await buildStep.readAsString(asset),
    };
    if (!texts.values.any((t) => _markers.any(t.contains))) {
      return;
    }
    try {
      final json = await _generate(buildStep, package, assets);
      await buildStep.writeAsString(output, json);
    } on Object catch (error, stackTrace) {
      final existing = await _directories.read(output);
      if (existing == null) {
        rethrow;
      }
      log.warning(
        '$outputPath is kept unchanged until this error is fixed:',
        error,
        stackTrace,
      );
      await buildStep.writeAsString(output, existing);
    }
  }

  // The libraries of `lib/` and `bin/`, generated files left out.
  Future<List<AssetId>> _sources(BuildStep buildStep) async {
    final assets =
        <AssetId>{
              for (final glob in ['lib/**.dart', 'bin/**.dart'])
                ...await buildStep.findAssets(Glob(glob)).toList(),
            }
            .where(
              (a) =>
                  a.package == buildStep.inputId.package &&
                  !a.path.endsWith('.spring.dart') &&
                  !p.url.split(a.path).contains('spring_gen'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return assets;
  }

  Future<String> _generate(
    BuildStep buildStep,
    String package,
    List<AssetId> assets,
  ) async {
    final resolver = buildStep.resolver;
    final module = ModuleModel();
    final scanner = BeanScanner(module);
    final properties = PropertyScanner(
      (fragment) => resolver.astNodeFor(fragment),
    );
    final readKeys = ReadKeyScanner();
    final profiles = <String>{};
    final defined = <Map<String, Object?>>[];
    for (final asset in assets) {
      if (!await resolver.isLibrary(asset)) {
        continue;
      }
      final library = await resolver.libraryFor(asset);
      await scanner.resolveBeanMethods(
        library,
        (fragment) => resolver.astNodeFor(fragment, resolve: true),
      );
      scanner.scanLibrary(library);
      await properties.scanLibrary(library);
      readKeys.scanLibrary(library);
      if ((await buildStep.readAsString(asset)).contains('BeanDefinition<')) {
        final unit = await resolver.astNodeFor(
          library.firstFragment,
          resolve: true,
        );
        if (unit is CompilationUnit) {
          final reader = BeanDefinitionReader(profiles);
          unit.accept(reader);
          defined.addAll(reader.beans);
        }
      }
    }
    for (final error in scanner.errors) {
      log.fine('Metadata scan: ${error.message}');
    }
    profiles.addAll(await _profileFiles(buildStep));
    return SpringMetadata.encode(
      SpringMetadata.assemble(
        package: package,
        // Keys bound by a class first: they have the better description.
        properties: [...properties.properties, ...readKeys.properties],
        hints: properties.hints.values.toList(),
        beans: [
          for (final bean in module.beans)
            MetadataBeans.fromModel(bean, profiles),
          ...defined,
        ],
        profiles: profiles,
        entities: scanner.entityMetadata(),
        repositories: scanner.repositoryMetadata(),
        theme: package == 'spring_boot_starter_flutter'
            ? await _theme(buildStep)
            : null,
      ),
    );
  }

  // `application-dev.yml` names the profile `dev`.
  Future<Set<String>> _profileFiles(BuildStep buildStep) async {
    final pattern = RegExp(r'^application-(.+)\.(ya?ml|properties)$');
    return {
      await for (final asset in buildStep.findAssets(
        Glob('lib/resources/**'),
      ))
        if (asset.package == buildStep.inputId.package)
          if (pattern.firstMatch(p.url.basename(asset.path)) case final m?)
            m[1]!,
    };
  }

  // The `{types, properties}` of the theme schema, read when the build
  // runs (the file is the source of the theme docs too).
  Future<Map<String, Object?>?> _theme(BuildStep buildStep) async {
    final json = await _readJson(buildStep, themePath);
    if (json == null || json['types'] == null || json['properties'] == null) {
      log.warning(
        '$themePath has no `types` and `properties`: the theme is left out '
        'of $outputPath.',
      );
      return null;
    }
    return {'types': json['types'], 'properties': json['properties']};
  }

  // A JSON object file of the package: from the build when it sees it,
  // else from disk (the root files are not always build sources).
  Future<Map<String, Object?>?> _readJson(
    BuildStep buildStep,
    String path,
  ) async {
    final id = AssetId(buildStep.inputId.package, path);
    final text = await buildStep.canRead(id)
        ? await buildStep.readAsString(id)
        : await _directories.read(id);
    if (text == null) {
      return null;
    }
    final json = jsonDecode(text);
    return json is Map
        ? {for (final e in json.entries) '${e.key}': e.value}
        : null;
  }
}
