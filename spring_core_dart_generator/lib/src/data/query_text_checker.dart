import 'package:spring_core_dart_generator/src/data_schema.dart';
import 'package:spring_core_dart_generator/src/did_you_mean.dart';
import 'package:spring_core_dart_generator/src/sql_lexer.dart';

/// What the build learned from the text of one `@Query`.
final class QueryTextResult {
  /// A result: the text has the `:#{...}` markers [expressions] and names
  /// the entities [entities] in `{Entity}` placeholders.
  const QueryTextResult(
    this.expressions,
    this.entities, [
    this.unresolved = const {},
  ]);

  /// The expressions of the `:#{...}` markers of the text, in text order
  /// (trimmed, without `:#{` and `}`).
  final List<String> expressions;

  /// The class names of the entities `{Entity}` and `{Entity.property}`
  /// placeholders name.
  final Set<String> entities;

  /// The class names the placeholders name that are no `@Table` class of
  /// the application and close to none: an entity of another module or
  /// package the build cannot tell, which the run time resolves (or fails
  /// to, with a message).
  final Set<String> unresolved;
}

/// Checks the SQL text of a `@Query` once, when the application is built:
/// everything that does not depend on the run time.
///
/// - **Parameters.** Each `:name` is a parameter of the method (`names`,
///   those a `Pageable` or `Sort` is not); `:#{expression}` is a value
///   computed from the method's arguments; a plain `?` and a `#{...}` that
///   is not `#{#entityName}` are refused; an expression that is not closed
///   is refused.
/// - **Entity placeholders.** `{Book}` is the table of the entity `Book`
///   and `{Book.authorId}` the column of its property: `Book` must be a
///   `@Table` class and `authorId` a stored property (not `@Transient`, not
///   a `@MappedCollection`). The run time writes the names, as the entity's
///   mapping gives them. A name that is no `@Table` class of the module is
///   an error only when a class of the module is close to it (a typo); else
///   it may be an entity of another module, which the build cannot see
///   (see `QueryTextResult.unresolved`).
/// - **Typos.** A table after `from`, `join`, `update`, `into` or `delete
///   from`, a qualified `alias.column`, and an unqualified column that the
///   schema does not know are errors only when a name the schema does know
///   is close (see `closestName`): `books.titel: no column titel in books,
///   did you mean 'title'?`. A name that is far from every known one is
///   left alone: it may be a table the build cannot see, a function, a
///   keyword of the database.
///
/// What the check cannot know is left alone: `${property}` placeholders
/// (which the run time resolves), tables and views it knows only by name,
/// columns of a derived table it cannot read (`select *`).
///
/// Spring (Java): none; Spring resolves `@Query` strings when the
/// repository is created. IntelliJ's SQL inspections do the same checks.
final class QueryTextChecker {
  /// A checker against [schema].
  QueryTextChecker(this.schema);

  /// The entities, tables and columns the build knows.
  final DataSchema schema;

  /// Checks [text]: [names] are the method's parameters that are bound by
  /// name, in order. Each problem is given to [problem] as `[where]: ...`,
  /// where [where] is `Repository.method` or `Repository.method
  /// (countQuery)`.
  QueryTextResult check(
    String text, {
    required String where,
    required List<String> names,
    required void Function(String problem) problem,
  }) {
    void report(String reason) => problem('$where: $reason');
    final tokens = SqlLexer.tokenize(text);
    final expressions = <String>[];
    var plainMarker = false;
    final unknown = <String>{};
    final entities = <String>{};
    final unresolved = <String>{};
    for (final token in tokens) {
      switch (token.kind) {
        case SqlTokenKind.unclosed:
          final end = token.start + 30 > text.length
              ? text.length
              : token.start + 30;
          report(
            'an expression is not closed: ${text.substring(token.start, end)}',
          );
        case SqlTokenKind.elExpression when token.value != '#entityName':
          report(
            '#{${token.value}} is not allowed in the SQL text: only '
            '#{#entityName} is; to bind a value write :#{${token.value}}',
          );
        case SqlTokenKind.expression:
          expressions.add(token.value);
        case SqlTokenKind.question:
          plainMarker = true;
        case SqlTokenKind.badParameter:
          report(token.value);
        case SqlTokenKind.parameter when !names.contains(token.value):
          if (unknown.add(token.value)) {
            final hint = token.value.contains('.')
                ? ' (to read a property write :#{#${token.value}})'
                : '';
            report(
              ':${token.value} matches no parameter of the method (it has '
              '${names.isEmpty ? 'none' : names.join(', ')})$hint',
            );
          }
        case SqlTokenKind.entity:
          _entity(token, entities, unresolved, report);
        case _:
          break;
      }
    }
    if (plainMarker) {
      report(
        'the query has a plain ? marker: write :name and bind it by the '
        'name of a parameter of the method',
      );
    }
    if (schema.reliable) {
      _SchemaChecker(tokens, schema, report).run();
    }
    return QueryTextResult(expressions, entities, unresolved);
  }

