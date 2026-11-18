part of 'bean_scanner.dart';

// The data repositories of spring_boot_starter_data: an interface extending
// `DataRepository` becomes a class extending the starter's `SimpleRepository`
// (the CRUD methods) with one method for each other method of the
// interface:
//
//  * `@Procedure`: a call of a database function (see
//    `repository_store_scanning.dart`, with the `watch…By` and
//    `changes…By` methods and the check of the store's capabilities);
//  * `@Query`: a description of the method, which the starter reads;
//  * a CRUD method redeclared with `@Lock`: an override passing the lock;
//  * anything else: a derived query, `findByTitleAndYear`, whose name the
//    build reads into a `PartTree` (see `PartTreeParser`) and checks against
//    the entity, the parameters and the return type.
//
// Every problem of an interface is collected and fails the build once.
// Matched by URL, so the generator does not depend on the starter.
//
// ```dart
// abstract interface class BookRepository
//     implements ListCrudRepository<Book, int> {
//   Future<List<Book>> findByTitel(String title);   // build error:
//   // BookRepository.findByTitel: No property 'titel' found for type
//   // 'Book'; did you mean 'title'? Available properties: ...
// }
// ```

const _lock = TypeChecker.fromUrl('$_dataAnnotations#Lock');
const _mappedCollection = TypeChecker.fromUrl(
  '$_dataAnnotations#MappedCollection',
);

// The libraries of the starter's repository interfaces (`DataRepository`,
// `CrudRepository`, ...): their methods are implemented by
// `SimpleRepository`, not by the generated class.
const _repositoryLibraries = 'package:spring_boot_starter_data/src/repository/';

// The interfaces `SimpleRepository` implements, besides `DataRepository`:
// its methods are the CRUD methods.
const _simpleRepositoryInterfaces = [
  'ListCrudRepository',
  'ListPagingAndSortingRepository',
];

