import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/mapping/entity_converter.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/query/part_tree.dart';
import 'package:spring_boot_starter_data/src/query/query_arguments.dart';
import 'package:spring_boot_starter_data/src/store/data_store.dart';
import 'package:spring_boot_starter_data/src/store/row_change.dart';

/// Tests rows and instances of an entity against a [Criteria], without a
/// database: what the in-memory store finds with, and what filters a
/// stream of changes the store could not filter itself.
///
/// The conditions follow SQL: a comparison with null is false (`isNull`
/// and `isNotNull` aside), `simpleProperty` with a null argument means
/// `isNull` and `negatingSimpleProperty` `isNotNull`; `ignoreCase` lower
/// cases both sides; `like` takes `%` (any text) and `_` (one character)
/// with `\` to escape them; `startingWith`, `endingWith` and `containing`
/// take their argument literally; `between` is inclusive; `in` and `notIn`
/// take a collection (`notIn` is false for a value when the collection
/// holds a null, as `NOT IN` is in SQL); an `AggregateReference` is
/// compared by its id; numbers compare as numbers and a `DateTime` by the
/// moment.
///
/// The criteria are compiled once, when the matcher is made: a property
/// that is not a column of the entity, or an argument that cannot be
/// compared (a text with a NUL, a value that is no collection for `in`),
/// is an `InvalidDataAccessApiUsageException` then.
///
/// ```dart
/// final matcher = CriteriaMatcher<Book>(
///   entity,
///   Criteria(tree.predicate, ['Dune']),
///   converter: converter,
/// );
/// matcher.matches(book); // an instance
/// matcher.matchesRow({'title': 'Dune', 'year': 1965}); // a row
/// ```
///
/// Spring (Java): none; Spring Data runs a `Criteria` in the database
/// (the nearest is `ExampleMatcher` of Query by Example, which is also
/// evaluated by the store).
final class CriteriaMatcher<T extends Object> {
  /// A matcher of [criteria] for [entity]; [converter] turns instances
  /// and arguments into column values (an enum into its name).
  CriteriaMatcher(this.entity, this.criteria, {EntityConverter? converter})
    : converter = converter ?? EntityConverter() {
    _matches = _compile();
  }

  /// The entity whose rows are tested.
  final PersistentEntity<T> entity;

  /// The condition.
  final Criteria criteria;

  /// Turns instances into rows and arguments into column values.
  final EntityConverter converter;

  late final bool Function(Map<String, Object?> row) _matches;

  /// Whether [row] (column names to column values, as the entity
  /// converter writes them) matches the criteria.
  bool matchesRow(Map<String, Object?> row) => _matches(row);

  /// Whether [instance] matches the criteria.
  bool matches(T instance) => _matches(converter.write(entity, instance));

  /// Whether [change] concerns the criteria: its row or its previous row
  /// matches, or the store did not tell a row that may have matched.
  /// That is a change without rows (only that a row changed), and an
  /// update or a delete without its previous row: the row may have
  /// matched before, so it may have left the criteria.
  bool concerns(RowChange<T> change) {
    final row = change.row;
    final previous = change.previous;
    if (row != null && matches(row)) {
      return true;
    }
    if (previous != null) {
      return matches(previous);
    }
    // No previous row: an insert has none, of the others it is unknown.
    return row == null || change.kind != RowChangeKind.insert;
  }

  bool Function(Map<String, Object?> row) _compile() {
    var next = 0;
    final alternatives = <List<bool Function(Map<String, Object?>)>>[];
    for (final or in criteria.predicate) {
      final conjunction = <bool Function(Map<String, Object?>)>[];
      for (final part in or.parts) {
        final property = _column(part.path.first);
        final count = part.type.argumentCount;
        final arguments = criteria.arguments.sublist(next, next + count);
        next += count;
        final test = _test(property, part, arguments);
        final column = property.columnName;
        conjunction.add((row) => test(row[column]));
      }
      alternatives.add(conjunction);
    }
    if (alternatives.isEmpty) {
      return (_) => true;
    }
    return (row) => alternatives.any((all) => all.every((test) => test(row)));
  }

  PersistentProperty _column(String name) {
    final property = entity.property(name);
    if (property == null || property.isMappedCollection) {
      throw InvalidDataAccessApiUsageException(
        'No column ${LogFormatUtils.formatValue(name)} of '
        '${entity.introspection.className} for a condition',
      );
    }
    return property;
  }

  static Object? _fold(Object? value, {required bool ignoreCase}) =>
      ignoreCase && value is String ? value.toLowerCase() : value;

