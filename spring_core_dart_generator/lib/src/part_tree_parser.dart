import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/did_you_mean.dart';
import 'package:spring_core_dart_generator/src/part_tree.dart';

// The types of spring_boot_starter_data a query method may take or return,
// matched by URL so the generator does not depend on the starter.
const _repositoryUrl = 'package:spring_boot_starter_data/src/repository';
const _sort = TypeChecker.fromUrl('$_repositoryUrl/sort.dart#Sort');
const _pageable = TypeChecker.fromUrl('$_repositoryUrl/page.dart#Pageable');
const _pageRequest = TypeChecker.fromUrl(
  '$_repositoryUrl/page.dart#PageRequest',
);
const _page = TypeChecker.fromUrl('$_repositoryUrl/page.dart#Page');
const _slice = TypeChecker.fromUrl('$_repositoryUrl/page.dart#Slice');

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
  QueryProblem(this.reason);

  /// What is wrong.
  final String reason;

  @override
  String toString() => reason;
}

/// A property the data layer stores for an entity: a field of the class
/// that is not `@Transient`.
final class StoredProperty {
  /// The property [name] of [type].
  StoredProperty(
    this.name,
    this.type, {
    this.isMappedCollection = false,
    this.referencedId,
  });

  /// The Dart name.
  final String name;

  /// The declared type, with nullability; for an `AggregateReference`, the
  /// reference type itself.
  final DartType type;

  /// Whether it holds children in tables of their own (`@MappedCollection`),
  /// which a derived query cannot use.
  final bool isMappedCollection;

  /// For an `AggregateReference<X, ID>`, the type `ID`; `null` otherwise.
  final DartType? referencedId;
}

/// The entity of a repository as a derived query sees it: its name and the
/// properties it stores.
final class QueryEntity {
  /// The entity [element] with its stored [properties], in declaration
  /// order.
  QueryEntity(this.element, List<StoredProperty> properties)
    : properties = List.unmodifiable(properties),
      _byName = {for (final p in properties) p.name: p};

  /// The entity's class.
  final InterfaceElement element;

  /// The class name.
  String get name => element.name!;

  /// The stored properties.
  final List<StoredProperty> properties;

  final Map<String, StoredProperty> _byName;

  /// The stored property named [name], or `null`.
  StoredProperty? property(String name) => _byName[name];

  /// The properties stored in the entity's own table: all but the
  /// `@MappedCollection`s.
  Iterable<StoredProperty> get columns =>
      properties.where((p) => !p.isMappedCollection);

  /// Whether [type] is the entity's class (nullability aside).
  bool isEntity(DartType type) =>
      type is InterfaceType && type.element == element;
}

/// A parameter of a query method.
final class QueryParameter {
  /// The parameter [name] of [type].
  const QueryParameter(this.name, this.type);

  /// The name as the generated code writes it.
  final String name;

  /// The declared type.
  final DartType type;
}

/// Reads a repository method's name as a query (`findTop5ByTitleContaining
/// IgnoreCaseAndYearGreaterThanOrderByYearDesc`) into a [PartTreeModel],
/// and checks it against the entity, the method's parameters and its return
/// type, so that a wrong method is an error of the build.
///
/// [parse] is structural: the name's grammar and the existence of every
/// property (stored in the entity's own table). [validate] needs the
/// method's signature: parameter count and types, `IgnoreCase`, the return
/// type. Both throw a [QueryProblem] for the first mistake.
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
/// final tree = const PartTreeParser().parse('findByTitelContaining', book);
/// // throws: No property 'titel' found for type 'Book'; did you mean
/// // 'title'? Available properties: id, title, year.
/// ```
///
/// Spring (Java): `PartTree`, `Part` and `OrderBySource` of
/// `org.springframework.data.repository.query.parser`.
final class PartTreeParser {
  /// A parser.
  const PartTreeParser();

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

