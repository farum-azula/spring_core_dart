// The model of spring_boot_starter_data's part of a module: the entities,
// the repositories and their methods, what the build knows of the stores,
// and the drivers' glue. The scan fills it (data_scanner.dart), the
// emitter writes it (data_emitter.dart). It lives in the module
// ([ModuleModel.starterModel]), so the core knows none of these types.

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spring_core_dart_generator/src/core/bean_model.dart';
import 'package:spring_core_dart_generator/src/data/data_stores.dart';
import 'package:spring_core_dart_generator/src/data/driver_glue.dart';
import 'package:spring_core_dart_generator/src/data/part_tree.dart';

/// What the part of `spring_boot_starter_data` found in a module and read
/// for it: the entities, what the build knows of the stores, the glue of
/// the drivers, and the repositories whose `@Query` texts are checked once
/// the whole module is scanned. The repositories themselves are beans of
/// the module, made by a [RepositoryCreation].
final class DataModuleModel {
  /// The data model of [module], made the first time it is asked for.
  static DataModuleModel of(ModuleModel module) =>
      module.starterModel(DataModuleModel.new);

  /// The classes the data layer stores or reads: `@Table` classes and the
  /// DTOs of `@Query` methods.
  final entities = <EntityModel>[];

  /// The classes described as entities so far (`@Table` and `@Query`
  /// DTOs), each once.
  final entityClasses = <ClassElement>{};

  /// The stores of spring_boot_starter_data the build knows, and the
  /// application's default store: what a repository (or a
  /// `@Transactional` bean) uses and its store cannot do is a build error.
  /// [DataStoreBuild.none] until the module build reads them, and in the
  /// metadata's scan.
  DataStoreBuild stores = DataStoreBuild.none;

  /// The glue of the drivers (and of the web starter) the module writes:
  /// the code after the module getter, the beans in its list.
  List<DriverGlueOutput> glue = const [];

  /// The repositories whose `@Query` texts wait for the end of the scan.
  final repositoryChecks = <RepositoryCheck>[];
}

/// The texts of one `@Query` method, kept to be checked once the whole
/// application is scanned.
final class QueryText {
  /// The texts of the method [where].
  QueryText(this.where, this.texts, this.names, this.model);

  /// `Repository.method`.
  final String where;

  /// The SQL and the count query, as `(label, text)`.
  final List<(String, String)> texts;

  /// The parameters bound by name.
  final List<String> names;

  /// The descriptor, which learns the expressions and the entities.
  final QueryMethodModel model;
}

/// A repository whose `@Query` texts wait for the end of the scan, with
/// the problems found so far: those of the texts join them in one error.
final class RepositoryCheck {
  /// The check of the repository [element] called [name].
  RepositoryCheck(this.element, this.name, this.problems, this.queries);

  /// The repository interface.
  final ClassElement element;

  /// Its name.
  final String name;

  /// Its problems so far.
  final List<String> problems;

  /// The texts of its `@Query` methods.
  final List<QueryText> queries;
}

/// A bean that is the generated implementation of a data repository of
/// `spring_boot_starter_data`: `_$XImpl.$create(r)`.
///
/// Like `InterfaceProxyCreation`, with no handler: the class extends the
/// starter's `SimpleRepository` for the CRUD methods and writes the rest
/// (derived queries, `@Query`) itself.
///
/// ```dart
/// // Input:
/// abstract interface class BookRepository
///     implements ListCrudRepository<Book, int> { ... }
/// // Output:
/// create: (r) => _$BookRepositoryImpl.$create(r),
/// ```
final class RepositoryCreation extends StarterCreation {
  /// Creates the repository of [model].
  RepositoryCreation(this.model);

  /// The repository and the methods the generated class writes.
  final RepositoryModel model;
}

/// A property of an [EntityModel], written as an `EntityProperty`.
class EntityPropertyModel {
  /// Creates an entity property.
  EntityPropertyModel({
    required this.name,
    required this.type,
    required this.annotations,
    required this.parameter,
    required this.writable,
    this.defaultValue,
  });

  /// The field name.
  final String name;

  /// The declared type, with nullability and type arguments.
  final DartType type;

  /// The user annotations of the field and its getter.
  final List<DartObject> annotations;

  /// Whether the unnamed constructor has a parameter of the same name.
  final bool parameter;

  /// Whether the field has a setter.
  final bool writable;

