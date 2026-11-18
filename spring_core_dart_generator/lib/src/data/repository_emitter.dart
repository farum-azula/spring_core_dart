part of 'module_emitter.dart';

// The class of a data repository (see `RepositoryModel`): it extends the
// starter's `SimpleRepository` and writes one method for each of the
// interface's own, each a call of `RepositoryOperations`:
//
// ```dart
// class _$BookRepositoryImpl extends SimpleRepository<Book, int>
//     implements BookRepository {
//   _$BookRepositoryImpl(super.operations);
//
//   static _$BookRepositoryImpl $create(DependencyResolver r) =>
//       _$BookRepositoryImpl(r
//           .dependency<RepositoryFactory>()
//           .operations<Book, int>(
//             r'BookRepository',
//             queries: [_cards],
//             // What the methods need of the store (`@Query`, `@Procedure`,
//             // `@Lock`, a stream of changes, `@Transactional`).
//             requirements: const [
//               StoreRequirement(r'cards', DataStoreCapability.queries),
//             ],
//           ));
//
//   static const _findByTitleAndYear = PartTree(r'findByTitleAndYear', [
//     OrPart([Part(r'title'), Part(r'year')]),
//   ]);
//   static const _cards = QueryMethod(
//     r'cards',
//     Query(r'select title from books where year = :year'),
//     parameters: [r'year'],
//     element: ClassType<BookCard>(),
//   );
//   // A `:#{...}` expression the build compiles makes it a `static final`:
//   static final _sameTitle = QueryMethod(
//     r'sameTitle',
//     Query(r'select * from books where title = :#{#book.title}'),
//     parameters: [r'book'],
//     element: ClassType<Book>(),
//     expressions: [(arguments, context) => (arguments[0] as Book).title],
//   );
//
//   @override
//   Future<List<Book>> findByTitleAndYear(String title, int year) =>
//       this.operations.list(_findByTitleAndYear, [title, year]);
//
//   @override
//   Future<List<BookCard>> cards(int year) =>
//       this.operations.query<List<BookCard>>(_cards, [year]);
// }
// ```

extension _RepositoryEmitter on ModuleEmitter {
  /// The class of [model].
  Class repositoryClass(RepositoryModel model) {
    final element = model.type.element;
    final interfaceType = _type(model.type, element);
    final entity = _type(model.entityType, element);
    final id = _type(model.idType, element);
    final self = refer(model.className);
    final queries = [
      for (final method in model.methods)
        if (method is QueryMethodModel) method,
    ];
    final functions = [
      for (final method in model.methods)
        if (method is ProcedureMethodModel) method,
    ];
    // `this.operations`, so a parameter called `operations` cannot hide it.
    final operations = refer('this').property('operations');
    // `r.dependency<RepositoryFactory>().operations<T, ID>(r'X', ...)`.
    final created = refer('r')
        .property('dependency')
        .call([], {}, [_data('RepositoryFactory')])
        .property('operations')
        .call(
          [_str(element.name!)],
          {
            if (model.annotations.isNotEmpty)
              'annotations': literalConstList([
                for (final annotation in model.annotations)
                  _constant(annotation, element),
              ]),
            if (queries.isNotEmpty)
              'queries': literalList([
                for (final query in queries) refer(_staticName(query)),
              ]),
            if (functions.isNotEmpty)
              'functions': literalList([
                for (final function in functions) refer(_staticName(function)),
              ]),
            if (model.requirements.isNotEmpty)
              'requirements': literalConstList([
                for (final need in model.requirements)
                  _data('StoreRequirement').constInstance([
                    _str(need.method!),
                    _data('DataStoreCapability').property(need.capability.name),
                  ]),
              ]),
          },
          [entity, id],
        );
    return Class(
      (c) => c
        ..docs.add(
          '/// Implements `${element.name}`: `SimpleRepository` has the CRUD '
          'methods.',
        )
        ..name = model.className
        ..extend = TypeReference(
          (t) => t
            ..symbol = 'SimpleRepository'
            ..url = _dataUrl
            ..types.addAll([entity, id]),
        )
        ..implements.add(interfaceType)
        ..constructors.add(
          Constructor(
            (k) => k.requiredParameters.add(
              Parameter(
                (p) => p
                  ..name = 'operations'
                  ..toSuper = true,
              ),
            ),
          ),
        )
        ..fields.addAll(
          [
            for (final method in model.methods)
              switch (method) {
                DerivedMethodModel() => Field(
                  (f) => f
                    ..static = true
                    ..modifier = FieldModifier.constant
                    ..name = _staticName(method)
                    ..assignment = _partTree(method.tree).code,
                ),
                QueryMethodModel() => _queryField(method, element),
                ProcedureMethodModel() => _procedureField(method, element),
                LockedMethodModel() => null,
              },
          ].nonNulls,
        )
        ..methods.addAll([
          Method(
            (m) => m
              ..static = true
              ..name = r'$create'
              ..returns = self
              ..requiredParameters.add(
                Parameter(
                  (p) => p
                    ..name = 'r'
                    ..type = _spring('DependencyResolver'),
                ),
              )
              ..lambda = true
              ..body = self.newInstance([created]).code,
          ),
          for (final method in model.methods)
            _repositoryMethod(
              method,
              element,
              switch (method) {
                LockedMethodModel(:final lock) =>
                  operations
                      .property('findById')
                      .call(
                        [refer(method.member.parameters.first.name)],
                        {'lock': _constant(lock, element)},
                      ),
                QueryMethodModel(:final isStream) => _resultCall(
                  isStream ? 'queryStream' : 'query',
                  method,
                  operations,
                  element,
                ),
                ProcedureMethodModel() => _resultCall(
                  method.isStream ? 'procedureStream' : 'procedure',
                  method,
                  operations,
                  element,
                ),
                DerivedMethodModel() => _derivedCall(
                  method,
                  operations,
                  element,
                ),
              },
            ),
        ]),
    );
  }

