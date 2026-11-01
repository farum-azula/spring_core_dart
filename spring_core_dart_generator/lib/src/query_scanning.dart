part of 'bean_scanner.dart';

// The `@Query` methods of a data repository, checked by the build. What
// the starter used to check when the application started is checked here,
// and what it still has to do (resolve `${property}` placeholders, run the
// expressions, bind, map) is told by a `QueryMethod`, which the build
// writes as a constant:
//
// ```dart
// @Query('select title from books where year = :year')
// Future<List<BookCard>> cards(int year);
//
// // Output:
// static const _cards = QueryMethod(
//   r'cards',
//   Query(r'select title from books where year = :year'),
//   parameters: [r'year'],
//   element: ClassType<BookCard>(),
// );
// ```
//
// The method's own problems (its signature against its annotation) are
// found while the repository is scanned. The text of the query needs the
// entities of the whole application and its schema, so it is checked once
// every library is scanned (see `_checkQueries`), and its problems join
// those of the repository in the one build error.

const _modifying = TypeChecker.fromUrl('$_dataAnnotations#Modifying');
const _column = TypeChecker.fromUrl('$_dataAnnotations#Column');
const _namingStrategy = TypeChecker.fromUrl(
  'package:spring_boot_starter_data/src/mapping/naming_strategy.dart'
  '#NamingStrategy',
);
const _jdbcDriver =
    'package:spring_boot_starter_data/src/jdbc/jdbc_driver.dart';
const _jdbcRow = TypeChecker.fromUrl('$_jdbcDriver#JdbcRow');
const _jdbcResult = TypeChecker.fromUrl('$_jdbcDriver#JdbcResult');

/// The texts of one `@Query` method, kept to be checked once the whole
/// application is scanned.
final class _QueryText {
  _QueryText(this.where, this.texts, this.names, this.model);

  // `Repository.method`.
  final String where;

  // The SQL and the count query, as `(label, text)`.
  final List<(String, String)> texts;

  // The parameters bound by name.
  final List<String> names;

  // The descriptor, which learns the expressions and the entities.
  final QueryMethodModel model;
}

/// A repository whose `@Query` texts wait for the end of the scan.
final class _RepositoryCheck {
  _RepositoryCheck(this.element, this.name, this.problems, this.queries);

  final ClassElement element;
  final String name;
  final List<String> problems;
  final List<_QueryText> queries;
}