  // `{Book}` and `{Book.authorId}`: the class is a `@Table` of the
  // application, the property one of its stored properties.
  void _entity(
    SqlToken token,
    Set<String> entities,
    Set<String> unresolved,
    void Function(String) report,
  ) {
    final name = token.value;
    final matches = schema.entities(name);
    final shown = token.text;
    if (matches.isEmpty) {
      // The entities of other modules are not in the schema: only a name
      // that is close to one of these is a typo.
      final near = closestName(name, [
        for (final entity in schema.allEntities) entity.className,
      ]);
      if (near == null) {
        unresolved.add(name);
      } else {
        report(
          '$shown: no @Table class $name in the application, did you mean '
          "'$near'?",
        );
      }
      return;
    }
    if (matches.length > 1) {
      report(
        '$shown: $name names ${matches.length} @Table classes '
        '(${matches.map((e) => e.library).join(', ')}): rename one',
      );
      return;
    }
    entities.add(name);
    final member = token.member;
    if (member == null) {
      return;
    }
    final entity = matches.single;
    final property = entity.property(member);
    if (property == null) {
      final stored = [
        for (final p in entity.properties)
          if (p.kind == EntityPropertyKind.column) p.name,
      ];
      final near = closestName(member, stored);
      report(
        '$shown: $name has no property $member'
        "${near == null ? '' : ", did you mean '$near'?"} "
        '(stored properties: ${stored.join(', ')})',
      );
    } else if (property.kind == EntityPropertyKind.transient) {
      report(
        '$shown: $name.$member is @Transient: it has no column',
      );
    } else if (property.kind == EntityPropertyKind.collection) {
      report(
        '$shown: $name.$member is a @MappedCollection: its rows are in the '
        'table of its children, not in a column of $name',
      );
    }
  }
}

// What a name in the FROM clause gives the query: the names it is known by
// (its alias, its table), the columns it has.
final class _Relation {
  _Relation(this.names, this.label, this.columns, {required this.complete});

  // Lower case.
  final Set<String> names;

  // What a message calls it.
  final String label;

  final List<String> columns;

  // Whether `columns` are all of them.
  final bool complete;

  bool has(String column) {
    final lower = column.toLowerCase();
    return columns.any((c) => c.toLowerCase() == lower);
  }
}

// A statement, or a subquery, or one side of a union: the tokens
// `[start, end)` that are its own and the relations its FROM names.
final class _Scope {
  _Scope(this.parent, this.start, this.end);

  final _Scope? parent;
  final int start;
  final int end;
  final relations = <_Relation>[];
}

// The typo detection of `QueryTextChecker`: a pass over the tokens of one
// query that learns its scopes, relations and aliases, then looks at every
// name once.
//
// Everything in it leans toward silence: a name is only wrong when it is
// unknown to every relation in sight (all of them known down to their
// columns) and some known name is close to it.
final class _SchemaChecker {
  _SchemaChecker(this.t, this.schema, this.report);

  final List<SqlToken> t;
  final DataSchema schema;
  final void Function(String) report;

  // The index of the `)` of each `(`.
  final _close = <int, int>{};