  // The static field holding the `PartTree`, `QueryMethod` or `ProcedureMethod`
  // of [method].
  String _staticName(RepositoryMethodModel method) => '_${method.member.name}';

  // The `QueryMethod` of [method]: a constant, unless the type of what a
  // row becomes needs code (an enum with `@JsonValue`) or an expression is
  // compiled to a function.
  Field _queryField(QueryMethodModel method, Element element) {
    final member = method.member;
    final info = method.element == null
        ? null
        : _typeInfo(method.element!, element);
    final expressions = _queryExpressions(method, element);
    return Field(
      (f) => f
        ..static = true
        ..modifier =
            info?.$2 == false || expressions.any((e) => e != literalNull)
            ? FieldModifier.final$
            : FieldModifier.constant
        ..name = _staticName(method)
        ..assignment = _data('QueryMethod')
            .newInstance(
              [_str(member.name), _constant(method.query, element)],
              {
                if (member.parameters.isNotEmpty)
                  'parameters': literalConstList([
                    for (final parameter in member.parameters)
                      _str(parameter.name),
                  ]),
                if (method.pageable case final index?)
                  'pageable': literalNum(index),
                if (method.sort case final index?) 'sort': literalNum(index),
                if (method.change == null && method.shape != ResultShape.list)
                  'shape': _data('QueryShape').property(method.shape.name),
                if (info != null) 'element': info.$1,
                if (method.change case final change?)
                  'change': _data('QueryChange').property(change.name),
                if (method.entities.isNotEmpty)
                  'entities': literalConstMap({
                    for (final MapEntry(:key, :value)
                        in method.entities.entries)
                      _str(key): _type(value, element),
                  }),
                if (expressions.isNotEmpty)
                  'expressions': expressions.any((e) => e != literalNull)
                      ? literalList(expressions)
                      : literalConstList(expressions),
              },
            )
            .code,
    );
  }

  // The `ProcedureMethod` of [method]: a constant, unless the type of what a
  // row becomes needs code (an enum with `@JsonValue`).
  Field _procedureField(ProcedureMethodModel method, Element element) {
    final member = method.member;
    final info = method.element == null
        ? null
        : _typeInfo(method.element!, element);
    return Field(
      (f) => f
        ..static = true
        ..modifier = info?.$2 == false
            ? FieldModifier.final$
            : FieldModifier.constant
        ..name = _staticName(method)
        ..assignment = _data('ProcedureMethod')
            .newInstance(
              [_str(member.name), _constant(method.procedure, element)],
              {
                if (member.parameters.isNotEmpty)
                  'parameters': literalConstList([
                    for (final parameter in member.parameters)
                      _str(parameter.name),
                  ]),
                if (method.element != null && method.shape != ResultShape.list)
                  'shape': _data('QueryShape').property(method.shape.name),
                if (info != null) 'element': info.$1,
              },
            )
            .code,
    );
  }

