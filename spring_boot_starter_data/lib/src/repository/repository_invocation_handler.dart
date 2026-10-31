import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/log_values.dart';
import 'package:spring_boot_starter_data/src/mapping/auditing.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/query/part_tree.dart';
import 'package:spring_boot_starter_data/src/query/part_tree_parser.dart';
import 'package:spring_boot_starter_data/src/repository/page.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';

typedef _Plan = Object? Function(List<Object?> arguments);

/// The engine behind one repository interface: the generated class hands
/// every method call to it, and it runs the call on the [store].
///
/// Each method is compiled into a plan when the handler is created, so a
/// mistake stops the application at startup, with every problem of the
/// repository listed in one `StateError`:
///
/// - the CRUD methods of `CrudRepository`, `PagingAndSortingRepository`
///   and their `List` variants are recognised by name and number of
///   parameters (`save`, `saveAll`, `findById`, `existsById`, `findAll`,
///   `findAllById`, `count`, `deleteById`, `delete`, `deleteAllById`,
///   `deleteAllOf`, `deleteAll`, `findAllSorted`, `findAllPaged`);
/// - every other method must be a derived query: its name is parsed into a
///   `PartTree` and checked against the entity, the parameters and the
///   return type; it must be asynchronous (return a `Future` or a
///   `Stream`);
/// - `@Query` and `@Lock` need a SQL store and are refused with the
///   in-memory store.
///
/// A call then does what its plan says. `save` inserts a new entity (by
/// `IsNewStrategy`: no version or version 0, else no id) and updates the
/// others, after auditing it when an [AuditingHandler] is given, and
/// returns what the store returns: the instance with its id and version
/// (a copy when they are `final`). Derived queries become a `Criteria` for
/// the store, with the name's `OrderBy` first and then the `Sort` of the
/// method's `Sort` or `Pageable` parameter. The result takes the shape of
/// the return type:
///
/// - `List`, `Iterable`, `Set`: all results; a `Stream` emits them when
///   listened to;
/// - the entity: the only result; `null` when there is none if the type
///   is nullable, else an `EmptyResultDataAccessException`; more than one
///   is an `IncorrectResultSizeDataAccessException` (unless the name has
///   `First` or `Top`);
/// - `Page`: the requested window and a count (limited by `Top`/`First`);
/// - `Slice`: the window, read with one more row to know whether there is
///   a next one;
/// - `int` for `count` and for `delete` (the number deleted), `bool` for
///   `exists`, `void` or the deleted entities for `delete`.
///
/// `First`/`Top` and a `Pageable` combine as in Spring Data: the page's
/// window is cut at the limit of the name (`findTop3By(Pageable)` with a
/// page size of 2 gives pages of 2 and 1).
///
/// What the store throws (all `DataAccessException`s) reaches the caller
/// unchanged; any other error is wrapped in one with the original as its
/// cause (`InvalidDataAccessApiUsageException` for a misuse such as a null
/// id, `DataAccessResourceFailureException` otherwise).
///
/// The starter's `RepositoryFactory` creates one per repository bean;
/// applications never create or call it, they call the interface.
///
/// Spring (Java): `SimpleJdbcRepository` (the CRUD methods) and
/// `PartTreeJdbcQuery` (the derived ones), behind the proxy that
/// `RepositoryFactorySupport` creates.
final class RepositoryInvocationHandler implements InvocationHandler {
  /// The handler of the interface described by [metadata], which stores the
  /// aggregates of [entity] in [store]. [problems] are mistakes found
  /// before (such as an unknown store): they are reported with those of the
  /// methods. Throws a [StateError] listing every problem.
  RepositoryInvocationHandler({
    required InterfaceMetadata<Object> metadata,
    required this.entity,
    required TypeInfo<Object?> entityType,
    required this.converter,
    required this.store,
    this.auditing,
    this.isNewStrategy = const IsNewStrategy(),
    List<String> problems = const [],
  }) : typeName = metadata.typeName,
       _log = SpringLog('spring.data.repository.${metadata.typeName}'),
       _shaper = entityType.capture<_Shaper>(<E>() => _TypedShaper<E>()) {
    final found = [...problems];
    if (entity.idProperty == null) {
      found.add(
        '${entity.introspection.className} has no @Id property: a '
        'repository stores aggregates by id',
      );
    }
    for (final method in metadata.methods) {
      final plan = _compile(metadata, method, found);
      if (plan != null) {
        _plans[method] = plan;
      }
    }
    if (found.isNotEmpty) {
      throw StateError(
        'Invalid repository $typeName:\n'
        '${found.map((p) => '  - $p').join('\n')}',
      );
    }
    _log.debug(
      'Created $typeName for ${entity.introspection.className} '
      '(${entity.tableName}) on the ${store.name} store: '
      '${_plans.length} method(s)',
    );
  }