  /// The constant the property defaults to: the initializer of the field,
  /// else the default of the constructor parameter; `null` when there is
  /// none or the generated code cannot write it (see
  /// [IntrospectedProperty.initialValue] for the shapes).
  final ({Object? value})? defaultValue;
}

/// An argument of the constructor call of an [EntityModel]: the value of
/// the property at [property], by position or by [name].
class EntityArgument {
  /// Creates an argument for the property at index [property].
  const EntityArgument(this.property, {this.name});

  /// The index into [EntityModel.properties].
  final int property;

  /// The parameter name when the parameter is named; `null` when it is
  /// positional.
  final String? name;
}

/// A class the data layer stores or reads (`@Table`, or the DTO of a
/// `@Query`): the properties and constructor call that let the starter
/// read, create and set it without reflection, written as an
/// `EntityIntrospection`. Unlike an [IntrospectionModel], it holds no
/// methods, no JSON hooks and no constructor metadata.
///
/// ```dart
/// // Input:
/// @Table('authors')
/// class Author {
///   Author({this.id, required this.name});
///   @Id() int? id;
///   String name;
/// }
/// // Output (EntityIntrospections.introspections):
/// EntityIntrospection<Author>(
///   r'Author',
///   const [
///     EntityProperty(r'id', ClassType<int>(nullable: true),
///         annotations: [Id()], parameter: true, writable: true),
///     EntityProperty(r'name', ClassType<String>(),
///         parameter: true, writable: true),
///   ],
///   annotations: const [Table(r'authors')],
///   read: (e) => [e.id, e.name],
///   create: (v) => Author(id: v[0] as int?, name: v[1] as String),
///   write: (e, i, v) => switch (i) {
///     0 => e.id = v as int?,
///     1 => e.name = v as String,
///     _ => null,
///   },
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Hibernate builds the metamodel (EntityType) of an @Entity class when
/// // the session factory starts, reading its fields by reflection:
/// metamodel.entity(Author.class).getAttributes();
/// ```
class EntityModel {
  /// Creates an entity model.
  EntityModel({
    required this.element,
    required this.type,
    required this.properties,
    required this.arguments,
    required this.annotations,
  });

  /// The class element, for error messages and imports.
  final ClassElement element;

  /// The class.
  final InterfaceType type;

  /// The public instance fields, the class's own first, then the mixins'
  /// and the superclasses'.
  final List<EntityPropertyModel> properties;

  /// What the unnamed constructor is called with, in parameter order:
  /// the parameters that name a property (an optional one that names none
  /// is left out).
  final List<EntityArgument> arguments;

  /// The user annotations of the class (`@Table`).
  final List<DartObject> annotations;
}

/// A data repository of `spring_boot_starter_data` (an interface extending
/// `DataRepository`), and the class the generator writes for it.
///
/// The class extends the starter's `SimpleRepository` for the CRUD methods
/// and implements the others itself, each a one-line call of
/// `RepositoryOperations`: a derived query as the `PartTree` the build made
/// from the method name, `@Query` as a description of the method. A
/// mistake in a method name is an error of the build.
///
/// ```dart
/// // Input:
/// abstract interface class BookRepository
///     implements ListCrudRepository<Book, int> {
///   Future<List<Book>> findByTitleAndYear(String title, int year);
/// }
/// // Output:
/// class _$BookRepositoryImpl extends SimpleRepository<Book, int>
///     implements BookRepository {
///   _$BookRepositoryImpl(super.operations);
///   static _$BookRepositoryImpl $create(DependencyResolver r) =>
///       _$BookRepositoryImpl(r
///           .dependency<RepositoryFactory>()
///           .operations<Book, int>(r'BookRepository'));
///   static const _findByTitleAndYear = PartTree(r'findByTitleAndYear', [
///     OrPart([Part(r'title'), Part(r'year')]),
///   ]);
///   @override
///   Future<List<Book>> findByTitleAndYear(String title, int year) =>
///       operations.list(_findByTitleAndYear, [title, year]);
/// }
/// ```
///
/// Spring (Java):
///
/// ```java
/// // RepositoryFactorySupport creates a proxy over SimpleJdbcRepository
/// // when the application starts, with a PartTreeJdbcQuery for each
/// // derived method, and checks the method names then.
/// ```
class RepositoryModel {
  /// Creates the model.
  RepositoryModel({
    required this.className,
    required this.type,
    required this.entityType,
    required this.idType,
    required this.annotations,
    required this.methods,
    this.requirements = const [],
  });

