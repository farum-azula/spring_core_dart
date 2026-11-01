import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/log_values.dart';
import 'package:spring_boot_starter_data/src/mapping/auditing.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/query/part_tree.dart';
import 'package:spring_boot_starter_data/src/repository/page.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_method.dart';
import 'package:spring_boot_starter_data/src/repository/query/string_based_jdbc_query.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/jdbc/jdbc_data_store.dart';
import 'package:spring_boot_starter_data/src/transaction/platform_transaction_manager.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_definition.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_exceptions.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_template.dart';

/// The engine behind one repository interface: the generated class calls
/// it for every method, and it runs the call on the [store].
///
/// The build has already parsed and checked the method names. A derived
/// query arrives as a constant [PartTree] with the method's arguments; the
/// CRUD methods are the ones of `SimpleRepository`; a `@Query` method is
/// compiled when the operations are created (see `RepositoryFactory`),
/// with the other mistakes found at startup (the store, the data source,
/// the entity, the `@Query` texts), all listed in one `StateError`:
///
/// - `@Query` needs a SQL store and is refused with the in-memory store;
/// - the entity needs an `@Id` property.
///
/// A call then does what its method says. [save] inserts a new entity (by
/// `IsNewStrategy`: no version or version 0, else no id) and updates the
/// others, after auditing it when an [AuditingHandler] is given, and
/// returns what the store returns: the instance with its id and version
/// (a copy when they are `final`). The derived queries ([list], [set],
/// [one], [single], [stream], [page], [slice], [countBy], [existsBy],
/// [deleteBy], [deleteByReturning]) turn the tree into a `Criteria` for
/// the store, with the name's `OrderBy` first and then the `Sort` or the
/// `Pageable`'s sort:
///
/// - [one] and [single]: the only result; no result is `null` for [one] and
///   an `EmptyResultDataAccessException` for [single]; more than one is an
///   `IncorrectResultSizeDataAccessException` (unless the name has `First`
///   or `Top`);
/// - [page]: the requested window and a count (limited by `Top`/`First`);
/// - [slice]: the window, read with one more row to know whether there is
///   a next one.
///
/// `First`/`Top` and a `Pageable` combine as in Spring Data: the page's
/// window is cut at the limit of the name (`findTop3By(Pageable)` with a
/// page size of 2 gives pages of 2 and 1).
///
/// **Transactions.** The write methods ([save], [saveAll], `delete*`,
/// [deleteBy]) run in a `required` transaction of the repository's store,
/// as Spring's `SimpleJdbcRepository` is `@Transactional`: [saveAll] and an
/// aggregate with its children are atomic, and inside a transaction of the
/// caller (a `@Transactional` service, a `TransactionTemplate`) they join
/// it. The read methods run in the caller's transaction when there is one,
/// else on their own. Without a [transactionManager] nothing is wrapped.
///
/// **Locks.** A derived find (and [findById]) given a `Lock` reads with the
/// lock, the timeout and `skipLocked` of the annotation; the store locks
/// the rows until the transaction ends. Called without a transaction of
/// that store it throws an `IllegalTransactionStateException`, and never
/// runs unlocked.
///
/// What the store throws (all `DataAccessException`s) reaches the caller
/// unchanged; any other error is wrapped in one with the original as its
/// cause (`InvalidDataAccessApiUsageException` for a misuse such as an
/// entity without an id, `DataAccessResourceFailureException` otherwise).
///
/// The starter's `RepositoryFactory` creates one per repository bean;
/// applications never create or call it, they call the interface.
///
/// Spring (Java): `SimpleJdbcRepository` (the CRUD methods) and
/// `PartTreeJdbcQuery` (the derived ones), behind the proxy that
/// `RepositoryFactorySupport` creates.
final class RepositoryOperations<T extends Object, ID extends Object> {
  /// The operations of the interface [typeName], which stores the
  /// aggregates of [entity] in [store]; [queries] are its `@Query` methods.
  /// [problems] are mistakes found before (such as an unknown store): they
  /// are reported with those of the queries. Throws a [StateError] listing
  /// every problem.
  RepositoryOperations({
    required this.typeName,
    required this.entity,
    required this.converter,
    required this.store,
    this.transactionManager,
    this.auditing,
    this.isNewStrategy = const IsNewStrategy(),
    this.environment,
    this.beanFactory,
    this.introspector,
    this.mappingContext,
    List<QueryMethod> queries = const [],
    List<String> problems = const [],
  }) : _log = SpringLog('spring.data.repository.$typeName') {
    final found = [...problems];
    if (entity.idProperty == null) {
      found.add(
        '${entity.introspection.className} has no @Id property: a '
        'repository stores aggregates by id',
      );
    }
    for (final method in queries) {
      final compiled = _compile(method, found);
      if (compiled != null) {
        _queries[method] = compiled;
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
      '${_queries.length} @Query method(s)',
    );
  }

  /// The name of the interface, such as `BookRepository`; the logger is
  /// `spring.data.repository.<typeName>`.
  final String typeName;

  /// The entity the repository stores.
  final PersistentEntity<T> entity;

  /// Reads the ids and versions of instances.
  final EntityConverter converter;

  /// Where the aggregates are kept.
  final DataStore store;

  /// Runs the write methods in transactions of [store]; `null` for none.
  final PlatformTransactionManager? transactionManager;

  /// Fills the audit properties on save; `null` when auditing is off.
  final AuditingHandler? auditing;

  /// Tells a new entity from one to update.
  final IsNewStrategy isNewStrategy;

  /// Resolves the `${property}` placeholders of a `@Query` and answers
  /// `@environment` in its SpEL; null for neither.
  final Environment? environment;

  /// Gives the SpEL of a `@Query` its `@bean` references; null for none.
  final BeanFactory? beanFactory;

  /// Lets SpEL read the properties of `@Introspected` arguments and maps
  /// the DTOs of a `@Query` that are `@Introspected`; null for the store's.
  final BeanIntrospector? introspector;

  /// Describes the DTOs a `@Query` returns (the classes the build described
  /// as projections); null for none.
  final RelationalMappingContext? mappingContext;

  final SpringLog _log;

  // The compiled @Query methods, by the QueryMethod the generated class
  // passes.
  final _queries = Map<QueryMethod, StringBasedJdbcQuery>.identity();

  // The conditions of a lookup by id.
  late final List<OrPart> _idPredicate = [
    OrPart([Part(entity.idProperty!.name)]),
  ];

  // ------------------------------------------------------------------ CRUD

  /// Inserts [instance] when it is new, else updates it; returns the saved
  /// instance, with the id and version the store gave.
  Future<T> save(T instance) {
    _called('save', const ['entity'], [instance]);
    return _write(() => _save(instance));
  }

  /// Saves each of [instances] as [save] does, atomically; returns them
  /// saved.
  Future<List<T>> saveAll(Iterable<T> instances) {
    _called('saveAll', const ['entities'], [instances]);
    return _write(() async {
      final saved = <T>[];
      for (final instance in instances) {
        saved.add(await _save(instance));
      }
      return saved;
    });
  }

  /// The aggregate with id [id], or null; read with [lock] when given.
  Future<T?> findById(ID id, {Lock? lock}) {
    _called('findById', const ['id'], [id]);
    return _guarded(
      () => store.findById<T>(
        entity,
        id,
        lock: lock?.value,
        lockTimeout: lock?.timeout,
        skipLocked: lock?.skipLocked ?? false,
      ),
    );
  }

  /// Whether an aggregate with id [id] exists.
  Future<bool> existsById(ID id) {
    _called('existsById', const ['id'], [id]);
    return _guarded(() => store.exists<T>(entity, criteria: _byId(id)));
  }

  /// Every aggregate.
  Future<List<T>> findAll() {
    _called('findAll', const [], const []);
    return _guarded(() => store.find<T>(entity));
  }

  /// The aggregates whose ids are among [ids].
  Future<List<T>> findAllById(Iterable<ID> ids) {
    _called('findAllById', const ['ids'], [ids]);
    return _guarded(() => store.findAllById<T>(entity, ids));
  }

  /// The number of aggregates.
  Future<int> count() {
    _called('count', const [], const []);
    return _guarded(() => store.count<T>(entity));
  }

  /// Deletes the aggregate with id [id], with its children.
  Future<void> deleteById(ID id) {
    _called('deleteById', const ['id'], [id]);
    return _write(() async {
      await store.deleteById<T>(entity, id);
    });
  }

  /// Deletes [instance] with its children, checking its version.
  Future<void> delete(T instance) {
    _called('delete', const ['entity'], [instance]);
    return _write(() => _delete(instance));
  }

  /// Deletes the aggregates whose ids are among [ids].
  Future<void> deleteAllById(Iterable<ID> ids) {
    _called('deleteAllById', const ['ids'], [ids]);
    return _write(() async {
      for (final id in ids) {
        await store.deleteById<T>(entity, id);
      }
    });
  }

  /// Deletes each of [instances] as [delete] does.
  Future<void> deleteAllOf(Iterable<T> instances) {
    _called('deleteAllOf', const ['entities'], [instances]);
    return _write(() async {
      for (final instance in instances) {
        await _delete(instance);
      }
    });
  }

  /// Deletes every aggregate.
  Future<void> deleteAll() {
    _called('deleteAll', const [], const []);
    return _write(() async {
      await store.deleteWhere<T>(entity);
    });
  }

  /// Every aggregate, ordered by [sort].
  Future<List<T>> findAllSorted(Sort sort) {
    _called('findAllSorted', const ['sort'], [sort]);
    return _guarded(() => store.find<T>(entity, sort: sort));
  }

  /// One page of aggregates, as [pageable] asks; the page knows the total.
  Future<Page<T>> findAllPaged(Pageable pageable) {
    _called('findAllPaged', const ['pageable'], [pageable]);
    return _guarded(() async {
      final window = _Window.of(pageable, null);
      final content = await store.find<T>(
        entity,
        sort: pageable.sort,
        offset: window.offset,
        limit: window.limit,
      );
      final total = pageable.isPaged
          ? await store.count<T>(entity)
          : content.length;
      return PageImpl<T>(content, pageable, total);
    });
  }

  // ------------------------------------------------------ derived queries
  //
  // Arguments: the values of the tree's parts, in order, without the Sort
  // and the Pageable, which are given by name.

  /// The matches of [tree] as a list, ordered by the tree's sort and then
  /// by [sort] (or the sort of [pageable]), cut to the window of
  /// [pageable]; read with [lock] when given.
  Future<List<T>> list(
    PartTree tree,
    List<Object?> arguments, {
    Sort? sort,
    Pageable? pageable,
    Lock? lock,
  }) {
    _calledTree(tree, arguments, sort: sort, pageable: pageable);
    return _guarded(
      () => _rows(tree, arguments, sort: sort, pageable: pageable, lock: lock),
    );
  }

  /// The matches of [tree] as a set (as [list] reads them).
  Future<Set<T>> set(
    PartTree tree,
    List<Object?> arguments, {
    Sort? sort,
    Pageable? pageable,
    Lock? lock,
  }) {
    _calledTree(tree, arguments, sort: sort, pageable: pageable);
    return _guarded(
      () async => (await _rows(
        tree,
        arguments,
        sort: sort,
        pageable: pageable,
        lock: lock,
      )).toSet(),
    );
  }

  /// The only match of [tree], or `null` when there is none; more than one
  /// is an `IncorrectResultSizeDataAccessException`, unless the name has
  /// `First` or `Top` (then the first).
  Future<T?> one(
    PartTree tree,
    List<Object?> arguments, {
    Sort? sort,
    Lock? lock,
  }) {
    _calledTree(tree, arguments, sort: sort);
    return _guarded(() async {
      final rows = await _rows(tree, arguments, sort: sort, lock: lock);
      return rows.isEmpty ? null : _only(tree, rows);
    });
  }

  /// The only match of [tree]: none is an
  /// `EmptyResultDataAccessException`, more than one an
  /// `IncorrectResultSizeDataAccessException` (as [one]).
  Future<T> single(
    PartTree tree,
    List<Object?> arguments, {
    Sort? sort,
    Lock? lock,
  }) {
    _calledTree(tree, arguments, sort: sort);
    return _guarded(() async {
      final rows = await _rows(tree, arguments, sort: sort, lock: lock);
      if (rows.isEmpty) {
        throw EmptyResultDataAccessException(
          1,
          message:
              '$typeName.${tree.methodName}: no result, but the method '
              'returns a non-null ${entity.introspection.className} '
              '(return it as nullable to get null)',
        );
      }
      return _only(tree, rows);
    });
  }

  /// The matches of [tree] as a stream, read when it is listened to.
  Stream<T> stream(
    PartTree tree,
    List<Object?> arguments, {
    Sort? sort,
    Pageable? pageable,
    Lock? lock,
  }) {
    _calledTree(tree, arguments, sort: sort, pageable: pageable);
    return _emit(
      () => _guarded(
        () =>
            _rows(tree, arguments, sort: sort, pageable: pageable, lock: lock),
      ),
    );
  }

  /// The page of [pageable] of the matches of [tree], with the total number
  /// of matches (limited by `Top`/`First`).
  Future<Page<T>> page(
    PartTree tree,
    List<Object?> arguments,
    Pageable pageable, {
    Lock? lock,
  }) {
    _calledTree(tree, arguments, pageable: pageable);
    return _guarded(() async {
      final criteria = Criteria(tree.predicate, arguments);
      final subject = tree.subject;
      final max = subject.maxResults;
      final window = _Window.of(pageable, max);
      final content = await _select(
        tree,
        criteria,
        window,
        _sortOf(tree, null, pageable),
        lock,
      );
      var total = content.length;
      if (pageable.isPaged) {
        total = subject.distinct
            ? (await store.find<T>(
                entity,
                criteria: criteria,
                distinct: true,
              )).length
            : await store.count<T>(entity, criteria: criteria);
        if (max != null && total > max) {
          total = max;
        }
      }
      return PageImpl<T>(content, pageable, total);
    });
  }

  /// The window of [pageable] of the matches of [tree], read with one more
  /// row to know whether a next window follows.
  Future<Slice<T>> slice(
    PartTree tree,
    List<Object?> arguments,
    Pageable pageable, {
    Lock? lock,
  }) {
    _calledTree(tree, arguments, pageable: pageable);
    return _guarded(() async {
      final criteria = Criteria(tree.predicate, arguments);
      final max = tree.subject.maxResults;
      final window = _Window.of(pageable, max);
      final size = window.size;
      final limit = window.limit;
      final canHaveMore =
          size != null &&
          limit != null &&
          limit == size &&
          (max == null || window.offset + limit < max);
      final rows = await _select(
        tree,
        criteria,
        window,
        _sortOf(tree, null, pageable),
        lock,
        extraRows: canHaveMore ? 1 : 0,
      );
      final hasNext = canHaveMore && rows.length > limit;
      return SliceImpl<T>(
        hasNext ? rows.sublist(0, limit) : rows,
        pageable,
        hasNext,
      );
    });
  }

  /// How many aggregates match [tree].
  Future<int> countBy(PartTree tree, List<Object?> arguments) {
    _calledTree(tree, arguments);
    return _guarded(
      () => store.count<T>(
        entity,
        criteria: Criteria(tree.predicate, arguments),
      ),
    );
  }

  /// Whether an aggregate matches [tree].
  Future<bool> existsBy(PartTree tree, List<Object?> arguments) {
    _calledTree(tree, arguments);
    return _guarded(
      () => store.exists<T>(
        entity,
        criteria: Criteria(tree.predicate, arguments),
      ),
    );
  }

  /// Deletes the aggregates that match [tree]; returns how many.
  Future<int> deleteBy(PartTree tree, List<Object?> arguments) {
    _calledTree(tree, arguments);
    return _write(
      () => store.deleteWhere<T>(
        entity,
        criteria: Criteria(tree.predicate, arguments),
      ),
    );
  }

  /// Deletes the aggregates that match [tree]; returns them, as they were
  /// stored.
  Future<List<T>> deleteByReturning(PartTree tree, List<Object?> arguments) {
    _calledTree(tree, arguments);
    return _write(
      () => store.deleteWhereAndReturn<T>(
        entity,
        criteria: Criteria(tree.predicate, arguments),
      ),
    );
  }

  // ------------------------------------------------------------- @Query

  /// Runs the `@Query` [method] (one of the `queries` given when the
  /// operations were created) with [arguments], in the order of its
  /// parameters; the result has the type the method returns.
  Future<R> query<R>(QueryMethod method, List<Object?> arguments) {
    final compiled = _compiled(method, arguments);
    if (compiled.isStream) {
      throw StateError(
        '$typeName.${method.name} returns a Stream: call queryStream',
      );
    }
    return _guarded<R>(
      () async =>
          await Future<Object?>.sync(() => compiled.call(arguments)) as R,
    );
  }

  /// Runs the `@Query` [method] that returns a stream, read as the
  /// database sends the rows.
  Stream<E> queryStream<E>(QueryMethod method, List<Object?> arguments) {
    final compiled = _compiled(method, arguments);
    if (!compiled.isStream) {
      throw StateError(
        '$typeName.${method.name} returns a Future: call query',
      );
    }
    return compiled.call(arguments)! as Stream<E>;
  }

  StringBasedJdbcQuery _compiled(QueryMethod method, List<Object?> arguments) {
    final compiled =
        _queries[method] ??
        (throw StateError(
          '$typeName.${method.name} was not given as a query when the '
          'operations were created',
        ));
    _called(method.name, method.parameters, arguments);
    return compiled;
  }

  StringBasedJdbcQuery? _compile(QueryMethod method, List<String> problems) {
    final where = '$typeName.${method.name}';
    if (store case final JdbcDataStore jdbc) {
      return StringBasedJdbcQuery.compile(
        typeName: typeName,
        method: method,
        entity: entity,
        store: jdbc,
        inTransaction: (body) => _inTransaction<Object?>(body),
        translateError: _translate,
        problems: problems,
        environment: environment,
        beanFactory: beanFactory,
        introspector: introspector,
        mappingContext: mappingContext,
      );
    }
    problems.add(
      '$where: @Query needs a SQL store: set spring.datasource.url and '
      'add a driver (coming in a later version); the ${store.name} store '
      'runs derived queries only',
    );
    return null;
  }

  // -------------------------------------------------------------- running

  // The rows of a derived find, in the window and the order its tree, sort
  // and pageable ask.
  Future<List<T>> _rows(
    PartTree tree,
    List<Object?> arguments, {
    Sort? sort,
    Pageable? pageable,
    Lock? lock,
  }) => _select(
    tree,
    Criteria(tree.predicate, arguments),
    _Window.of(pageable, tree.subject.maxResults),
    _sortOf(tree, sort, pageable),
    lock,
  );

  // The sort of the tree's name, then the Sort given, else the pageable's.
  Sort _sortOf(PartTree tree, Sort? sort, Pageable? pageable) =>
      tree.sort.and(sort ?? pageable?.sort ?? Sort.unsorted);

  Future<List<T>> _select(
    PartTree tree,
    Criteria criteria,
    _Window window,
    Sort sort,
    Lock? lock, {
    int extraRows = 0,
  }) {
    final limit = window.limit;
    if (limit == 0) {
      return Future.value(<T>[]);
    }
    return store.find<T>(
      entity,
      criteria: criteria,
      sort: sort,
      offset: window.offset,
      limit: limit == null ? null : limit + extraRows,
      distinct: tree.subject.distinct,
      lock: lock?.value,
      lockTimeout: lock?.timeout,
      skipLocked: lock?.skipLocked ?? false,
    );
  }

  // The first row of a non-empty result that must have one row, unless the
  // name limits the results (First, Top).
  T _only(PartTree tree, List<T> rows) {
    if (rows.length > 1 && tree.subject.maxResults == null) {
      throw IncorrectResultSizeDataAccessException(
        1,
        rows.length,
        message:
            '$typeName.${tree.methodName}: ${rows.length} results for a '
            'method that returns one (use First or Top, or return a List)',
      );
    }
    return rows.first;
  }

  // Emits [rows] when the stream is listened to.
  Stream<T> _emit(Future<List<T>> Function() rows) async* {
    yield* Stream<T>.fromIterable(await rows());
  }

  /// Runs [body], letting a `DataAccessException` through and wrapping
  /// any other error in one.
  Future<R> _guarded<R>(Future<R> Function() body) async {
    try {
      return await body();
    } on DataAccessException {
      rethrow;
    } on TransactionException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(_translate(error), stackTrace);
    }
  }

