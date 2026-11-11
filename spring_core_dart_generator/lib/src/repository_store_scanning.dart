part of 'bean_scanner.dart';

// What a data repository asks of its store beyond the CRUD and the derived
// finds, and the build's check that the store can do it:
//
//  * `@Procedure('name')`: a call of a database function, told to the starter
//    by a `ProcedureMethod` (see `ProcedureMethodModel`);
//  * `watch…By` (`Stream<List<T>>`: the result of the query, kept up to
//    date) and `changes…By` (`Stream<RowChange<T>>`: the changes of the
//    rows the conditions match), derived from the name as a find is;
//  * the capabilities the methods need (`StoreNeed`), written into the
//    generated class as `StoreRequirement`s and compared here with the
//    store when the build knows it (`DataStoreBuild`);
//  * `@Transactional` of any bean against the application's default store.
//
// ```dart
// @UseStore('documents')        // a store described without transactions
// abstract interface class Notes implements CrudRepository<Note, int> {
//   @Lock(LockMode.pessimisticWrite)
//   Future<Note?> findByTitle(String title);   // build error:
//   // Notes.findByTitle: @Lock needs a store with row locks, and the
//   // documents store is none: ...
// }
// ```

const _procedure = TypeChecker.fromUrl('$_dataAnnotations#Procedure');
const _useStore = TypeChecker.fromUrl('$_dataAnnotations#UseStore');
const _useDataSource = TypeChecker.fromUrl('$_dataAnnotations#UseDataSource');
const _rowChange = TypeChecker.fromUrl(
  'package:spring_boot_starter_data/src/store/row_change.dart#RowChange',
);

extension _RepositoryStoreScanning on BeanScanner {
  /// The `@Procedure` methods of [repository] and of its supertypes, each with
  /// its annotation; a method overridden further down is read once.
  Iterable<(MethodElement, DartObject)> _procedureMethods(
    ClassElement repository,
  ) sync* {
    final names = <String>{};
    for (final type in [
      repository.thisType,
      ...repository.thisType.allSupertypes,
    ]) {
      if (type.element.library.isInSdk) {
        continue;
      }
      for (final method in type.methods) {
        final name = method.name;
        if (method.isStatic || name == null || !names.add(name)) {
          continue;
        }
        if (_procedure.firstAnnotationOf(method) case final procedure?) {
          yield (method, procedure);
        }
      }
    }
  }

  /// What the starter is told of the `@Procedure` method [member], or `null`
  /// when it has a problem (added to [problems]). The result is what a
  /// `@Query` may return, without a `Page` or a `Slice`; the parameters
  /// are the function's arguments, so none is a `Pageable` or a `Sort`.
  ProcedureMethodModel? _procedureMethod(
    String where,
    ProxyMember member, {
    required DartObject procedure,
    required DartObject? query,
    required DartObject? lock,
    required DartObject? modifying,
    required DartType valueType,
    required bool isFuture,
    required bool isStream,
    required InterfaceElement entity,
    required List<String> problems,
  }) {
    final before = problems.length;
    void problem(String reason) => problems.add('$where: $reason');
    final name = ConstantReader(procedure).peek('name');
    if (name == null || !name.isString || name.stringValue.trim().isEmpty) {
      problem('@Procedure has no function name');
    }
    if (query != null) {
      problem(
        '@Procedure and @Query on one method: it calls a database function or '
        'runs SQL, not both',
      );
    }
    if (modifying != null) {
      problem(
        '@Modifying is for a @Query: a function changes what it changes; '
        'return what it returns, or nothing (Future<void>)',
      );
    }
    if (lock != null) {
      problem(
        '@Lock is for the derived find methods and findById: a function '
        'takes its own locks',
      );
    }
    if (!isFuture && !isStream) {
      problems.add(_notAsynchronous(where, valueType));
    }
    for (final parameter in member.parameters) {
      final special = PartTreeParser.isPageable(parameter.type)
          ? 'Pageable'
          : PartTreeParser.isSort(parameter.type)
          ? 'Sort'
          : null;
      if (special != null) {
        problem(
          "the parameter '${parameter.name}' is a $special: every parameter "
          'of a @Procedure method is an argument of the function; give the '
          'function a limit, an offset or an order as arguments of its own',
        );
      }
    }
    var shape = ResultShape.single;
    DartType? element;
    if (valueType is! VoidType) {
      final wrapped = PartTreeParser.wrapped(valueType);
      shape = wrapped?.$1 ?? ResultShape.single;
      element = wrapped?.$2 ?? valueType;
      if (shape == ResultShape.stream && isFuture) {
        problem(
          'a Stream is already asynchronous: return Stream<'
          '${element.getDisplayString()}>, not a Future of it',
        );
      }
      if (shape == ResultShape.page || shape == ResultShape.slice) {
        problem(
          '@Procedure cannot return a ${shape.name}: a function is not '
          'windowed; return a List, or give the function a limit and an offset '
          'as arguments',
        );
      }
      if (_unreadable(element, entity) case final reason?) {
        // A function's rows have no mapper of their own.
        problem(reason.replaceAll(', or give a rowMapper', ''));
      }
    }
    if (problems.length > before) {
      return null;
    }
    return ProcedureMethodModel(
      member,
      procedure: procedure,
      shape: shape,
      element: element,
    );
  }