  bool Function(Object? value) _test(
    PersistentProperty property,
    Part part,
    List<Object?> arguments,
  ) {
    final ic = part.ignoreCase;
    Object? argument(int index) {
      final value = converter.toColumnValue(arguments[index]);
      rejectNul(value, property.name);
      return _fold(value, ignoreCase: ic);
    }

    Object? fold(Object? value) => _fold(value, ignoreCase: ic);
    bool compare(Object? value, Object? other, bool Function(int c) holds) {
      if (value == null || other == null) {
        return false;
      }
      final c = compareValues(fold(value), other);
      return c != null && holds(c);
    }

    switch (part.type) {
      case PartType.isNull:
        return (value) => value == null;
      case PartType.isNotNull:
        return (value) => value != null;
      case PartType.isTrue:
        return (value) => value == true;
      case PartType.isFalse:
        return (value) => value == false;
      case PartType.simpleProperty:
        final other = argument(0);
        return other == null
            ? (value) => value == null
            : (value) => value != null && sameValue(fold(value), other);
      case PartType.negatingSimpleProperty:
        final other = argument(0);
        return other == null
            ? (value) => value != null
            : (value) => value != null && !sameValue(fold(value), other);
      case PartType.lessThan:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c < 0);
      case PartType.lessThanEqual:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c <= 0);
      case PartType.greaterThan:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c > 0);
      case PartType.greaterThanEqual:
        final other = argument(0);
        return (value) => compare(value, other, (c) => c >= 0);
      case PartType.between:
        final low = argument(0);
        final high = argument(1);
        return (value) =>
            compare(value, low, (c) => c >= 0) &&
            compare(value, high, (c) => c <= 0);
      case PartType.like || PartType.notLike:
        final pattern = argument(0);
        final negate = part.type == PartType.notLike;
        final regex = pattern is String ? _likeRegex(pattern) : null;
        return (value) {
          if (value is! String || regex == null) {
            return false;
          }
          return regex.hasMatch(fold(value)! as String) != negate;
        };
      case PartType.startingWith:
        return _literal(argument(0), fold, (v, a) => v.startsWith(a));
      case PartType.endingWith:
        return _literal(argument(0), fold, (v, a) => v.endsWith(a));
      case PartType.containing:
        return _literal(argument(0), fold, (v, a) => v.contains(a));
      case PartType.notContaining:
        return _literal(argument(0), fold, (v, a) => !v.contains(a));
      case PartType.in_ || PartType.notIn:
        final raw = arguments[0];
        if (raw is! Iterable<Object?>) {
          throw InvalidDataAccessApiUsageException(
            "'${property.name}' ${part.type.name} needs a collection, not "
            '${raw == null ? 'null' : raw.runtimeType}',
          );
        }
        final elements = [
          for (final element in raw)
            _fold(converter.toColumnValue(element), ignoreCase: ic),
        ];
        for (final element in elements) {
          rejectNul(element, property.name);
        }
        if (part.type == PartType.in_) {
          return (value) =>
              value != null &&
              elements.any((e) => e != null && sameValue(fold(value), e));
        }
        final hasNull = elements.contains(null);
        return (value) {
          if (elements.isEmpty) {
            return true;
          }
          return value != null &&
              !hasNull &&
              !elements.any((e) => sameValue(fold(value), e));
        };
    }
  }

  bool Function(Object? value) _literal(
    Object? argument,
    Object? Function(Object?) fold,
    bool Function(String value, String argument) holds,
  ) =>
      (value) =>
          value is String &&
          argument is String &&
          holds(fold(value)! as String, argument);

  // `%` any text, `_` one character, `\` makes the next one literal.
  static RegExp _likeRegex(String pattern) {
    final out = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == r'\' && i + 1 < pattern.length) {
        out.write(RegExp.escape(pattern[++i]));
      } else if (c == '%') {
        out.write('.*');
      } else if (c == '_') {
        out.write('.');
      } else {
        out.write(RegExp.escape(c));
      }
    }
    out.write(r'$');
    return RegExp(out.toString(), dotAll: true);
  }

  /// The order of two column values of one type (numbers, texts, dates,
  /// booleans, `BigInt`s), as `Comparable.compare` gives it; null when
  /// they cannot be compared (different types).
  static int? compareValues(Object? a, Object? b) {
    if (a is num && b is num) {
      return a.compareTo(b);
    }
    if (a is String && b is String) {
      return a.compareTo(b);
    }
    if (a is DateTime && b is DateTime) {
      return a.compareTo(b);
    }
    if (a is bool && b is bool) {
      return (a ? 1 : 0).compareTo(b ? 1 : 0);
    }
    if (a is BigInt && b is BigInt) {
      return a.compareTo(b);
    }
    return null;
  }

  /// Whether two column values are the same: by [compareValues] when they
  /// compare (1 and 1.0, two `DateTime`s of one moment), bytes by content,
  /// else by `==`; two nulls are the same.
  static bool sameValue(Object? a, Object? b) {
    if (a == null || b == null) {
      return a == null && b == null;
    }
    final c = compareValues(a, b);
    if (c != null) {
      return c == 0;
    }
    if (a is List<int> && b is List<int>) {
      return a.length == b.length &&
          Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
    }
    return a == b;
  }
}
