import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/annotations.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';
import 'package:spring_boot_starter_data/src/mapping/naming_strategy.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_method.dart';
import 'package:spring_boot_starter_data/src/repository/query/query_result_mapper.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/data_store_capabilities.dart';
import 'package:spring_boot_starter_data/src/store/function_data_store.dart';

/// What the run time needs to know of a `@Procedure` method: its annotation,
/// its parameters, the shape of its result.
///
/// The build writes one for each `@Procedure` method of a repository and hands
/// them to `RepositoryFactory.operations` as its `functions`; the
/// generated method calls `RepositoryOperations.procedure` (or
/// `procedureStream`) with it.
///
/// ```dart
/// // For: @Procedure('accounts_over')
/// //      Future<List<Account>> over(int balance);
/// static const _over = ProcedureMethod(
///   r'over',
///   Procedure(r'accounts_over'),
///   parameters: [r'balance'],
///   element: ClassType<Account>(),
/// );
/// ```
///
/// Spring (Java):
/// `org.springframework.data.jpa.repository.query.StoredProcedureAttributes`
/// (what Spring Data JPA keeps of a `@Procedure` method).
final class ProcedureMethod {
  /// The method [name] annotated with [procedure].
  ///
  /// [parameters] are the names of its parameters, in order: each is an
  /// argument of the function, named in snake case. [shape] is the shape
  /// of the result (`list`, `set`, `stream` or `single`) and [element] the
  /// type of what one row becomes (the type itself for a single result);
  /// a method that returns nothing (`Future<void>`) has no [element].
  const ProcedureMethod(
    this.name,
    this.procedure, {
    this.parameters = const [],
    this.shape = QueryShape.list,
    this.element,
  });

  /// The name of the method.
  final String name;

  /// The annotation: the name of the function.
  final Procedure procedure;

  /// The names of the parameters, in order.
  final List<String> parameters;

  /// The shape of the result.
  final QueryShape shape;

  /// The type of what one row becomes; null for a method that returns
  /// nothing.
  final TypeInfo<Object?>? element;

  @override
  String toString() => 'ProcedureMethod($name)';
}

/// Runs a repository method's `@Procedure`: the database function of the
/// annotation, called through the store with the method's arguments by
/// name, its rows read as the rows of a `@Query` are (the same
/// [QueryResultMapper]).
///
/// What depends on the run time is checked when the repository is created
/// ([compile]), and reported with its other problems: the store has
/// database functions, the result can be built from rows, the shape is
/// one a function has (not a `Page` or a `Slice`: a function is not
/// windowed).
///
/// - **Arguments**: the name of each parameter in snake case, by the
///   naming strategy of the mapping (`accountId` → `account_id`), with the
///   value the method was called with (the store converts it).
/// - **Results**: the repository's entity (read by the store with its
///   children when it is a `RowReadingDataStore`, else by the entity
///   converter from the columns of each row), a described class from the
///   columns by name, a simple type from the single column; as a `List`, a
///   `Set`, a `Stream` (the rows are read first, then emitted), one value,
///   or nothing.
///
/// Spring (Java):
/// `org.springframework.data.jpa.repository.query.StoredProcedureJpaQuery`.
final class FunctionQuery {
  FunctionQuery._(
    this._where,
    this._store,
    this._entity,
    this._method,
    this._result,
    this._arguments,
    this._translateError,
  );

