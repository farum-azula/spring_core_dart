import 'package:spring_core_dart_generator/src/sql_lexer.dart';

/// A table or view the build knows: its name and its columns.
///
/// [complete] says whether the columns are all of them. A table whose
/// definition the build did not fully understand (`create table x (like
/// y)`, `alter table x add (a int, b int)`, a view that selects `*`) is not
/// complete: what is not in its [columns] may be there, so nothing is said
/// about a column it lacks.
///
/// Spring (Java): none; the metadata a `DatabaseMetaData` gives.
final class SchemaTable {
  /// A table or view called [name], with no column yet.
  SchemaTable(this.name, {this.isView = false});

  /// The name, as first written.
  String name;

  /// Whether this is a view.
  final bool isView;

  /// Whether [columns] are all the columns there are.
  bool complete = true;

  final _columns = <String, String>{};

  /// The columns, as first written, in the order they were added.
  Iterable<String> get columns => _columns.values;

  /// Whether the table has a column called [name] (in any case).
  bool hasColumn(String name) => _columns.containsKey(name.toLowerCase());

  /// Adds the column [name], once.
  void addColumn(String name) =>
      _columns.putIfAbsent(name.toLowerCase(), () => name);

  /// Adds the columns of [other], another definition of this table that may
  /// be the one that runs: the table is complete only if both are.
  void merge(SchemaTable other) {
    complete &= other.complete;
    other.columns.forEach(addColumn);
  }

  /// Removes the column [name]; a column that is not there leaves the table
  /// incomplete (it was added in a way the build did not read).
  void dropColumn(String name) {
    if (_columns.remove(name.toLowerCase()) == null) {
      complete = false;
    }
  }

  /// Renames the column [from] to [to].
  void renameColumn(String from, String to) {
    if (_columns.remove(from.toLowerCase()) == null) {
      complete = false;
    }
    addColumn(to);
  }

  @override
  String toString() =>
      '${isView ? 'view' : 'table'} $name(${columns.join(', ')})';
}

/// How the data layer treats a property of an entity.
enum EntityPropertyKind {
  /// Stored in a column of the entity's table.
  column,

  /// `@Transient`: not stored.
  transient,

  /// A `@MappedCollection`: stored in the children's table.
  collection,
}

/// A property of an [EntityDescription].
final class EntityProperty {
  /// The property [name] of [kind]; [column] is the name `@Column` gives.
  const EntityProperty(
    this.name,
    this.kind, {
    this.column,
    this.idColumn,
    this.keyColumn,
    this.child,
  });

  /// The Dart name.
  final String name;

  /// How it is stored.
  final EntityPropertyKind kind;

  /// The column `@Column` gives, or `null` for the default.
  final String? column;

  /// For a collection, the column of the children holding the root's id
  /// (`@MappedCollection(idColumn:)`), or `null` for the default.
  final String? idColumn;

  /// For a collection, the column holding a child's position or key
  /// (`@MappedCollection(keyColumn:)`), or `null` for the default.
  final String? keyColumn;

  /// For a collection, the class name of its children.
  final String? child;
}

/// A `@Table` class as the build sees it: the names of its table and
/// columns, as the annotations give them.
///
/// Spring (Java): `RelationalPersistentEntity`.
final class EntityDescription {
  /// The class [className] (declared in [library]) with its [properties];
  /// [table] is the name `@Table` gives, or `null` for the default.
  const EntityDescription(
    this.className,
    this.library,
    this.properties, {
    this.table,
  });

  /// The class name, as `{Book}` writes it.
  final String className;

  /// The library that declares the class, to tell two classes of one name
  /// apart.
  final String library;

  /// The name `@Table` gives, or `null` for the class name in snake case.
  final String? table;

  /// The properties, in declaration order.
  final List<EntityProperty> properties;

  /// The property called [name], or `null`.
  EntityProperty? property(String name) {
    for (final property in properties) {
      if (property.name == name) {
        return property;
      }
    }
    return null;
  }
}