  // The `(` of each parenthesis that opens a subquery.
  final _queryGroups = <int>{};

  // Tokens that are definitions or relations, not column references.
  final _consumed = <int>{};

  // The `)` of the parentheses of a parenthesized join, `from (a join b on
  // ...)`: its items belong to the query, the parentheses are no group.
  final _transparent = <int>{};

  // Lower-case names the query defines: aliases (of columns, relations,
  // window), the names and columns of CTEs.
  final _defined = <String>{};

  // The CTE names, lower case, by the relation they are.
  final _ctes = <String, _Relation>{};

  final _scopes = <_Scope>[];
  final _pending = <_Scope>[];

  void run() {
    _matchParentheses();
    _markTypes();
    _segments(null, 0, t.length);
    for (var i = 0; i < _pending.length; i++) {
      _build(_pending[i]);
    }
    _scopes.forEach(_look);
  }

  void _matchParentheses() {
    final open = <int>[];
    for (var i = 0; i < t.length; i++) {
      if (t[i].isSymbol('(')) {
        open.add(i);
      } else if (t[i].isSymbol(')') && open.isNotEmpty) {
        final from = open.removeLast();
        _close[from] = i;
        if (i > from + 1 && _opensStatement(t[from + 1])) {
          _queryGroups.add(from);
        }
      }
    }
  }

  // Whether [token], the first after a `(`, makes the group a statement of
  // its own: a subquery, a `values` list, or the data-changing statement of a
  // CTE.
  static bool _opensStatement(SqlToken token) =>
      token.kind == SqlTokenKind.word &&
      const {
        'select', 'with', 'values', 'insert', 'update', 'delete', 'merge', //
      }.contains(token.lower);

  // The scopes of the tokens `[start, end)`: one for each side of a union
  // (or of a `;`).
  void _segments(_Scope? parent, int start, int end) {
    var from = start;
    var i = start;
    var compound = false;
    while (i < end) {
      if (_queryGroups.contains(i)) {
        i = _close[i]! + 1;
        continue;
      }
      final token = t[i];
      if (token.isSymbol('(')) {
        // A group that is no subquery: skip it whole, its unions are its own.
        i = (_close[i] ?? i) + 1;
        continue;
      }
      if (token.isSymbol(';') ||
          token.isWord('union') ||
          token.isWord('intersect') ||
          token.isWord('except')) {
        compound = !token.isSymbol(';');
        _add(parent, from, i);
        from = i + 1;
      }
      i++;
    }
    if (compound) {
      _leaveTail(from, end);
    }
    _add(parent, from, end);
  }

  // The `order by`, `limit`, `offset` or `fetch` that ends the last side of
  // a union belongs to the whole union: it names the columns the union gives
  // (those of its first side, or an alias), not those of the last side, so
  // its names are not looked at.
  void _leaveTail(int from, int end) {
    var i = from;
    while (i < end) {
      if (t[i].isSymbol('(')) {
        i = (_close[i] ?? i) + 1;
        continue;
      }
      if (t[i].isWord('order') ||
          t[i].isWord('limit') ||
          t[i].isWord('offset') ||
          t[i].isWord('fetch')) {
        _consumed.addAll([for (var j = i; j < end; j++) j]);
        return;
      }
      i++;
    }
  }

  // The names of types in casts, `x::geography(Point, 4326)` and `cast(x as
  // citext)`: names of the database, no columns.
  void _markTypes() {
    void leave(int from, int end) {
      var j = from;
      while (j < end && t[j].isName) {
        _consumed.add(j);
        j++;
        if (j + 1 < end && t[j].isSymbol('.') && t[j + 1].isName) {
          j++;
        } else {
          break;
        }
      }
      if (j < end && t[j].isSymbol('(')) {
        for (var k = j; k <= (_close[j] ?? j); k++) {
          _consumed.add(k);
        }
      }
    }

    for (var i = 0; i < t.length; i++) {
      if (t[i].isSymbol('::')) {
        leave(i + 1, t.length);
      } else if (t[i].isWord('cast') &&
          i + 1 < t.length &&
          t[i + 1].isSymbol('(')) {
        final close = _close[i + 1] ?? t.length;
        var depth = 0;
        for (var j = i + 2; j < close; j++) {
          if (t[j].isSymbol('(')) {
            depth++;
          } else if (t[j].isSymbol(')')) {
            depth--;
          } else if (depth == 0 && t[j].isWord('as')) {
            leave(j + 1, close);
            break;
          }
        }
      }
    }
  }

