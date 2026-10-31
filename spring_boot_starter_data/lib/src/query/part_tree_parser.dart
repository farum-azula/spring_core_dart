import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'package:spring_boot_starter_data/src/exceptions.dart';
import 'package:spring_boot_starter_data/src/mapping/persistent_entity.dart';
import 'package:spring_boot_starter_data/src/query/part_tree.dart';
import 'package:spring_boot_starter_data/src/repository/page.dart';
import 'package:spring_boot_starter_data/src/repository/sort.dart';

/// A repository method whose name is not a valid query, or does not fit
/// the entity, its parameters or its return type. Thrown when the query is
/// created (at start up), never while it runs.
///
/// The [message] says exactly what is wrong; for an unknown property it
/// lists the entity's properties and suggests the closest one.
///
/// Spring (Java):
/// `org.springframework.data.repository.query.QueryCreationException`.
class QueryCreationException extends InvalidDataAccessApiUsageException {
  /// The method [methodName] (of [repositoryName], when known) cannot be
  /// turned into a query because of [reason].
  QueryCreationException(
    this.reason, {
    required this.methodName,
    this.repositoryName,
  }) : super(
         'Failed to create query for method '
         '${repositoryName == null ? '' : '$repositoryName.'}$methodName: '
         '$reason',
       );

  /// The repository method's name.
  final String methodName;

  /// The repository interface's name, or null when not known.
  final String? repositoryName;

  /// What is wrong, without the method's name.
  final String reason;
}

/// Reads a repository method's name as a query (`findTop5ByTitleContaining
/// IgnoreCaseAndYearGreaterThanOrderByYearDesc`) into a [PartTree], and
/// checks the tree against the entity, the method's parameters and its
/// return type.
///
/// [parse] is structural: the name's grammar and the existence of every
/// property (stored in the entity's own table). [validate] needs the
/// method's signature: parameter count and types, `ignoreCase`, the return
/// type. A generator calls both for each method, so a wrong method is an
/// error at build or start up.
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
/// Spring (Java): `PartTree`, `Part` and `OrderBySource` of
/// `org.springframework.data.repository.query.parser`.
final class PartTreeParser {
  /// A parser; [repositoryName] only improves the messages.
  const PartTreeParser({this.repositoryName});

  /// The repository's name for messages; null when not known.
  final String? repositoryName;

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