  /// The name of the generated class, e.g. `_$BookRepositoryImpl`.
  final String className;

  /// The repository interface.
  final InterfaceType type;

  /// The aggregate the repository stores (`T` of `DataRepository<T, ID>`).
  final InterfaceType entityType;

  /// The type of the aggregate's id (`ID`).
  final InterfaceType idType;

  /// The user annotations on the interface (`@Repository('books')`,
  /// `@UseStore('jdbc')`), which the starter reads to pick the store.
  final List<DartObject> annotations;

  /// The methods the class writes: those `SimpleRepository` does not
  /// implement, in declaration order.
  final List<RepositoryMethodModel> methods;

  /// What the methods (and the interface) need of the store, in
  /// declaration order: `@Lock`, `@Query`, `@Procedure`, a stream of changes,
  /// `@Transactional`. Written as `StoreRequirement`s, which the starter
  /// checks against the store when the repository is created.
  final List<StoreNeed> requirements;
}

/// A method of a [RepositoryModel] that the generated class writes.
sealed class RepositoryMethodModel {
  /// Creates the model.
  RepositoryMethodModel(this.member);

  /// The signature to repeat, with its parameter names and defaults.
  final ProxyMember member;
}

/// A CRUD method the interface redeclares with `@Lock` (`findById`): the
/// override passes the lock to the starter's own implementation.
///
/// ```dart
/// // Input:
/// @Lock(LockMode.pessimisticWrite)
/// Future<Book?> findById(int id);
/// // Output:
/// @override
/// Future<Book?> findById(int id) => operations.findById(id,
///     lock: const Lock(LockMode.pessimisticWrite));
/// ```
class LockedMethodModel extends RepositoryMethodModel {
  /// Creates the model.
  LockedMethodModel(super.member, this.lock);

  /// The `@Lock` annotation.
  final DartObject lock;
}

/// What a `@Modifying` method returns: the number of rows changed
/// (`Future<int>`), whether any changed (`Future<bool>`) or nothing
/// (`Future<void>`); each is the value of `QueryChange` in the starter.
enum ModifyingResult {
  /// `Future<int>`: the rows changed.
  rows,

  /// `Future<bool>`: whether any row changed.
  any,

  /// `Future<void>`.
  nothing,
}

/// One `:#{...}` expression of a `@Query`: the text, and whether the build
/// compiles it to Dart (else the starter interprets the text, which needs
/// the classes of the arguments described for SpEL).
///
/// ```dart
/// // `:#{#book.title}` on `sameTitle(Book book)` is compiled:
/// // (arguments, context) => (arguments[0] as Book).title
/// ```
class QueryExpressionModel {
  /// An expression of [text], [compiled] or not.
  const QueryExpressionModel(this.text, {required this.compiled});

  /// The expression, without `:#{` and `}`.
  final String text;

  /// Whether the build writes the expression as Dart.
  final bool compiled;
}

/// A method with `@Query`: the build checks it, and tells the starter what
/// is left to do at run time with a `QueryMethod`, a constant that holds
/// the annotation, the parameters and the shape of the result.
///
/// ```dart
/// // Input:
/// @Query('select title, year from books where year = :year')
/// Future<List<BookCard>> cards(int year);
/// // Output:
/// static const _cards = QueryMethod(
///   r'cards',
///   Query(r'select title, year from books where year = :year'),
///   parameters: [r'year'],
///   element: ClassType<BookCard>(),
/// );
/// @override
/// Future<List<BookCard>> cards(int year) =>
///     operations.query<List<BookCard>>(_cards, [year]);
/// ```
class QueryMethodModel extends RepositoryMethodModel {
  /// Creates the model of a method annotated with [query].
  QueryMethodModel(
    super.member, {
    required this.query,
    required this.shape,
    this.element,
    this.change,
    this.pageable,
    this.sort,
  });

  /// The `@Query` annotation.
  final DartObject query;

  /// How the result is shaped; `single` for a change.
  final ResultShape shape;

  /// The type of what one row becomes (the element of a `List`, the type
  /// itself for a single result); `null` for a `@Modifying` method.
  final DartType? element;

  /// What a `@Modifying` method returns; `null` for a method that reads.
  final ModifyingResult? change;

