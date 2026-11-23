// Where spring_boot_starter_data's annotations may go: `@Transactional`
// is advice; the paging defaults are handler parameters; the query
// annotations go on a repository's methods, the store annotations on a
// repository; the mapping annotations on the stored properties of an
// entity. Matched by URL (the generator does not depend on the starter).
import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/data/data_model.dart';
import 'package:spring_core_dart_generator/src/data/data_scanner.dart';

const _annotations = 'package:spring_boot_starter_data/src/annotations.dart';

TypeChecker _data(String name) => TypeChecker.fromUrl('$_annotations#$name');

/// The placements of the data starter's annotations.
final List<AnnotationPlacement> dataPlacements = [
  const AdvicePlacement([
    TypeChecker.fromUrl(
      'package:spring_boot_starter_data/src/transaction/'
      'transaction_definition.dart#Transactional',
    ),
  ], effect: 'the transaction would not start'),
  const ParameterPlacement(
    [
      TypeChecker.fromUrl(
        'package:spring_boot_starter_data/src/web/web_paging.dart'
        '#PageableDefault',
      ),
      TypeChecker.fromUrl(
        'package:spring_boot_starter_data/src/web/web_paging.dart#SortDefault',
      ),
    ],
    methodNoun: 'a handler method (@GetMapping, @PostMapping...)',
  ),
  _RepositoryMethodPlacement([
    _data('Query'),
    _data('Modifying'),
    _data('Procedure'),
    _data('Lock'),
  ]),
  _RepositoryClassPlacement([_data('UseStore'), _data('UseDataSource')]),
  _EntityPropertyPlacement([
    _data('Id'),
    _data('Column'),
    _data('Transient'),
    _data('Json'),
    _data('Version'),
    _data('CreatedDate'),
    _data('LastModifiedDate'),
    _data('CreatedBy'),
    _data('LastModifiedBy'),
    _data('MappedCollection'),
    _data('Reference'),
    _data('Unique'),
    _data('OnDelete'),
  ]),
  ClassPlacement([_data('Table')]),
  _UniqueConstraintPlacement([_data('UniqueConstraint')]),
  _EnableAuditingPlacement([
    const TypeChecker.fromUrl(
      'package:spring_boot_starter_data/src/mapping/auditing.dart'
      '#EnableDataAuditing',
    ),
  ]),
  _TestOnlyPlacement([
    for (final name in const ['DataTest', 'Rollback', 'Commit'])
      TypeChecker.fromUrl(
        'package:spring_boot_starter_data/src/testing/data_test.dart#$name',
      ),
  ]),
  _DataStoreDeclarationPlacement(),
];

// `@EnableDataAuditing`: read from the annotations of a bean.
final class _EnableAuditingPlacement extends ClassPlacement {
  _EnableAuditingPlacement(super.checkers);

  @override
  PlacementOwner? owner(AnnotationSite site) => PlacementOwner.beanItself;

  @override
  String ownerProblem(AnnotationSite site) =>
      '@EnableDataAuditing on ${site.subject}: it is read from the '
      'annotations of a bean, and ${site.element.displayName} is none, so '
      'auditing would stay off. Put it on a @Configuration class.';
}

// `@DataTest`, `@Rollback`, `@Commit`: read by the test builder, on the
// classes and methods of test/; in a scanned library nothing reads them.
final class _TestOnlyPlacement extends CheckedPlacement {
  _TestOnlyPlacement(super.checkers);

  @override
  String? problem(AnnotationSite site) =>
      '${site.name} on ${site.subject}: it belongs on a @DataTest class or '
      'its test methods, under test/; in the application it would do '
      'nothing.';
}

// `@DataStoreDeclaration`: a constant top-level variable.
final class _DataStoreDeclarationPlacement extends CheckedPlacement {
  _DataStoreDeclarationPlacement()
    : super(const [
        TypeChecker.fromUrl(
          'package:spring_boot_starter_data/src/store/data_store_descriptor.dart'
          '#DataStoreDeclaration',
        ),
      ]);

  @override
  String? problem(AnnotationSite site) => switch (site.element) {
    TopLevelVariableElement(isConst: true) => null,
    _ =>
      '@DataStoreDeclaration on ${site.subject}: it goes on a constant '
          'top-level DataStoreDescriptor (`const`), which the build reads.',
  };
}