  // The `expressions` of [method], one for each `:#{...}`: `null` for an
  // expression the starter interprets, else a function of the arguments and
  // the `QueryExpressionContext`, `(arguments, context) => ...`.
  List<Expression> _queryExpressions(
    QueryMethodModel method,
    Element element,
  ) => [
    for (final expression in method.expressions)
      if (expression.compiled)
        switch (compileQueryExpression(
          expression.text,
          repository: element.library!,
          member: method.member,
          beans: method.beans,
          cast: (value, type) => value.asA(_anyType(type, element)),
        )) {
          SpelCompiled(:final code) => Method(
            (m) => m
              ..requiredParameters.addAll([
                Parameter((p) => p..name = 'arguments'),
                Parameter((p) => p..name = 'context'),
              ])
              ..lambda = true
              ..body = code.code,
          ).closure,
          _ => throw StateError(
            'The expression :#{${expression.text}} compiled when the '
            'repository was scanned, not now.',
          ),
        }
      else
        literalNull,
  ];

  // `this.operations.query<R>(_x, [args])`, `...queryStream<E>(...)`, and
  // the same for a database function: `procedure<R>`, `procedureStream<E>`.
  Expression _resultCall(
    String operation,
    RepositoryMethodModel method,
    Expression operations,
    Element element,
  ) {
    final member = method.member;
    final returnType = member.returnType;
    // `Future<R>` gives `R`; a `Stream<E>` gives `E`.
    final valueType =
        returnType is InterfaceType &&
            (returnType.isDartAsyncFuture || returnType.isDartAsyncStream)
        ? returnType.typeArguments.single
        : returnType;
    return operations
        .property(operation)
        .call(
          [
            refer(_staticName(method)),
            _argumentList([
              for (final parameter in member.parameters) parameter.name,
            ]),
          ],
          {},
          [_anyType(valueType, element)],
        );
  }

  // `this.operations.list(_x, [args], sort: s)`; a page or slice takes its
  // `Pageable` as the third argument.
  Expression _derivedCall(
    DerivedMethodModel method,
    Expression operations,
    Element element,
  ) {
    final paged =
        method.operation == DerivedOperation.page ||
        method.operation == DerivedOperation.slice;
    return operations
        .property(method.operation.name)
        .call(
          [
            refer(_staticName(method)),
            _argumentList(method.arguments),
            if (paged) refer(method.pageable!),
          ],
          {
            if (method.sort case final sort?) 'sort': refer(sort),
            if (!paged)
              if (method.pageable case final pageable?)
                'pageable': refer(pageable),
            if (method.lock case final lock?) 'lock': _constant(lock, element),
          },
        );
  }

  Expression _argumentList(List<String> names) => names.isEmpty
      ? literalConstList([])
      : literalList([for (final name in names) refer(name)]);

  // The method of [method]'s signature with [body] as its arrow body.
  Method _repositoryMethod(
    RepositoryMethodModel method,
    Element element,
    Expression body,
  ) {
    final member = method.member;
    return Method(
      (m) => m
        ..annotations.add(refer('override'))
        ..name = member.name
        ..returns = _anyType(member.returnType, element)
        ..requiredParameters.addAll([
          for (final parameter in member.parameters)
            if (!parameter.isNamed && parameter.isRequired)
              _proxyParameter(parameter, element),
        ])
        ..optionalParameters.addAll([
          for (final parameter in member.parameters)
            if (parameter.isNamed || !parameter.isRequired)
              _proxyParameter(parameter, element),
        ])
        ..lambda = true
        ..body = body.code,
    );
  }

  // The `PartTree` of a method name, without what is the default (a plain
  // find, no order, a simple property).
  Expression _partTree(PartTreeModel tree) => _data('PartTree').newInstance(
    [
      _str(tree.methodName),
      literalList([
        for (final or in tree.predicate)
          _data('OrPart').newInstance([
            literalList([
              for (final part in or.parts)
                _data('Part').newInstance([
                  _str(part.property),
                  // `ignoreCase` is the third positional parameter.
                  if (part.kind != PartKind.simpleProperty || part.ignoreCase)
                    _data('PartType').property(part.kind.name),
                  if (part.ignoreCase) literalTrue,
                ]),
            ]),
          ]),
      ]),
    ],
    {
      if (!tree.subject.isDefault)
        'subject': _data('Subject').newInstance(
          [_data('SubjectKind').property(tree.subject.kind.name)],
          {
            if (tree.subject.maxResults case final max?)
              'maxResults': literalNum(max),
            if (tree.subject.distinct) 'distinct': literalTrue,
          },
        ),
      if (tree.sort.isNotEmpty)
        'sort': _data('Sort').newInstance([
          literalList([
            for (final order in tree.sort)
              _data('SortOrder').newInstanceNamed(
                order.descending ? 'desc' : 'asc',
                [_str(order.property)],
              ),
          ]),
        ]),
    },
  );
}
