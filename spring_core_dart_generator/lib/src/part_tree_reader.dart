import 'package:spring_core_dart_generator/src/did_you_mean.dart';
import 'package:spring_core_dart_generator/src/part_tree.dart';

/// A repository method that is no valid query: its name is not one, or it
/// does not fit the entity, its parameters or its return type.
///
/// [reason] says what is wrong, without the method's name; for an unknown
/// property it lists the entity's properties and suggests the closest.
///
/// Spring (Java):
/// `org.springframework.data.repository.query.QueryCreationException`.
final class QueryProblem implements Exception {
  /// A problem described by [reason].
  QueryProblem(this.reason, {this.property});

  /// What is wrong.
  final String reason;

  /// The property of the name the problem is about (as written, first letter
  /// lower case), or `null`: where an editor underlines it.
  final String? property;

  @override
  String toString() => reason;
}

/// A property a derived query can name, as [PartTreeReader] needs to know
/// it: the build describes it from the element, an editor from the metadata.
abstract interface class PartTreeProperty {
  /// The Dart name.
  String get name;

  /// Whether it holds children in tables of their own (`@MappedCollection`),
  /// which a derived query cannot use.
  bool get isMappedCollection;

  /// Whether its type is `String` (`IgnoreCase` and `Like` need it).
  bool get isString;
}

/// The entity of a repository as [PartTreeReader] reads a name against it.
abstract interface class PartTreeEntity {
  /// The class name.
  String get name;

  /// The stored property named [name], or `null`.
  PartTreeProperty? property(String name);

  /// The properties stored in the entity's own table (no
  /// `@MappedCollection`), in declaration order.
  Iterable<PartTreeProperty> get columns;

  /// Every stored property, collections included.
  Iterable<PartTreeProperty> get properties;
}

/// Reads a repository method's name (`findTop5ByTitleContainingIgnoreCase
/// AndYearGreaterThanOrderByYearDesc`) into a [PartTreeModel] and finds the
/// properties in it. Nothing here needs the analyzer: the build
/// (`PartTreeParser`) and the language server read names with the same rules.
///
/// Grammar, as Spring's `PartTree`:
///
/// * subject: `find|read|get|query|search|stream` (find), `count`,
///   `exists`, `delete|remove`; then optional words, `Distinct`, and for
///   find `First`/`Top` with an optional number; then `By`.
/// * predicate: split at `OrderBy`, then at `Or`, then at `And`, only where
///   an upper-case letter follows (`OrderNumber` and `Android` stay whole).
///   `AllIgnoreCase` / `AllIgnoringCase` anywhere in the predicate applies
///   to every `String` part. Each part is `<Property><Keyword>?`, with
///   `IgnoreCase` / `IgnoringCase` allowed in it.
/// * order: `OrderBy<Property>(Asc|Desc)?` repeated.
///
/// ```dart
/// final tree = const PartTreeReader().parse('findByTitelContaining', book);
/// // throws: No property 'titel' found for type 'Book'; did you mean
/// // 'title'? Available properties: id, title, year.
/// ```
///
/// Spring (Java): `PartTree`, `Part` and `OrderBySource` of
/// `org.springframework.data.repository.query.parser`.
final class PartTreeReader {
  /// A reader.
  const PartTreeReader();

  static final RegExp _subject = RegExp(
    '^(find|read|get|query|search|stream|count|exists|delete|remove)'
    r'((\p{Lu}.*?))??By',
    unicode: true,
  );
  static final RegExp _orderBy = RegExp(r'OrderBy(?=\p{Lu})', unicode: true);
  static final RegExp _or = RegExp(r'Or(?=\p{Lu})', unicode: true);
  static final RegExp _and = RegExp(r'And(?=\p{Lu})', unicode: true);
  static final RegExp _allIgnoreCase = RegExp('AllIgnor(ing|e)Case');
  static final RegExp _ignoreCase = RegExp('Ignor(ing|e)Case');
  static final RegExp _limit = RegExp(
    r'^(First|Top)(\d*)(?=\p{Lu}|$)',
    unicode: true,
  );
  static final RegExp _orderBlocks = RegExp(
    r'(?<=Asc|Desc)(?=\p{Lu})',
    unicode: true,
  );
  static final RegExp _orderBlock = RegExp(r'^(.+?)(Asc|Desc)?$');