bool _isRepository(ClassElement element, ModuleModel module) =>
    DataScanner.isRepository(element);

bool _isEntity(ClassElement element, ModuleModel module) =>
    DataScanner.isEntity(element) ||
    DataModuleModel.of(module).entityClasses.contains(element);

const _interfaces = 'an interface extending CrudRepository or DataRepository';

const _repository = 'repository ($_interfaces)';

// `@Query`, `@Modifying`, `@Procedure`, `@Lock`: an abstract method of a
// repository, whose implementation the build writes.
final class _RepositoryMethodPlacement extends MethodPlacement {
  _RepositoryMethodPlacement(super.checkers)
    : super(
        does: 'the build writes the query',
        methodOwner: const PredicateOwner(_isRepository, abstractToo: true),
        ownerNoun: _repository,
      );

  @override
  String ownerProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}: queries are run by repositories, and '
      '${site.ownerName} is no repository ($_interfaces), so it would do '
      'nothing. Move the method into a repository.';
}

// `@UseStore`, `@UseDataSource`: a repository.
final class _RepositoryClassPlacement extends ClassPlacement {
  _RepositoryClassPlacement(super.checkers);

  @override
  PlacementOwner? owner(AnnotationSite site) =>
      const PredicateOwner(_isRepository, abstractToo: true);

  @override
  String ownerProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}: it chooses the store of a '
      'repository, and ${site.element.displayName} is no repository '
      '($_interfaces), so it would do nothing. Put it on the repository.';
}

// The mapping annotations: a stored property of an entity (a `@Table`
// class, or a class a `@Query` method reads), which is a public instance
// field, or a getter with a setter.
final class _EntityPropertyPlacement extends CheckedPlacement {
  _EntityPropertyPlacement(super.checkers);

  @override
  String? problem(AnnotationSite site) {
    final what = '${site.name} on ${site.subject}';
    const stored =
        'the stored properties of an entity are its public instance fields '
        '(or a getter with a setter)';
    switch (site.kind) {
      case PlaceKind.field || PlaceKind.getter || PlaceKind.setter
          when site.isPrivate || site.isStatic:
        return '$what: $stored; a ${site.isPrivate ? 'private' : 'static'} '
            'member is not mapped, so it would do nothing. Make it a public '
            'instance field.';
      case PlaceKind.field || PlaceKind.setter:
        return null;
      case PlaceKind.getter:
        final owner = site.owner;
        final hasSetter =
            owner is InterfaceElement &&
            owner.thisType.lookUpSetter(
                  site.element.displayName,
                  owner.library,
                ) !=
                null;
        return hasSetter
            ? null
            : '$what: $stored; a getter without a setter is computed, not '
                  'stored, so it would do nothing. Annotate a field.';
      case PlaceKind.parameter:
        return null;
      case PlaceKind.classDeclaration ||
          PlaceKind.mixin ||
          PlaceKind.enumDeclaration ||
          PlaceKind.extension ||
          PlaceKind.extensionType ||
          PlaceKind.topLevel ||
          PlaceKind.foreignMember ||
          PlaceKind.constructor ||
          PlaceKind.method ||
          PlaceKind.operator ||
          PlaceKind.enumValue ||
          PlaceKind.typedefDeclaration ||
          PlaceKind.typeParameter ||
          PlaceKind.library:
        return '$what: $stored; here it would do nothing.';
    }
  }

  @override
  PlacementOwner? owner(AnnotationSite site) =>
      site.kind == PlaceKind.parameter ? null : const PredicateOwner(_isEntity);

  @override
  String ownerProblem(AnnotationSite site) =>
      '${site.name} on ${site.subject}: ${site.ownerName} is no entity (no '
      '@Table, and no @Query method reads it), so it would do nothing. Add '
      '@Table() to ${site.ownerName}, or remove ${site.name}.';
}

// `@UniqueConstraint`: a `@Table` class.
final class _UniqueConstraintPlacement extends ClassPlacement {
  _UniqueConstraintPlacement(super.checkers);

  @override
  PlacementOwner? owner(AnnotationSite site) =>
      AnnotatedOwner([_data('Table')]);

  @override
  String ownerProblem(AnnotationSite site) =>
      '@UniqueConstraint on ${site.subject}: it constrains the table of a '
      '@Table class, and ${site.element.displayName} has no @Table, so it '
      'would do nothing. Add @Table().';
}