  void _add(_Scope? parent, int start, int end) {
    if (end <= start) {
      return;
    }
    final scope = _Scope(parent, start, end);
    _scopes.add(scope);
    _pending.add(scope);
  }

  // ------------------------------------------------------------- building

  // Words that end a FROM clause.
  static const _endsFrom = {
    'where', 'group', 'having', 'order', 'limit', 'offset', 'window', //
    'returning', 'set', 'values', 'select', 'fetch', 'for', 'union',
    'intersect', 'except',
  };

  void _build(_Scope scope) {
    String? statement;
    var inFrom = false;
    var depth = 0;
    var i = scope.start;
    while (i < scope.end) {
      if (_queryGroups.contains(i)) {
        _segments(scope, i + 1, _close[i]!);
        i = _close[i]! + 1;
        continue;
      }
      final token = t[i];
      if (token.isSymbol('(')) {
        depth++;
      } else if (token.isSymbol(')')) {
        if (_transparent.contains(i)) {
          i = _joinAlias(scope, i + 1);
          continue;
        }
        depth--;
      }
      if (depth > 0 || token.kind != SqlTokenKind.word) {
        if (depth == 0 && inFrom && token.isSymbol(',')) {
          i = _relation(scope, i + 1);
          continue;
        }
        i++;
        continue;
      }
      final word = token.lower;
      switch (word) {
        case 'with':
          i = _with(scope, i + 1);
          continue;
        case 'select':
          statement ??= word;
          _selectList(scope, i + 1);
          inFrom = false;
        case 'returning':
          _selectList(scope, i + 1);
          inFrom = false;
        case 'constraint' when i + 1 < scope.end && t[i + 1].isName:
          // `on conflict on constraint uq_title`.
          _consumed.add(i + 1);
        case 'indexed'
            when i + 2 < scope.end && t[i + 1].isWord('by') && t[i + 2].isName:
          // SQLite's `indexed by ix_title`.
          _consumed.add(i + 2);
        case 'of'
            when i > 0 &&
                (t[i - 1].isWord('update') || t[i - 1].isWord('share')):
          // `for update of books, authors`.
          for (var j = i + 1; j < scope.end && t[j].isName; j += 2) {
            _consumed.add(j);
            if (j + 1 >= scope.end || !t[j + 1].isSymbol(',')) {
              break;
            }
          }
        case 'insert' || 'replace' || 'delete' || 'merge':
          statement ??= word;
        case 'update' when statement == null:
          statement = word;
          var j = i + 1;
          if (j + 1 < scope.end && t[j].isWord('or')) {
            j += 2;
          }
          i = _relation(scope, j, target: true);
          inFrom = false;
          continue;
        case 'from' when !(i > scope.start && t[i - 1].isWord('distinct')):
          inFrom = true;
          i = _relation(scope, i + 1);
          continue;
        case 'join':
          i = _relation(scope, i + 1);
          continue;
        case 'into' when statement == 'insert' || statement == 'replace':
          i = _relation(scope, i + 1, target: true);
          continue;
        case 'using' when statement == 'delete':
          if (i + 1 < scope.end && !t[i + 1].isSymbol('(')) {
            inFrom = true;
            i = _relation(scope, i + 1);
            continue;
          }
        case 'window':
          if (i + 1 < scope.end && t[i + 1].isName) {
            _define(i + 1);
          }
          inFrom = false;
        case _:
          if (_endsFrom.contains(word)) {
            inFrom = false;
          }
      }
      i++;
    }
  }