extension _RepositoryScanning on BeanScanner {
  /// Adds the bean of [element], an interface extending `DataRepository`,
  /// with its generated class. Fails the build, listing every problem, when
  /// a method is neither a CRUD method, a `@Query` nor a valid derived
  /// query.
  void scanRepository(ClassElement element) {
    final name = _requireName(element);
    final source = '${element.library.uri}#$name';
    if (!module.markScanned(source)) {
      return;
    }
    if (element.isPrivate) {
      BeanScanner._fail('Interface $name must be public.', element);
    }
    final type = element.thisType;
    final problems = <String>[];
    final data = type.allSupertypes.firstWhere(_dataRepository.isExactlyType);
    final entityType = _repositoryType(
      data.typeArguments[0],
      'entity',
      name,
      problems,
    );
    final idType = _repositoryType(data.typeArguments[1], 'id', name, problems);
    final entityClass = entityType?.element;
    if (entityType != null && entityClass is! ClassElement) {
      problems.add(
        '${entityType.element.name} is not a class, so it cannot be an '
        'entity',
      );
    }
    if (entityType == null ||
        idType == null ||
        entityClass is! ClassElement ||
        problems.isNotEmpty) {
      _failRepository(name, problems, element);
    }
    final simple = _simpleRepository(data, entityType, idType);
    // Only a repository with derived queries reads the entity's properties.
    late final queryEntity = _queryEntity(entityClass);
    final hierarchy = [type, ...type.allSupertypes];
    final declared = _declaredMethodNames(element, type, problems);
    final methods = <RepositoryMethodModel>[];
    final queries = <_QueryText>[];
    // What the interface and its methods need of the store.
    final needs = <StoreNeed>[
      if (DataStoreBuild.isTransactional(element))
        const StoreNeed(null, StoreCapability.transactions),
    ];
    for (final methodName in declared) {
      final method = type.lookUpMethod(methodName, element.library);
      if (method == null) {
        continue;
      }
      final where = '$name.$methodName';
      // Members of the generated class: the call of every method, and its
      // factory.
      if (methodName == 'operations' || methodName == r'$create') {
        problems.add(
          '$where: the generated class has a member of this name: rename '
          'the method.',
        );
        continue;
      }
      if (!method.isAbstract) {
        problems.add(
          '$where has a body: every method of the interface is implemented '
          'by the generated class.',
        );
        continue;
      }
      if (method.typeParameters.isNotEmpty) {
        problems.add('$where must not be generic.');
        continue;
      }
      final ProxyMember? member;
      try {
        member = _proxyMethod(
          method,
          hierarchy,
          method.enclosingElement?.name ?? name,
        );
      } on InvalidGenerationSource catch (error) {
        problems.add('$where: ${error.message}');
        continue;
      }
      if (member == null) {
        problems.add(
          '$where cannot be implemented: a parameter default value is not a '
          'public constant, or its signature uses a private type.',
        );
        continue;
      }
      final model = _repositoryMethod(
        where,
        method,
        member,
        simple: simple,
        hierarchy: hierarchy,
        entity: () => queryEntity,
        entityElement: entityClass,
        problems: problems,
        queries: queries,
      );
      if (model != null) {
        methods.add(model);
        needs.addAll(_needsOf(model));
      }
      if (_transactionalMethod(method, hierarchy)) {
        needs.add(StoreNeed(methodName, StoreCapability.transactions));
      }
    }
    _checkStore(name, element, needs, problems);
    _checkCollections(element, entityClass, problems);
    if (queries.isNotEmpty) {
      // The texts of the @Query methods are checked with the whole
      // application: their problems join these in one error.
      _repositoryChecks.add(_RepositoryCheck(element, name, problems, queries));
      if (problems.isNotEmpty) {
        return;
      }
    } else if (problems.isNotEmpty) {
      _failRepository(name, problems, element);
    }
    final model = RepositoryModel(
      className: module.uniqueClassName('_\$${name}Impl'),
      type: type,
      entityType: entityType,
      idType: idType,
      annotations: _userAnnotations(element),
      methods: methods,
      // The interface's own `@Transactional` is among its annotations,
      // which the starter reads.
      requirements: [
        for (final need in needs)
          if (need.method != null) need,
      ],
    );
    final explicitName = ConstantReader(
      _component.firstAnnotationOf(element),
    ).peek('name')?.stringValue;
    module.beans.add(
      BeanModel(
        element: element,
        source: source,
        name: explicitName ?? BeanScanner._decapitalize(name),
        type: type,
        exposedTypes: _exposedTypes(type),
        creation: RepositoryCreation(model),
        primary: _primary.hasAnnotationOf(element),
        qualifiers: _qualifiersOf(element),
        annotations: _beanAnnotations(element),
        conditions: [
          if (_conditions(element) case final own when own.isNotEmpty)
            GroupConditionModel(source, own),
        ],
        // Advice (e.g. @Transactional on repository methods) wraps it.
        proxy: proxyMode == ProxyMode.none
            ? null
            : _proxyModel(type, '_\$${name}Proxy', implementSelf: true),
      ),
    );
  }

  // `T` or `ID` of `DataRepository<T, ID>` as a type the generated class
  // can name; a problem is added to [problems] and `null` returned.
  InterfaceType? _repositoryType(
    DartType type,
    String what,
    String name,
    List<String> problems,
  ) {
    if (type is! InterfaceType ||
        type.nullabilitySuffix == NullabilitySuffix.question) {
      problems.add(
        'the $what type of DataRepository<T, ID> is '
        '${type.getDisplayString()}: $name must name a class, as in '
        '`implements ListCrudRepository<Book, int>`',
      );
      return null;
    }
    if (BeanScanner._privateType(type) case final private?) {
      problems.add(
        'the $what type ${private.element.name} is private, which the '
        'generated class cannot name: make it public',
      );
      return null;
    }
    return type;
  }

  Never _failRepository(String name, List<String> problems, Element element) =>
      BeanScanner._fail(
        'Invalid repository $name:\n'
        '${problems.map((p) => '  - $p').join('\n')}',
        element,
      );