  /// The model of the derived method [member] whose name starts with
  /// `watch` or `changes` ([prefix]), or `null` when it has a problem
  /// (added to [problems]).
  ///
  /// * `watch…By…` returns `Stream<List<Entity>>`: the result of the query
  ///   of its name (conditions, `First`/`Top`, `Distinct`, `OrderBy`, a
  ///   `Sort` or a `Pageable` parameter), emitted again after every change
  ///   that concerns it.
  /// * `changes…By…` returns `Stream<RowChange<Entity>>`: the changes of
  ///   the rows its conditions match; it is no result, so it has no order
  ///   and no window.
  /// * Nothing after `By` means every row: `watchAllBy()`,
  ///   `changesAllBy()`, as `findAllBy()` does.
  DerivedMethodModel? _liveMethod(
    String where,
    ProxyMember member, {
    required String prefix,
    required DartObject? lock,
    required QueryEntity entity,
    required List<QueryParameter> parameters,
    required List<String> problems,
  }) {
    final watching = prefix == 'watch';
    final before = problems.length;
    void problem(String reason) => problems.add('$where: $reason');
    const parser = PartTreeParser();
    final PartTreeModel tree;
    try {
      tree = parser.parse(member.name, entity);
      parser.validate(
        tree,
        entity,
        parameters,
        returnType: member.returnType,
        isFuture: false,
        checkReturn: false,
      );
    } on QueryProblem catch (found) {
      problem(found.reason);
      return null;
    }
    final expected = watching
        ? 'Stream<List<${entity.name}>>'
        : 'Stream<RowChange<${entity.name}>>';
    if (!_isLiveResult(member.returnType, entity, watching: watching)) {
      problem(
        watching
            ? 'a watch method keeps the result of its query up to date: it '
                  'returns $expected, not '
                  '${member.returnType.getDisplayString()}'
            : 'a changes method reports the changes of the rows its '
                  'conditions match: it returns $expected, not '
                  '${member.returnType.getDisplayString()}',
      );
    }
    if (lock != null) {
      problem(
        '@Lock is for the derived find methods and findById: a $prefix '
        'method reads outside the transaction of its caller',
      );
    }
    final pageable = parameters
        .where((p) => PartTreeParser.isPageable(p.type))
        .firstOrNull;
    final sort = parameters
        .where((p) => PartTreeParser.isSort(p.type))
        .firstOrNull;
    if (!watching &&
        (pageable != null ||
            sort != null ||
            tree.sort.isNotEmpty ||
            tree.subject.maxResults != null ||
            tree.subject.distinct)) {
      problem(
        'a changes method reports changes, not a result: no First, Top, '
        'Distinct or OrderBy in its name, and no Sort or Pageable '
        'parameter (a watch method has them)',
      );
    }
    if (problems.length > before) {
      return null;
    }
    return DerivedMethodModel(
      member,
      tree: tree,
      operation: watching ? DerivedOperation.watch : DerivedOperation.changes,
      arguments: [
        for (final parameter in parameters)
          if (!PartTreeParser.isPageable(parameter.type) &&
              !PartTreeParser.isSort(parameter.type))
            parameter.name,
      ],
      sort: sort?.name,
      pageable: pageable?.name,
    );
  }

  // `Stream<List<Entity>>` for a watch method, `Stream<RowChange<Entity>>`
  // for a changes method: nothing nullable, nothing else.
  bool _isLiveResult(
    DartType returned,
    QueryEntity entity, {
    required bool watching,
  }) {
    bool plain(DartType type) =>
        type is InterfaceType &&
        type.nullabilitySuffix == NullabilitySuffix.none;
    if (!plain(returned) ||
        !(returned as InterfaceType).isDartAsyncStream ||
        returned.typeArguments.length != 1) {
      return false;
    }
    final inner = returned.typeArguments.single;
    if (!plain(inner) ||
        (inner as InterfaceType).typeArguments.length != 1 ||
        !(watching ? inner.isDartCoreList : _rowChange.isExactlyType(inner))) {
      return false;
    }
    final row = inner.typeArguments.single;
    return plain(row) && entity.isEntity(row);
  }

  /// What the method [model] of a repository needs of its store.
  Iterable<StoreNeed> _needsOf(RepositoryMethodModel model) sync* {
    final name = model.member.name;
    switch (model) {
      case LockedMethodModel():
        yield StoreNeed(name, StoreCapability.locks);
      case QueryMethodModel():
        yield StoreNeed(name, StoreCapability.queries);
      case ProcedureMethodModel():
        yield StoreNeed(name, StoreCapability.functions);
      case DerivedMethodModel(:final lock, :final operation):
        if (lock != null) {
          yield StoreNeed(name, StoreCapability.locks);
        }
        if (operation == DerivedOperation.watch ||
            operation == DerivedOperation.changes) {
          yield StoreNeed(name, StoreCapability.changes);
        }
    }
  }