  /// The name of the interface, such as `BookRepository`; the logger is
  /// `spring.data.repository.<typeName>`.
  final String typeName;

  /// The entity the repository stores.
  final PersistentEntity<Object> entity;

  /// Reads the ids and versions of instances.
  final EntityConverter converter;

  /// Where the aggregates are kept.
  final DataStore store;

  /// Fills the audit properties on save; `null` when auditing is off.
  final AuditingHandler? auditing;

  /// Tells a new entity from one to update.
  final IsNewStrategy isNewStrategy;

  final SpringLog _log;
  final _Shaper _shaper;
  final _plans = Map<ProxyMethod, _Plan>.identity();

  static List<String> _names(ProxyMethod method) => [
    for (final parameter in method.parameters) parameter.name,
  ];

  @override
  Object? invoke(ProxyMethod method, List<Object?> arguments) {
    final plan = _plans[method]!;
    if (_log.isEnabled(SpringLogLevel.debug)) {
      _log.debug('$typeName.${method.name}');
    }
    if (_log.isEnabled(SpringLogLevel.trace)) {
      _log.trace(
        '$typeName.${method.name}('
        '${LogValues.arguments(_names(method), arguments)})',
      );
    }
    return plan(arguments);
  }

  // ------------------------------------------------------------ compiling

  _Plan? _compile(
    InterfaceMetadata<Object> metadata,
    ProxyMethod method,
    List<String> problems,
  ) {
    final where = '$typeName.${method.name}';
    final before = problems.length;
    if (method.annotation<Lock>() != null) {
      problems.add(
        '$where: @Lock needs transactions, which the ${store.name} store '
        'has not: use a SQL store (coming in a later version)',
      );
    }
    if (method.annotation<Query>() != null) {
      problems.add(
        '$where: @Query needs a SQL store: set spring.datasource.url and '
        'add a driver (coming in a later version); the ${store.name} store '
        'runs derived queries only',
      );
    }
    if (problems.length > before) {
      return null;
    }
    final crud = _crud(method);
    if (crud != null) {
      return crud;
    }
    if (!PartTreeParser.isDerivedQuery(method.name)) {
      problems.add(
        '$where: not a CRUD method of the repository interfaces and not a '
        'derived query: a query method starts with find, read, get, query, '
        'search, stream, count, exists, delete or remove, then By and the '
        'conditions (findByTitle)',
      );
      return null;
    }
    return _derived(method, where, problems);
  }

  bool _isStream(TypeInfo<Object?> type) =>
      type is GenericType<Object?> && type.isSubtypeOf<Stream<Object?>>();

  _Plan? _derived(ProxyMethod method, String where, List<String> problems) {
    final isStream = _isStream(method.returnType);
    if (!method.isFuture && !isStream) {
      problems.add(
        '$where: a repository method is asynchronous: return a Future '
        '(Future<${method.returnType}>) or a Stream',
      );
    }
    final parser = PartTreeParser(repositoryName: typeName);
    final PartTree tree;
    try {
      tree = parser.parse(method.name, entity);
      parser.validate(
        tree,
        entity,
        method.parameters,
        // The generator describes `Future<void>` as a DynamicType with
        // `isVoid` set on the method; the parser looks at the type.
        returnType: method.isVoid
            ? const DynamicType.forVoid()
            : method.returnType,
        isFuture: method.isFuture,
      );
    } on QueryCreationException catch (e) {
      problems.add('$where: ${e.message}');
      return null;
    }
    if (!method.isFuture && !isStream) {
      return null;
    }
    return _DerivedQuery(this, method, tree, isStream: isStream).call;
  }