  // The names of the methods the generated class has to consider: those
  // the interface and its supertypes declare, the starter's own interfaces
  // left out. Getters and setters are problems.
  List<String> _declaredMethodNames(
    ClassElement element,
    InterfaceType type,
    List<String> problems,
  ) {
    final names = <String>{};
    for (final supertype in [type, ...type.allSupertypes]) {
      final owner = supertype.element;
      if (owner.library.isInSdk || _isRepositoryInterface(owner)) {
        continue;
      }
      for (final accessor in [...owner.getters, ...owner.setters]) {
        if (!accessor.isStatic && accessor.name != null) {
          problems.add(
            '${element.name}.${accessor.name}: only methods are supported in '
            'a repository (no getters or setters).',
          );
        }
      }
      for (final method in owner.methods) {
        final name = method.name;
        // The members every object has are not repository methods.
        if (!method.isStatic &&
            name != null &&
            name != 'toString' &&
            name != 'noSuchMethod' &&
            name != '==') {
          names.add(name);
        }
      }
    }
    return names.toList();
  }

  // Declared by one of the starter's repository interfaces.
  bool _isRepositoryInterface(InterfaceElement element) =>
      element.library.uri.toString().startsWith(_repositoryLibraries);

  // The interfaces `SimpleRepository` implements, with the entity and id of
  // the repository: what the generated class inherits. They are declared in
  // the library of `DataRepository` (`_dataRepository` is matched by that
  // URL), whatever the repository imports.
  List<InterfaceType> _simpleRepository(
    InterfaceType data,
    InterfaceType entity,
    InterfaceType id,
  ) => [
    for (final name in _simpleRepositoryInterfaces)
      if (data.element.library.exportNamespace.get2(name)
          case final InterfaceElement found when _isRepositoryInterface(found))
        found.instantiate(
          typeArguments: [entity, id],
          nullabilitySuffix: NullabilitySuffix.none,
        ),
  ];