  // A write: atomic, and part of the caller's transaction when there is
  // one.
  Future<R> _write<R>(Future<R> Function() body) =>
      _guarded(() => _inTransaction(body));

  /// Runs [body] in a `required` transaction of the store: joins the
  /// caller's, or begins one that commits when [body] completes and rolls
  /// back when it fails.
  Future<R> _inTransaction<R>(Future<R> Function() body) {
    final manager = transactionManager;
    if (manager == null) {
      return body();
    }
    return runInTransaction<R>(
      manager,
      TransactionDefinition(name: '$typeName.write'),
      (_) => body(),
    );
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

  Criteria _byId(ID id) => Criteria(_idPredicate, [id]);

  Future<T> _save(T instance) async {
    final isNew = isNewStrategy.isNew(entity, instance);
    var toSave = instance;
    if (auditing case final handler?) {
      toSave = isNew
          ? await handler.markCreated<T>(entity, toSave)
          : await handler.markModified<T>(entity, toSave);
    }
    return await (isNew
        ? store.insert<T>(entity, toSave)
        : store.update<T>(entity, toSave));
  }

  Future<void> _delete(T instance) async {
    final id = converter.idOf(entity, instance);
    if (id == null) {
      throw InvalidDataAccessApiUsageException(
        'Cannot delete ${entity.introspection.className}: its id is null',
      );
    }
    final version = entity.versionProperty?.getValue(instance);
    await store.deleteById<T>(entity, id, expectedVersion: version);
  }

  // --------------------------------------------------------------- logging

  void _called(String method, List<String> names, List<Object?> arguments) {
    if (_log.isEnabled(SpringLogLevel.debug)) {
      _log.debug('$typeName.$method');
    }
    if (_log.isEnabled(SpringLogLevel.trace)) {
      _log.trace(
        '$typeName.$method(${LogValues.arguments(names, arguments)})',
      );
    }
  }

  // A derived query: the arguments are named after the properties of the
  // parts that take them.
  void _calledTree(
    PartTree tree,
    List<Object?> arguments, {
    Sort? sort,
    Pageable? pageable,
  }) {
    if (_log.isEnabled(SpringLogLevel.trace)) {
      _called(
        tree.methodName,
        [
          for (final part in tree.parts)
            for (var i = 0; i < part.type.argumentCount; i++) part.property,
          if (sort != null) 'sort',
          if (pageable != null) 'pageable',
        ],
        [...arguments, ?sort, ?pageable],
      );
    } else {
      _called(tree.methodName, const [], const []);
    }
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