  // `with a as (...), b(x, y) as (...)`: registers each CTE, returns the
  // index after the definitions.
  int _with(_Scope scope, int from) {
    var i = from;
    if (i < scope.end && t[i].isWord('recursive')) {
      i++;
    }
    while (i < scope.end && t[i].isName) {
      final name = t[i];
      _define(i);
      i++;
      List<String>? columns;
      if (i < scope.end && t[i].isSymbol('(') && !_queryGroups.contains(i)) {
        final close = _close[i] ?? i;
        columns = [
          for (var j = i + 1; j < close; j++)
            if (t[j].isName) t[j].value,
        ];
        for (var j = i + 1; j < close; j++) {
          if (t[j].isName) {
            _define(j);
          }
        }
        i = close + 1;
      }
      if (i < scope.end && t[i].isWord('as')) {
        i++;
      }
      if (i < scope.end && t[i].isWord('not')) {
        i++;
      }
      if (i < scope.end && t[i].isWord('materialized')) {
        i++;
      }
      if (i < scope.end && _queryGroups.contains(i)) {
        final body = t.sublist(i + 1, _close[i]);
        // A `values` list or a data-changing statement gives columns the
        // build cannot read (what `returning` lists, `column1`).
        final select = t[i + 1].isWord('select') || t[i + 1].isWord('with');
        final (read, complete) = select
            ? DataSchema.selectColumns(body)
            : (const <String>[], false);
        _segments(scope, i + 1, _close[i]!);
        _ctes[name.lower] = _Relation(
          {name.lower},
          name.value,
          columns ?? read,
          complete: columns != null || complete,
        );
        i = _close[i]! + 1;
      } else if (i < scope.end && t[i].isSymbol('(')) {
        _ctes[name.lower] = _Relation(
          {name.lower},
          name.value,
          columns ?? const [],
          complete: columns != null,
        );
        i = (_close[i] ?? i) + 1;
      } else {
        _ctes[name.lower] = _Relation(
          {name.lower},
          name.value,
          const [],
          complete: false,
        );
      }
      if (i < scope.end && t[i].isSymbol(',')) {
        i++;
      } else {
        break;
      }
    }
    return i;
  }

  // The aliases of a select list that starts at [from].
  void _selectList(_Scope scope, int from) {
    var depth = 0;
    var itemStart = from;
    void item(int end) {
      if (end - itemStart >= 2) {
        final last = t[end - 1];
        final before = t[end - 2];
        if (last.isName &&
            (before.isWord('as') ||
                (!before.isSymbol('.') && DataSchema.endsOperand(before)))) {
          _define(end - 1);
        }
      }
      itemStart = end + 1;
    }

    var i = from;
    if (i < scope.end && (t[i].isWord('distinct') || t[i].isWord('all'))) {
      i++;
      itemStart = i;
    }
    for (; i < scope.end; i++) {
      final token = t[i];
      if (token.isSymbol('(')) {
        depth++;
      } else if (token.isSymbol(')')) {
        depth--;
      } else if (depth == 0 &&
          (token.isSymbol(',') ||
              (token.kind == SqlTokenKind.word &&
                  (token.lower == 'from' ||
                      token.lower == 'into' ||
                      token.lower == 'where')))) {
        item(i);
        if (!token.isSymbol(',')) {
          return;
        }
      }
    }
    item(scope.end);
  }

  void _define(int index) {
    _consumed.add(index);
    _defined.add(t[index].lower);
  }

  // A name that is no alias: a word of the language, or one that ends a
  // FROM item.
  bool _isKeyword(SqlToken token) =>
      token.kind == SqlTokenKind.word && _keywords.contains(token.lower);

  // The end of a name that placeholders and words make together
  // (`${schema}.books`, `books_${year}`): the index after the one that
  // starts at [from].
  int _nameEnd(int from, int end) {
    var i = from + 1;
    while (i < end) {
      final token = t[i];
      final touching =
          token.start == t[i - 1].end &&
          (token.kind == SqlTokenKind.property ||
              token.isName ||
              token.kind == SqlTokenKind.number);
      final dotted =
          token.isSymbol('.') &&
          i + 1 < end &&
          (t[i + 1].kind == SqlTokenKind.property || t[i + 1].isName);
      if (touching) {
        i++;
      } else if (dotted) {
        i += 2;
      } else {
        break;
      }
    }
    return i;
  }