  /// Whether a parameter of [type] is a `Pageable` (or `PageRequest`),
  /// which windows the result instead of filtering it.
  static bool isPageable(DartType type) =>
      _pageable.isExactlyType(type) || _pageRequest.isExactlyType(type);

  /// Whether a parameter of [type] is a `Sort`, which orders the result.
  static bool isSort(DartType type) => _sort.isExactlyType(type);

  /// The shape a result of [type] has: the type inside the `Future` of a
  /// find method, or the `Stream` itself.
  static ResultShape shapeOf(DartType type) =>
      wrapped(type)?.$1 ?? ResultShape.single;

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
  PartTreeModel parse(String methodName, QueryEntity entity) {
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

  /// Checks [tree] (from [parse]) against the method's [parameters] and
  /// [returnType] (the type inside the `Future`, or the `Stream` or the
  /// type itself of a method that is no `Future`; [isFuture] says which);
  /// throws a [QueryProblem] for the first problem.
  ///
  /// Parameters:
  ///
  /// * `Sort` and `Pageable` parameters, anywhere, are special: at most one
  ///   of them, only for a find method (not count, exists, delete), and not
  ///   both (put the sort in the `Pageable`). A `Pageable` is allowed with
  ///   `First`/`Top`.
  /// * The other parameters, in declaration order, are consumed by the
  ///   parts in order, `argumentCount` each; their number must match
  ///   exactly. Named parameters are taken in declaration order too.
  /// * `IgnoreCase` needs a `String` property; `True`/`False` a `bool`;
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
    PartTreeModel tree,
    QueryEntity entity,
    List<QueryParameter> parameters, {
    required DartType returnType,
    required bool isFuture,
  }) {
    final kind = tree.subject.kind;
    QueryParameter? pageable;
    QueryParameter? sort;
    final queryParameters = <QueryParameter>[];
    for (final parameter in parameters) {
      if (isPageable(parameter.type)) {
        if (pageable != null) {
          throw QueryProblem('it has more than one Pageable parameter');
        }
        pageable = parameter;
      } else if (isSort(parameter.type)) {
        if (sort != null) {
          throw QueryProblem('it has more than one Sort parameter');
        }
        sort = parameter;
      } else {
        queryParameters.add(parameter);
      }
    }
    if (pageable != null && sort != null) {
      throw QueryProblem(
        'it has a Pageable and a Sort parameter; sort in the Pageable '
        'instead',
      );
    }
    if ((pageable ?? sort) != null && kind != SubjectKind.find) {
      throw QueryProblem(
        'a Sort or Pageable parameter is only allowed on a find method, '
        'not on ${kind.name}',
      );
    }

    if (queryParameters.length != tree.parameterCount) {
      throw QueryProblem(
        'the name needs ${tree.parameterCount} parameter(s) besides Sort '
        'and Pageable, but the method declares ${queryParameters.length}',
      );
    }
    var index = 0;
    for (final part in tree.parts) {
      final property = entity.property(part.property);
      if (property == null) {
        throw _unknownProperty(part.property, entity);
      }
      final args = queryParameters.sublist(
        index,
        index + part.kind.argumentCount,
      );
      index += part.kind.argumentCount;
      _validatePart(part, property, args);
    }

    _validateReturn(
      tree,
      entity,
      returnType,
      isFuture: isFuture,
      hasPageable: pageable != null,
    );
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
    QueryEntity entity,
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
    StoredProperty property,
    PartKind kind,
    bool ignoreCase,
    bool allIgnoreCase,
  ) {
    _requireColumn(property, 'in a condition');
    final always =
        allIgnoreCase && kind.argumentCount > 0 && _isString(property.type);
    return PartModel(property.name, kind, ignoreCase: ignoreCase || always);
  }

