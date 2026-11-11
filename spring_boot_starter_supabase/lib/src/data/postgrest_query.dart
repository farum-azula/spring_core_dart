import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

/// Writes what Spring Data asks of a store (a `Criteria`, a `Sort`) as
/// the query parameters of the database's REST API (PostgREST).
///
/// ```dart
/// // findByDoneAndTitleStartingWith(false, 'Buy')
/// const PostgrestQuery().filters(entity, criteria);
/// // done=eq.false&title=match.^Buy
/// ```
///
/// A value is always data: text that the API would read as syntax (a
/// comma, a parenthesis, a quote) is quoted, and the patterns of `Like`,
/// `StartingWith`, `EndingWith` and `Containing` are sent as anchored
/// regular expressions (`match` / `imatch`) with the text escaped, because
/// the API's own `like` reads every `*` as a wildcard and has no way to
/// say a literal one.
final class PostgrestQuery {
  /// The translation, converting values with [converter] (an enum to its
  /// name, a reference to its id).
  const PostgrestQuery([this.converter]);

  /// What turns a value of the application into the value of a column.
  final EntityConverter? converter;

  /// The parameters that select the rows of [criteria] among those of
  /// [entity]: one per condition when there is no `Or`, else one `or=(…)`.
  ///
  /// Throws an [InvalidDataAccessApiUsageException] for a property that
  /// is not a column, and for what the API cannot express (a comparison
  /// that ignores case other than equality and the text patterns).
  List<MapEntry<String, String>> filters(
    PersistentEntity<Object> entity,
    Criteria? criteria,
  ) {
    if (criteria == null || criteria.isEmpty) {
      return const [];
    }
    var argument = 0;
    final groups = <List<_Condition>>[];
    for (final or in criteria.predicate) {
      final group = <_Condition>[];
      for (final part in or.parts) {
        final count = part.type.argumentCount;
        group.addAll(
          _conditions(
            entity,
            part,
            criteria.arguments.sublist(argument, argument + count),
          ),
        );
        argument += count;
      }
      groups.add(group);
    }
    // An empty group matches every row, and so does an `or` with one.
    if (groups.any((group) => group.isEmpty)) {
      return const [];
    }
    if (groups.length == 1) {
      return [
        for (final condition in groups.single)
          MapEntry(condition.column, condition.plain),
      ];
    }
    final alternatives = [
      for (final group in groups)
        if (group.length == 1)
          group.single.nested
        else
          'and(${group.map((condition) => condition.nested).join(',')})',
    ];
    return [MapEntry('or', '(${alternatives.join(',')})')];
  }

  /// The `order` parameter of [sort] for [entity]; `null` when unsorted.
  ///
  /// Throws an [InvalidDataAccessApiUsageException] for a property that
  /// is not a column and for an order that ignores case (the API orders
  /// by columns only).
  String? order(PersistentEntity<Object> entity, Sort sort) {
    if (sort.isUnsorted) {
      return null;
    }
    return [
      for (final order in sort.orders)
        [
          if (order.ignoreCase)
            throw InvalidDataAccessApiUsageException(
              'An order that ignores case (${order.property}) cannot be '
              "asked of the database's REST API: order by a column that "
              'holds the lower-case text, or use the SQL path '
              '(spring.supabase.db.url)',
            )
          else
            _column(entity, order.property),
          if (order.direction == Direction.desc) 'desc' else 'asc',
          ...switch (order.nullHandling) {
            NullHandling.native => const <String>[],
            NullHandling.nullsFirst => const ['nullsfirst'],
            NullHandling.nullsLast => const ['nullslast'],
          },
        ].join('.'),
    ].join(',');
  }

  /// One value as the API reads it after an operator, outside any list:
  /// `eq.<this>`.
  String scalar(Object? value) => _text(_convert(value));

  static String _column(PersistentEntity<Object> entity, String name) {
    final property = entity.property(name.split('.').first);
    if (property == null || property.isMappedCollection) {
      throw InvalidDataAccessApiUsageException(
        "No column for the property '$name' of ${entity.type}",
      );
    }
    return property.columnName;
  }

  Object? _convert(Object? value) =>
      converter == null ? value : converter!.toColumnValue(value);