  // The alias of a parenthesized join, `(a join b on ...) as j`, read from
  // [from]; the index after it. The columns of the alias are not known.
  int _joinAlias(_Scope scope, int from) {
    var i = from;
    final explicit = i < scope.end && t[i].isWord('as');
    if (explicit) {
      i++;
    }
    if (i < scope.end && t[i].isName && (explicit || !_isKeyword(t[i]))) {
      _define(i);
      scope.relations.add(
        _Relation({t[i].lower}, t[i].value, const [], complete: false),
      );
      return i + 1;
    }
    return from;
  }

  // One FROM item (a table, a subquery, a function) with its alias, read
  // from [from]; the index after it.
  int _relation(_Scope scope, int from, {bool target = false}) {
    var i = from;
    while (i < scope.end &&
        (t[i].isWord('lateral') ||
            t[i].isWord('only') ||
            t[i].isWord('natural'))) {
      i++;
    }
    if (i >= scope.end) {
      return i;
    }
    final token = t[i];
    String label;
    var names = <String>{};
    var columns = <String>[];
    var complete = false;
    if (_queryGroups.contains(i)) {
      final body = t.sublist(i + 1, _close[i]);
      (columns, complete) = t[i + 1].isWord('select') || t[i + 1].isWord('with')
          ? DataSchema.selectColumns(body)
          : (const <String>[], false);
      _segments(scope, i + 1, _close[i]!);
      label = 'the subquery';
      i = _close[i]! + 1;
    } else if (token.isSymbol('(')) {
      // A parenthesized join, `(a join b on ...)`: its items are the
      // query's own, read in place. The `)` is no end of a group.
      final close = _close[i];
      if (close == null) {
        return i + 1;
      }
      _transparent.add(close);
      return _relation(scope, i + 1);
    } else if (token.kind == SqlTokenKind.entity) {
      final entity = schema.entities(token.value);
      final table = entity.length == 1 ? schema.tableOf(entity.single) : null;
      label = table?.name ?? token.value;
      if (table != null) {
        names.add(table.name.toLowerCase());
        columns = table.columns.toList();
        complete = table.complete;
      }
      i++;
    } else if ((token.isName || token.kind == SqlTokenKind.property) &&
        _hasPlaceholder(i, _nameEnd(i, scope.end))) {
      // `${schema}.books`, `books_${year}`: a name the run time writes.
      final end = _nameEnd(i, scope.end);
      for (var j = i; j < end; j++) {
        _consumed.add(j);
      }
      label = 'a relation';
      i = end;
    } else if (token.isName) {
      // `a`, `a.b`, `a.b.c`: the table is the last part.
      var last = i;
      while (last + 2 < scope.end &&
          t[last + 1].isSymbol('.') &&
          t[last + 2].isName) {
        last += 2;
      }
      for (var j = i; j <= last; j++) {
        _consumed.add(j);
      }
      final name = t[last];
      final qualified = last > i;
      i = last + 1;
      if (!target && i < scope.end && t[i].isSymbol('(')) {
        // A table function: its columns are its own.
        label = name.value;
        i = (_close[i] ?? i) + 1;
        // `with ordinality` adds a column.
        if (i + 1 < scope.end &&
            t[i].isWord('with') &&
            t[i + 1].isWord('ordinality')) {
          i += 2;
        }
      } else {
        final table = schema.table(name.value);
        final cte = qualified ? null : _ctes[name.lower];
        label = table?.name ?? name.value;
        if (cte != null) {
          names = {name.lower};
          columns = cte.columns;
          complete = cte.complete;
        } else if (table != null) {
          names = {table.name.toLowerCase()};
          columns = table.columns.toList();
          complete = table.complete;
        } else {
          names = {name.lower};
          if (!qualified &&
              !_defined.contains(name.lower) &&
              !schema.unknownTables) {
            final near = closestName(name.value, schema.tableNames);
            if (near != null) {
              report(
                '${name.value}: no table ${name.value}, '
                "did you mean '$near'?",
              );
            }
          }
        }
      }
    } else {
      // Something else: columns nobody can tell.
      scope.relations.add(
        _Relation(const {}, 'a relation', const [], complete: false),
      );
      return i;
    }
    // The alias, and the names it gives the columns.
    var explicit = false;
    if (i < scope.end && t[i].isWord('as')) {
      explicit = true;
      i++;
    }
    String? alias;
    if (i < scope.end && t[i].isName && (explicit || !_isKeyword(t[i]))) {
      alias = t[i].lower;
      _define(i);
      names.add(alias);
      i++;
      if (i < scope.end && t[i].isSymbol('(') && !_queryGroups.contains(i)) {
        final close = _close[i] ?? i;
        columns = [
          for (var j = i + 1; j < close; j++)
            if (t[j].isName) t[j].value,
        ];
        complete = true;
        for (var j = i + 1; j < close; j++) {
          if (t[j].isName) {
            _define(j);
          }
        }
        i = close + 1;
      }
    }
    scope.relations.add(
      _Relation(
        names.isEmpty ? {?alias} : names,
        label,
        columns,
        complete: complete,
      ),
    );
    return i;
  }