  // What the generated class writes for [method], or `null` when
  // `SimpleRepository` already implements it; a mistake is added to
  // [problems].
  RepositoryMethodModel? _repositoryMethod(
    String where,
    MethodElement method,
    ProxyMember member, {
    required List<InterfaceType> simple,
    required List<InterfaceType> hierarchy,
    required QueryEntity Function() entity,
    required InterfaceElement entityElement,
    required List<String> problems,
    required List<_QueryText> queries,
  }) {
    // The annotations are read from the declarations themselves, not from
    // `member.annotations`, which leaves out one whose values the
    // generated code cannot write (`rowMapper: _private`): that would turn
    // a `@Query` into a derived query without a word.
    final declarations = [
      method,
      for (final type in hierarchy)
        for (final other in type.element.methods)
          if (other.name == method.name &&
              !other.isStatic &&
              other.baseElement != method.baseElement)
            other,
    ];
    var unwritable = false;
    DartObject? annotationOf(TypeChecker checker) {
      for (final declaration in declarations) {
        if (checker.firstAnnotationOf(declaration) case final found?) {
          if (_unwritable(where, found, problems)) {
            unwritable = true;
            return null;
          }
          return found;
        }
      }
      return null;
    }

    final returnType = member.returnType;
    final isFuture =
        returnType is InterfaceType &&
        returnType.isDartAsyncFuture &&
        returnType.nullabilitySuffix == NullabilitySuffix.none;
    final valueType = isFuture ? returnType.typeArguments.single : returnType;
    final isStream =
        !isFuture &&
        valueType is InterfaceType &&
        valueType.isDartAsyncStream &&
        valueType.nullabilitySuffix == NullabilitySuffix.none;
    final lock = annotationOf(_lock);
    final query = annotationOf(_query);
    final modifying = annotationOf(_modifying);
    final procedure = annotationOf(_procedure);
    if (unwritable) {
      return null;
    }
    final methodName = member.name;
    final parameters = [
      for (final parameter in member.parameters)
        QueryParameter(parameter.name, parameter.type),
    ];

    // `@Procedure`: a database function, whatever the name of the method says.
    if (procedure != null) {
      return _procedureMethod(
        where,
        member,
        procedure: procedure,
        query: query,
        lock: lock,
        modifying: modifying,
        valueType: valueType,
        isFuture: isFuture,
        isStream: isStream,
        entity: entityElement,
        problems: problems,
      );
    }

    // `@Query`: checked here and in `_checkQueries`; the starter is told
    // what is left to do.
    if (query != null) {
      return _queryMethod(
        where,
        member,
        query: query,
        lock: lock,
        modifying: modifying,
        valueType: valueType,
        isFuture: isFuture,
        isStream: isStream,
        entity: entityElement,
        problems: problems,
        queries: queries,
      );
    }

    // A CRUD method of `SimpleRepository`: nothing to write, unless it is
    // redeclared with a lock.
    final inherited = [
      for (final type in simple) ?type.lookUpMethod(methodName, method.library),
    ].firstOrNull;
    if (inherited != null &&
        inherited.formalParameters.length == method.formalParameters.length) {
      if (!method.library.typeSystem.isSubtypeOf(inherited.type, method.type)) {
        problems.add(
          '$where: has the name of a CRUD method of the repository '
          'interfaces, ${_signature(inherited)}, but a signature that does '
          'not fit it: make it that one, or rename the method',
        );
        return null;
      }
      if (lock == null) {
        return null;
      }
      if (methodName != 'findById') {
        problems.add(_lockProblem(where));
        return null;
      }
      return LockedMethodModel(member, lock);
    }

    // Anything else is a derived query.
    if (!PartTreeParser.isDerivedQuery(methodName)) {
      problems.add(
        '$where: not a CRUD method of the repository interfaces and not a '
        'derived query: a query method starts with find, read, get, query, '
        'search, stream, watch, changes, count, exists, delete or remove, '
        'then By and the conditions (findByTitle)',
      );
      return null;
    }
    // `watch…By` and `changes…By`: streams that follow the store.
    final prefix = PartTreeReader.prefixOf(methodName);
    if (prefix == 'watch' || prefix == 'changes') {
      try {
        return _liveMethod(
          where,
          member,
          prefix: prefix!,
          lock: lock,
          entity: entity(),
          parameters: parameters,
          problems: problems,
        );
      } on QueryProblem catch (problem) {
        problems.add('$where: ${problem.reason}');
        return null;
      }
    }
    if (!isFuture && !isStream) {
      problems.add(_notAsynchronous(where, valueType));
    }
    const parser = PartTreeParser();
    final PartTreeModel tree;
    try {
      final query = entity();
      tree = parser.parse(methodName, query);
      parser.validate(
        tree,
        query,
        parameters,
        returnType: valueType,
        isFuture: isFuture,
      );
    } on QueryProblem catch (problem) {
      problems.add('$where: ${problem.reason}');
      return null;
    }
    final kind = tree.subject.kind;
    if (lock != null && kind != SubjectKind.find) {
      problems.add(
        '${_lockProblem(where)}, and this one '
        '${switch (kind) {
          SubjectKind.count => 'counts',
          SubjectKind.exists => 'checks existence',
          _ => 'deletes',
        }}',
      );
      return null;
    }
    if (!isFuture && !isStream) {
      return null;
    }
    final shape = PartTreeParser.shapeOf(valueType);
    final pageable = parameters
        .where((p) => PartTreeParser.isPageable(p.type))
        .firstOrNull;
    final sort = parameters
        .where((p) => PartTreeParser.isSort(p.type))
        .firstOrNull;
    final operation = switch (kind) {
      SubjectKind.count => DerivedOperation.countBy,
      SubjectKind.exists => DerivedOperation.existsBy,
      SubjectKind.delete =>
        valueType.isDartCoreList
            ? DerivedOperation.deleteByReturning
            : DerivedOperation.deleteBy,
      SubjectKind.find => switch (shape) {
        ResultShape.list => DerivedOperation.list,
        ResultShape.set => DerivedOperation.set,
        ResultShape.page => DerivedOperation.page,
        ResultShape.slice => DerivedOperation.slice,
        ResultShape.stream => DerivedOperation.stream,
        ResultShape.single =>
          valueType.nullabilitySuffix == NullabilitySuffix.question
              ? DerivedOperation.one
              : DerivedOperation.single,
      },
    };
    if (pageable != null) {
      if (shape == ResultShape.single) {
        problems.add(
          '$where: a method that returns one ${valueType.getDisplayString()} '
          'cannot take a Pageable: return a List, Page or Slice of it',
        );
        return null;
      }
      if ((shape == ResultShape.page || shape == ResultShape.slice) &&
          pageable.type.nullabilitySuffix == NullabilitySuffix.question) {
        problems.add(
          "$where: the Pageable parameter '${pageable.name}' of a method "
          'returning a Page or Slice must not be nullable',
        );
        return null;
      }
    }
    return DerivedMethodModel(
      member,
      tree: tree,
      operation: operation,
      arguments: [
        for (final parameter in parameters)
          if (!PartTreeParser.isPageable(parameter.type) &&
              !PartTreeParser.isSort(parameter.type))
            parameter.name,
      ],
      sort: sort?.name,
      pageable: pageable?.name,
      lock: lock,
    );
  }

  // Whether [annotation], one of a repository method, has a value the
  // generated code cannot write (a private function or constant): the
  // problem is added to [problems], naming the field.
  bool _unwritable(
    String where,
    DartObject annotation,
    List<String> problems,
  ) {
    if (_isRecreatable(annotation)) {
      return false;
    }
    final type = annotation.type;
    final name = type?.element?.name ?? 'annotation';
    final fields = [
      if (type is InterfaceType)
        for (final field in type.element.fields)
          if (!field.isStatic && field.name != null)
            if (annotation.getField(field.name!) case final value?
                when !_isRecreatable(value))
              field.name!,
    ];
    for (final field in fields.isEmpty ? const ['value'] : fields) {
      problems.add(
        '$where: the $field of @$name must be public: the generated code '
        'refers to it',
      );
    }
    return true;
  }

  String _notAsynchronous(String where, DartType valueType) =>
      '$where: a repository method is asynchronous: return a Future '
      '(Future<${valueType.getDisplayString()}>) or a Stream';

  String _lockProblem(String where) =>
      '$where: @Lock is for the derived find methods (findByTitle) and '
      'findById: a lock is taken by reading rows';

  // `Future<Book?> findById(int id)`, for a message.
  String _signature(MethodElement method) {
    final positional = [
      for (final p in method.formalParameters)
        if (!p.isNamed) '${p.type.getDisplayString()} ${p.name}',
    ];
    final named = [
      for (final p in method.formalParameters)
        if (p.isNamed) '${p.type.getDisplayString()} ${p.name}',
    ];
    return '${method.returnType.getDisplayString()} ${method.name}('
        '${positional.join(', ')}'
        '${named.isEmpty ? '' : '${positional.isEmpty ? '' : ', '}'
                  '{${named.join(', ')}}'}'
        ')';
  }

  // The properties a derived query can use: the fields the data layer
  // stores, the way the starter maps them (see `EntityModel`): not
  // `@Transient`, and settable or a constructor parameter.
  QueryEntity _queryEntity(ClassElement entity) {
    final parameters = {
      for (final parameter
          in entity.unnamedConstructor?.formalParameters ??
              const <FormalParameterElement>[])
        ?parameter.name,
    };
    bool marked(TypeChecker checker, FieldElement field) =>
        checker.hasAnnotationOf(field) ||
        (field.getter != null && checker.hasAnnotationOf(field.getter!));
    final properties = <StoredProperty>[];
    for (final field in _describedFields(_describedClasses(entity))) {
      final fieldName = field.name!;
      if (marked(_transient, field) ||
          (field.setter == null && !parameters.contains(fieldName))) {
        continue;
      }
      final type = _fieldType(entity, field);
      DartType? referencedId;
      if (type is InterfaceType) {
        for (final candidate in [type, ...type.allSupertypes]) {
          if (_aggregateReference.isExactlyType(candidate) &&
              candidate.typeArguments.length == 2) {
            referencedId = candidate.typeArguments[1];
            break;
          }
        }
      }
      properties.add(
        StoredProperty(
          fieldName,
          type,
          isMappedCollection: marked(_mappedCollection, field),
          isJson: marked(_dataJson, field),
          referencedId: referencedId,
        ),
      );
    }
    return QueryEntity(entity, properties);
  }
}
