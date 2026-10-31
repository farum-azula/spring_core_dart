import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';

/// Where the values of `:name` parameters come from.
///
/// Spring (Java): `org.springframework.jdbc.core.namedparam.
/// SqlParameterSource`.
abstract interface class SqlParameterSource {
  /// The source for [source]: a [SqlParameterSource] as it is, a `Map` of
  /// names to values, or an introspected bean (its properties by name).
  factory SqlParameterSource.of(
    Object source, {
    BeanIntrospector? introspector,
  }) {
    return switch (source) {
      final SqlParameterSource s => s,
      final Map<Object?, Object?> m => MapSqlParameterSource(
        m.map((k, v) => MapEntry('$k', v)),
      ),
      _ => BeanPropertySqlParameterSource(source, introspector: introspector),
    };
  }

  /// Whether a value (maybe null) is supplied for [name].
  bool hasValue(String name);

  /// The value for [name]; only asked after [hasValue].
  Object? getValue(String name);
}

/// Values from a map.
///
/// Spring (Java): `MapSqlParameterSource`.
final class MapSqlParameterSource implements SqlParameterSource {
  /// A source of [values], by name.
  MapSqlParameterSource([Map<String, Object?> values = const {}])
    : _values = Map.of(values);

  final Map<String, Object?> _values;

  /// Adds [name], and returns this to chain.
  MapSqlParameterSource addValue(String name, Object? value) {
    _values[name] = value;
    return this;
  }

  @override
  bool hasValue(String name) => _values.containsKey(name);

  @override
  Object? getValue(String name) => _values[name];
}

/// Values from the properties of an introspected bean: `:title` reads
/// `book.title`; `:author_name` also finds `authorName`.
///
/// Spring (Java): `BeanPropertySqlParameterSource`.
final class BeanPropertySqlParameterSource implements SqlParameterSource {
  /// A source reading [bean]; its class is looked up in [introspector]
  /// (default `BeanIntrospector.shared`).
  BeanPropertySqlParameterSource(this.bean, {BeanIntrospector? introspector})
    : _introspection =
          (introspector ?? BeanIntrospector.shared).findIntrospection(bean) ??
          (throw InvalidDataAccessApiUsageException(
            '${bean.runtimeType} is not introspected: use a Map, or mark '
            'the class @Introspected',
          ));

  /// The bean read.
  final Object bean;

  final BeanIntrospection<Object> _introspection;

  static String _normalize(String name) =>
      name.replaceAll('_', '').toLowerCase();

  BeanProperty<Object>? _property(String name) {
    final exact = _introspection.getProperty(name);
    if (exact != null) {
      return exact;
    }
    final wanted = _normalize(name);
    for (final property in _introspection.properties) {
      if (_normalize(property.name) == wanted) {
        return property;
      }
    }
    return null;
  }

  @override
  bool hasValue(String name) => _property(name) != null;

  @override
  Object? getValue(String name) => _property(name)!.getValue(bean);
}

/// A statement with `:name` parameters, parsed: its text and the names, in
/// the order they occur.
final class ParsedSql {
  ParsedSql._(this.sql, this._parts, this.names, this.unnamedCount);

  /// The statement as written.
  final String sql;

  final List<Object> _parts;

  /// The parameter names, one per occurrence, in order.
  final List<String> names;

  /// How many plain `?` markers the statement has outside literals.
  final int unnamedCount;

  @override
  String toString() => 'ParsedSql($sql)';
}

/// A statement with its `?` markers and the values in order.
final class SubstitutedSql {
  SubstitutedSql._(this.sql, this.values, this.names);

  /// The statement with `?` for each value.
  final String sql;

  /// The values, one per `?`.
  final List<Object?> values;

  /// The parameter name of each value (a list's elements share its name).
  final List<String> names;
}

/// Parses `:name` parameters and turns them into `?`.
///
/// What is a parameter, as in Spring's `NamedParameterUtils`:
///
/// - `:name` (letters, digits, `_`, inner `.`, not starting with a digit)
///   and `:{name}`; the same name may occur many times;
/// - not inside quoted text (`'...'`, `"..."`, `` `...` ``, with a doubled
///   quote as an escape), a `--` comment, a `/* */` comment or a
///   `$tag$...$tag$` literal;
/// - `::` (a PostgreSQL cast) and a `:` not followed by a name are text.
///
/// A value that is a list or set is expanded to `?, ?, ?` (`in (:ids)`); a
/// list of lists to `(?, ?), (?, ?)`. An **empty** list is refused with an
/// [InvalidDataAccessApiUsageException]: `in ()` is not valid SQL in most
/// databases, and `in (null)` would silently mean something else for
/// `not in`; the caller knows what an empty set should mean.
///
/// Spring (Java): `org.springframework.jdbc.core.namedparam.
/// NamedParameterUtils`.
abstract final class NamedParameterUtils {
  static bool _isNameStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;

  static bool _isNameChar(int c) => _isNameStart(c) || (c >= 0x30 && c <= 0x39);

  static final _dollarTag = RegExp(r'\$[A-Za-z_]*\$');