extension _QueryScanning on BeanScanner {
  /// What the starter is told of the `@Query` method [member], or `null`
  /// when it has a problem (added to [problems]); its text is added to
  /// [queries].
  QueryMethodModel? _queryMethod(
    String where,
    ProxyMember member, {
    required DartObject query,
    required DartObject? lock,
    required DartObject? modifying,
    required DartType valueType,
    required bool isFuture,
    required bool isStream,
    required InterfaceElement entity,
    required List<String> problems,
    required List<_QueryText> queries,
  }) {
    final before = problems.length;
    void problem(String reason) => problems.add('$where: $reason');
    final reader = ConstantReader(query);
    final sql = reader.peek('value')?.stringValue ?? '';
    final countQuery = reader.peek('countQuery');
    final count = countQuery != null && countQuery.isString
        ? countQuery.stringValue
        : null;
    final rowMapper = reader.peek('rowMapper');
    final extractor = reader.peek('resultSetExtractor');
    final hasMapper = rowMapper != null && !rowMapper.isNull;
    final hasExtractor = extractor != null && !extractor.isNull;

    // ---- the annotation
    if (sql.trim().isEmpty) {
      problem(
        reader.peek('name')?.isNull == false
            ? 'named queries (@Query(name: ...)) are not supported yet; give '
                  'the SQL as the value'
            : '@Query has no SQL',
      );
    }
    if (hasMapper && hasExtractor) {
      problem('@Query has both rowMapper and resultSetExtractor: use one');
    }
    for (final (what, function, parameter, type) in [
      ('rowMapper', rowMapper, 'JdbcRow', _jdbcRow),
      ('resultSetExtractor', extractor, 'JdbcResult', _jdbcResult),
    ]) {
      if (function != null &&
          !function.isNull &&
          !_takes(function.objectValue, type)) {
        problem(
          'the $what is a ${function.objectValue.type?.getDisplayString()}: '
          'it must be a function that takes a $parameter (a static method or '
          'a top-level function)',
        );
      }
    }

    // ---- the method
    if (!isFuture && !isStream) {
      problems.add(_notAsynchronous(where, valueType));
    }
    if (lock != null) {
      problem(
        '@Lock is for the derived find methods and findById; in a @Query '
        'write the lock in the SQL (select ... for update) and call it in a '
        'transaction',
      );
    }
    int? pageable;
    int? sort;
    final names = <String>[];
    for (final (index, parameter) in member.parameters.indexed) {
      if (PartTreeParser.isPageable(parameter.type)) {
        if (pageable != null) {
          problem('more than one Pageable parameter');
        }
        pageable = index;
      } else if (PartTreeParser.isSort(parameter.type)) {
        if (sort != null) {
          problem('more than one Sort parameter');
        }
        sort = index;
      } else {
        names.add(parameter.name);
      }
    }

    var shape = ResultShape.single;
    DartType? element;
    ModifyingResult? change;
    if (modifying != null) {
      change = switch (valueType) {
        VoidType() => ModifyingResult.nothing,
        _ when valueType.isDartCoreInt => ModifyingResult.rows,
        _ when valueType.isDartCoreBool => ModifyingResult.any,
        _ => null,
      };
      if (change == null) {
        problem(
          '@Modifying returns the rows changed (Future<int>), whether any '
          'changed (Future<bool>) or nothing (Future<void>), not '
          '${valueType.getDisplayString()}',
        );
      }
      if (hasMapper || hasExtractor) {
        problem('@Modifying has no result to map: drop the rowMapper');
      }
      if (pageable != null) {
        problem('@Modifying cannot take a Pageable');
      }
    } else {
      if (valueType is VoidType) {
        problem(
          'the method returns nothing: a change needs @Modifying, a read a '
          'result type',
        );
      }
      final wrapped = PartTreeParser.wrapped(valueType);
      shape = wrapped?.$1 ?? ResultShape.single;
      element = wrapped?.$2 ?? valueType;
      if (shape == ResultShape.stream && isFuture) {
        problem(
          'a Stream is already asynchronous: return Stream<'
          '${element.getDisplayString()}>, not a Future of it',
        );
      }
      if ((shape == ResultShape.page || shape == ResultShape.slice) &&
          pageable == null) {
        problem(
          'a ${shape.name} needs a Pageable parameter (the window to read)',
        );
      }
      if (hasExtractor) {
        if (shape != ResultShape.single &&
            shape != ResultShape.list &&
            shape != ResultShape.set) {
          problem(
            'a resultSetExtractor gives the whole result: return what it '
            'returns, or a List or Set of it, not a ${shape.name}',
          );
        }
        if (pageable != null) {
          problem(
            'a resultSetExtractor reads the whole result: it cannot be '
            'paged',
          );
        }
      }
      if (!hasMapper && !hasExtractor && valueType is! VoidType) {
        if (_unreadable(element, entity) case final reason?) {
          problem(reason);
        }
      }
    }
    if (count != null && shape != ResultShape.page) {
      problem('countQuery is for a method that returns a Page');
    }
    if (problems.length > before) {
      return null;
    }
    final model = QueryMethodModel(
      member,
      query: query,
      shape: shape,
      element: element,
      change: change,
      pageable: pageable,
      sort: sort,
    );
    queries.add(
      _QueryText(
        where,
        [('', sql), if (count != null) (' (countQuery)', count)],
        names,
        model,
      ),
    );
    return model;
  }

  // Whether [function], the value of a `rowMapper` or `resultSetExtractor`,
  // can be called with one argument of the type [parameter] stands for:
  // it takes one positional parameter that accepts it, and nothing else is
  // required.
  bool _takes(DartObject function, TypeChecker parameter) {
    final type = function.type;
    if (type is! FunctionType) {
      return false;
    }
    final positional = [
      for (final p in type.formalParameters)
        if (p.isPositional) p,
    ];
    if (positional.isEmpty ||
        type.formalParameters.where((p) => p.isRequiredPositional).length > 1 ||
        type.formalParameters.any((p) => p.isRequiredNamed)) {
      return false;
    }
    final accepted = positional.first.type;
    return accepted is DynamicType ||
        accepted.isDartCoreObject ||
        parameter.isExactlyType(accepted);
  }