  _Plan? _crud(ProxyMethod method) {
    final count = method.parameters.length;
    Future<Object?> run(Future<Object?> Function() body) => _guarded(body);
    switch ((method.name, count)) {
      case ('save', 1):
        return (a) => run(() => _save(_instance(a[0])));
      case ('saveAll', 1):
        return (a) => run(() async {
          final saved = <Object>[];
          for (final instance in _iterable(a[0])) {
            saved.add(await _save(_instance(instance)));
          }
          return _shaper.list(saved);
        });
      case ('findById', 1):
        return (a) => run(() => store.findById(entity, _id(a[0])));
      case ('existsById', 1):
        return (a) => run(() => store.exists(entity, criteria: _byId(a[0])));
      case ('findAll', 0):
        return (a) => run(() async => _shaper.list(await store.find(entity)));
      case ('findAllById', 1):
        return (a) => run(
          () async => _shaper.list(
            await store.findAllById(entity, [
              for (final id in _iterable(a[0])) _id(id),
            ]),
          ),
        );
      case ('count', 0):
        return (a) => run(() => store.count(entity));
      case ('deleteById', 1):
        return (a) => run(() async {
          await store.deleteById(entity, _id(a[0]));
          return null;
        });
      case ('delete', 1):
        return (a) => run(() async {
          await _delete(_instance(a[0]));
          return null;
        });
      case ('deleteAllById', 1):
        return (a) => run(() async {
          for (final id in _iterable(a[0])) {
            await store.deleteById(entity, _id(id));
          }
          return null;
        });
      case ('deleteAllOf', 1):
        return (a) => run(() async {
          for (final instance in _iterable(a[0])) {
            await _delete(_instance(instance));
          }
          return null;
        });
      case ('deleteAll', 0):
        return (a) => run(() async {
          await store.deleteWhere(entity);
          return null;
        });
      case ('findAllSorted', 1):
        return (a) => run(() async {
          final sort = a[0]! as Sort;
          return _shaper.list(await store.find(entity, sort: sort));
        });
      case ('findAllPaged', 1):
        return (a) => run(() => _page(a[0]! as Pageable));
    }
    return null;
  }

  // -------------------------------------------------------------- running

  /// Runs [body], letting a `DataAccessException` through and wrapping
  /// any other error in one.
  Future<R> _guarded<R>(Future<R> Function() body) async {
    try {
      return await body();
    } on DataAccessException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_translate(error), stackTrace);
    }
  }

  DataAccessException _translate(Object error) {
    final message = '$typeName failed: $error';
    return switch (error) {
      ArgumentError() ||
      StateError() ||
      TypeError() ||
      UnsupportedError() ||
      FormatException() => InvalidDataAccessApiUsageException(
        message,
        cause: error,
      ),
      _ => DataAccessResourceFailureException(message, cause: error),
    };
  }

  Object _instance(Object? value) =>
      value ??
      (throw InvalidDataAccessApiUsageException(
        'The entity must not be null',
      ));

  Object _id(Object? value) =>
      value ??
      (throw InvalidDataAccessApiUsageException('The id must not be null'));

  Iterable<Object?> _iterable(Object? value) =>
      value as Iterable<Object?>? ??
      (throw InvalidDataAccessApiUsageException(
        'The collection must not be null',
      ));

  Criteria _byId(Object? id) => Criteria(
    [
      OrPart([
        Part([entity.idProperty!.name], PartType.simpleProperty),
      ]),
    ],
    [_id(id)],
  );

  Future<Object> _save(Object instance) async {
    final isNew = isNewStrategy.isNew(entity, instance);
    var toSave = instance;
    if (auditing case final handler?) {
      toSave = isNew
          ? await handler.markCreated(entity, toSave)
          : await handler.markModified(entity, toSave);
    }
    return await (isNew
        ? store.insert(entity, toSave)
        : store.update(entity, toSave));
  }

  Future<void> _delete(Object instance) async {
    final id = converter.idOf(entity, instance);
    if (id == null) {
      throw InvalidDataAccessApiUsageException(
        'Cannot delete ${entity.introspection.className}: its id is null',
      );
    }
    final version = entity.versionProperty?.getValue(instance);
    await store.deleteById(entity, id, expectedVersion: version);
  }

  Future<Object> _page(Pageable pageable) async {
    final window = _Window.of(pageable, null);
    final content = await store.find(
      entity,
      sort: pageable.sort,
      offset: window.offset,
      limit: window.limit,
    );
    final total = pageable.isPaged ? await store.count(entity) : content.length;
    return _shaper.page(content, pageable, total);
  }
}

