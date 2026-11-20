import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart' hide Resource;
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/builder/generated_path.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_directory.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/core/metadata/metadata_beans.dart';
import 'package:spring_core_dart_generator/src/core/metadata/metadata_properties.dart';
import 'package:spring_core_dart_generator/src/core/metadata/metadata_read_keys.dart';
import 'package:spring_core_dart_generator/src/core/metadata/spring_metadata.dart';

/// Writes `lib/spring_gen/spring_metadata.json`, what editors and tools
/// need to know about the Spring side of a package: its configuration
/// properties, beans, profiles, value hints and what the packages' parts
/// ([generations]) add (the loader kinds, the routes, the theme). See
/// `roadmap/spring_metadata.md` for the format.
///
/// It runs for a package with Spring code: a `@ComponentScan`,
/// `@SpringBootApplication`, `@AutoConfigurationModule`,
/// `@ConfigurationProperties` or hand-written `BeanDefinition`s in `lib/` or
/// `bin/`, or a marker of a package's part
/// ([PackageGeneration.markers]). Everything is derived from the code:
/// nothing is written by hand.
///
/// Like the main builder it keeps an existing file while the sources have
/// errors, so `build_runner watch` does not delete it on every keystroke.
///
/// Spring Boot: `spring-boot-configuration-processor` writes
/// `META-INF/spring-configuration-metadata.json`.
final class SpringMetadataBuilder implements Builder {
  /// Creates the builder with the packages' parts [generations] (the
  /// builder factory passes the built-in ones); tests pass
  /// [packageDirectories] of their own.
  SpringMetadataBuilder({
    PackageDirectories? packageDirectories,
    this.generations = const [],
  }) : _directories = packageDirectories ?? PackageDirectories.current;

  final PackageDirectories _directories;

  /// The packages' parts: those whose starter the package reaches scan its
  /// libraries along with the core and add their entries to the file.
  final List<PackageGeneration> generations;

  /// The generated file.
  static const outputPath = 'lib/spring_gen/spring_metadata.json';

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
    final markers = [
      ..._markers,
      for (final generation in generations) ...generation.markers,
    ];
    if (!texts.values.any((t) => markers.any(t.contains))) {
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
                  !isGeneratedSource(a.path) &&
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
    final started = startedGenerations(
      generations,
      await SpringBuilder.reachablePackages(buildStep),
    );
    final scanner = BeanScanner(module, generations: started);
    final properties = PropertyScanner(
      (fragment) => resolver.astNodeFor(fragment),
    );
    final readKeys = ReadKeyScanner();
    final profiles = <String>{};
    final defined = <Map<String, Object?>>[];
    final libraries = <AssetId, String>{};
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
      final text = libraries[asset] = await buildStep.readAsString(asset);
      if (text.contains('BeanDefinition<')) {
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
    final metadata = MetadataBuild(
      buildStep: buildStep,
      module: module,
      libraries: libraries,
      packageDirectories: _directories,
    );
    final starters = <String, Object?>{
      for (final generation in started) ...await generation.metadata(metadata),
    };
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
        starters: starters,
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
}
