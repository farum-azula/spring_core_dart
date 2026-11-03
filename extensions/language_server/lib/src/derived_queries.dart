import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/data_model.dart';
import 'package:dart_spring_language_server/src/repository_scan.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:spring_core_dart_generator/query_syntax.dart';

/// A derived query method of a repository, read against its entity.
final class _Derived {
  _Derived(this.method, this.parameters, this.entity, this.tree, this.problem);

  final MethodDeclaration method;
  final List<ParameterInfo> parameters;
  final EntityView entity;

  /// The name read as a query; `null` when [problem] says it cannot be.
  final PartTreeModel? tree;
  final QueryProblem? problem;

  String get name => method.name.lexeme;
}

/// The editor support for the derived queries of a repository
/// (`findByTitleAndYearGreaterThan`, `countByAuthor`, `deleteByYearLessThan`,
/// `OrderBy...`): the name is read with the rules the build reads it with
/// (`PartTreeReader`), against the entity of the repository. An unknown
/// property is an error with "did you mean", a hover tells the SQL the name
/// stands for, and the property part of the name goes to the entity's field.
final class DerivedQueryEditor {
  /// An editor over [workspace].
  DerivedQueryEditor(this.workspace);

  /// The workspace.
  final SpringWorkspace workspace;

  DataModel get _data => workspace.data;

  static final _by = RegExp(
    '^(find|read|get|query|search|stream|count|exists|delete|remove)'
    r'((\p{Lu}.*?))??By',
    unicode: true,
  );

  // The derived methods of [file] whose repository has a known entity.
  List<_Derived> _methods(DartFile file, String path) {
    final result = <_Derived>[];
    for (final repository in repositoriesIn(file)) {
      final entityName = _data.entityOf(repository.declaration, path);
      final entity = entityName == null ? null : _data.entity(entityName, path);
      if (entity == null) {
        continue;
      }
      for (final (method, parameters) in repository.derived) {
        final name = method.name.lexeme;
        if (!PartTreeReader.isDerivedQuery(name)) {
          result.add(_Derived(method, parameters, entity, null, null));
          continue;
        }
        if (!entity.complete) {
          continue;
        }
        try {
          result.add(
            _Derived(
              method,
              parameters,
              entity,
              const PartTreeReader().parse(name, entity),
              null,
            ),
          );
        } on QueryProblem catch (problem) {
          result.add(_Derived(method, parameters, entity, null, problem));
        }
      }
    }
    return result;
  }

  // Where each property of the name is, after `By`: `(property, start, end)`
  // as offsets into the method name.
  static List<(String, int, int)> _propertySpans(
    String name,
    PartTreeModel tree,
  ) {
    var cursor = _by.firstMatch(name)?.end ?? 0;
    final result = <(String, int, int)>[];
    for (final property in [
      for (final part in tree.parts) part.property,
      for (final order in tree.sort) order.property,
    ]) {
      final written = property[0].toUpperCase() + property.substring(1);
      final at = name.indexOf(written, cursor);
      if (at < 0) {
        continue;
      }
      result.add((property, at, at + written.length));
      cursor = at + written.length;
    }
    return result;
  }

  /// The problems of the derived query methods of [file].
  List<Problem> problems(DartFile file, String path) {
    final problems = <Problem>[];
    for (final derived in _methods(file, path)) {
      final name = derived.name;
      final start = derived.method.name.offset;
      void report(int from, int to, String message, {bool error = true}) =>
          problems.add(
            Problem(
              workspace.rangeOf(file, from, to),
              message,
              error: error,
            ),
          );
      if (!PartTreeReader.isDerivedQuery(name)) {
        report(
          start,
          start + name.length,
          "'$name' is not a derived query and has no @Query: a method of a "
          'repository must start with find, read, get, query, search, '
          'stream, count, exists, delete or remove, and then "By" '
          '(or have a @Query)',
          error: false,
        );
        continue;
      }
      final problem = derived.problem;
      if (problem != null) {
        var from = start;
        var to = start + name.length;
        if (problem.property case final property?) {
          final written = property[0].toUpperCase() + property.substring(1);
          final at = name.indexOf(written, _by.firstMatch(name)?.end ?? 0);
          if (at >= 0) {
            from = start + at;
            to = from + written.length;
          }
        }
        report(from, to, problem.reason);
        continue;
      }
      final tree = derived.tree!;
      final values = derived.parameters.where((p) => !p.isSpecial).length;
      if (values != tree.parameterCount) {
        report(
          start,
          start + name.length,
          'The name needs ${tree.parameterCount} parameter(s) besides Sort '
          'and Pageable, but the method declares $values',
        );
      }
    }
    return problems;
  }

