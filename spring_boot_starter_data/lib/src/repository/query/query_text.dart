import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/mapping/mapping_context.dart';

/// The text of a `@Query` after its creation time processing: the SQL with
/// `:name` markers only, and the SpEL expressions that `:#{...}` stood for.
///
/// Spring (Java): none; the work of `StringBasedJdbcQuery`'s
/// `SpelEvaluator` and `ExpressionQueryMethodEvaluationContextProvider`.
final class QueryText {
  /// A text of [sql] whose markers [expressions] are SpEL.
  const QueryText(this.sql, this.expressions);

  /// The SQL: plain `:name` markers, the `:#{...}` ones renamed
  /// (`:spel0_book_title`), `#{#entityName}` replaced by the quoted table.
  final String sql;

  /// The SpEL expressions bound by name: the marker (without `:`) to the
  /// expression's text.
  final Map<String, String> expressions;
}

/// What happens to the text of a `@Query` once, when the repository is
/// created (all of it configuration or the application's own text, never
/// a user's input):
///
/// 1. `${property}` and `${property:default}` are resolved from the
///    environment, as Spring does for every annotation value; a property
///    with neither a value nor a default is a problem;
/// 2. `#{#entityName}` becomes the quoted table of the entity;
/// 3. `{Book}` becomes the quoted table of the entity `Book` and
///    `{Book.authorId}` the quoted column of its property, as the mapping
///    names them (the naming strategy, `@Table` and `@Column` decide);
/// 4. `:#{expression}` becomes a named marker whose value is the
///    expression's result at each call.
///
/// The scan leaves quoted text (`'...'`, `"..."`, `` `...` ``), comments
/// and Postgres `$tag$...$tag$` literals as they are, and understands `::`
/// (a cast) and `:{name}` (a parameter).
///
/// The build has already refused an expression that is not closed, a
/// `#{...}` other than `#{#entityName}`, and an entity or property named
/// that does not exist, but it cannot read a text with a `${property}`
/// placeholder, whose result is known only here: the same problems are
/// found at the start of the application for such a text (a `:#{` that is
/// not closed, a `#{expression}` that is not `#{#entityName}`).
///
/// Spring (Java): `StringBasedJdbcQuery` (with `SpelEvaluator` and the
/// `@Value`-style placeholder resolution of the annotation).
abstract final class QueryTextPreparer {
  static final RegExp _entity = RegExp(
    r'\{([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?\}',
  );
  static final RegExp _dollarTag = RegExp(r'\$[A-Za-z_]*\$');

  /// Prepares [text]; every problem found is added to [problems] (with
  /// [where] in front) and the text is then not usable. [entityName] gives
  /// the quoted table of an entity (`property` is `null`) or the quoted
  /// column of one of its properties.
  static QueryText prepare(
    String text, {
    required String quotedTable,
    required PropertyResolver? environment,
    required String where,
    required List<String> problems,
    required String Function(String entity, String? property) entityName,
  }) {
    final resolved = _placeholders(text, environment, where, problems);
    final expressions = <String, String>{};
    final out = StringBuffer();
    final n = resolved.length;
    var i = 0;
    while (i < n) {
      final c = resolved[i];
      final next = i + 1 < n ? resolved[i + 1] : '';
      if (c == "'" || c == '"' || c == '`') {
        final end = _endOfQuote(resolved, i);
        out.write(resolved.substring(i, end));
        i = end;
      } else if (c == r'$' && _dollarTag.matchAsPrefix(resolved, i) != null) {
        // A Postgres literal: its text is no marker, entity or expression.
        final tag = _dollarTag.matchAsPrefix(resolved, i)![0]!;
        final end = resolved.indexOf(tag, i + tag.length);
        final stop = end < 0 ? n : end + tag.length;
        out.write(resolved.substring(i, stop));
        i = stop;
      } else if (c == '-' && next == '-') {
        final end = resolved.indexOf('\n', i);
        final stop = end < 0 ? n : end + 1;
        out.write(resolved.substring(i, stop));
        i = stop;
      } else if (c == '/' && next == '*') {
        final end = resolved.indexOf('*/', i + 2);
        final stop = end < 0 ? n : end + 2;
        out.write(resolved.substring(i, stop));
        i = stop;
      } else if (c == ':' && next == ':') {
        out.write('::');
        i += 2;
      } else if (c == ':' && next == '{') {
        // `:{name}`: a parameter, not an entity.
        final end = resolved.indexOf('}', i + 2);
        final stop = end < 0 ? n : end + 1;
        out.write(resolved.substring(i, stop));
        i = stop;
      } else if ((c == ':' && next == '#' && _at(resolved, i + 2, '{')) ||
          (c == '#' && next == '{')) {
        final isParameter = c == ':';
        final open = isParameter ? i + 3 : i + 2;
        final close = _endOfBraces(resolved, open);
        if (close < 0) {
          problems.add(
            '$where: an expression is not closed: ${_excerpt(resolved, i)}',
          );
          out.write(resolved.substring(i));
          i = n;
          continue;
        }
        final expression = resolved.substring(open, close).trim();
        if (isParameter) {
          final marker = _marker(expressions.length, expression);
          expressions[marker] = expression;
          out.write(':$marker');
        } else if (expression == '#entityName') {
          out.write(quotedTable);
        } else {
          problems.add(
            '$where: #{$expression} is not allowed in the SQL text: only '
            '#{#entityName} is; to bind a value write :#{$expression}',
          );
          out.write(resolved.substring(i, close + 1));
        }
        i = close + 1;
      } else if (c == '{' && _entity.matchAsPrefix(resolved, i) != null) {
        final match = _entity.matchAsPrefix(resolved, i)!;
        try {
          out.write(entityName(match[1]!, match[2]));
        } on MappingException catch (error) {
          problems.add('$where: ${error.message}');
          out.write(match[0]);
        }
        i = match.end;
      } else {
        out.write(c);
        i++;
      }
    }
    return QueryText(out.toString(), expressions);
  }