  /// Whether a declaration of [method] in [hierarchy] (the interface or
  /// one it extends) is `@Transactional`.
  bool _transactionalMethod(
    MethodElement method,
    List<InterfaceType> hierarchy,
  ) => [
    method,
    for (final type in hierarchy)
      for (final other in type.element.methods)
        if (other.name == method.name && !other.isStatic) other,
  ].any(DataStoreBuild.isTransactional);

  /// Adds to [problems] what the repository [name] needs ([needs]) and its
  /// store lacks, when the build knows the store: its `@UseStore`, the SQL
  /// store with a `@UseDataSource`, else the application's default store.
  void _checkStore(
    String name,
    ClassElement element,
    List<StoreNeed> needs,
    List<String> problems,
  ) {
    final store = needs.isEmpty ? null : _storeOf(element);
    if (store == null) {
      return;
    }
    for (final need in needs) {
      final problem = dataStores.problem(name, need, store);
      if (problem != null && !problems.contains(problem)) {
        problems.add(problem);
      }
    }
  }

  /// The described store of the repository [element], or null when the
  /// build cannot tell or does not know it.
  DescribedStore? _storeOf(ClassElement element) {
    if (dataStores.stores.isEmpty) {
      return null;
    }
    final useStore = _useStore.firstAnnotationOf(element);
    return dataStores.storeOf(
      useStore: useStore == null
          ? null
          : ConstantReader(useStore).peek('value')?.stringValue,
      usesDataSource: _useDataSource.hasAnnotationOf(element),
    );
  }

  /// Adds to [problems] the collection properties of [entity] (and of the
  /// children of its mapped collections) that the store of the repository
  /// [element] has no column for, when the build knows the store and the
  /// store says so (`collectionsNeedJson`: the SQL store): a `Map`, a
  /// `Set`, or a `List` of anything but simple values, with neither
  /// `@Json` nor `@MappedCollection`. Bytes (`List<int>`, `Uint8List`) are
  /// a column; a list of simple values may be one (an array of
  /// PostgreSQL), so the store decides when the repository is created.
  void _checkCollections(
    ClassElement element,
    ClassElement entity,
    List<String> problems,
  ) {
    if (!(_storeOf(element)?.collectionsNeedJson ?? false)) {
      return;
    }
    final root = _queryEntity(entity);
    final entities = [
      root,
      for (final property in root.properties)
        if (property.isMappedCollection)
          if (_childClass(property.type) case final child?) _queryEntity(child),
    ];
    for (final checked in entities) {
      for (final property in checked.columns) {
        if (property.isJson ||
            property.referencedId != null ||
            !_needsJson(property.type)) {
          continue;
        }
        final shown = property.type.getDisplayString();
        final problem = DataStoreBuild.collectionProblem(
          '${checked.name}.${property.name}',
          shown.endsWith('?') ? shown.substring(0, shown.length - 1) : shown,
        );
        if (!problems.contains(problem)) {
          problems.add(problem);
        }
      }
    }
  }

  // The class of the children of a mapped collection of [type]: the
  // element of a list or a set, the value of a map, else the type itself.
  ClassElement? _childClass(DartType type) {
    if (type is! InterfaceType) {
      return null;
    }
    final child =
        type.isDartCoreList || type.isDartCoreSet || type.isDartCoreMap
        ? type.typeArguments.last
        : type;
    return switch (child.element) {
      final ClassElement element => element,
      _ => null,
    };
  }

  // Whether a property of [type] is a collection no SQL database has a
  // column for.
  bool _needsJson(DartType type) {
    if (type is! InterfaceType) {
      return false;
    }
    if (type.isDartCoreMap || type.isDartCoreSet) {
      return true;
    }
    return type.isDartCoreList && !_isSimple(type.typeArguments.single);
  }

  // What a column, or an element of an array column, holds.
  bool _isSimple(DartType type) =>
      type.isDartCoreInt ||
      type.isDartCoreDouble ||
      type.isDartCoreNum ||
      type.isDartCoreBool ||
      type.isDartCoreString ||
      type.element is EnumElement ||
      (type is InterfaceType &&
          type.element.library.isDartCore &&
          const {'DateTime', 'BigInt'}.contains(type.element.name));

  /// Fails the beans whose `@Transactional` has no transaction to run in:
  /// the application's default store is described without transactions
  /// and the annotation names no transaction manager. A repository is
  /// checked with its own store, not here.
  void _checkTransactionalBeans() {
    if (dataStores.stores.isEmpty) {
      return;
    }
    for (final bean in module.beans) {
      final element = bean.type.element;
      if (bean.creation is RepositoryCreation) {
        continue;
      }
      if (dataStores.transactionalProblem(element) case final problem?) {
        collectErrors(
          () => throw InvalidGenerationSource(
            problem,
            element: element,
            todo:
                'Select a store with transactions, name a transaction '
                'manager in @Transactional, or remove the annotation.',
          ),
        );
      }
    }
  }
}