/// The tables, views and columns the build knows of the application's
/// database: those its entities say, and those its migrations and init
/// scripts create, in the order they run.
///
/// Used to find a misspelled table or column in a `@Query`, so everything
/// here leans toward knowing too much: a column both an entity and a
/// migration name is known, a statement the build does not understand
/// leaves its table incomplete, and a table that was dropped but is mapped
/// by an entity stays known.
///
/// ```dart
/// final schema = DataSchema()
///   ..apply('create table books (id integer primary key, title text);')
///   ..apply('alter table books add column year integer;');
/// schema.table('BOOKS')!.columns; // id, title, year
/// ```
///
/// Spring (Java): none; Flyway and Hibernate know the schema when they run.
final class DataSchema {
  /// A schema with no table.
  DataSchema();

  /// The schema the scripts of [variants] make: for each alternative (the
  /// migrations of one database, of which one runs) its scripts in the order
  /// they run. A table is known when any alternative has it, with the
  /// columns any gives it, and is complete only if it is so in every
  /// alternative that has it.
  factory DataSchema.fromScripts(Iterable<Iterable<String>> variants) {
    final union = DataSchema();
    for (final scripts in variants) {
      final schema = DataSchema();
      scripts.forEach(schema.apply);
      union._merge(schema);
    }
    return union;
  }

  void _merge(DataSchema other) {
    unknownTables |= other.unknownTables;
    for (final MapEntry(:key, :value) in other._tables.entries) {
      final known = _tables[key];
      if (known == null) {
        _tables[key] = SchemaTable(value.name, isView: value.isView)
          ..merge(value);
      } else {
        known.merge(value);
      }
    }
  }

  final _tables = <String, SchemaTable>{};

  /// Whether the build knows the schema well enough to look for typos:
  /// `false` when the application keeps migrations the build cannot read.
  bool reliable = true;

  /// Whether a statement of a migration created, changed or dropped a table
  /// whose name the build could not read (`create table ${table}`): any
  /// table name may be one of those, and every known table may have more
  /// columns than the build knows.
  bool unknownTables = false;

  final _entities = <String, List<EntityDescription>>{};

  /// The table or view called [name] (in any case), or `null`.
  SchemaTable? table(String name) => _tables[name.toLowerCase()];

  /// The names of the tables and views.
  Iterable<String> get tableNames => [for (final t in _tables.values) t.name];

  /// The entities called [className]; more than one when two classes of
  /// different libraries share a name.
  List<EntityDescription> entities(String className) =>
      _entities[className] ?? const [];

  /// Every entity.
  Iterable<EntityDescription> get allEntities =>
      _entities.values.expand((e) => e);

  /// The table of [entity] as the build can tell, or `null` when the name
  /// comes from a naming strategy the build does not know.
  SchemaTable? tableOf(EntityDescription entity) {
    final name =
        entity.table ?? (_customNaming ? null : snakeCase(entity.className));
    return name == null ? null : table(name);
  }

  bool _customNaming = false;

  /// Reads [sql], the text of a migration or an init script: `create
  /// table`, `create view`, `alter table`, `drop table`, `drop view`. Any
  /// other statement is skipped, and what is not understood in these
  /// leaves their table incomplete.
  void apply(String sql) {
    _statements(SqlLexer.tokenize(sql)).forEach(_statement);
  }

