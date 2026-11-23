// What spring_boot_starter_data's part reads of a module: the entities
// (entity_scanning.dart), the repositories (repository_scanning.dart) with
// their `@Query` methods (query_scanning.dart) and what they ask of their
// store (repository_store_scanning.dart), and the data layer's share of
// `spring_metadata.json` (data_metadata.dart). It reads through the
// module's scan, as the core reads its own beans, and keeps what it finds
// in the module's [DataModuleModel].
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/core/metadata/metadata_locations.dart'
    show lineOf, sourceOf;
import 'package:spring_core_dart_generator/src/core/spel/spel_compiler.dart';
import 'package:spring_core_dart_generator/src/data/data_model.dart';
import 'package:spring_core_dart_generator/src/data/data_schema.dart';
import 'package:spring_core_dart_generator/src/data/data_stores.dart';
import 'package:spring_core_dart_generator/src/data/part_tree.dart';
import 'package:spring_core_dart_generator/src/data/part_tree_parser.dart';
import 'package:spring_core_dart_generator/src/data/part_tree_reader.dart';
import 'package:spring_core_dart_generator/src/data/query_expressions.dart';
import 'package:spring_core_dart_generator/src/data/query_text_checker.dart';
import 'package:spring_core_dart_generator/src/data/schema_sources.dart';

part 'data_metadata.dart';
part 'entity_scanning.dart';
part 'query_scanning.dart';
part 'repository_scanning.dart';
part 'repository_store_scanning.dart';

const _annotations = 'package:spring_boot_starter_data/src/annotations.dart';

// spring_boot_starter_data's marker of repositories, matched by URL so the
// generator does not depend on the starter.
const TypeChecker _dataRepository = TypeChecker.fromUrl(
  'package:spring_boot_starter_data/src/repository/repository.dart'
  '#DataRepository',
);

/// Reads spring_boot_starter_data's share of a module through its [scan]:
/// the `@Table` entities and the DTOs of `@Query` methods (each described
/// for the data layer), the repositories (beans whose class the build
/// writes), the checks of their `@Query` texts and of what they ask of
/// their store, and the metadata of both.
///
/// A scanner keeps nothing of its own: what it finds is in the module's
/// [data], so one is made wherever it is needed.
final class DataScanner {
  /// The data scanner of the module [scan] fills.
  DataScanner(this.scan) : data = DataModuleModel.of(scan.module);

  /// The module's scan: the module, the build's errors, and the readings
  /// of a class the core makes for its own beans.
  final ModuleScan scan;

  /// What the data part found in the module so far.
  final DataModuleModel data;

  /// The module being filled.
  ModuleModel get module => scan.module;

  /// Whether [element] is a repository of the data starter: an interface
  /// (or abstract class) extending `DataRepository`, annotated or not
  /// (Spring Data's way). A generic one is a base of others, never a bean
  /// (`@NoRepositoryBean`).
  static bool isRepository(ClassElement element) =>
      element.isAbstract &&
      _dataRepository.isAssignableFrom(element) &&
      !_dataRepository.isExactly(element);

  /// Whether [element] is a `@Table` class: an entity the data layer
  /// stores.
  static bool isEntity(ClassElement element) => _table.hasAnnotationOf(element);

  /// Describes [element] for the data layer when it is a `@Table` class:
  /// the data layer reads and writes it.
  void describeClass(ClassElement element) {
    if (isEntity(element)) {
      scan.collectErrors(() => checkEntityRules(element));
      scanEntity(element);
    }
  }

  /// The rules of the starter's mapping that the build can check, with the
  /// texts of the start's `MappingException`: one `@Id` and one `@Version`
  /// at most, a `@Version` that is an `int` or a `DateTime`, one audit
  /// annotation per property, a `@CreatedDate` or `@LastModifiedDate` that
  /// is a `DateTime`, and a `@UniqueConstraint` over properties the class
  /// has. Checked at start only, an entity no repository uses would never
  /// be.
  void checkEntityRules(ClassElement element) {
    final className = element.name!;
    final fields = scan.describedFields(element).toList();
    bool has(FieldElement field, String name) => [
      field,
      ?field.getter,
    ].any((e) => TypeChecker.fromUrl('$_annotations#$name').hasAnnotationOf(e));
    String typeOf(FieldElement field) =>
        field.type.getDisplayString().replaceFirst(RegExp(r'\?$'), '');
    for (final name in const ['Id', 'Version']) {
      final annotated = [
        for (final field in fields)
          if (has(field, name)) field.name!,
      ];
      if (annotated.length > 1) {
        _fail(
          '$className has more than one @$name: ${annotated.join(', ')}',
          element,
        );
      }
    }
    for (final field in fields) {
      final where = '$className.${field.name}';
      if (has(field, 'Version') &&
          !const {'int', 'DateTime'}.contains(typeOf(field))) {
        _fail(
          '$where: @Version must be an int or a DateTime, not '
          '${typeOf(field)}',
          field,
        );
      }
      final audits = [
        for (final name in const [
          'CreatedDate',
          'LastModifiedDate',
          'CreatedBy',
          'LastModifiedBy',
        ])
          if (has(field, name)) name,
      ];
      if (audits.length > 1) {
        _fail(
          '$where has more than one audit annotation: ${audits.join(', ')}',
          field,
        );
      }
      if (audits case ['CreatedDate' || 'LastModifiedDate'] && final kind
          when typeOf(field) != 'DateTime') {
        _fail(
          '$where: @${kind.single} must be a DateTime, not ${typeOf(field)}',
          field,
        );
      }
    }
    final names = {for (final field in fields) field.name};
    for (final annotation in TypeChecker.fromUrl(
      '$_annotations#UniqueConstraint',
    ).annotationsOf(element)) {
      for (final property
          in annotation.getField('properties')?.toListValue() ?? const []) {
        final name = property.toStringValue();
        if (name != null && !names.contains(name)) {
          _fail(
            '$className: @UniqueConstraint names $name, which is no '
            'property of $className (${names.join(', ')}).',
            element,
          );
        }
      }
    }
  }

  /// Whether [element] is a repository ([isRepository]): its bean is added
  /// with the class the build writes for it, and the DTOs of its `@Query`
  /// methods are described; a generic one is a base of others and adds
  /// nothing.
  bool claimClass(ClassElement element) {
    if (!isRepository(element)) {
      return false;
    }
    if (element.typeParameters.isEmpty) {
      scanRepository(element);
      scanQueries(element);
    }
    return true;
  }

  /// The classes reached from [element] whose fields' initial values the
  /// descriptions read: [element] itself when it is a `@Table` class, the
  /// DTOs of its `@Query` methods when it is a repository.
  Iterable<ClassElement> initialValueClasses(ClassElement element) => [
    if (isEntity(element)) element,
    if (isRepository(element) && element.typeParameters.isEmpty)
      ...projectionsOf(element),
  ];

  /// Checks what needs the whole module, once it is scanned: the texts of
  /// the `@Query` methods (their entities, tables and columns, against the
  /// schema the module's [resources] say), whose problems join those of
  /// their repository; then the `@Transactional` beans against the
  /// application's default store.
  void checkModule(Map<String, String> resources) {
    scan.collectErrors(() => _checkQueries(resources));
    _checkTransactionalBeans();
  }

  // A build error at [element].
  static Never _fail(String message, Element element) =>
      throw InvalidGenerationSource(message, element: element.baseElement);
}