  Iterable<_Condition> _conditions(
    PersistentEntity<Object> entity,
    Part part,
    List<Object?> arguments,
  ) sync* {
    final column = _column(entity, part.property);
    _Condition condition(
      String operator,
      Object? value, {
      bool negated = false,
    }) => _Condition(column, operator, _convert(value), negated: negated);
    _Condition pattern(String regex, {bool negated = false}) => _Condition(
      column,
      part.ignoreCase ? 'imatch' : 'match',
      regex,
      negated: negated,
    );
    void noIgnoreCase() {
      if (part.ignoreCase) {
        throw InvalidDataAccessApiUsageException(
          '${part.property} ${part.type.name} ignoring case cannot be '
          "asked of the database's REST API: only equality and the text "
          'patterns can ignore case there. Use the SQL path '
          '(spring.supabase.db.url) for it',
        );
      }
    }

    String text(Object? value) => switch (_convert(value)) {
      final String text => text,
      final other => throw InvalidDataAccessApiUsageException(
        '${part.property} ${part.type.name} needs text, not '
        '${other.runtimeType}',
      ),
    };

    switch (part.type) {
      case PartType.simpleProperty:
        final value = arguments.single;
        if (value == null) {
          yield _Condition(column, 'is', _Keyword.nil);
        } else if (part.ignoreCase) {
          yield pattern('^${_escape(text(value))}\$');
        } else {
          yield condition('eq', value);
        }
      case PartType.negatingSimpleProperty:
        final value = arguments.single;
        if (value == null) {
          yield _Condition(column, 'is', _Keyword.nil, negated: true);
        } else if (part.ignoreCase) {
          yield pattern('^${_escape(text(value))}\$', negated: true);
        } else {
          yield condition('neq', value);
        }
      case PartType.isNull:
        yield _Condition(column, 'is', _Keyword.nil);
      case PartType.isNotNull:
        yield _Condition(column, 'is', _Keyword.nil, negated: true);
      case PartType.isTrue:
        yield _Condition(column, 'is', _Keyword.yes);
      case PartType.isFalse:
        yield _Condition(column, 'is', _Keyword.no);
      case PartType.lessThan:
        noIgnoreCase();
        yield condition('lt', arguments.single);
      case PartType.lessThanEqual:
        noIgnoreCase();
        yield condition('lte', arguments.single);
      case PartType.greaterThan:
        noIgnoreCase();
        yield condition('gt', arguments.single);
      case PartType.greaterThanEqual:
        noIgnoreCase();
        yield condition('gte', arguments.single);
      case PartType.between:
        noIgnoreCase();
        yield condition('gte', arguments.first);
        yield condition('lte', arguments.last);
      case PartType.in_:
      case PartType.notIn:
        noIgnoreCase();
        final values = switch (arguments.single) {
          final Iterable<Object?> values => values,
          final other => throw InvalidDataAccessApiUsageException(
            '${part.property} ${part.type.name} needs a collection, not '
            '${other.runtimeType}',
          ),
        };
        yield _Condition(
          column,
          'in',
          _InList([for (final value in values) _convert(value)]),
          negated: part.type == PartType.notIn,
        );
      case PartType.like:
        yield pattern(_like(text(arguments.single)));
      case PartType.notLike:
        yield pattern(_like(text(arguments.single)), negated: true);
      case PartType.startingWith:
        yield pattern('^${_escape(text(arguments.single))}');
      case PartType.endingWith:
        yield pattern('${_escape(text(arguments.single))}\$');
      case PartType.containing:
        yield pattern(_escape(text(arguments.single)));
      case PartType.notContaining:
        yield pattern(_escape(text(arguments.single)), negated: true);
    }
  }

  // Text as a regular expression that matches exactly it.
  static String _escape(String text) => text.replaceAllMapped(
    RegExp(r'[\\.^$|?*+()\[\]{}]'),
    (match) => '\\${match[0]}',
  );

  // A LIKE pattern (`%`, `_`, `\` before a character to mean it) as an
  // anchored regular expression.
  static String _like(String pattern) {
    final out = StringBuffer('^');
    for (var index = 0; index < pattern.length; index++) {
      final char = pattern[index];
      if (char == r'\' && index + 1 < pattern.length) {
        out.write(_escape(pattern[++index]));
      } else if (char == '%') {
        out.write('.*');
      } else if (char == '_') {
        out.write('.');
      } else {
        out.write(_escape(char));
      }
    }
    out.write(r'$');
    return out.toString();
  }

  static String _text(Object? value) => switch (value) {
    null => 'null',
    final DateTime time => time.toUtc().toIso8601String(),
    final Enum value => value.name,
    _ => '$value',
  };

  // A value inside a list or a logical group, where `,`, `(`, `)` and `"`
  // are syntax: text is always quoted.
  static String _quoted(Object? value) => switch (value) {
    null => 'null',
    final num number => '$number',
    final bool flag => '$flag',
    _ => '"${_text(value).replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"',
  };
}

enum _Keyword {
  nil('null'),
  yes('true'),
  no('false');

  _Keyword(this.text);
  final String text;
}

final class _InList {
  _InList(this.values);
  final List<Object?> values;
}

// One condition on a column, written alone (`column=op.value`) or inside
// a logical group (`column.op.value`).
final class _Condition {
  _Condition(this.column, this.operator, this.value, {this.negated = false});

  final String column;
  final String operator;
  final Object? value;
  final bool negated;

  String get _operator => negated ? 'not.$operator' : operator;

  String _value(String Function(Object? value) other) => switch (value) {
    final _Keyword keyword => keyword.text,
    final _InList list =>
      '(${list.values.map(PostgrestQuery._quoted).join(',')})',
    _ => other(value),
  };

  String get plain => '$_operator.${_value(PostgrestQuery._text)}';

  String get nested => '$column.$_operator.${_value(PostgrestQuery._quoted)}';
}