// The part of a result a Pageable asks for, cut at the limit of First/Top.
final class _Window {
  const _Window(this.offset, this.limit, this.size);

  factory _Window.of(Pageable? pageable, int? max) {
    final paged = pageable != null && pageable.isPaged;
    final offset = paged ? pageable.offset : 0;
    final size = paged ? pageable.pageSize : null;
    int? limit;
    if (size == null) {
      limit = max;
    } else if (max == null) {
      limit = size;
    } else {
      limit = (max - offset).clamp(0, size);
    }
    return _Window(offset, limit, size);
  }

  final int offset;

  /// The most rows of the window; null for no limit.
  final int? limit;

  /// The page size; null when unpaged.
  final int? size;
}

// A derived query method: the tree of its name and where its arguments
// are.
final class _DerivedQuery {
  _DerivedQuery(
    this.handler,
    this.method,
    this.tree, {
    required this.isStream,
  }) {
    for (final (index, parameter) in method.parameters.indexed) {
      final type = parameter.type.type;
      if (type == Pageable || type == PageRequest) {
        _pageable = index;
      } else if (type == Sort) {
        _sort = index;
      } else {
        _arguments.add(index);
      }
    }
    final returnType = method.returnType;
    _nullable = returnType.nullable;
    _shape = switch (returnType) {
      ListType() => _Shape.list,
      SetType() => _Shape.set,
      final GenericType<Object?> g when g.isSubtypeOf<Page<Object?>>() =>
        _Shape.page,
      final GenericType<Object?> g when g.isSubtypeOf<Slice<Object?>>() =>
        _Shape.slice,
      final GenericType<Object?> g when g.isSubtypeOf<Stream<Object?>>() =>
        _Shape.stream,
      final GenericType<Object?> g when g.isSubtypeOf<Iterable<Object?>>() =>
        _Shape.list,
      _ => _Shape.single,
    };
  }

  final RepositoryInvocationHandler handler;
  final ProxyMethod method;
  final PartTree tree;
  final bool isStream;

  final _arguments = <int>[];
  int? _pageable;
  int? _sort;
  late final bool _nullable;
  late final _Shape _shape;

  DataStore get _store => handler.store;
  PersistentEntity<Object> get _entity => handler.entity;
  _Shaper get _shaper => handler._shaper;

  Object? call(List<Object?> arguments) {
    if (isStream) {
      return _shaper.stream(() => handler._guarded(() => _run(arguments)));
    }
    return handler._guarded(() => _run(arguments));
  }

  Future<Object?> _run(List<Object?> arguments) async {
    final criteria = Criteria(tree.predicate, [
      for (final index in _arguments) arguments[index],
    ]);
    final subject = tree.subject;
    switch (subject.kind) {
      case SubjectKind.count:
        return await _store.count(_entity, criteria: criteria);
      case SubjectKind.exists:
        return await _store.exists(_entity, criteria: criteria);
      case SubjectKind.delete:
        final returnType = method.returnType;
        if (returnType is ListType) {
          return _shaper.list(
            await _store.deleteWhereAndReturn(_entity, criteria: criteria),
          );
        }
        final deleted = await _store.deleteWhere(_entity, criteria: criteria);
        return returnType.type == int ? deleted : null;
      case SubjectKind.find:
        return await _find(arguments, criteria);
    }
  }

