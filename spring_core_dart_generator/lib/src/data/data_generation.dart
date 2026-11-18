// spring_boot_starter_data's part of the module build: its entities and
// repositories, the checks of their `@Query` texts and of what they ask of
// their store, the drivers' glue, and its share of the metadata (a part of
// its own, DataMetadataGeneration below).
import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:spring_core_dart_generator/src/core/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/spring_builder.dart';
import 'package:spring_core_dart_generator/src/core/spring_metadata.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';
import 'package:spring_core_dart_generator/src/data/data_emitter.dart';
import 'package:spring_core_dart_generator/src/data/data_model.dart';
import 'package:spring_core_dart_generator/src/data/data_scanner.dart';
import 'package:spring_core_dart_generator/src/data/data_stores.dart';
import 'package:spring_core_dart_generator/src/data/driver_glue.dart';

/// The part of `spring_boot_starter_data` in the module build.
///
/// - Before the scan it reads the stores the package's dependencies
///   declare ([DataStoreBuild]) and the glue of the drivers it lists
///   ([driverGlueFor]).
/// - It describes each `@Table` class for the data layer, before the core
///   decides which bean the class is, and makes the bean of each
///   repository (an interface extending `DataRepository`) itself: a
///   method that is no CRUD method, `@Query`, `@Procedure` or valid
///   derived query fails the build, as what the store of the repository
///   cannot do.
/// - Once the module is scanned it checks the texts of the `@Query`
///   methods against the entities and the schema the resources say, and
///   the `@Transactional` beans against the default store.
/// - The module gets the class of each repository, its `EntityIntrospections`
///   bean and the drivers' beans, and the drivers' code after its getter.
///
/// Its share of `spring_metadata.json` is [DataMetadataGeneration]'s.
///
/// ```dart
/// // Output (in the module):
/// class _$BookRepositoryImpl extends SimpleRepository<Book, int>
///     implements BookRepository { ... }
///
/// BeanModule get $application => BeanModule(r'application', [
///   BeanDefinition<BookRepository>(
///     name: r'bookRepository',
///     create: (r) => _$BookRepositoryImpl.$create(r), ...),
///   BeanDefinition<EntityIntrospections>(
///     name: r'entityIntrospections#application', ...),
/// ]);
/// ```
///
/// Spring (Java): Spring Data's `RepositoryRegistrationAotProcessor`, and
/// the repository scan of `@EnableJdbcRepositories`.
final class DataGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const DataGeneration();

  @override
  String get package => 'spring_boot_starter_data';

  @override
  Future<void> prepareModule(ModuleBuild build) async {
    final data = DataModuleModel.of(build.module);
    final buildStep = build.buildStep;
    data
      ..stores = await DataStoreBuild.read(
        buildStep,
        reachablePackages: () => SpringBuilder.reachablePackages(buildStep),
        configuration: build.resources,
      )
      ..glue = await driverGlueFor(
        buildStep,
        build.dependencies,
        reachable: build.importablePackages,
      );
  }

  @override
  void describeClass(ClassElement element, ModuleScan scan) =>
      DataScanner(scan).describeClass(element);

  @override
  bool claimClass(ClassElement element, ModuleScan scan) =>
      DataScanner(scan).claimClass(element);

  @override
  Iterable<ClassElement> initialValueClasses(
    ClassElement element,
    ModuleScan scan,
  ) => DataScanner(scan).initialValueClasses(element);

  @override
  Future<void> checkModule(ModuleBuild build) async =>
      DataScanner(build).checkModule(build.resources);

  @override
  Iterable<Spec> classes(ModuleEmission emission) =>
      _emitter(emission).repositoryClasses();

  @override
  Expression? beanCreation(BeanModel bean, ModuleEmission emission) =>
      switch (bean.creation) {
        RepositoryCreation(:final model) => _emitter(
          emission,
        ).repositoryCreation(model),
        _ => null,
      };

  @override
  Iterable<Expression> beanDefinitions(ModuleEmission emission) =>
      _emitter(emission).beanDefinitions();

  // The code the drivers' beans are made by.
  @override
  Iterable<Spec> leadingDeclarations(ModuleEmission emission) => [
    for (final glue in DataModuleModel.of(emission.module).glue) glue.code,
  ];

  static DataEmitter _emitter(ModuleEmission emission) =>
      DataEmitter(emission, DataModuleModel.of(emission.module));
}

/// The share of `spring_boot_starter_data` in `spring_metadata.json`: the
/// `entities` (the `@Table` classes with their tables, columns and
/// relations) and the `repositories` with the methods the build writes,
/// read from the module [DataGeneration] scanned, so the editor and the
/// build agree. A part of its own, as its entries come right after the
/// core's, before those of the Flutter starter's parts (see
/// `lib/src/starters.dart`).
final class DataMetadataGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const DataMetadataGeneration();

  // The keys of an entity and of a repository, in their order.
  static const _entityKeys = [
    'class',
    'table',
    'source',
    'line',
    'id',
    'properties',
  ];
  static const _repositoryKeys = [
    'name',
    'entity',
    'id',
    'source',
    'line',
    'methods',
  ];

  @override
  String get package => 'spring_boot_starter_data';

  @override
  Future<Map<String, Object?>> metadata(MetadataBuild build) async {
    final data = DataMetadata(build.module);
    final entities = data.entityMetadata();
    final repositories = data.repositoryMetadata();
    return {
      // Only for a package with a data layer, so other files stay as they
      // are.
      if (entities.isNotEmpty)
        'entities': [
          for (final entity in SpringMetadata.byName(entities, 'class'))
            SpringMetadata.ordered(entity, _entityKeys, nullable: true),
        ],
      if (repositories.isNotEmpty)
        'repositories': [
          for (final repository in SpringMetadata.byName(repositories, 'name'))
            SpringMetadata.ordered(repository, _repositoryKeys, nullable: true),
        ],
    };
  }
}
