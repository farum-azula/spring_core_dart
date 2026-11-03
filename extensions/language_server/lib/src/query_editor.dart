import 'package:dart_spring_language_server/src/config_editor.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/data_model.dart';
import 'package:dart_spring_language_server/src/repository_scan.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
// The SpEL tokenizer is not exported: the checks read its tokens.
// ignore: implementation_imports
import 'package:spring_core_dart/src/expression/tokenizer.dart';
import 'package:spring_core_dart_generator/query_syntax.dart';

/// The words of SQL that are coloured as keywords.
const _keywords = {
  'add', 'all', 'alter', 'and', 'any', 'as', 'asc', 'between', 'by', 'case',
  'cast', 'check', 'column', 'constraint', 'create', 'cross', 'default',
  'delete', 'desc', 'distinct', 'drop', 'else', 'end', 'escape', 'except',
  'exists', 'false', 'fetch', 'first', 'for', 'foreign', 'from', 'full',
  'group', 'having', 'ilike', 'in', 'index', 'inner', 'insert', 'intersect',
  'into', 'is', 'join', 'key', 'last', 'left', 'like', 'limit', 'natural',
  'not', 'null', 'nulls', 'offset', 'on', 'only', 'or', 'order', 'outer',
  'over', 'partition', 'primary', 'references', 'returning', 'right', 'rows',
  'select', 'set', 'table', 'then', 'top', 'true', 'union', 'unique',
  'update', 'using', 'values', 'view', 'when', 'where', 'with', //
};

// Words after which a name is a table.
const _tableWords = {'from', 'join', 'into', 'update', 'table'};

// The variables every query expression has besides the parameters.
final _builtinVariable = RegExp(r'^(root|this|entityName|methodName|[pa]\d+)$');

/// A `@Query` text parsed once: its tokens, its comments and the names it
/// gives to tables.
final class _Parsed {
  _Parsed(this.query) : tokens = SqlLexer.tokenize(query.text) {
    var from = 0;
    final text = query.text;
    void gap(int end) {
      var i = from;
      while (i < end) {
        if (text.startsWith('--', i)) {
          final stop = text.indexOf('\n', i);
          final to = stop < 0 || stop > end ? end : stop;
          comments.add((i, to, true));
          i = to;
        } else if (text.startsWith('/*', i)) {
          final stop = text.indexOf('*/', i + 2);
          final to = stop < 0 ? text.length : stop + 2;
          comments.add((i, to, stop >= 0));
          i = to;
        } else {
          i++;
        }
      }
    }

    for (final token in tokens) {
      gap(token.start);
      from = token.end;
    }
    gap(text.length);
  }

  final QueryString query;
  final List<SqlToken> tokens;

  /// Comments as `(start, end, closed)`.
  final comments = <(int, int, bool)>[];

  /// The token covering [at] of the text, or `null`.
  int? indexAt(int at) {
    // The token that starts at [at] wins over the one that ends there.
    for (var i = 0; i < tokens.length; i++) {
      if (at >= tokens[i].start && at < tokens[i].end) {
        return i;
      }
    }
    for (var i = 0; i < tokens.length; i++) {
      if (at == tokens[i].end) {
        return i;
      }
    }
    return null;
  }
}

/// The editor support for the SQL of `@Query` methods of repositories
/// (`spring_boot_starter_data`): colours, navigation, hovers, completion and
/// checks. The SQL is cut into tokens by the lexer the build checks it with
/// (`SqlLexer`), so the editor and the build agree on what is a `:param`, a
/// `{Entity.property}` or a `:#{expression}`. The entities come from
/// [DataModel] (the source and the Spring metadata); the SpEL is read by
/// the SpEL editor, with the method's parameters as `#name` variables.
///
/// A text with an escape (`\n`) or an interpolation is not read: its offsets
/// would not map back to the file.
final class QueryEditor {
  /// An editor over [workspace].
  QueryEditor(this.workspace);

  /// The workspace.
  final SpringWorkspace workspace;

  DataModel get _data => workspace.data;

  final _cache = Expando<Map<QueryString, _Parsed>>('parsed queries');

  _Parsed _parsed(DartFile file, QueryString query) {
    final byQuery = _cache[file] ??= {};
    return byQuery[query] ??= _Parsed(query);
  }