  Future<Object?> _find(List<Object?> arguments, Criteria criteria) async {
    final subject = tree.subject;
    final max = subject.maxResults;
    final pageable = switch (_pageable) {
      final index? => arguments[index]! as Pageable,
      null => null,
    };
    final extra = switch ((_sort, pageable)) {
      (final index?, _) => arguments[index]! as Sort,
      (_, final pageable?) => pageable.sort,
      _ => Sort.unsorted,
    };
    final sort = tree.sort.and(extra);
    final window = _Window.of(pageable, max);
    Future<List<Object>> select({int? extraRows}) => window.limit == 0
        ? Future.value(const [])
        : _store.find(
            _entity,
            criteria: criteria,
            sort: sort,
            offset: window.offset,
            limit: switch (window.limit) {
              final limit? => limit + (extraRows ?? 0),
              null => null,
            },
            distinct: subject.distinct,
          );

    switch (_shape) {
      case _Shape.list || _Shape.stream:
        final rows = await select();
        return _shaper.list(rows);
      case _Shape.set:
        return _shaper.set(await select());
      case _Shape.page:
        final content = await select();
        var total = content.length;
        if (pageable != null && pageable.isPaged) {
          total = subject.distinct
              ? (await _store.find(
                  _entity,
                  criteria: criteria,
                  distinct: true,
                )).length
              : await _store.count(_entity, criteria: criteria);
          if (max != null && total > max) {
            total = max;
          }
        }
        return _shaper.page(content, pageable!, total);
      case _Shape.slice:
        final size = window.size;
        final limit = window.limit;
        final canHaveMore =
            size != null &&
            limit != null &&
            limit == size &&
            (max == null || window.offset + limit < max);
        final rows = await select(extraRows: canHaveMore ? 1 : 0);
        final hasNext = canHaveMore && rows.length > limit;
        return _shaper.slice(
          hasNext ? rows.sublist(0, limit) : rows,
          pageable!,
          hasNext,
        );
      case _Shape.single:
        final rows = await select();
        if (rows.isEmpty) {
          if (_nullable) {
            return null;
          }
          throw EmptyResultDataAccessException(
            1,
            message:
                '${handler.typeName}.${method.name}: no result, but the '
                'method returns a non-null ${_entity.introspection.className}'
                ' (return it as nullable to get null)',
          );
        }
        if (rows.length > 1 && max == null) {
          throw IncorrectResultSizeDataAccessException(
            1,
            rows.length,
            message:
                '${handler.typeName}.${method.name}: ${rows.length} results '
                'for a method that returns one (use First or Top, or '
                'return a List)',
          );
        }
        return rows.first;
    }
  }
}

enum _Shape { list, set, page, slice, stream, single }

// Creates the collections of the result with the entity as the real type
// argument: a `Future<List<Book>>` method must not get a `List<Object>`.
abstract interface class _Shaper {
  Object list(Iterable<Object?> items);
  Object set(Iterable<Object?> items);
  Object stream(Future<Object?> Function() items);
  Object page(List<Object> content, Pageable pageable, int total);
  Object slice(List<Object> content, Pageable pageable, bool hasNext);
}

final class _TypedShaper<E> implements _Shaper {
  @override
  Object list(Iterable<Object?> items) => <E>[
    for (final item in items) item as E,
  ];

  @override
  Object set(Iterable<Object?> items) => <E>{
    for (final item in items) item as E,
  };

  @override
  Object stream(Future<Object?> Function() items) => _stream(items);

  Stream<E> _stream(Future<Object?> Function() items) async* {
    for (final item in (await items())! as Iterable<Object?>) {
      yield item as E;
    }
  }

  @override
  Object page(List<Object> content, Pageable pageable, int total) =>
      PageImpl<E>(<E>[for (final item in content) item as E], pageable, total);

  @override
  Object slice(List<Object> content, Pageable pageable, bool hasNext) =>
      SliceImpl<E>(
        <E>[for (final item in content) item as E],
        pageable,
        hasNext,
      );
}
