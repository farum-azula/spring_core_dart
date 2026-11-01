import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';

/// How the result of a `@Query` method is shaped.
///
/// Spring (Java): the `QueryMethod` result types (`isCollectionQuery()`,
/// `isPageQuery()`, `isSliceQuery()`, `isStreamQuery()`).
enum QueryShape {
  /// A `List` (or an `Iterable`) of the rows.
  list,

  /// A `Set` of the rows.
  set,

  /// A `Page`: a window of the rows and the total.
  page,

  /// A `Slice`: a window of the rows and whether another follows.
  slice,

  /// A `Stream`: the rows as the database sends them.
  stream,

  /// One row (or the one value an extractor returns).
  single,
}

/// What a `@Modifying` method returns.
enum QueryChange {
  /// The number of rows changed (`Future<int>`).
  rows,

  /// Whether any row changed (`Future<bool>`).
  any,

  /// Nothing (`Future<void>`).
  nothing,
}

/// What a compiled `:#{...}` expression of a `@Query` may use besides the
/// method's arguments: the beans (`@clock`), the environment
/// (`@environment.getProperty('x')`), the quoted table of the entity
/// (`#entityName`) and the method's name (`#methodName`).
///
/// Spring (Java): the `EvaluationContext` of
/// `org.springframework.data.spel.EvaluationContextProvider`.
final class QueryExpressionContext {
  /// A context over [beanFactory] and [environment] for the method
  /// [methodName] of the entity stored in [entityName] (quoted).
  const QueryExpressionContext({
    required this.entityName,
    required this.methodName,
    this.beanFactory,
    this.environment,
  });

  /// The quoted table of the repository's entity: `#entityName`.
  final String entityName;

  /// The name of the method: `#methodName`.
  final String methodName;

  /// The beans, or `null` when the repository has no bean factory.
  final BeanFactory? beanFactory;

  /// The configuration, or `null` when the repository has none.
  final Environment? environment;

  /// The bean called [name]: `@name`. Throws an
  /// `ArgumentError` when there is no bean factory.
  Object bean(String name) =>
      (beanFactory ??
              (throw ArgumentError(
                'no BeanFactory to look up the bean @$name',
              )))
          .getBeanByName(name);
}

/// A `:#{...}` expression compiled by the build: the value to bind, from
/// the method's [arguments] (in the order of its parameters) and the
/// [context].
///
/// Spring (Java): none; Spring evaluates the SpEL text of a `:#{...}` at
/// each call.
typedef QueryExpression = Object? Function(
  List<Object?> arguments,
  QueryExpressionContext context,
);

/// What the run time needs to know of a `@Query` method once the build has
/// checked it: its annotation, its parameters, the shape of its result.
///
/// The build writes one for each `@Query` method of a repository and hands
/// them to `RepositoryFactory.operations`; it has already refused every
/// mistake it can find in the method and the SQL (an unknown `:name`, a
/// `Page` without a `Pageable`, a misspelled table...), so what is left is
/// what depends on the run time: the `${property}` placeholders, the
/// `{Entity}` placeholders (the mapping names the table and the columns),
/// the expressions, the dialect, and what the database holds.
///
/// ```dart
/// // For: @Query('select title from books where year = :year')
/// //      Future<List<BookCard>> cards(int year);
/// static const _cards = QueryMethod(
///   r'cards',
///   Query(r'select title from books where year = :year'),
///   parameters: [r'year'],
///   element: ClassType<BookCard>(),
/// );
/// ```
///
/// Spring (Java): `org.springframework.data.repository.query.QueryMethod`.
final class QueryMethod {
  /// The method [name] annotated with [query].
  ///
  /// [parameters] are the names of all its parameters, in order; the ones
  /// at [pageable] and [sort] are not bound, the others are, by name.
  /// [shape] is the shape of the result and [element] the type of what one
  /// row becomes (the type itself for a single result); a method that
  /// changes data has a [change] instead of an [element].
  ///
  /// [entities] are the entities the `{Entity}` placeholders name, by
  /// class name. [expressions] has one entry for each `:#{...}` of the SQL
  /// and then of the count query, in text order: the expression compiled
  /// by the build, or `null` to evaluate its text with the SpEL
  /// interpreter. An empty list means every expression is interpreted.
  const QueryMethod(
    this.name,
    this.query, {
    this.parameters = const [],
    this.pageable,
    this.sort,
    this.shape = QueryShape.list,
    this.element,
    this.change,
    this.entities = const {},
    this.expressions = const [],
  }) : assert(
         element != null || change != null,
         'a method reads (element) or changes (change)',
       );

  /// The name of the method.
  final String name;

  /// The annotation: the SQL, the count query, the row mapper or result
  /// set extractor.
  final Query query;

  /// The names of the parameters, in order.
  final List<String> parameters;

  /// The index of the `Pageable` parameter, or null.
  final int? pageable;

  /// The index of the `Sort` parameter, or null.
  final int? sort;

  /// The shape of the result.
  final QueryShape shape;

  /// The type of what one row becomes; null for a method that changes
  /// data.
  final TypeInfo<Object?>? element;

  /// What the method returns when it changes data (`@Modifying`); null for
  /// a method that reads.
  final QueryChange? change;

  /// The entities `{Entity}` placeholders name, by class name.
  final Map<String, Type> entities;

  /// The compiled `:#{...}` expressions, `null` where the text is
  /// interpreted.
  final List<QueryExpression?> expressions;

  /// The parameters bound by name, with their position: all but the
  /// `Pageable` and the `Sort`.
  Map<String, int> get boundParameters => {
    for (final (index, name) in parameters.indexed)
      if (index != pageable && index != sort) name: index,
  };

  @override
  String toString() => 'QueryMethod($name)';
}