  /// The index of the `Pageable` parameter, if any.
  final int? pageable;

  /// The index of the `Sort` parameter, if any.
  final int? sort;

  /// The `:#{...}` expressions of the texts (the SQL, then the count
  /// query), in text order, once the build has read them.
  List<QueryExpressionModel> expressions = const [];

  /// The beans of the application by name, for the compiled expressions
  /// that read one (`@clock`).
  Map<String, InterfaceType> beans = const {};

  /// The entities `{Entity}` placeholders name, by class name, once the
  /// build has read the texts.
  Map<String, InterfaceType> entities = const {};

  /// Whether the method returns a `Stream` (`queryStream`) instead of a
  /// `Future` (`query`).
  bool get isStream => shape == ResultShape.stream;
}

/// A method with `@Procedure`: a call of a database function. The build checks
/// the method and tells the starter what is left to do with an
/// `ProcedureMethod`, a constant that holds the annotation, the parameters (the
/// function's arguments, by name) and the shape of the result.
///
/// ```dart
/// // Input:
/// @Procedure('accounts_over')
/// Future<List<Account>> over(int balance);
/// // Output:
/// static const _over = ProcedureMethod(
///   r'over',
///   Procedure(r'accounts_over'),
///   parameters: [r'balance'],
///   element: ClassType<Account>(),
/// );
/// @override
/// Future<List<Account>> over(int balance) =>
///     operations.procedure<List<Account>>(_over, [balance]);
/// ```
class ProcedureMethodModel extends RepositoryMethodModel {
  /// Creates the model of a method annotated with [procedure].
  ProcedureMethodModel(
    super.member, {
    required this.procedure,
    required this.shape,
    this.element,
  });

  /// The `@Procedure` annotation.
  final DartObject procedure;

  /// How the result is shaped; `single` for a method that returns nothing.
  final ResultShape shape;

  /// The type of what one row becomes (the element of a `List`, the type
  /// itself for a single result); `null` for a method that returns
  /// nothing.
  final DartType? element;

  /// Whether the method returns a `Stream` (`procedureStream`) instead of a
  /// `Future` (`procedure`).
  bool get isStream => shape == ResultShape.stream;
}

/// What a derived query asks of `RepositoryOperations`; each is the method
/// of that name.
enum DerivedOperation {
  /// All results as a `List`.
  list,

  /// All results as a `Set`.
  set,

  /// At most one result (`Future<T?>`).
  one,

  /// Exactly one result (`Future<T>`).
  single,

  /// The results as a `Stream`.
  stream,

  /// A window of the results and their total.
  page,

  /// A window of the results.
  slice,

  /// The number of results (`countBy`).
  countBy,

  /// Whether there is a result (`existsBy`).
  existsBy,

  /// Deletes the results, returning their number (`deleteBy`).
  deleteBy,

  /// Deletes the results, returning them (`deleteByReturning`).
  deleteByReturning,

  /// The results as a `Stream<List<T>>`, emitted again after every change
  /// that concerns them (`watch…By`).
  watch,

  /// The changes of the rows the predicate matches, as a
  /// `Stream<RowChange<T>>` (`changes…By`).
  changes,
}

/// A derived query: a method whose name the build read as a `PartTree`.
///
/// ```dart
/// // Input: Future<Page<Book>> findByYearAfter(int year, Pageable page);
/// // Output:
/// static const _findByYearAfter = PartTree(r'findByYearAfter',
///     [OrPart([Part(r'year', PartType.greaterThan)])]);
/// @override
/// Future<Page<Book>> findByYearAfter(int year, Pageable page) =>
///     operations.page(_findByYearAfter, [year], page);
/// ```
class DerivedMethodModel extends RepositoryMethodModel {
  /// Creates the model.
  DerivedMethodModel(
    super.member, {
    required this.tree,
    required this.operation,
    required this.arguments,
    this.sort,
    this.pageable,
    this.lock,
  });

  /// The method's name read as a query.
  final PartTreeModel tree;

  /// The operation that runs it.
  final DerivedOperation operation;

  /// The parameters the predicate consumes, in order.
  final List<String> arguments;

  /// The name of the `Sort` parameter, if any.
  final String? sort;

  /// The name of the `Pageable` parameter, if any.
  final String? pageable;

  /// The `@Lock` annotation, if any.
  final DartObject? lock;
}