  List<SortOrderModel> _parseOrder(String clause, QueryEntity entity) {
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

  StoredProperty? _resolve(String text, QueryEntity entity) {
    final uncapitalized = _uncapitalize(text);
    return entity.property(uncapitalized) ?? entity.property(text);
  }

  void _requireColumn(StoredProperty property, String where) {
    if (property.isMappedCollection) {
      throw QueryProblem(
        "property '${property.name}' cannot be used $where: it holds child "
        'entities, and derived queries stay within the columns of the root '
        "entity's own table",
      );
    }
  }

  QueryProblem _unresolved(String text, QueryEntity entity) {
    final name = _uncapitalize(text);
    if (name.contains('_')) {
      return QueryProblem(
        "nested property path '$name' is not supported yet; only "
        "properties of '${entity.name}' can be used",
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
        );
      }
    }
    return _unknownProperty(name, entity);
  }

  QueryProblem _unknownProperty(String name, QueryEntity entity) {
    final names = [for (final p in entity.columns) p.name];
    final best = closestName(name, names);
    final hint = best == null ? '' : "; did you mean '$best'?";
    return QueryProblem(
      "No property '$name' found for type '${entity.name}'$hint "
      'Available properties: ${names.join(', ')}.',
    );
  }

  void _validatePart(
    PartModel part,
    StoredProperty property,
    List<QueryParameter> args,
  ) {
    final kind = part.kind;
    final propertyType = _show(property.type);
    final label = "'${property.name}' ($propertyType) with ${kind.name}";
    if (part.ignoreCase && !_isString(property.type)) {
      throw QueryProblem(
        "IgnoreCase needs a String property, but '${property.name}' is "
        '$propertyType',
      );
    }
    switch (kind) {
      case PartKind.isTrue || PartKind.isFalse:
        if (!property.type.isDartCoreBool) {
          throw QueryProblem(
            "True/False need a bool property, but '${property.name}' is "
            '$propertyType',
          );
        }
      case PartKind.like ||
          PartKind.notLike ||
          PartKind.startingWith ||
          PartKind.endingWith ||
          PartKind.containing ||
          PartKind.notContaining:
        if (!_isString(property.type)) {
          throw QueryProblem(
            '${kind.name} needs a String property, but $label is not',
          );
        }
        if (!_isString(args.single.type)) {
          throw QueryProblem(
            "parameter '${args.single.name}' (${_show(args.single.type)}) "
            'must be a String for ${kind.name} on $label',
          );
        }
      case PartKind.in_ || PartKind.notIn:
        final element = _elementOf(args.single.type);
        if (element == null) {
          throw QueryProblem(
            "parameter '${args.single.name}' (${_show(args.single.type)}) "
            'must be a List, Set or Iterable for ${kind.name} on $label',
          );
        }
        if (!_fits(property, element)) {
          throw QueryProblem(
            "the elements of parameter '${args.single.name}' "
            '(${_show(element)}) do not fit $label',
          );
        }
      case PartKind.between ||
          PartKind.isNotNull ||
          PartKind.isNull ||
          PartKind.lessThan ||
          PartKind.lessThanEqual ||
          PartKind.greaterThan ||
          PartKind.greaterThanEqual ||
          PartKind.negatingSimpleProperty ||
          PartKind.simpleProperty:
        for (final arg in args) {
          if (!_fits(property, arg.type)) {
            throw QueryProblem(
              "parameter '${arg.name}' (${_show(arg.type)}) does not fit "
              '$label',
            );
          }
        }
    }
  }