  // Why rows cannot become [element] when no `rowMapper` or
  // `resultSetExtractor` maps them, or `null` when they can: the entity of
  // the repository, a column type, a `Map<String, Object?>`, or a class the
  // build describes (an entity of another repository, a DTO).
  String? _unreadable(DartType element, InterfaceElement entity) {
    if (element is DynamicType) {
      return 'the result type is not known (dynamic): return the entity, a '
          'class of yours, a column type or a Map, or give a rowMapper';
    }
    if (element is! InterfaceType) {
      return '${element.getDisplayString()} cannot be built from rows: '
          'return the entity, a class of yours, a column type or a '
          'Map<String, Object?>, or give a rowMapper';
    }
    if (element.element == entity || _isColumnType(element)) {
      return null;
    }
    if (element.isDartCoreMap) {
      final [key, value] = element.typeArguments;
      return key.isDartCoreString &&
              (value is DynamicType || value.isDartCoreObject)
          ? null
          : 'a row as a map is a Map<String, Object?>, not '
                '${element.getDisplayString()}';
    }
    if (element.element.library.isInSdk ||
        _aggregateReference.isExactlyType(element)) {
      return '${element.getDisplayString()} cannot be built from rows: it is '
          'no column type, no Map<String, Object?> and no class of yours; '
          'return the entity, a class of yours, a column type or a Map, or '
          'give a rowMapper';
    }
    return null;
  }

  // What one column holds: a number, text, bool, DateTime, BigInt, bytes
  // or an enum.
  bool _isColumnType(InterfaceType type) {
    for (final candidate in [type, ...type.allSupertypes]) {
      final element = candidate.element;
      final library = element.library.uri.toString();
      if (library == 'dart:core' &&
          const {
            'num',
            'String',
            'bool',
            'DateTime',
            'BigInt',
            'Enum',
          }.contains(element.name)) {
        return true;
      }
      if (library == 'dart:typed_data' && element.name == 'Uint8List') {
        return true;
      }
    }
    return false;
  }

  /// Checks the texts of the `@Query` methods of every repository scanned,
  /// now that all entities and beans are known: the parameters, the
  /// placeholders, the names of tables and columns. Every problem joins the
  /// ones of its repository in one error, and the descriptors learn their
  /// expressions and entities.
  void _checkQueries() {
    if (_repositoryChecks.isEmpty) {
      return;
    }
    final schema = _dataSchema();
    final checker = QueryTextChecker(schema);
    // The `@Table` classes only: a DTO of the same name is no entity.
    final classes = {
      for (final entity in module.entities)
        if (_table.hasAnnotationOf(entity.element))
          entity.element.name!: entity.type,
    };
    final beans = _expressionBeans();
    for (final check in _repositoryChecks) {
      for (final query in check.queries) {
        final entities = <String, InterfaceType>{};
        final expressions = <QueryExpressionModel>[];
        for (final (label, text) in query.texts) {
          final where = '${query.where}$label';
          final result = checker.check(
            text,
            where: where,
            names: query.names,
            problem: check.problems.add,
          );
          for (final name in result.entities) {
            entities[name] = classes[name]!;
          }
          for (final name in result.unresolved) {
            if (_visibleEntity(check.element, name, where, check.problems)
                case final type?) {
              entities[name] = type;
            }
          }
          for (final expression in result.expressions) {
            expressions.add(
              _compileExpression(expression, check, query, where, beans),
            );
          }
        }
        query.model
          ..expressions = expressions
          ..beans = beans
          ..entities = {
            for (final name in entities.keys.toList()..sort())
              name: entities[name]!,
          };
        // What the starter interprets reads the properties and calls the
        // methods of its arguments through their introspection; what the
        // build compiled needs none.
        if (expressions.any((expression) => !expression.compiled)) {
          for (final parameter in query.model.member.parameters) {
            collectErrors(
              () => _introspectUsed(
                parameter.type,
                check.element,
                need: IntrospectionNeed.spel,
              ),
            );
          }
          // So are the beans it names (`@catalog.lookup(...)`): the
          // interpreter calls their methods the same way.
          for (final expression in expressions) {
            if (expression.compiled) {
              continue;
            }
            for (final name in _beanNamesIn(expression.text)) {
              if (beans[name] case final type?) {
                collectErrors(
                  () => _introspectUsed(
                    type,
                    check.element,
                    need: IntrospectionNeed.spel,
                  ),
                );
              }
            }
          }
        }
      }
      if (check.problems.isNotEmpty) {
        collectErrors(
          () => _failRepository(check.name, check.problems, check.element),
        );
      }
    }
  }