  bool _hasPlaceholder(int from, int end) => [
    for (var j = from; j < end; j++) t[j],
  ].any((token) => token.kind == SqlTokenKind.property);

  // -------------------------------------------------------------- looking

  void _look(_Scope scope) {
    var i = scope.start;
    while (i < scope.end) {
      if (_queryGroups.contains(i)) {
        i = _close[i]! + 1;
        continue;
      }
      final token = t[i];
      if (!token.isName || _consumed.contains(i) || _isKeyword(token)) {
        i++;
        continue;
      }
      final before = i > 0 ? t[i - 1] : null;
      final after = i + 1 < t.length ? t[i + 1] : null;
      if (before != null &&
          (before.isSymbol('.') ||
              before.isSymbol('::') ||
              before.isWord('collate') ||
              ((before.isSymbol('@') || before.isSymbol(r'$')) &&
                  before.end == token.start))) {
        i++;
        continue;
      }
      if (after != null && after.isSymbol('(')) {
        i++;
        continue;
      }
      if (after != null &&
          after.isSymbol('.') &&
          i + 2 < t.length &&
          (t[i + 2].isName || t[i + 2].isSymbol('*'))) {
        // `a.b`, `a.*`; `a.b.c` and `a.f(...)` are left alone.
        final third = i + 3 < t.length ? t[i + 3] : null;
        if (third != null && (third.isSymbol('.') || third.isSymbol('('))) {
          i += 3;
          continue;
        }
        _qualified(scope, token, t[i + 2]);
        i += 3;
        continue;
      }
      _unqualified(scope, token);
      i++;
    }
  }

  // `q.c`: the column [column] of the relation [qualifier] names.
  void _qualified(_Scope scope, SqlToken qualifier, SqlToken column) {
    final name = qualifier.lower;
    final seen = <String>[];
    for (var s = scope as _Scope?; s != null; s = s.parent) {
      for (final relation in s.relations) {
        if (relation.names.contains(name)) {
          if (column.isName &&
              relation.complete &&
              !relation.has(column.value)) {
            final near = closestName(column.value, relation.columns);
            if (near != null) {
              report(
                '${qualifier.value}.${column.value}: no column '
                '${column.value} in ${relation.label}, '
                "did you mean '$near'?",
              );
            }
          }
          return;
        }
        seen.addAll(relation.names);
      }
    }
    if (_defined.contains(name) || _ctes.containsKey(name)) {
      return;
    }
    final near = closestName(qualifier.value, seen);
    if (near != null) {
      report(
        '${qualifier.value}.${column.value}: no table or alias '
        "${qualifier.value} here, did you mean '$near'?",
      );
    }
  }