  /// Adds the tables and columns of [entities], then the columns of the
  /// children tables of their collections.
  ///
  /// With [customNaming] (the application declares its own naming strategy)
  /// a name the entity does not spell out, a table or column named by
  /// default, is not known: the table is incomplete.
  void addEntities(
    Iterable<EntityDescription> entities, {
    bool customNaming = false,
  }) {
    _customNaming = customNaming;
    final list = entities.toList();
    for (final entity in list) {
      _entities.putIfAbsent(entity.className, () => []).add(entity);
    }
    final created = <SchemaTable>{};
    for (final entity in list) {
      final name = _tableName(entity);
      if (name == null) {
        continue;
      }
      var table = this.table(name);
      if (table == null) {
        // A migration the build could not read may have made it, with more.
        table = _tables[name.toLowerCase()] = SchemaTable(name)
          ..complete = !unknownTables;
        created.add(table);
      }
      for (final property in entity.properties) {
        if (property.kind != EntityPropertyKind.column) {
          continue;
        }
        final column = property.column ?? _derived(snakeCase(property.name));
        if (column == null) {
          if (created.contains(table)) {
            table.complete = false;
          }
        } else {
          table.addColumn(column);
        }
      }
    }
    for (final entity in list) {
      final root = _tableName(entity);
      for (final property in entity.properties) {
        if (property.kind != EntityPropertyKind.collection ||
            property.child == null) {
          continue;
        }
        for (final child in this.entities(property.child!)) {
          final name = _tableName(child);
          if (name == null) {
            continue;
          }
          final table = this.table(name)!;
          final id =
              property.idColumn ??
              (root == null ? null : _derived('${root}_id'));
          final key =
              property.keyColumn ??
              (root == null ? null : _derived('${root}_key'));
          for (final column in [id, key]) {
            if (column != null) {
              table.addColumn(column);
            } else if (created.contains(table)) {
              table.complete = false;
            }
          }
        }
      }
    }
  }

  String? _tableName(EntityDescription entity) =>
      entity.table ?? _derived(snakeCase(entity.className));

  // A name the default strategy gives; unknown to the build when the
  // application replaces the strategy.
  String? _derived(String name) => _customNaming ? null : name;