  /// Where go to definition leads from [offset] of [file]: the entity field
  /// of the property part of a derived query's name. `null` when [offset]
  /// is not on such a name.
  List<SourceRange>? definition(DartFile file, String path, int offset) {
    final found = _at(file, path, offset);
    if (found == null) {
      return null;
    }
    final (derived, at) = found;
    if (derived.tree case final tree?) {
      for (final (property, start, end) in _propertySpans(derived.name, tree)) {
        if (at >= start && at <= end) {
          if (derived.entity.property(property) case final view?) {
            return _data.locateProperty(view, path);
          }
        }
      }
    }
    return const [];
  }

  /// The hover at [offset] of [file]: a property of the name, or the SQL
  /// the whole name stands for. `null` outside a derived query's name.
  String? hover(DartFile file, String path, int offset) {
    final found = _at(file, path, offset);
    if (found == null) {
      return null;
    }
    final (derived, at) = found;
    final tree = derived.tree;
    if (tree == null) {
      return null;
    }
    for (final (property, start, end) in _propertySpans(derived.name, tree)) {
      if (at >= start && at <= end) {
        if (derived.entity.property(property) case final view?) {
          final column = view.column == null
              ? 'column named by the naming strategy'
              : 'column `${view.column}`';
          return '**${derived.entity.name}.${view.name}**: $column, type '
              '`${view.type}`';
        }
      }
    }
    return [
      '**${derived.name}**: derived query of `${derived.entity.name}`',
      '',
      '```sql',
      describe(tree, derived.entity, [
        for (final p in derived.parameters)
          if (!p.isSpecial) p.name,
      ]),
      '```',
    ].join('\n');
  }

  (_Derived, int)? _at(DartFile file, String path, int offset) {
    for (final derived in _methods(file, path)) {
      final token = derived.method.name;
      if (offset >= token.offset && offset <= token.end) {
        return (derived, offset - token.offset);
      }
    }
    return null;
  }

  /// The SQL a derived query stands for, roughly: [names] are the method's
  /// parameters, bound in order by the parts of the name.
  static String describe(
    PartTreeModel tree,
    EntityView entity,
    List<String> names,
  ) {
    final table = entity.table ?? DataSchema.snakeCase(entity.name);
    String column(String property) =>
        entity.property(property)?.column ?? DataSchema.snakeCase(property);
    var next = 0;
    String argument() => next < names.length ? ':${names[next++]}' : '?';

    String condition(PartModel part) {
      var c = column(part.property);
      String a() => part.ignoreCase ? 'lower(${argument()})' : argument();
      if (part.ignoreCase) {
        c = 'lower($c)';
      }
      return switch (part.kind) {
        PartKind.between => () {
          final from = a();
          return '$c between $from and ${a()}';
        }(),
        PartKind.isNotNull => '$c is not null',
        PartKind.isNull => '$c is null',
        PartKind.lessThan => '$c < ${a()}',
        PartKind.lessThanEqual => '$c <= ${a()}',
        PartKind.greaterThan => '$c > ${a()}',
        PartKind.greaterThanEqual => '$c >= ${a()}',
        PartKind.notLike => '$c not like ${a()}',
        PartKind.like => '$c like ${a()}',
        PartKind.startingWith => "$c like ${a()} || '%'",
        PartKind.endingWith => "$c like '%' || ${a()}",
        PartKind.notContaining => "$c not like '%' || ${a()} || '%'",
        PartKind.containing => "$c like '%' || ${a()} || '%'",
        PartKind.notIn => '$c not in (${a()})',
        PartKind.in_ => '$c in (${a()})',
        PartKind.isTrue => '$c = true',
        PartKind.isFalse => '$c = false',
        PartKind.negatingSimpleProperty => '$c <> ${a()}',
        PartKind.simpleProperty => '$c = ${a()}',
      };
    }

    final groups = [
      for (final or in tree.predicate) or.parts.map(condition).join(' and '),
    ];
    final grouped =
        groups.length > 1 && tree.predicate.any((o) => o.parts.length > 1);
    final joined = (grouped ? [for (final g in groups) '($g)'] : groups).join(
      ' or ',
    );
    final where = groups.isEmpty ? '' : ' where $joined';
    final sorted = [
      for (final o in tree.sort)
        '${column(o.property)}${o.descending ? ' desc' : ''}',
    ];
    final order = sorted.isEmpty ? '' : ' order by ${sorted.join(', ')}';
    final limit = tree.subject.maxResults == null
        ? ''
        : ' limit ${tree.subject.maxResults}';
    final distinct = tree.subject.distinct ? 'distinct ' : '';
    return switch (tree.subject.kind) {
      SubjectKind.find => 'select $distinct* from $table$where$order$limit',
      SubjectKind.count => 'select count(*) from $table$where',
      SubjectKind.exists => 'select 1 from $table$where limit 1',
      SubjectKind.delete => 'delete from $table$where',
    };
  }
}