  void _validateReturn(
    PartTreeModel tree,
    QueryEntity entity,
    DartType returnType, {
    required bool isFuture,
    required bool hasPageable,
  }) {
    final entityName = entity.name;
    switch (tree.subject.kind) {
      case SubjectKind.count:
        if (!returnType.isDartCoreInt) {
          throw QueryProblem('a count method must return int');
        }
      case SubjectKind.exists:
        if (!returnType.isDartCoreBool) {
          throw QueryProblem('an exists method must return bool');
        }
      case SubjectKind.delete:
        final shaped = wrapped(returnType);
        final list =
            returnType.isDartCoreList &&
            shaped != null &&
            entity.isEntity(shaped.$2);
        if (returnType is! VoidType && !returnType.isDartCoreInt && !list) {
          throw QueryProblem(
            'a delete method must return void, int (the number deleted) '
            'or List<$entityName>',
          );
        }
      case SubjectKind.find:
        if (entity.isEntity(returnType)) {
          return;
        }
        final element = wrapped(returnType);
        if (element == null || !entity.isEntity(element.$2)) {
          throw QueryProblem(
            'a find method must return $entityName, or a List, Set, '
            'Iterable, Stream, Page or Slice of $entityName (projections '
            'are not supported), not ${_show(returnType)}',
          );
        }
        switch (element.$1) {
          case ResultShape.stream when isFuture:
            throw QueryProblem(
              'a Stream is already asynchronous: return Stream<$entityName>, '
              'not a Future of it',
            );
          case ResultShape.page || ResultShape.slice when !hasPageable:
            throw QueryProblem(
              'a method returning Page or Slice needs a Pageable parameter',
            );
          case ResultShape.list ||
              ResultShape.set ||
              ResultShape.stream ||
              ResultShape.page ||
              ResultShape.slice ||
              ResultShape.single:
        }
    }
  }

  /// The shape of a collection-like [type] (`List`, `Set`, `Iterable`,
  /// `Page`, `Slice`, `Stream`) and the type of its elements; `null` for
  /// anything else.
  static (ResultShape, DartType)? wrapped(DartType type) {
    if (type is! InterfaceType) {
      return null;
    }
    if (type.typeArguments.length != 1) {
      return null;
    }
    final element = type.typeArguments.single;
    if (type.isDartCoreList) {
      return (ResultShape.list, element);
    }
    if (type.isDartCoreSet) {
      return (ResultShape.set, element);
    }
    if (_page.isAssignableFromType(type)) {
      return (ResultShape.page, element);
    }
    if (_slice.isAssignableFromType(type)) {
      return (ResultShape.slice, element);
    }
    if (_isSubtype(type, (t) => t.isDartAsyncStream)) {
      return (ResultShape.stream, element);
    }
    if (_isSubtype(type, (t) => t.isDartCoreIterable)) {
      return (ResultShape.list, element);
    }
    return null;
  }

  static bool _isSubtype(InterfaceType type, bool Function(DartType) test) =>
      test(type) || type.allSupertypes.any(test);

  // The type of the elements of a collection parameter (`In`); `dynamic`
  // fits anything; null when it is no collection.
  DartType? _elementOf(DartType type) {
    if (type is DynamicType) {
      return type;
    }
    if (type is! InterfaceType) {
      return null;
    }
    if (type.isDartCoreIterable) {
      return type.typeArguments.firstOrNull ?? type;
    }
    for (final supertype in type.allSupertypes) {
      if (supertype.isDartCoreIterable) {
        return supertype.typeArguments.firstOrNull;
      }
    }
    return null;
  }

  bool _fits(StoredProperty property, DartType value) {
    if (_typeFits(property.type, value)) {
      return true;
    }
    final id = property.referencedId;
    return id != null && _typeFits(id, value);
  }

  bool _typeFits(DartType target, DartType value) {
    if (value is DynamicType || target is DynamicType) {
      return true;
    }
    return _sameType(target, value) ||
        value.isDartCoreObject ||
        (_isNumber(target) && _isNumber(value));
  }

  // The same class with the same type arguments, nullability aside.
  bool _sameType(DartType a, DartType b) {
    if (a is InterfaceType && b is InterfaceType) {
      if (a.element != b.element ||
          a.typeArguments.length != b.typeArguments.length) {
        return false;
      }
      for (var i = 0; i < a.typeArguments.length; i++) {
        if (!_sameType(a.typeArguments[i], b.typeArguments[i])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  bool _isNumber(DartType type) =>
      type.isDartCoreInt || type.isDartCoreDouble || type.isDartCoreNum;

  bool _isString(DartType type) => type.isDartCoreString;

  String _show(DartType type) => type.getDisplayString();

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