  /// Whether [methodName] starts like a derived query: a prefix (`find`,
  /// `read`, `get`, `query`, `search`, `stream`, `count`, `exists`,
  /// `delete`, `remove`), optional words starting with an upper-case
  /// letter, then `By`. It says nothing about the rest of the name.
  static bool isDerivedQuery(String methodName) =>
      _subject.hasMatch(methodName);

  /// Parses [methodName] into a [PartTreeModel] for [entity].
  ///
  /// Throws a [QueryProblem] when the name is not a derived query (no
  /// prefix and `By`), has two `OrderBy`, an unknown property, a property
  /// that is not a column of the entity's own table (a `@MappedCollection`),
  /// a nested path (`AddressCity`, `Address_City`: not supported yet), or
  /// an empty part.
  ///
  /// An empty predicate (`findAllBy`, `findBy`, `countBy`,
  /// `findAllByOrderByTitleAsc`) matches every aggregate, as in Spring.
  PartTreeModel parse(String methodName, PartTreeEntity entity) {
    final match = _subject.firstMatch(methodName);
    if (match == null) {
      throw QueryProblem(
        'the name is not a derived query: it must start with find, read, '
        'get, query, search, stream, count, exists, delete or remove, '
        'optionally followed by words, and then "By"',
      );
    }
    final prefix = match.group(1)!;
    final middle = match.group(2) ?? '';
    final subject = _subjectOf(prefix, middle);

    var predicate = methodName.substring(match.end);
    var allIgnoreCase = false;
    if (_allIgnoreCase.firstMatch(predicate) case final all?) {
      allIgnoreCase = true;
      predicate = predicate.replaceRange(all.start, all.end, '');
    }

    final blocks = _split(predicate, _orderBy);
    if (blocks.length > 2) {
      throw QueryProblem('the name has more than one "OrderBy"');
    }
    final or = <OrPartModel>[];
    for (final alternative in _split(blocks.first, _or)) {
      if (alternative.isEmpty) {
        continue;
      }
      final parts = <PartModel>[
        for (final text in _split(alternative, _and))
          if (text.isNotEmpty) _parsePart(text, entity, allIgnoreCase),
      ];
      if (parts.isNotEmpty) {
        or.add(OrPartModel(parts));
      }
    }
    final sort = blocks.length == 2
        ? _parseOrder(blocks[1], entity)
        : const <SortOrderModel>[];
    return PartTreeModel(methodName, subject, or, sort);
  }

  SubjectModel _subjectOf(String prefix, String middle) {
    final distinct = middle.contains('Distinct');
    switch (prefix) {
      case 'count':
        return SubjectModel(SubjectKind.count, distinct: distinct);
      case 'exists':
        return SubjectModel(SubjectKind.exists, distinct: distinct);
      case 'delete' || 'remove':
        return SubjectModel(SubjectKind.delete, distinct: distinct);
    }
    int? max;
    final limit = _limit.firstMatch(middle.replaceFirst('Distinct', ''));
    if (limit != null) {
      final digits = limit.group(2)!;
      max = digits.isEmpty ? 1 : int.parse(digits);
    }
    return SubjectModel(SubjectKind.find, maxResults: max, distinct: distinct);
  }