  /// Whether the literal whose contents start at [contentsOffset] is part
  /// of a `@Query` text this editor reads; the generic annotation-string
  /// handling then leaves it alone.
  bool covers(DartFile file, int contentsOffset) => [
    for (final repository in repositoriesIn(file))
      for (final method in repository.queries)
        for (final text in method.texts)
          for (final segment in text.segments) segment.$2,
  ].contains(contentsOffset);

  // The query text and method at [offset] of [file].
  (QueryMethod, QueryString, int)? _at(DartFile file, int offset) {
    for (final repository in repositoriesIn(file)) {
      for (final method in repository.queries) {
        for (final text in method.texts) {
          if (text.textOffset(offset) case final at?) {
            return (method, text, at);
          }
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Colours
  // ---------------------------------------------------------------------

  /// Calls [add] with the file span and the semantic token type of each
  /// piece of every `@Query` text of [file]. A span may cover several
  /// lines.
  void tokens(DartFile file, void Function(int, int, String) add) {
    // A token must not span lines: a multi-line string or comment is cut.
    void addCut(int start, int end, String type) {
      var from = start;
      for (var i = start; i < end; i++) {
        if (file.text.codeUnitAt(i) == 10) {
          if (i > from) {
            add(from, i, type);
          }
          from = i + 1;
        }
      }
      if (end > from) {
        add(from, end, type);
      }
    }

    for (final repository in repositoriesIn(file)) {
      for (final method in repository.queries) {
        for (final text in method.texts) {
          final parsed = _parsed(file, text);
          void put(int start, int end, String type) {
            for (final (a, b) in text.pieces(start, end)) {
              addCut(a, b, type);
            }
          }

          for (final (start, end, _) in parsed.comments) {
            put(start, end, 'comment');
          }
          _colour(parsed, put);
        }
      }
    }
  }

  void _colour(_Parsed parsed, void Function(int, int, String) put) {
    final tokens = parsed.tokens;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final previous = i > 0 ? tokens[i - 1] : null;
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      final text = token.text;
      switch (token.kind) {
        case SqlTokenKind.word || SqlTokenKind.quoted:
          if (token.kind == SqlTokenKind.word &&
              _keywords.contains(token.lower)) {
            put(token.start, token.end, 'keyword');
          } else if (next != null &&
              next.isSymbol('(') &&
              next.start == token.end) {
            put(token.start, token.end, 'method');
          } else if (previous != null && previous.isSymbol('.')) {
            put(token.start, token.end, 'property');
          } else if (next != null && next.isSymbol('.')) {
            put(token.start, token.end, 'variable');
          } else if (previous != null &&
              previous.kind == SqlTokenKind.word &&
              _tableWords.contains(previous.lower)) {
            put(token.start, token.end, 'class');
          } else if (previous != null &&
              (previous.kind == SqlTokenKind.entity ||
                  previous.isWord('as') ||
                  (previous.isName &&
                      i >= 2 &&
                      tokens[i - 2].kind == SqlTokenKind.word &&
                      _tableWords.contains(tokens[i - 2].lower)))) {
            // `from {Book} b`, `from books b`, `select x as y`: an alias.
            put(token.start, token.end, 'variable');
          } else {
            put(token.start, token.end, 'property');
          }
        case SqlTokenKind.string:
          put(token.start, token.end, 'string');
        case SqlTokenKind.number:
          put(token.start, token.end, 'number');
        case SqlTokenKind.parameter:
          put(token.start, token.end, 'variable');
        case SqlTokenKind.entity:
          put(token.start, token.start + 1, 'operator');
          put(token.start + 1, token.start + 1 + token.value.length, 'class');
          if (token.member != null) {
            final memberStart = token.start + 2 + token.value.length;
            put(memberStart, memberStart + token.member!.length, 'property');
          }
          put(token.end - 1, token.end, 'operator');
        case SqlTokenKind.property:
          put(token.start, token.start + 2, 'operator');
          put(token.start + 2, token.end - 1, 'property');
          put(token.end - 1, token.end, 'operator');
        case SqlTokenKind.expression || SqlTokenKind.elExpression:
          final open = text.indexOf('{') + 1;
          put(token.start, token.start + open, 'keyword');
          workspace.spelTokens(
            text.substring(open, text.length - 1),
            token.start + open,
            put,
          );
          put(token.end - 1, token.end, 'keyword');
        case SqlTokenKind.question:
          put(token.start, token.end, 'operator');
        case SqlTokenKind.symbol:
          if ('=<>!+-*/%|&'.contains(text) || text == '::') {
            put(token.start, token.end, 'operator');
          }
        case SqlTokenKind.unclosed || SqlTokenKind.badParameter:
          break;
      }
    }
  }

  // ---------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------

  /// The problems of the `@Query` methods of [file] (at [path]).
  List<Problem> problems(DartFile file, String path) {
    final problems = <Problem>[];
    for (final repository in repositoriesIn(file)) {
      for (final method in repository.queries) {
        _methodProblems(file, path, method, problems);
      }
    }
    return problems;
  }

  void _methodProblems(
    DartFile file,
    String path,
    QueryMethod method,
    List<Problem> problems,
  ) {
    final names = [for (final p in method.parameters) p.name];
    final used = <String>{};
    for (final text in method.texts) {
      final parsed = _parsed(file, text);
      void report(
        int start,
        int end,
        String message, {
        bool error = true,
      }) {
        final span = text.span(start, end);
        if (span != null) {
          problems.add(
            Problem(
              workspace.rangeOf(file, span.$1, span.$2),
              message,
              error: error,
            ),
          );
        }
      }

      _syntaxProblems(parsed, report);
      for (final token in parsed.tokens) {
        switch (token.kind) {
          case SqlTokenKind.unclosed:
            report(
              token.start,
              token.start + 3,
              "Unclosed SpEL expression: missing '}'",
            );
          case SqlTokenKind.badParameter:
            report(token.start, token.end, token.value);
          case SqlTokenKind.question:
            report(
              token.start,
              token.end,
              'A plain ? marker is not supported: write :name and bind it by '
              'the name of a parameter of the method',
            );
          case SqlTokenKind.elExpression when token.value != '#entityName':
            report(
              token.start,
              token.end,
              '#{${token.value}} is not allowed in the SQL text: only '
              '#{#entityName} is; to bind a value write :#{${token.value}}',
            );
          case SqlTokenKind.parameter:
            used.add(token.value.split('.').first);
            if (!names.contains(token.value)) {
              final guess = closestName(token.value, names);
              final hint = token.value.contains('.')
                  ? ' (to read a property write :#{#${token.value}})'
                  : (guess == null ? '' : ". Did you mean ':$guess'?");
              report(
                token.start,
                token.end,
                'Unknown parameter :${token.value}: the method has '
                "${names.isEmpty ? 'no parameter' : names.join(', ')}$hint",
              );
            }
          case SqlTokenKind.expression:
            _expressionProblems(path, token, names, used, report);
          case SqlTokenKind.entity:
            _entityProblems(path, token, report);
          case _:
            break;
        }
      }
    }
    if (method.texts.isEmpty) {
      return;
    }
    if (used.contains('root')) {
      return; // `#root` is the list of all arguments
    }
    for (final parameter in method.parameters) {
      if (parameter.isSpecial ||
          used.contains(parameter.name) ||
          used.contains('p${parameter.index}') ||
          used.contains('a${parameter.index}')) {
        continue;
      }
      problems.add(
        Problem(
          workspace.rangeOf(
            file,
            parameter.offset,
            parameter.offset + parameter.name.length,
          ),
          "Parameter '${parameter.name}' is not used in the query",
        ),
      );
    }
  }

  // Unclosed quotes and comments, unbalanced parentheses, a stray brace.
  void _syntaxProblems(
    _Parsed parsed,
    void Function(int, int, String, {bool error}) report,
  ) {
    final open = <SqlToken>[];
    for (final token in parsed.tokens) {
      switch (token.kind) {
        case SqlTokenKind.string || SqlTokenKind.quoted:
          final quote = token.text[0];
          if ((quote == "'" || quote == '"' || quote == '`') &&
              quote.allMatches(token.text).length.isOdd) {
            report(
              token.start,
              token.end,
              'Unclosed ${quote == "'" ? 'string' : 'quoted name'}: '
              'missing a closing $quote',
            );
          }
        case SqlTokenKind.symbol:
          if (token.text == '(') {
            open.add(token);
          } else if (token.text == ')') {
            if (open.isEmpty) {
              report(token.start, token.end, "Unmatched ')'");
            } else {
              open.removeLast();
            }
          } else if (token.text == '{' || token.text == '}') {
            report(
              token.start,
              token.end,
              "'${token.text}' is no placeholder: write {Entity} or "
              '{Entity.property}',
            );
          }
        case _:
          break;
      }
    }
    for (final token in open) {
      report(token.start, token.end, "Unclosed '(': missing ')'");
    }
    for (final (start, _, closed) in parsed.comments) {
      if (!closed) {
        report(
          start,
          start + 2,
          "Unclosed comment: missing '*/'",
          error: false,
        );
      }
    }
  }

  void _expressionProblems(
    String path,
    SqlToken token,
    List<String> names,
    Set<String> used,
    void Function(int, int, String, {bool error}) report,
  ) {
    final open = token.text.indexOf('{') + 1;
    final expression = token.text.substring(open, token.text.length - 1);
    if (expression.contains(r'${')) {
      return; // placeholders are resolved first
    }
    final issues = workspace.spelIssues(path, expression);
    for (final issue in issues) {
      if (expression.substring(issue.start, issue.end) == '@environment' &&
          issue.message.startsWith("Unknown bean 'environment'")) {
        continue; // the environment is always there
      }
      report(
        token.start + open + issue.start,
        token.start + open + issue.end,
        issue.message,
        error: issue.error,
      );
    }
    if (issues.any((i) => i.message.startsWith('SpEL:'))) {
      return;
    }
    for (final (name, start, end) in _variables(expression)) {
      used.add(name);
      if (names.contains(name) || _builtinVariable.hasMatch(name)) {
        continue;
      }
      final guess = closestName(name, names);
      final didYouMean = guess == null ? '' : ". Did you mean '#$guess'?";
      final listed = names.isEmpty
          ? ''
          : '; parameters: ${names.map((n) => '#$n').join(', ')}';
      report(
        token.start + open + start - 1,
        token.start + open + end,
        "Unknown variable '#$name'$didYouMean$listed",
      );
    }
  }

  // `#name` in a SpEL expression: the name and its span (without the `#`).
  static List<(String, int, int)> _variables(String expression) {
    final List<Token> tokens;
    try {
      tokens = Tokenizer(expression).process();
    } on Object {
      return const [];
    }
    return [
      for (var i = 1; i < tokens.length; i++)
        if (tokens[i].kind == TokenKind.identifier &&
            tokens[i - 1].kind == TokenKind.hash)
          (
            expression.substring(tokens[i].start, tokens[i].end),
            tokens[i].start,
            tokens[i].end,
          ),
    ];
  }

  void _entityProblems(
    String path,
    SqlToken token,
    void Function(int, int, String, {bool error}) report,
  ) {
    final name = token.value;
    final nameEnd = token.start + 1 + name.length;
    final entity = _data.entity(name, path);
    if (entity == null) {
      final names = _data.entityNames(path);
      final guess = closestName(name, names);
      final complete = workspace.metadataFor(path).complete;
      final stale = complete
          ? ''
          : ' (run build_runner to refresh the Spring metadata)';
      if (_data.classExists(name)) {
        report(
          token.start + 1,
          nameEnd,
          '{$name}: no @Table class $name in the application: the class '
          'exists but is not marked @Table',
        );
      } else {
        report(
          token.start + 1,
          nameEnd,
          guess != null
              ? '{$name}: no @Table class $name in the application, did you '
                    "mean '$guess'?"
              : '{$name}: no @Table class $name found$stale',
          error: guess != null || complete,
        );
      }
      return;
    }
    final member = token.member;
    if (member == null) {
      return;
    }
    final memberStart = nameEnd + 1;
    final memberEnd = memberStart + member.length;
    final property = entity.property(member);
    final shown = token.text;
    if (property == null) {
      if (entity.transients.contains(member)) {
        report(
          memberStart,
          memberEnd,
          '$shown: $name.$member is @Transient: it has no column',
        );
      } else if (entity.complete) {
        final stored = [for (final p in entity.columns) p.name];
        final guess = closestName(member, stored);
        report(
          memberStart,
          memberEnd,
          '$shown: $name has no property $member'
          "${guess == null ? '' : ", did you mean '$guess'?"} "
          '(stored properties: ${stored.join(', ')})',
        );
      }
    } else if (property.isMappedCollection) {
      report(
        memberStart,
        memberEnd,
        '$shown: $name.$member is a @MappedCollection: its rows are in the '
        'table of its children, not in a column of $name',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Navigation and hovers
  // ---------------------------------------------------------------------

  /// Where go to definition leads from [offset] of [file]; `null` when
  /// [offset] is not in a `@Query` text, empty when it is but there is
  /// nothing to go to.
  List<SourceRange>? definition(DartFile file, String path, int offset) {
    final found = _at(file, offset);
    if (found == null) {
      return null;
    }
    final (method, text, at) = found;
    final parsed = _parsed(file, text);
    final index = parsed.indexAt(at);
    if (index == null) {
      return const [];
    }
    final token = parsed.tokens[index];
    switch (token.kind) {
      case SqlTokenKind.entity:
        final entity = _data.entity(token.value, path);
        if (entity == null) {
          return const [];
        }
        final memberStart = token.start + 2 + token.value.length;
        if (token.member != null && at >= memberStart) {
          final property = entity.property(token.member!);
          if (property != null) {
            return _data.locateProperty(property, path);
          }
        }
        return _data.locate(entity, path);
      case SqlTokenKind.parameter:
        return _parameterRanges(file, method, token.value.split('.').first);
      case SqlTokenKind.expression || SqlTokenKind.elExpression:
        final open = token.text.indexOf('{') + 1;
        final expression = token.text.substring(open, token.text.length - 1);
        final inner = at - token.start - open;
        for (final (name, start, end) in _variables(expression)) {
          if (inner >= start - 1 && inner <= end) {
            return _parameterRanges(file, method, name);
          }
        }
        return workspace.spelDefinition(path, expression, inner);
      case SqlTokenKind.property:
        final key = token.value;
        return [
          for (final entry in workspace.property(key, from: file))
            SourceRange(
              entry.path,
              entry.line,
              entry.keyStart,
              entry.line,
              entry.keyEnd,
            ),
        ];
      case SqlTokenKind.word || SqlTokenKind.quoted:
        final target = _nameTarget(path, parsed, index);
        if (target?.property case final property?) {
          return _data.locateProperty(property, path);
        }
        if (target?.entity case final entity?) {
          return _data.locate(entity, path);
        }
        return const [];
      case _:
        return const [];
    }
  }

  List<SourceRange> _parameterRanges(
    DartFile file,
    QueryMethod method,
    String name,
  ) => [
    for (final parameter in method.parameters)
      if (parameter.name == name)
        workspace.rangeOf(
          file,
          parameter.offset,
          parameter.offset + parameter.name.length,
        ),
  ];

  /// The hover at [offset] of [file]; `null` when [offset] is not in a
  /// `@Query` text or has nothing to say.
  String? hover(DartFile file, String path, int offset) {
    final found = _at(file, offset);
    if (found == null) {
      return null;
    }
    final (method, text, at) = found;
    final parsed = _parsed(file, text);
    final index = parsed.indexAt(at);
    if (index == null) {
      return null;
    }
    final token = parsed.tokens[index];
    switch (token.kind) {
      case SqlTokenKind.entity:
        final entity = _data.entity(token.value, path);
        if (entity == null) {
          return '**{${token.value}}**: no @Table class of that name';
        }
        final memberStart = token.start + 2 + token.value.length;
        if (token.member != null && at >= memberStart) {
          final property = entity.property(token.member!);
          return property == null
              ? '**${entity.name}.${token.member}**: no such stored property'
              : _propertyText(entity, property);
        }
        return _entityText(entity);
      case SqlTokenKind.parameter:
        return _parameterText(method, token.value.split('.').first);
      case SqlTokenKind.expression || SqlTokenKind.elExpression:
        final open = token.text.indexOf('{') + 1;
        final expression = token.text.substring(open, token.text.length - 1);
        final inner = at - token.start - open;
        for (final (name, start, end) in _variables(expression)) {
          if (inner >= start - 1 && inner <= end) {
            return _parameterText(method, name);
          }
        }
        return workspace.spelHover(path, expression, inner);
      case SqlTokenKind.property:
        final entries = workspace.property(token.value, from: file);
        if (entries.isEmpty) {
          return '**`${token.value}`**: not defined in any properties file';
        }
        return [
          '**`${token.value}`**',
          '',
          for (final entry in entries)
            '- `${entry.fileName}`: `${entry.value}`',
        ].join('\n');
      case SqlTokenKind.word || SqlTokenKind.quoted:
        final target = _nameTarget(path, parsed, index);
        if (target?.property case final property?) {
          return _propertyText(target!.entity!, property);
        }
        if (target?.entity case final entity?) {
          return _entityText(entity);
        }
        return null;
      case _:
        return null;
    }
  }

  String _parameterText(QueryMethod method, String name) {
    for (final parameter in method.parameters) {
      if (parameter.name == name) {
        return '**:$name**: parameter `${parameter.type} $name` of '
            '`${method.method.name.lexeme}`';
      }
    }
    final names = [for (final p in method.parameters) p.name];
    return '**:$name**: no such parameter (the method has '
        "${names.isEmpty ? 'none' : names.join(', ')})";
  }

  String _entityText(EntityView entity) {
    final columns = [for (final p in entity.columns) p.name];
    final table = entity.table == null ? '' : ', table `${entity.table}`';
    return [
      '**${entity.name}**: entity$table',
      '',
      if (entity.id != null) '- id: `${entity.id}`',
      if (columns.isNotEmpty)
        '- properties: ${columns.map((c) => '`$c`').join(', ')}',
    ].join('\n');
  }

  String _propertyText(EntityView entity, PropertyView property) {
    final referenceId = property.relationId == null
        ? ''
        : ' (id `${property.relationId}`)';
    final column = property.isColumn
        ? (property.column == null
              ? 'column named by the naming strategy'
              : 'column `${property.column}`')
        : (property.isMappedCollection
              ? 'children in a table of their own'
              : 'not stored');
    return [
      '**${entity.name}.${property.name}**: $column',
      '',
      '- type: `${property.type}`',
      if (property.relationEntity != null)
        '- references `${property.relationEntity}`$referenceId',
      if (entity.id == property.name) '- the id of `${entity.name}`',
    ].join('\n');
  }

  // The entity or the property a plain name in the SQL stands for: a table
  // (`books`), an alias (`b`), `b.title` or an unqualified column when the
  // query reads one table.
  ({EntityView? entity, PropertyView? property})? _nameTarget(
    String path,
    _Parsed parsed,
    int index,
  ) {
    final tokens = parsed.tokens;
    final (aliases, tables) = _aliases(path, parsed);
    final token = tokens[index];
    final name = token.value.toLowerCase();
    PropertyView? columnOf(EntityView entity) {
      for (final p in entity.columns) {
        if ((p.column ?? p.name).toLowerCase() == name ||
            p.name.toLowerCase() == name) {
          return p;
        }
      }
      return null;
    }

    if (index >= 2 && tokens[index - 1].isSymbol('.')) {
      final owner = aliases[tokens[index - 2].value.toLowerCase()];
      if (owner == null) {
        return null;
      }
      final property = columnOf(owner);
      return property == null ? null : (entity: owner, property: property);
    }
    if (index + 1 < tokens.length && tokens[index + 1].isSymbol('.')) {
      final owner = aliases[name];
      return owner == null ? null : (entity: owner, property: null);
    }
    if (aliases.containsKey(name) && !_isColumnContext(tokens, index)) {
      return (entity: aliases[name], property: null);
    }
    if (tables.length == 1) {
      final property = columnOf(tables.single);
      if (property != null) {
        return (entity: tables.single, property: property);
      }
    }
    return null;
  }

  static bool _isColumnContext(List<SqlToken> tokens, int index) =>
      index > 0 && tokens[index - 1].isSymbol('.');

  // The names the query gives to the entities it reads: `from {Book} b`,
  // `join books as a`, `from books`; and the entities it reads.
  (Map<String, EntityView>, List<EntityView>) _aliases(
    String path,
    _Parsed parsed,
  ) {
    final aliases = <String, EntityView>{};
    final tables = <EntityView>[];
    final tokens = parsed.tokens;
    EntityView? byTable(String table) {
      for (final name in _data.entityNames(path)) {
        final entity = _data.entity(name, path);
        if (entity != null && entity.table?.toLowerCase() == table) {
          return entity;
        }
      }
      return null;
    }

    for (var i = 0; i + 1 < tokens.length; i++) {
      final word = tokens[i];
      if (word.kind != SqlTokenKind.word || !_tableWords.contains(word.lower)) {
        continue;
      }
      final named = tokens[i + 1];
      final entity = switch (named.kind) {
        SqlTokenKind.entity => _data.entity(named.value, path),
        SqlTokenKind.word || SqlTokenKind.quoted => byTable(named.lower),
        _ => null,
      };
      if (entity == null) {
        continue;
      }
      tables.add(entity);
      aliases[entity.name.toLowerCase()] = entity;
      if (entity.table != null) {
        aliases[entity.table!.toLowerCase()] = entity;
      }
      var j = i + 2;
      if (j < tokens.length && tokens[j].isWord('as')) {
        j++;
      }
      if (j < tokens.length &&
          tokens[j].isName &&
          !_keywords.contains(tokens[j].lower)) {
        aliases[tokens[j].lower] = entity;
      }
    }
    return (aliases, tables);
  }

  // ---------------------------------------------------------------------
  // Completion
  // ---------------------------------------------------------------------

  /// The proposals at [offset] of [file] inside a `@Query` text: entities
  /// after `{`, the properties of an entity after `{Entity.`, the method's
  /// parameters after `:`, and in `:#{...}` the `#parameters` and the SpEL
  /// beans and members. `null` when [offset] is not in a `@Query` text or
  /// nothing fits.
  CompletionResult? completion(DartFile file, String path, int offset) {
    final found = _at(file, offset);
    if (found == null) {
      return null;
    }
    final (method, text, at) = found;
    final before = text.text.substring(0, at);
    final after = text.text.substring(at);
    // Inside a string or a comment nothing is proposed.
    final tokens = SqlLexer.tokenize(before);
    if (tokens.isNotEmpty &&
        tokens.last.end == before.length &&
        (tokens.last.kind == SqlTokenKind.string ||
            tokens.last.kind == SqlTokenKind.quoted) &&
        tokens.last.text[0].allMatches(tokens.last.text).length.isOdd) {
      return null;
    }
    final lastLine = before.substring(before.lastIndexOf('\n') + 1);
    if (lastLine.contains('--')) {
      return null;
    }
    CompletionResult result(int typedLength, List<Completion> items) =>
        CompletionResult(
          workspace.rangeOf(file, offset - typedLength, offset),
          items,
        );

    final expression = RegExp(r'#\{([^}]*)$').firstMatch(before);
    if (expression != null) {
      final inner = expression.group(1)!;
      final variable = RegExp(r'#(\w*)$').firstMatch(inner);
      if (variable != null) {
        final typed = variable.group(1)!;
        return result(typed.length, [
          for (final p in method.parameters)
            Completion(
              p.name,
              kind: 6,
              detail: p.type,
              documentation: 'parameter of `${method.method.name.lexeme}`',
            ),
          for (final name in ['root', 'entityName', 'methodName'])
            Completion(name, kind: 6, detail: 'query variable'),
        ]);
      }
      final spel = workspace.spelComplete(path, inner);
      if (spel == null) {
        return null;
      }
      return result(inner.length - spel.$1, spel.$2);
    }
    final property = RegExp(
      r'(?<![\$#])\{([A-Za-z_]\w*)\.(\w*)$',
    ).firstMatch(before);
    if (property != null) {
      final entity = _data.entity(property.group(1)!, path);
      if (entity == null) {
        return null;
      }
      final close = after.startsWith('}') ? '' : '}';
      return result(property.group(2)!.length, [
        for (final p in entity.columns)
          Completion(
            p.name,
            detail: p.type,
            documentation: p.column == null ? null : 'column `${p.column}`',
            insertText: '${p.name}$close',
          ),
      ]);
    }
    final entityName = RegExp(r'(?<![\$#])\{([A-Za-z_]?\w*)$')
        .firstMatch(before);
    if (entityName != null) {
      return result(entityName.group(1)!.length, [
        for (final name in _data.entityNames(path))
          if (_data.entity(name, path) case final entity?)
            Completion(
              name,
              kind: 7,
              detail: 'entity',
              documentation: entity.table == null
                  ? null
                  : 'table `${entity.table}`',
            ),
      ]);
    }
    final parameter = RegExp(r'(?<![:\w]):(\w*)$').firstMatch(before);
    if (parameter != null) {
      return result(parameter.group(1)!.length, [
        for (final p in method.parameters)
          if (!p.isSpecial)
            Completion(
              p.name,
              kind: 6,
              detail: p.type,
              documentation: 'parameter of `${method.method.name.lexeme}`',
            ),
      ]);
    }
    return null;
  }
}