  /// Parses [methodName] into a [PartTree] for [entity].
  ///
  /// Throws a [QueryCreationException] when the name is not a derived
  /// query (no prefix and `By`), has two `OrderBy`, an unknown property, a
  /// property that is not a column of the entity's own table (a
  /// `@MappedCollection` or a child entity), a nested path
  /// (`AddressCity`, `Address_City`: not supported yet), or an empty part.
  ///
  /// An empty predicate (`findAllBy`, `findBy`, `countBy`,
  /// `findAllByOrderByTitleAsc`) matches every aggregate, as in Spring.
  PartTree parse(String methodName, PersistentEntity<Object> entity) {
    final match = _subject.firstMatch(methodName);
    if (match == null) {
      throw _error(
        methodName,
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
      throw _error(methodName, 'the name has more than one "OrderBy"');
    }
    final or = <OrPart>[];
    for (final alternative in _split(blocks.first, _or)) {
      if (alternative.isEmpty) {
        continue;
      }
      final parts = <Part>[
        for (final text in _split(alternative, _and))
          if (text.isNotEmpty)
            _parsePart(methodName, text, entity, allIgnoreCase),
      ];
      if (parts.isNotEmpty) {
        or.add(OrPart(parts));
      }
    }
    final sort = blocks.length == 2
        ? _parseOrder(methodName, blocks[1], entity)
        : Sort.unsorted;
    return PartTree(
      methodName: methodName,
      subject: subject,
      predicate: or,
      sort: sort,
    );
  }

  /// Checks [tree] (from [parse]) against the method's [parameters] and
  /// [returnType] ([returnType] is the type inside the `Future` when
  /// [isFuture]); throws a [QueryCreationException] for the first problem.
  ///
  /// Parameters:
  ///
  /// * `Sort` and `Pageable` parameters, anywhere, are special: at most one
  ///   of them, only for a find method (not count, exists, delete), and not
  ///   both (put the sort in the `Pageable`). A `Pageable` is allowed with
  ///   `First`/`Top`.
  /// * The other parameters, in declaration order, are consumed by the
  ///   parts in order, [PartType.argumentCount] each; their number must
  ///   match exactly. Named parameters are taken in declaration order too.
  /// * `ignoreCase` needs a `String` property; `True`/`False` a `bool`;
  ///   `Like`, `NotLike`, `StartingWith`, `EndingWith`, `Containing` and
  ///   `NotContaining` a `String` property and a `String` parameter;
  ///   `In`/`NotIn` a `List`, `Set` or `Iterable` parameter whose elements
  ///   fit the property; the others a parameter that fits the property:
  ///   the same type (nullability ignored), `num`/`int`/`double` with each
  ///   other, for an `AggregateReference` property the reference or its id
  ///   type, and a `dynamic` or `Object` parameter always fits.
  ///
  /// Return type:
  ///
  /// * count: `int`; exists: `bool`;
  /// * delete: `void`, `int` (the number deleted) or `List<Entity>` (the
  ///   deleted aggregates);
  /// * find: `Entity` (nullable: at most one result, null for none;
  ///   non-nullable: exactly one, the store throws when there is none),
  ///   `List`, `Set`, `Iterable` or `Stream` of the entity, or `Page` /
  ///   `Slice` of it, which need a `Pageable` parameter. `Stream` is not
  ///   wrapped in a `Future`. Projections and DTOs are not supported.
  void validate(
    PartTree tree,
    PersistentEntity<Object> entity,
    List<BeanParameter> parameters, {
    required TypeInfo<Object?> returnType,
    required bool isFuture,
  }) {
    final name = tree.methodName;
    final kind = tree.subject.kind;
    BeanParameter? pageable;
    BeanParameter? sort;
    final queryParameters = <BeanParameter>[];
    for (final parameter in parameters) {
      final type = parameter.type.type;
      if (type == Pageable || type == PageRequest) {
        if (pageable != null) {
          throw _error(name, 'it has more than one Pageable parameter');
        }
        pageable = parameter;
      } else if (type == Sort) {
        if (sort != null) {
          throw _error(name, 'it has more than one Sort parameter');
        }
        sort = parameter;
      } else {
        queryParameters.add(parameter);
      }
    }
    if (pageable != null && sort != null) {
      throw _error(
        name,
        'it has a Pageable and a Sort parameter; sort in the Pageable '
        'instead',
      );
    }
    if ((pageable ?? sort) != null && kind != SubjectKind.find) {
      throw _error(
        name,
        'a Sort or Pageable parameter is only allowed on a find method, '
        'not on ${kind.name}',
      );
    }

    if (queryParameters.length != tree.parameterCount) {
      throw _error(
        name,
        'the name needs ${tree.parameterCount} parameter(s) besides Sort '
        'and Pageable, but the method declares ${queryParameters.length}',
      );
    }
    var index = 0;
    for (final part in tree.parts) {
      final property = entity.property(part.path.first);
      if (property == null) {
        throw _unknownProperty(name, part.path.first, entity);
      }
      final args = queryParameters.sublist(
        index,
        index + part.type.argumentCount,
      );
      index += part.type.argumentCount;
      _validatePart(name, part, property, args);
    }

    _validateReturn(
      tree,
      entity,
      returnType,
      isFuture: isFuture,
      hasPageable: pageable != null,
    );
  }

  Subject _subjectOf(String prefix, String middle) {
    final distinct = middle.contains('Distinct');
    switch (prefix) {
      case 'count':
        return Subject(SubjectKind.count, distinct: distinct);
      case 'exists':
        return Subject(SubjectKind.exists, distinct: distinct);
      case 'delete' || 'remove':
        return Subject(SubjectKind.delete, distinct: distinct);
    }
    int? max;
    final limit = _limit.firstMatch(middle.replaceFirst('Distinct', ''));
    if (limit != null) {
      final digits = limit.group(2)!;
      max = digits.isEmpty ? 1 : int.parse(digits);
    }
    return Subject(SubjectKind.find, maxResults: max, distinct: distinct);
  }

  Part _parsePart(
    String methodName,
    String source,
    PersistentEntity<Object> entity,
    bool allIgnoreCase,
  ) {
    var text = source;
    var ignoreCase = false;
    if (_ignoreCase.firstMatch(text) case final m?) {
      ignoreCase = true;
      text = text.replaceRange(m.start, m.end, '');
    }
    if (text.isEmpty) {
      throw _error(methodName, 'the part "$source" names no property');
    }

    String? firstRest;
    for (final type in PartType.values) {
      for (final keyword in type.keywords) {
        if (!text.endsWith(keyword) || text.length == keyword.length) {
          continue;
        }
        final rest = text.substring(0, text.length - keyword.length);
        firstRest ??= rest;
        final property = _resolve(rest, entity);
        if (property != null) {
          return _part(methodName, property, type, ignoreCase, allIgnoreCase);
        }
      }
    }
    final property = _resolve(text, entity);
    if (property != null) {
      return _part(
        methodName,
        property,
        PartType.simpleProperty,
        ignoreCase,
        allIgnoreCase,
      );
    }
    throw _unresolved(methodName, firstRest ?? text, entity);
  }

  Part _part(
    String methodName,
    PersistentProperty property,
    PartType type,
    bool ignoreCase,
    bool allIgnoreCase,
  ) {
    _requireColumn(methodName, property, 'in a condition');
    final always =
        allIgnoreCase && type.argumentCount > 0 && _isString(property.type);
    return Part([property.name], type, ignoreCase: ignoreCase || always);
  }

  Sort _parseOrder(
    String methodName,
    String clause,
    PersistentEntity<Object> entity,
  ) {
    final orders = <SortOrder>[];
    for (final block in _split(clause, _orderBlocks)) {
      final match = _orderBlock.firstMatch(block);
      final property = _resolve(match!.group(1)!, entity);
      if (property == null) {
        throw _unresolved(methodName, match.group(1)!, entity);
      }
      _requireColumn(methodName, property, 'in OrderBy');
      orders.add(
        match.group(2) == 'Desc'
            ? SortOrder.desc(property.name)
            : SortOrder.asc(property.name),
      );
    }
    return Sort.byOrders(orders);
  }

  PersistentProperty? _resolve(String text, PersistentEntity<Object> entity) {
    final uncapitalized = _uncapitalize(text);
    return entity.property(uncapitalized) ?? entity.property(text);
  }

  void _requireColumn(
    String methodName,
    PersistentProperty property,
    String where,
  ) {
    if (property.isMappedCollection || property.childEntity != null) {
      throw _error(
        methodName,
        "property '${property.name}' cannot be used $where: it holds child "
        'entities, and derived queries stay within the columns of the root '
        "entity's own table",
      );
    }
  }

  QueryCreationException _unresolved(
    String methodName,
    String text,
    PersistentEntity<Object> entity,
  ) {
    final name = _uncapitalize(text);
    if (name.contains('_')) {
      return _error(
        methodName,
        "nested property path '$name' is not supported yet; only "
        "properties of '${entity.type}' can be used",
      );
    }
    for (final property in entity.properties) {
      final p = property.name;
      if (name.length > p.length &&
          name.startsWith(p) &&
          name[p.length].toUpperCase() == name[p.length] &&
          name[p.length].toLowerCase() != name[p.length]) {
        return _error(
          methodName,
          "nested property path '$name' (property '$p' and then "
          "'${_uncapitalize(name.substring(p.length))}') is not supported "
          'yet; only properties of the entity can be used',
        );
      }
    }
    return _unknownProperty(methodName, name, entity);
  }

  QueryCreationException _unknownProperty(
    String methodName,
    String name,
    PersistentEntity<Object> entity,
  ) {
    final names = [for (final p in entity.columns) p.name];
    String? best;
    var bestDistance = 1 << 30;
    for (final candidate in names) {
      final distance = _distance(name.toLowerCase(), candidate.toLowerCase());
      final longest = name.length > candidate.length
          ? name.length
          : candidate.length;
      if (distance < bestDistance && distance <= (longest / 3).ceil()) {
        best = candidate;
        bestDistance = distance;
      }
    }
    final hint = best == null ? '' : "; did you mean '$best'?";
    return _error(
      methodName,
      "No property '$name' found for type '${entity.type}'$hint "
      'Available properties: ${names.join(', ')}.',
    );
  }

  void _validatePart(
    String name,
    Part part,
    PersistentProperty property,
    List<BeanParameter> args,
  ) {
    final type = part.type;
    final label = "'${property.name}' (${property.type}) with ${type.name}";
    if (part.ignoreCase && !_isString(property.type)) {
      throw _error(
        name,
        "IgnoreCase needs a String property, but '${property.name}' is "
        '${property.type}',
      );
    }
    switch (type) {
      case PartType.isTrue || PartType.isFalse:
        if (property.type.type != bool) {
          throw _error(
            name,
            "True/False need a bool property, but '${property.name}' is "
            '${property.type}',
          );
        }
      case PartType.like ||
          PartType.notLike ||
          PartType.startingWith ||
          PartType.endingWith ||
          PartType.containing ||
          PartType.notContaining:
        if (!_isString(property.type)) {
          throw _error(
            name,
            '${type.name} needs a String property, but $label is not',
          );
        }
        if (!_isString(args.single.type)) {
          throw _error(
            name,
            "parameter '${args.single.name}' (${args.single.type}) must be "
            'a String for ${type.name} on $label',
          );
        }
      case PartType.in_ || PartType.notIn:
        final element = _elementOf(args.single.type);
        if (element == null) {
          throw _error(
            name,
            "parameter '${args.single.name}' (${args.single.type}) must be "
            'a List, Set or Iterable for ${type.name} on $label',
          );
        }
        if (!_fits(property, element)) {
          throw _error(
            name,
            "the elements of parameter '${args.single.name}' ($element) do "
            'not fit $label',
          );
        }
      case PartType.between ||
          PartType.isNotNull ||
          PartType.isNull ||
          PartType.lessThan ||
          PartType.lessThanEqual ||
          PartType.greaterThan ||
          PartType.greaterThanEqual ||
          PartType.negatingSimpleProperty ||
          PartType.simpleProperty:
        for (final arg in args) {
          if (!_fits(property, arg.type)) {
            throw _error(
              name,
              "parameter '${arg.name}' (${arg.type}) does not fit $label",
            );
          }
        }
    }
  }

  void _validateReturn(
    PartTree tree,
    PersistentEntity<Object> entity,
    TypeInfo<Object?> returnType, {
    required bool isFuture,
    required bool hasPageable,
  }) {
    final name = tree.methodName;
    final entityName = entity.type.toString();
    bool isEntity(TypeInfo<Object?> t) => t.type == entity.type;
    switch (tree.subject.kind) {
      case SubjectKind.count:
        if (returnType.type != int) {
          throw _error(name, 'a count method must return int');
        }
      case SubjectKind.exists:
        if (returnType.type != bool) {
          throw _error(name, 'an exists method must return bool');
        }
      case SubjectKind.delete:
        final isVoid = returnType is DynamicType && returnType.isVoid;
        final list = returnType is ListType && isEntity(returnType.element);
        if (!isVoid && returnType.type != int && !list) {
          throw _error(
            name,
            'a delete method must return void, int (the number deleted) '
            'or List<$entityName>',
          );
        }
      case SubjectKind.find:
        if (isEntity(returnType)) {
          return;
        }
        final element = _findElement(returnType);
        if (element == null || !isEntity(element.$2)) {
          throw _error(
            name,
            'a find method must return $entityName, or a List, Set, '
            'Iterable, Stream, Page or Slice of $entityName (projections '
            'are not supported), not $returnType',
          );
        }
        switch (element.$1) {
          case _Wrapper.stream when isFuture:
            throw _error(
              name,
              'a Stream is already asynchronous: return Stream<$entityName>, '
              'not a Future of it',
            );
          case _Wrapper.page || _Wrapper.slice when !hasPageable:
            throw _error(
              name,
              'a method returning Page or Slice needs a Pageable parameter',
            );
          case _Wrapper.list ||
              _Wrapper.set ||
              _Wrapper.iterable ||
              _Wrapper.stream ||
              _Wrapper.page ||
              _Wrapper.slice:
        }
    }
  }

  (_Wrapper, TypeInfo<Object?>)? _findElement(TypeInfo<Object?> t) {
    if (t is ListType) {
      return (_Wrapper.list, t.element);
    }
    if (t is SetType) {
      return (_Wrapper.set, t.element);
    }
    if (t is GenericType && t.arguments.length == 1) {
      final element = t.arguments.single;
      if (t.isSubtypeOf<Page<Object?>>()) {
        return (_Wrapper.page, element);
      }
      if (t.isSubtypeOf<Slice<Object?>>()) {
        return (_Wrapper.slice, element);
      }
      if (t.isSubtypeOf<Stream<Object?>>()) {
        return (_Wrapper.stream, element);
      }
      if (t.isSubtypeOf<Iterable<Object?>>()) {
        return (_Wrapper.iterable, element);
      }
    }
    return null;
  }

  TypeInfo<Object?>? _elementOf(TypeInfo<Object?> t) {
    if (t is DynamicType) {
      return t;
    }
    if (t is ListType) {
      return t.element;
    }
    if (t is SetType) {
      return t.element;
    }
    if (t is GenericType && t.isSubtypeOf<Iterable<Object?>>()) {
      return t.arguments.isEmpty ? const DynamicType() : t.arguments.first;
    }
    return null;
  }

  bool _fits(PersistentProperty property, TypeInfo<Object?> value) {
    if (_typeFits(property.type, value)) {
      return true;
    }
    final id = property.referencedType;
    return id != null && _typeFits(id, value);
  }

  static const _numbers = {int, double, num};

  bool _typeFits(TypeInfo<Object?> target, TypeInfo<Object?> value) {
    if (value is DynamicType || target is DynamicType) {
      return true;
    }
    final a = target.type;
    final b = value.type;
    return a == b ||
        b == Object ||
        (_numbers.contains(a) && _numbers.contains(b));
  }

  bool _isString(TypeInfo<Object?> t) => t.type == String;

  QueryCreationException _error(String methodName, String reason) =>
      QueryCreationException(
        reason,
        methodName: methodName,
        repositoryName: repositoryName,
      );

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

  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final best = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        current[j] = best;
      }
      previous = current;
    }
    return previous[b.length];
  }
}

enum _Wrapper { list, set, iterable, stream, page, slice }