  /// Parses [sql].
  static ParsedSql parse(String sql) {
    final parts = <Object>[];
    final names = <String>[];
    var unnamed = 0;
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        parts.add(text.toString());
        text.clear();
      }
    }

    final n = sql.length;
    var i = 0;
    while (i < n) {
      final c = sql[i];
      final next = i + 1 < n ? sql[i + 1] : '';
      if (c == "'" || c == '"' || c == '`') {
        var j = i + 1;
        while (j < n) {
          if (sql[j] == c) {
            if (j + 1 < n && sql[j + 1] == c) {
              j += 2;
              continue;
            }
            break;
          }
          j++;
        }
        final end = j < n ? j + 1 : n;
        text.write(sql.substring(i, end));
        i = end;
      } else if (c == '-' && next == '-') {
        final end = sql.indexOf('\n', i);
        final stop = end < 0 ? n : end + 1;
        text.write(sql.substring(i, stop));
        i = stop;
      } else if (c == '/' && next == '*') {
        final end = sql.indexOf('*/', i + 2);
        final stop = end < 0 ? n : end + 2;
        text.write(sql.substring(i, stop));
        i = stop;
      } else if (c == r'$' && _dollarTag.matchAsPrefix(sql, i) != null) {
        final tag = _dollarTag.matchAsPrefix(sql, i)![0]!;
        final end = sql.indexOf(tag, i + tag.length);
        final stop = end < 0 ? n : end + tag.length;
        text.write(sql.substring(i, stop));
        i = stop;
      } else if (c == ':') {
        if (next == ':') {
          text.write('::');
          i += 2;
        } else if (next == '{') {
          final end = sql.indexOf('}', i + 2);
          if (end < 0) {
            throw InvalidDataAccessApiUsageException(
              'Unterminated :{ parameter at position $i of [$sql]',
            );
          }
          final name = sql.substring(i + 2, end);
          if (name.isEmpty) {
            throw InvalidDataAccessApiUsageException(
              'Empty parameter :{} at position $i of [$sql]',
            );
          }
          flush();
          parts.add(_Param(name));
          names.add(name);
          i = end + 1;
        } else if (next.isNotEmpty && _isNameStart(next.codeUnitAt(0))) {
          var j = i + 1;
          while (j < n) {
            final code = sql.codeUnitAt(j);
            if (_isNameChar(code) ||
                (code == 0x2E &&
                    j + 1 < n &&
                    _isNameStart(sql.codeUnitAt(j + 1)))) {
              j++;
            } else {
              break;
            }
          }
          final name = sql.substring(i + 1, j);
          flush();
          parts.add(_Param(name));
          names.add(name);
          i = j;
        } else {
          text.write(c);
          i++;
        }
      } else {
        if (c == '?') {
          unnamed++;
        }
        text.write(c);
        i++;
      }
    }
    flush();
    return ParsedSql._(sql, parts, names, unnamed);
  }

  /// [parsed] with `?` markers and the values of [source] in order.
  ///
  /// Throws an [InvalidDataAccessApiUsageException] when a name has no
  /// value ("No value supplied for the SQL parameter 'x'"), when the
  /// statement mixes `?` and names, or when a list is empty.
  static SubstitutedSql substitute(
    ParsedSql parsed,
    SqlParameterSource source,
  ) {
    if (parsed.unnamedCount > 0) {
      throw InvalidDataAccessApiUsageException(
        parsed.names.isEmpty
            ? 'The statement has plain ? markers: with named parameters '
                  'write :name, or use the positional methods'
            : 'Cannot mix ? and :name parameters in one statement',
        sql: parsed.sql,
      );
    }
    final out = StringBuffer();
    final values = <Object?>[];
    final names = <String>[];
    for (final part in parsed._parts) {
      if (part is String) {
        out.write(part);
        continue;
      }
      final name = (part as _Param).name;
      if (!source.hasValue(name)) {
        throw InvalidDataAccessApiUsageException(
          "No value supplied for the SQL parameter '$name'",
          sql: parsed.sql,
        );
      }
      final value = source.getValue(name);
      if (_isList(value)) {
        final items = (value! as Iterable<Object?>).toList();
        if (items.isEmpty) {
          throw InvalidDataAccessApiUsageException(
            "The list for the SQL parameter '$name' is empty: 'in ()' is "
            'not valid SQL; decide what an empty list means before the '
            'query',
            sql: parsed.sql,
          );
        }
        final groups = <String>[];
        for (final item in items) {
          if (_isList(item)) {
            final tuple = (item! as Iterable<Object?>).toList();
            groups.add('(${List.filled(tuple.length, '?').join(', ')})');
            values.addAll(tuple);
            names.addAll(List.filled(tuple.length, name));
          } else {
            groups.add('?');
            values.add(item);
            names.add(name);
          }
        }
        out.write(groups.join(', '));
      } else {
        out.write('?');
        values.add(value);
        names.add(name);
      }
    }
    return SubstitutedSql._(out.toString(), values, names);
  }

  static bool _isList(Object? value) =>
      value is Iterable<Object?> && value is! Uint8List;
}

final class _Param {
  const _Param(this.name);

  final String name;
}