  PartModel _parsePart(
    String source,
    PartTreeEntity entity,
    bool allIgnoreCase,
  ) {
    var text = source;
    var ignoreCase = false;
    if (_ignoreCase.firstMatch(text) case final m?) {
      ignoreCase = true;
      text = text.replaceRange(m.start, m.end, '');
    }
    if (text.isEmpty) {
      throw QueryProblem('the part "$source" names no property');
    }

    String? firstRest;
    for (final kind in PartKind.values) {
      for (final keyword in kind.keywords) {
        if (!text.endsWith(keyword) || text.length == keyword.length) {
          continue;
        }
        final rest = text.substring(0, text.length - keyword.length);
        firstRest ??= rest;
        final property = _resolve(rest, entity);
        if (property != null) {
          return _part(property, kind, ignoreCase, allIgnoreCase);
        }
      }
    }
    final property = _resolve(text, entity);
    if (property != null) {
      return _part(
        property,
        PartKind.simpleProperty,
        ignoreCase,
        allIgnoreCase,
      );
    }
    throw _unresolved(firstRest ?? text, entity);
  }

  PartModel _part(
    PartTreeProperty property,
    PartKind kind,
    bool ignoreCase,
    bool allIgnoreCase,
  ) {
    _requireColumn(property, 'in a condition');
    final always = allIgnoreCase && kind.argumentCount > 0 && property.isString;
    return PartModel(property.name, kind, ignoreCase: ignoreCase || always);
  }

  List<SortOrderModel> _parseOrder(String clause, PartTreeEntity entity) {
    final orders = <SortOrderModel>[];
    for (final block in _split(clause, _orderBlocks)) {
      final match = _orderBlock.firstMatch(block);
      final property = _resolve(match!.group(1)!, entity);
      if (property == null) {
        throw _unresolved(match.group(1)!, entity);
      }
      _requireColumn(property, 'in OrderBy');
      orders.add(
        SortOrderModel(property.name, descending: match.group(2) == 'Desc'),
      );
    }
    return orders;
  }

  PartTreeProperty? _resolve(String text, PartTreeEntity entity) {
    final uncapitalized = _uncapitalize(text);
    return entity.property(uncapitalized) ?? entity.property(text);
  }

  void _requireColumn(PartTreeProperty property, String where) {
    if (property.isMappedCollection) {
      throw QueryProblem(
        "property '${property.name}' cannot be used $where: it holds child "
        'entities, and derived queries stay within the columns of the root '
        "entity's own table",
        property: property.name,
      );
    }
  }

  QueryProblem _unresolved(String text, PartTreeEntity entity) {
    final name = _uncapitalize(text);
    if (name.contains('_')) {
      return QueryProblem(
        "nested property path '$name' is not supported yet; only "
        "properties of '${entity.name}' can be used",
        property: name,
      );
    }
    for (final property in entity.properties) {
      final p = property.name;
      if (name.length > p.length &&
          name.startsWith(p) &&
          name[p.length].toUpperCase() == name[p.length] &&
          name[p.length].toLowerCase() != name[p.length]) {
        return QueryProblem(
          "nested property path '$name' (property '$p' and then "
          "'${_uncapitalize(name.substring(p.length))}') is not supported "
          'yet; only properties of the entity can be used',
          property: name,
        );
      }
    }
    return unknownProperty(name, entity);
  }

  /// The problem of a name that is no property of [entity], with the
  /// closest property as a hint and the ones there are.
  static QueryProblem unknownProperty(String name, PartTreeEntity entity) {
    final names = [for (final p in entity.columns) p.name];
    final best = closestName(name, names);
    final hint = best == null ? '' : "; did you mean '$best'?";
    return QueryProblem(
      "No property '$name' found for type '${entity.name}'$hint "
      'Available properties: ${names.join(', ')}.',
      property: name,
    );
  }

  static List<String> _split(String text, RegExp pattern) {
    final out = <String>[];
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      out.add(text.substring(last, m.start));
      last = m.end;
    }
    out.add(text.substring(last));
    return out;
  }

  static String _uncapitalize(String text) =>
      text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
}