  // A name by itself: a column of a relation in sight, or an alias.
  void _unqualified(_Scope scope, SqlToken token) {
    if (_defined.contains(token.lower)) {
      return;
    }
    final relations = <_Relation>[];
    for (var s = scope as _Scope?; s != null; s = s.parent) {
      relations.addAll(s.relations);
    }
    if (relations.isEmpty || relations.any((r) => !r.complete)) {
      return;
    }
    if (relations.any((r) => r.has(token.value))) {
      return;
    }
    final columns = {for (final r in relations) ...r.columns}.toList();
    final near = closestName(token.value, columns);
    if (near != null) {
      final labels = {for (final r in relations) r.label}.join(', ');
      report(
        '${token.value}: no column ${token.value} in $labels, '
        "did you mean '$near'?",
      );
    }
  }

  // Words of the language (and of the usual dialects) that are no column:
  // a name here is never reported. A word a column is called too (`year`,
  // `key`) is only left unchecked.
  static const _keywords = {
    // clauses
    'select', 'from', 'where', 'group', 'by', 'having', 'order', 'limit',
    'offset', 'fetch', 'first', 'next', 'only', 'rows', 'row', 'union',
    'intersect', 'except', 'all', 'distinct', 'on', 'using', 'join', 'inner',
    'left', 'right', 'full', 'outer', 'cross', 'natural', 'lateral', 'as',
    'with', 'recursive', 'materialized', 'insert', 'into', 'values', 'update',
    'set', 'delete', 'replace', 'returning', 'merge', 'matched', 'conflict',
    'do', 'nothing', 'default', 'create', 'alter', 'drop', 'table', 'view',
    'index', 'truncate', 'begin', 'commit', 'rollback', 'explain', 'analyze',
    'pragma', 'vacuum', 'for', 'share', 'nowait', 'skip', 'locked', 'key',
    'no', 'window', 'over', 'partition', 'range', 'groups', 'unbounded',
    'preceding', 'following', 'current', 'exclude', 'ties', 'others',
    'filter', 'within', 'ordinality', 'duplicate', 'ignore', 'abort', 'fail',
    'indexed',
    'if', 'temp', 'temporary', 'unlogged', 'virtual', 'global', 'local',
    'cascade', 'restrict', 'references', 'primary', 'foreign', 'unique',
    'check', 'constraint', 'tablespace', 'instead', 'of', 'after', 'before',
    'trigger', 'each', 'statement', 'also',
    // expressions
    'and', 'or', 'not', 'is', 'in', 'exists', 'between', 'like', 'ilike',
    'glob', 'regexp', 'rlike', 'similar', 'to', 'escape', 'any', 'some',
    'case', 'when', 'then', 'else', 'end', 'null', 'true', 'false', 'unknown',
    'asc', 'desc', 'nulls', 'last', 'collate', 'cast', 'interval', 'at',
    'time', 'zone', 'isnull', 'notnull', 'both', 'leading', 'trailing',
    'position', 'overlay', 'placing', 'extract', 'substring', 'trim',
    // types
    'int', 'integer', 'bigint', 'smallint', 'tinyint', 'mediumint', 'serial',
    'bigserial', 'real', 'double', 'precision', 'float', 'decimal', 'numeric',
    'number', 'boolean', 'bool', 'bit', 'char', 'character', 'varchar',
    'nvarchar', 'text', 'clob', 'blob', 'binary', 'varbinary', 'bytea',
    'date', 'timestamp', 'timestamptz', 'datetime', 'timetz', 'json',
    'jsonb', 'uuid', 'xml', 'money', 'array', 'varying', 'unsigned',
    'signed',
    // values the database provides
    'current_date', 'current_time', 'current_timestamp', 'localtime',
    'localtimestamp', 'current_user', 'session_user', 'system_user', 'user',
    'rowid', 'oid', 'ctid', 'rownum', 'sysdate', 'excluded', 'old', 'new',
    // parts of a date
    'year', 'month', 'day', 'hour', 'minute', 'second', 'week', 'quarter',
    'epoch', 'dow', 'doy', 'isodow', 'isoyear', 'millennium', 'century',
    'decade', 'microseconds', 'milliseconds', 'timezone', 'timezone_hour',
    'timezone_minute',
  };
}