  // The class a `{Name}` placeholder names that is no `@Table` class of this
  // module: the class [name] as the library of [repository] sees it. An
  // entity of another module or package is written into the descriptor
  // through it; a class that is no `@Table` is a problem; a name that
  // nothing in sight has is left to the run time, which fails when the
  // repository is created and says so.
  InterfaceType? _visibleEntity(
    ClassElement repository,
    String name,
    String where,
    List<String> problems,
  ) {
    final found = repository.library.firstFragment.scope.lookup(name).getter;
    if (found is! ClassElement) {
      return null;
    }
    if (!_table.hasAnnotationOf(found)) {
      problems.add('$where: {$name}: no @Table class $name in the application');
      return null;
    }
    return found.isPublic && found.typeParameters.isEmpty
        ? found.thisType
        : null;
  }

  // The names of the beans `@name` and `@'name'` an expression text
  // mentions (a string that holds one is taken for it: it only describes a
  // class more).
  static Iterable<String> _beanNamesIn(String text) => [
    for (final match in RegExp(
      r"@(?:([A-Za-z_]\w*)|'([^']+)')",
    ).allMatches(text))
      match[1] ?? match[2]!,
  ];

  // The beans of the application by name (and alias) that a compiled
  // expression may name with their type: those of a public class the
  // generated code can write; a factory bean gives another object.
  Map<String, InterfaceType> _expressionBeans() => {
    for (final bean in module.beans)
      if (bean.factoryObjectTypes == null && bean.type.element.isPublic)
        for (final name in [bean.name, ...bean.aliases]) name: bean.type,
  };

  // Compiles [text], an expression of [query], to learn whether the build
  // writes it: what the compiler finds wrong (a typo in a property, an
  // unknown variable, a syntax error) is a problem of the repository; what
  // it leaves to the interpreter stays interpreted.
  QueryExpressionModel _compileExpression(
    String text,
    _RepositoryCheck check,
    _QueryText query,
    String where,
    Map<String, InterfaceType> beans,
  ) {
    // The run time resolves `${property}` placeholders in the whole text,
    // the expression's too: the text it evaluates is not the one written.
    if (text.contains(r'${')) {
      return QueryExpressionModel(text, compiled: false);
    }
    final result = compileQueryExpression(
      text,
      repository: check.element.library,
      member: query.model.member,
      beans: beans,
      cast: (value, type) => value,
    );
    if (result is SpelInvalid) {
      for (final problem in result.problems) {
        check.problems.add(
          '$where: the expression :#{$text} is invalid: ${problem.message}',
        );
      }
    }
    return QueryExpressionModel(text, compiled: result is SpelCompiled);
  }

  // The tables and columns the application's entities, migrations and
  // init scripts say.
  DataSchema _dataSchema() {
    final sources = SchemaSources.find(sqlResources);
    // Migrations of several databases: any one of them may be the schema.
    return DataSchema.fromScripts(sources.variants)
      ..reliable = sources.reliable
      ..addEntities(
        [
          for (final entity in module.entities)
            if (_table.hasAnnotationOf(entity.element)) _description(entity),
        ],
        customNaming: module.beans.any(
          (bean) => _namingStrategy.isAssignableFromType(bean.type),
        ),
      );
  }

  EntityDescription _description(EntityModel entity) {
    final table = ConstantReader(_table.firstAnnotationOf(entity.element));
    DartObject? annotation(EntityPropertyModel property, TypeChecker checker) {
      for (final a in property.annotations) {
        if (a.type != null && checker.isAssignableFromType(a.type!)) {
          return a;
        }
      }
      return null;
    }

    String? string(DartObject? object, String field) {
      final value = object == null ? null : ConstantReader(object).peek(field);
      return value != null && value.isString ? value.stringValue : null;
    }

    return EntityDescription(
      entity.element.name!,
      entity.element.library.uri.toString(),
      [
        for (final property in entity.properties)
          if (annotation(property, _transient) != null)
            EntityProperty(property.name, EntityPropertyKind.transient)
          else if (annotation(property, _mappedCollection)
              case final collection?)
            EntityProperty(
              property.name,
              EntityPropertyKind.collection,
              idColumn: string(collection, 'idColumn'),
              keyColumn: string(collection, 'keyColumn'),
              child: _childClass(property.type),
            )
          else
            EntityProperty(
              property.name,
              EntityPropertyKind.column,
              column: string(annotation(property, _column), 'value'),
            ),
      ],
      table: table.peek('value')?.isString == true
          ? table.peek('value')!.stringValue
          : null,
    );
  }

  // The class a `@MappedCollection` holds: `C` of `List<C>`, `Set<C>`,
  // `Map<K, C>`, or the type itself.
  String? _childClass(DartType type) {
    if (type is! InterfaceType) {
      return null;
    }
    final inner = type.typeArguments.isEmpty ? type : type.typeArguments.last;
    return inner is InterfaceType ? inner.element.name : null;
  }
}