  /// Compiles the `@Procedure` of [method] on [entity] for [store], or returns
  /// null after adding to [problems] every mistake found.
  ///
  /// [translateError] wraps what a stream fails with in a
  /// `DataAccessException`; [introspector] and [mappingContext] describe
  /// the classes the rows become; [naming] names the arguments.
  static FunctionQuery? compile({
    required String typeName,
    required ProcedureMethod method,
    required PersistentEntity<Object> entity,
    required DataStore store,
    required EntityConverter converter,
    required DataAccessException Function(Object error) translateError,
    required List<String> problems,
    BeanIntrospector? introspector,
    RelationalMappingContext? mappingContext,
    NamingStrategy? naming,
  }) {
    final where = '$typeName.${method.name}';
    var before = problems.length;
    final missing = StoreRequirement(
      method.name,
      DataStoreCapability.functions,
    ).problemWith(typeName, store);
    if (missing != null) {
      // Once, also when the build wrote the same requirement.
      if (problems.contains(missing)) {
        before--;
      } else {
        problems.add(missing);
      }
    } else if (store is! FunctionDataStore) {
      problems.add(
        '$where: the ${store.name} store says it has database functions '
        'but is no FunctionDataStore',
      );
    }
    if (method.shape == QueryShape.page || method.shape == QueryShape.slice) {
      problems.add(
        '$where: @Procedure cannot return a ${method.shape.name}: a function '
        'is not windowed; return a List, or give the function a limit and '
        'an offset as arguments',
      );
    }
    final result = QueryResultMapper.of(
      where: where,
      element: method.element,
      entity: entity,
      converter: converter,
      introspector: introspector ?? converter.introspector,
      problems: problems,
      reader: store is RowReadingDataStore ? store.valueReader : null,
      mappingContext: mappingContext,
    );
    if (problems.length > before || store is! FunctionDataStore) {
      return null;
    }
    final names = mappingContext?.namingStrategy ?? naming;
    return FunctionQuery._(
      where,
      store,
      entity,
      method,
      result,
      [
        for (final parameter in method.parameters)
          (names ?? const NamingStrategy()).snakeCase(parameter),
      ],
      translateError,
    );
  }

  final String _where;
  final FunctionDataStore _store;
  final PersistentEntity<Object> _entity;
  final ProcedureMethod _method;
  final QueryResultMapper _result;

  // The names of the function's arguments, in the order of the parameters.
  final List<String> _arguments;
  final DataAccessException Function(Object error) _translateError;

  /// Whether the method returns a `Stream` (its [call] returns the stream
  /// itself, not a `Future`).
  bool get isStream => _method.shape == QueryShape.stream;

  /// The names of the function's arguments, in the order of the method's
  /// parameters.
  List<String> get argumentNames => List.unmodifiable(_arguments);

  /// Calls the function with the method's [arguments]: a `Future` of the
  /// result, or for a `Stream` method the stream (which calls the function
  /// when listened to).
  Object? call(List<Object?> arguments) {
    if (isStream) {
      return _result.shaper.streamOf(_stream(arguments));
    }
    return _run(arguments);
  }

  Stream<Object?> _stream(List<Object?> arguments) async* {
    try {
      yield* Stream<Object?>.fromIterable(await _rows(arguments));
    } on DataAccessException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      Error.throwWithStackTrace(_translateError(error), stackTrace);
    }
  }

  Future<Object?> _run(List<Object?> arguments) async {
    if (_method.element == null) {
      await _call(arguments);
      return null;
    }
    return _result.shaped(_method.shape, await _rows(arguments));
  }

  Future<List<Map<String, Object?>>> _call(List<Object?> arguments) {
    if (arguments.length != _arguments.length) {
      throw InvalidDataAccessApiUsageException(
        '$_where: ${arguments.length} argument(s) for '
        '${_arguments.length} parameter(s)',
      );
    }
    return _store.callFunction(_method.procedure.name, {
      for (final (index, name) in _arguments.indexed) name: arguments[index],
    });
  }

  // What each row of the function's result becomes.
  Future<List<Object?>> _rows(List<Object?> arguments) async {
    final rows = _jdbcRows(await _call(arguments));
    if (_result.kind == QueryResultKind.entity) {
      return switch (_store) {
        final RowReadingDataStore reader => await reader.readAggregates<Object>(
          _entity,
          rows,
        ),
        _ => [
          for (final row in rows) _result.converter.read(_entity, row.toMap()),
        ],
      };
    }
    final mapper = _result.rowMapper();
    return [for (final row in rows) mapper(row)];
  }

  // The rows as a result set: rows with the same columns share their list
  // of columns, as the rows of a driver do (the mappers plan once for it).
  static List<JdbcRow> _jdbcRows(List<Map<String, Object?>> rows) {
    List<String>? columns;
    return [
      for (final row in rows)
        JdbcRow(columns = _columnsOf(row, columns), row.values.toList()),
    ];
  }

  static List<String> _columnsOf(Map<String, Object?> row, List<String>? last) {
    if (last != null && last.length == row.length) {
      var index = 0;
      if (row.keys.every((key) => key == last[index++])) {
        return last;
      }
    }
    return row.keys.toList();
  }

  @override
  String toString() => 'FunctionQuery($_where)';
}