  /// [name] in snake case, as the starter's `NamingStrategy` writes it:
  /// `OrderLine` is `order_line`, `HTTPRequest` is `http_request`, `authorId`
  /// is `author_id`.
  static String snakeCase(String name) {
    bool isUpper(String c) => c != c.toLowerCase();
    bool isLower(String c) => c != c.toUpperCase();
    bool isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
    final out = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final c = name[i];
      if (isUpper(c) && i > 0) {
        final previous = name[i - 1];
        final nextIsLower = i + 1 < name.length && isLower(name[i + 1]);
        if (isLower(previous) ||
            isDigit(previous) ||
            (isUpper(previous) && nextIsLower)) {
          out.write('_');
        }
      }
      out.write(c.toLowerCase());
    }
    return out.toString();
  }

  // ----------------------------------------------------------- statements

  static List<List<SqlToken>> _statements(List<SqlToken> tokens) {
    final statements = <List<SqlToken>>[];
    var current = <SqlToken>[];
    var depth = 0;
    for (final token in tokens) {
      if (token.isSymbol('(')) {
        depth++;
      } else if (token.isSymbol(')')) {
        depth--;
      }
      if (token.isSymbol(';') && depth <= 0) {
        depth = 0;
        statements.add(current);
        current = [];
      } else {
        current.add(token);
      }
    }
    statements.add(current);
    return statements;
  }

  void _statement(List<SqlToken> t) {
    if (t.isEmpty || !t.first.isName) {
      return;
    }
    final words = [
      for (final token in t.take(12))
        if (token.kind == SqlTokenKind.word) token.lower,
    ];
    switch (t.first.lower) {
      case 'create':
        var i = 1;
        const modifiers = {
          'or', 'replace', 'temp', 'temporary', 'global', 'local', 'unlogged',
          'virtual', 'materialized', 'recursive', //
        };
        while (i < t.length &&
            t[i].kind == SqlTokenKind.word &&
            modifiers.contains(t[i].lower)) {
          i++;
        }
        if (i >= t.length || t[i].kind != SqlTokenKind.word) {
          return;
        }
        switch (t[i].lower) {
          case 'table':
            _createTable(t, i + 1);
          case 'view':
            _createView(t, i + 1);
        }
      case 'alter':
        if (words.length > 1 && words[1] == 'table') {
          _alterTable(t);
        }
      case 'drop':
        if (words.length > 1 && (words[1] == 'table' || words[1] == 'view')) {
          _drop(t);
        }
    }
  }

  // `if not exists` at [i]; the index after it.
  static int _skipIfNotExists(List<SqlToken> t, int i) {
    if (i + 2 < t.length &&
        t[i].isWord('if') &&
        t[i + 1].isWord('not') &&
        t[i + 2].isWord('exists')) {
      return i + 3;
    }
    return i;
  }

  static int _skipIfExists(List<SqlToken> t, int i) {
    if (i + 1 < t.length && t[i].isWord('if') && t[i + 1].isWord('exists')) {
      return i + 2;
    }
    return i;
  }

  // The name at [i], `a`, `a.b` or `a.b.c`, as its last part, and the index
  // after it; `null` when there is none (a symbol), or when a `${property}`
  // makes the table's own name (`${table}`, `books_${year}`): the table is
  // then unknown, see [_unknownTable]. A qualifier may be a property
  // (`${schema}.books`).
  static (String, int)? _name(List<SqlToken> t, int i) {
    bool part(int j) =>
        j < t.length && (t[j].isName || t[j].kind == SqlTokenKind.property);
    if (!part(i)) {
      return null;
    }
    var last = i;
    while (last + 2 < t.length && t[last + 1].isSymbol('.') && part(last + 2)) {
      last += 2;
    }
    bool touches(int j) =>
        j >= 0 &&
        j < t.length &&
        t[j].kind == SqlTokenKind.property &&
        (j > last ? t[j].start == t[last].end : t[j].end == t[last].start);
    if (!t[last].isName || touches(last + 1) || touches(last - 1)) {
      return null;
    }
    return (t[last].value, last + 1);
  }

  /// Notes that a statement is about a table the build cannot name, when
  /// [t] has a `${property}`: every known table may have more columns now.
  void _unknownTable(List<SqlToken> t) {
    if (!t.any((token) => token.kind == SqlTokenKind.property)) {
      return;
    }
    unknownTables = true;
    for (final table in _tables.values) {
      table.complete = false;
    }
  }

  void _createTable(List<SqlToken> t, int from) {
    final afterIf = _skipIfNotExists(t, from);
    final read = _name(t, afterIf);
    if (read == null) {
      _unknownTable(t);
      return;
    }
    final (name, after) = read;
    // `if not exists` leaves a table that is there as it is, with the
    // columns later statements gave it.
    if (afterIf != from && this.table(name) != null) {
      return;
    }
    final table = _tables[name.toLowerCase()] = SchemaTable(name);
    if (after < t.length && t[after].isSymbol('(')) {
      final close = _closing(t, after);
      for (final item in _split(t.sublist(after + 1, close))) {
        _columnDefinition(table, item);
      }
      // `inherits (parent)`, `partition of ...`: more columns than written.
      for (final token in t.skip(close + 1)) {
        if (token.isWord('inherits')) {
          table.complete = false;
        }
      }
      return;
    }
    // `create table x as select ...`.
    if (after < t.length && t[after].isWord('as')) {
      final (columns, complete) = selectColumns(t.sublist(after + 1));
      columns.forEach(table.addColumn);
      table.complete = complete;
      return;
    }
    table.complete = false;
  }

  // The words that begin a table constraint.
  static const _constraintWords = {
    'constraint', 'primary', 'unique', 'check', 'foreign', 'exclude', //
  };

  // The words that begin an index definition in MySQL (`key idx (a)`).
  static const _indexWords = {'key', 'index', 'fulltext', 'spatial'};

  // Types a column may have with arguments: `key varchar(16)` is a column
  // called `key`, not an index called `varchar`.
  static const _typeWords = {
    'varchar', 'char', 'character', 'nvarchar', 'nchar', 'varchar2', //
    'numeric', 'decimal', 'dec', 'number', 'float', 'double', 'real', 'bit',
    'varbinary', 'binary', 'timestamp', 'time', 'datetime', 'interval',
    'int', 'integer', 'bigint', 'smallint', 'tinyint', 'mediumint', 'text',
    'blob', 'varying',
  };

  // Whether [item], a definition in `create table (...)` (or the action of
  // an `alter table` after `add`), is a table constraint or an index and no
  // column: it begins with a word of one and goes on as that does
  // (`primary key (a)`, `check (...)`, `unique key u (b)`, `key idx (a)`).
  // A column that is called `key`, `check` or `period` goes on with its
  // type (`period varchar(16)`).
  static bool _isConstraint(List<SqlToken> item) {
    final first = item.first;
    if (first.kind != SqlTokenKind.word) {
      return false;
    }
    final second = item.length > 1 ? item[1] : null;
    final third = item.length > 2 ? item[2] : null;
    // An index of a name: `key idx (a)`, but not `key varchar(16)`.
    final named =
        second != null &&
        second.isName &&
        !_typeWords.contains(second.lower) &&
        third != null &&
        third.isSymbol('(');
    final indexed =
        second != null &&
        (second.isSymbol('(') ||
            second.isWord('key') ||
            second.isWord('index') ||
            named);
    return switch (first.lower) {
      'constraint' => true,
      'primary' || 'foreign' => second?.isWord('key') ?? false,
      'check' => second?.isSymbol('(') ?? false,
      'exclude' =>
        second != null && (second.isSymbol('(') || second.isWord('using')),
      'unique' || 'key' || 'index' || 'fulltext' || 'spatial' => indexed,
      'period' => second?.isWord('for') ?? false,
      _ => false,
    };
  }

  void _columnDefinition(SchemaTable table, List<SqlToken> item) {
    if (item.isEmpty || _isConstraint(item)) {
      return;
    }
    final first = item.first;
    if (first.isWord('like')) {
      table.complete = false;
    } else if (first.isName) {
      table.addColumn(first.value);
    } else {
      table.complete = false;
    }
  }

  void _createView(List<SqlToken> t, int from) {
    final afterIf = _skipIfNotExists(t, from);
    final read = _name(t, afterIf);
    if (read == null) {
      _unknownTable(t);
      return;
    }
    final (name, after) = read;
    if (afterIf != from && table(name) != null) {
      return;
    }
    final view = _tables[name.toLowerCase()] = SchemaTable(name, isView: true);
    var i = after;
    if (i < t.length && t[i].isSymbol('(')) {
      final close = _closing(t, i);
      for (final item in _split(t.sublist(i + 1, close))) {
        if (item.length == 1 && item.single.isName) {
          view.addColumn(item.single.value);
        } else {
          view.complete = false;
        }
      }
      return;
    }
    while (i < t.length && !t[i].isWord('as')) {
      i++;
    }
    if (i >= t.length) {
      view.complete = false;
      return;
    }
    final (columns, complete) = selectColumns(t.sublist(i + 1));
    columns.forEach(view.addColumn);
    view.complete = complete;
  }

  void _alterTable(List<SqlToken> t) {
    var i = 2;
    i = _skipIfExists(t, i);
    if (i < t.length && t[i].isWord('only')) {
      i++;
    }
    final read = _name(t, i);
    if (read == null) {
      _unknownTable(t);
      return;
    }
    final (name, after) = read;
    // A table not created in the files the build reads is incomplete.
    var table =
        this.table(name) ??
        (_tables[name.toLowerCase()] = SchemaTable(name)..complete = false);
    for (final action in _split(t.sublist(after))) {
      table = _alterAction(table, action);
    }
  }

  // One action of an `alter table`; the table, which `rename to` replaces.
  SchemaTable _alterAction(SchemaTable table, List<SqlToken> a) {
    if (a.isEmpty || a.first.kind != SqlTokenKind.word) {
      return table..complete = false;
    }
    bool isWord(int i, String word) => i < a.length && a[i].isWord(word);
    bool isName(int i) => i < a.length && a[i].isName;
    switch (a.first.lower) {
      case 'add':
        var i = 1;
        final explicit = isWord(i, 'column');
        if (explicit) {
          i++;
        }
        if (!explicit && i < a.length && _isConstraint(a.sublist(i))) {
          return table;
        }
        if (isWord(i, 'if') &&
            isWord(i + 1, 'not') &&
            isWord(i + 2, 'exists')) {
          i += 3;
        }
        if (isName(i)) {
          table.addColumn(a[i].value);
        } else {
          table.complete = false;
        }
      case 'drop':
        var i = 1;
        final explicit = isWord(i, 'column');
        if (explicit) {
          i++;
        }
        // `drop constraint c`, `drop primary key`, `drop index i`: something
        // after the word; a lone `drop key` drops a column.
        if (!explicit &&
            i + 1 < a.length &&
            a[i].kind == SqlTokenKind.word &&
            (_constraintWords.contains(a[i].lower) ||
                _indexWords.contains(a[i].lower))) {
          return table;
        }
        if (isWord(i, 'if') && isWord(i + 1, 'exists')) {
          i += 2;
        }
        if (isName(i)) {
          table.dropColumn(a[i].value);
        } else {
          table.complete = false;
        }
      case 'rename':
        if (isWord(1, 'to') && isName(2)) {
          _tables.remove(table.name.toLowerCase());
          table.name = a[2].value;
          _tables[table.name.toLowerCase()] = table;
          return table;
        }
        var i = 1;
        if (a.length > 1 &&
            a[1].kind == SqlTokenKind.word &&
            const {'constraint', 'index', 'key'}.contains(a[1].lower)) {
          return table;
        }
        if (isWord(i, 'column')) {
          i++;
        }
        if (isName(i) && isWord(i + 1, 'to') && isName(i + 2)) {
          table.renameColumn(a[i].value, a[i + 2].value);
        } else {
          table.complete = false;
        }
      case 'change':
        var i = 1;
        if (isWord(i, 'column')) {
          i++;
        }
        if (isName(i) && isName(i + 1)) {
          table.renameColumn(a[i].value, a[i + 1].value);
        } else {
          table.complete = false;
        }
      case 'alter' ||
          'modify' ||
          'set' ||
          'owner' ||
          'enable' ||
          'disable' ||
          'validate' ||
          'cluster' ||
          'no' ||
          'force' ||
          'attach' ||
          'detach' ||
          'inherit' ||
          'replica':
        break;
      default:
        table.complete = false;
    }
    return table;
  }

  void _drop(List<SqlToken> t) {
    final view = t[1].isWord('view');
    var i = _skipIfExists(t, 2);
    while (true) {
      final read = _name(t, i);
      if (read == null) {
        _unknownTable(t);
        return;
      }
      final (name, after) = read;
      final existing = table(name);
      if (existing != null && existing.isView == view) {
        _tables.remove(name.toLowerCase());
      }
      if (after < t.length && t[after].isSymbol(',')) {
        i = after + 1;
      } else {
        return;
      }
    }
  }

  // The index of the `)` that closes the `(` at [open]; the end of [t] when
  // there is none.
  static int _closing(List<SqlToken> t, int open) {
    var depth = 0;
    for (var i = open; i < t.length; i++) {
      if (t[i].isSymbol('(')) {
        depth++;
      } else if (t[i].isSymbol(')')) {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    return t.length;
  }

  // [t] cut at the commas outside parentheses.
  static List<List<SqlToken>> _split(List<SqlToken> t) {
    final items = <List<SqlToken>>[];
    var current = <SqlToken>[];
    var depth = 0;
    for (final token in t) {
      if (token.isSymbol('(')) {
        depth++;
      } else if (token.isSymbol(')')) {
        depth--;
      }
      if (token.isSymbol(',') && depth == 0) {
        items.add(current);
        current = [];
      } else {
        current.add(token);
      }
    }
    if (current.isNotEmpty) {
      items.add(current);
    }
    return items;
  }

  /// The names of the columns the first `select` of [tokens] gives, and
  /// whether they are all of the columns.
  ///
  /// A column is named by its `as` alias, by a trailing alias, or by the
  /// column it selects (`a.title`). A `*` or an expression with no alias
  /// leaves the list incomplete.
  static (List<String>, bool) selectColumns(List<SqlToken> tokens) {
    var depth = 0;
    var start = -1;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.isSymbol('(')) {
        depth++;
      } else if (token.isSymbol(')')) {
        depth--;
      } else if (depth == 0 && token.isWord('select')) {
        start = i + 1;
        break;
      }
    }
    if (start < 0) {
      return (const [], false);
    }
    var i = start;
    if (i < tokens.length &&
        (tokens[i].isWord('distinct') || tokens[i].isWord('all'))) {
      i++;
      if (i < tokens.length &&
          tokens[i].isWord('on') &&
          i + 1 < tokens.length &&
          tokens[i + 1].isSymbol('(')) {
        i = _closing(tokens, i + 1) + 1;
      }
    }
    final list = <SqlToken>[];
    depth = 0;
    for (; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.isSymbol('(')) {
        depth++;
      } else if (token.isSymbol(')')) {
        depth--;
      } else if (depth == 0 &&
          token.kind == SqlTokenKind.word &&
          const {
            'from',
            'union',
            'intersect',
            'except',
            'where',
            'into',
          }.contains(token.lower)) {
        break;
      } else if (depth == 0 && token.isSymbol(';')) {
        break;
      }
      list.add(token);
    }
    final names = <String>[];
    var complete = true;
    for (final item in _split(list)) {
      final name = columnNameOf(item);
      if (name == null) {
        complete = false;
      } else {
        names.add(name);
      }
    }
    return (names, complete);
  }

  /// The name a select-list [item] gives its column, or `null` when it has
  /// none the build can read (`*`, `count(*)`, `a + b`).
  static String? columnNameOf(List<SqlToken> item) {
    if (item.isEmpty) {
      return null;
    }
    final last = item.last;
    if (!last.isName) {
      return null;
    }
    if (item.length == 1) {
      return last.value;
    }
    final before = item[item.length - 2];
    if (before.isWord('as') || before.isSymbol('.')) {
      return last.value;
    }
    return endsOperand(before) && !_operatorWords.contains(last.lower)
        ? last.value
        : null;
  }

  // Words that stand between operands, so a name after one of them is no
  // alias.
  static const _operatorWords = {
    'and', 'or', 'not', 'is', 'in', 'like', 'ilike', 'between', 'when', 'then',
    'else', 'case', 'select', 'distinct', 'all', 'any', 'some', 'exists',
    'escape', 'collate', 'glob', 'regexp', 'match', 'similar', 'to', 'interval',
    'on', 'by', 'from', 'as', 'null', 'true', 'false', 'asc', 'desc', //
  };

  /// Whether [token] can end an operand, so a name right after it is an
  /// alias (`title t`, `count(*) c`, `case ... end c`).
  static bool endsOperand(SqlToken token) => switch (token.kind) {
    SqlTokenKind.word => !_operatorWords.contains(token.lower),
    SqlTokenKind.quoted ||
    SqlTokenKind.string ||
    SqlTokenKind.number ||
    SqlTokenKind.parameter ||
    SqlTokenKind.expression ||
    SqlTokenKind.property ||
    SqlTokenKind.entity => true,
    SqlTokenKind.symbol => token.text == ')' || token.text == ']',
    _ => false,
  };
}