  static String _placeholders(
    String text,
    PropertyResolver? environment,
    String where,
    List<String> problems,
  ) {
    if (!text.contains(r'${')) {
      return text;
    }
    if (environment == null) {
      problems.add(
        '$where: the query has \${...} placeholders but there is no '
        'Environment to resolve them',
      );
      return text;
    }
    try {
      return environment.resolveRequiredPlaceholders(text);
    } on PlaceholderResolutionException catch (error) {
      problems.add('$where: ${error.message}');
    } on Object catch (error) {
      problems.add('$where: cannot resolve the placeholders: $error');
    }
    return text;
  }

  static String _marker(int index, String expression) {
    final words = expression
        .replaceAll(RegExp('[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final shown = words.length > 40 ? words.substring(0, 40) : words;
    return shown.isEmpty ? 'spel$index' : 'spel${index}_$shown';
  }

  static bool _at(String text, int index, String char) =>
      index < text.length && text[index] == char;

  static String _excerpt(String text, int from) {
    final end = from + 30 > text.length ? text.length : from + 30;
    return text.substring(from, end);
  }

  // The end (exclusive) of the quoted text that starts at [start]; a quote
  // doubled inside is part of the text.
  static int _endOfQuote(String text, int start) {
    final quote = text[start];
    var j = start + 1;
    while (j < text.length) {
      if (text[j] == quote) {
        if (j + 1 < text.length && text[j + 1] == quote) {
          j += 2;
          continue;
        }
        return j + 1;
      }
      j++;
    }
    return text.length;
  }

  // The index of the `}` that closes the `{` before [start]; -1 when there
  // is none. Braces nest, and SpEL strings may hold braces.
  static int _endOfBraces(String text, int start) {
    var depth = 1;
    var j = start;
    while (j < text.length) {
      final c = text[j];
      if (c == "'" || c == '"') {
        j = _endOfQuote(text, j);
        continue;
      }
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          return j;
        }
      }
      j++;
    }
    return -1;
  }
}

/// Helpers to put a sort and a window on the text of a query.
abstract final class QueryTextSupport {
  /// [sql] without its trailing whitespace and semicolons.
  static String trim(String sql) {
    var end = sql.length;
    while (end > 0) {
      final c = sql[end - 1];
      if (c == ';' || c.trim().isEmpty) {
        end--;
      } else {
        break;
      }
    }
    return sql.substring(0, end);
  }

  /// Whether [sql] has an `order by` of its own, outside of parentheses,
  /// quotes and comments: a sort is then added to it with a comma.
  static bool hasTopLevelOrderBy(String sql) {
    var depth = 0;
    var i = 0;
    final n = sql.length;
    bool isWord(int at, String word) {
      if (at + word.length > n) {
        return false;
      }
      if (sql.substring(at, at + word.length).toLowerCase() != word) {
        return false;
      }
      final before = at == 0 ? ' ' : sql[at - 1];
      final after = at + word.length < n ? sql[at + word.length] : ' ';
      return !_isWordChar(before) && !_isWordChar(after);
    }

    while (i < n) {
      final c = sql[i];
      if (c == "'" || c == '"' || c == '`') {
        i = QueryTextPreparer._endOfQuote(sql, i);
        continue;
      }
      if (c == '-' && i + 1 < n && sql[i + 1] == '-') {
        final end = sql.indexOf('\n', i);
        i = end < 0 ? n : end + 1;
        continue;
      }
      if (c == '/' && i + 1 < n && sql[i + 1] == '*') {
        final end = sql.indexOf('*/', i + 2);
        i = end < 0 ? n : end + 2;
        continue;
      }
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (depth == 0 && isWord(i, 'order')) {
        var j = i + 5;
        while (j < n && sql[j].trim().isEmpty) {
          j++;
        }
        if (j > i + 5 && isWord(j, 'by')) {
          return true;
        }
      }
      i++;
    }
    return false;
  }

  static bool _isWordChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F;
  }
}
