part of 'module_emitter.dart';

// Generated subclasses of full-mode `@Configuration` classes (see
// `ConfigurationClassModel`): every instance `@Bean` method returns the
// container's bean, and `_$method(r)` runs the original method for the
// container. Like Spring's `BeanMethodInterceptor`, the arguments of an
// inter-bean call are passed to the creation of the bean when that call
// creates it (`beanFactory.getBean(name, args)`): an existing singleton is
// returned as it is, a prototype is created with them, and a singleton
// ignores them when one is `null`.

/// The generated marker class of a defaulted `@Bean` parameter left out of
/// an inter-bean call.
const absentClass = r'_$Absent';

extension _ConfigurationEmitter on ModuleEmitter {
  /// `class _$Absent { const _$Absent(); }`, emitted when a full-mode
  /// `@Bean` method has a defaulted parameter.
  Class absentMarkerClass() => Class(
    (c) => c
      ..docs.add(
        '/// A defaulted `@Bean` parameter left out of an inter-bean call.',
      )
      ..name = absentClass
      ..constructors.add(Constructor((k) => k..constant = true)),
  );

  /// `(r.dependency<AppConfig>(...) as _$AppConfigConfiguration)._$m(r)`.
  Expression enhancedBeanMethodCall(
    BeanMethodCreation creation,
    EnhancedBeanMethod method,
    Element element,
  ) => refer('r')
      .property('dependency')
      .call(
        [],
        {'qualifier': _str(creation.ownerName)},
        [_type(creation.ownerType, element)],
      )
      .asA(refer(method.className))
      .property('_\$${creation.methodName}')
      .call([refer('r')]);

  /// The subclass of [model].
  Class configurationClass(ConfigurationClassModel model) {
    final element = model.type.element;
    final withArguments = model.beanMethods.any((m) => m.parameters.isNotEmpty);
    return Class(
      (c) => c
        ..docs.add(
          '/// `${element.name}` whose `@Bean` methods return the beans of the '
          'container\n/// (full-mode `@Configuration`).',
        )
        ..modifier = model.isBase ? ClassModifier.final$ : null
        ..name = model.className
        ..extend = _type(model.type, element)
        ..fields.addAll([
          Field(
            (f) => f
              ..name = r'_$beanFactory'
              ..modifier = FieldModifier.final$
              ..type = _spring('BeanFactory'),
          ),
          if (withArguments)
            Field(
              (f) => f
                ..name = r'_$arguments'
                ..modifier = FieldModifier.final$
                ..assignment = literalMap(
                  const {},
                  refer('String'),
                  TypeReference(
                    (t) => t
                      ..symbol = 'List'
                      ..types.add(refer('Object?')),
                  ),
                ).code,
            ),
        ])
        ..constructors.add(
          _forwardingConstructor(
            model.constructorName,
            model.constructorParameters,
            Parameter(
              (p) => p
                ..name = r'_$beanFactory'
                ..toThis = true,
            ),
          ),
        )
        ..methods.addAll([
          for (final method in model.beanMethods) ...[
            _beanMethodOverride(method, element),
            _beanMethodForContainer(method, element),
          ],
        ]),
    );
  }

  // `foo()` returns `getBeanByName('foo')`; with parameters, the arguments
  // are kept for the creation of the bean while the container looks it up.
  Method _beanMethodOverride(EnhancedBeanMethod method, Element element) {
    final returnType = _anyType(method.returnType, element);
    // Fields through `this.`, locals with `_$` names: a parameter may be
    // called `arguments` or `_$beanFactory` without shadowing them.
    final bean = refer('this')
        .property(r'_$beanFactory')
        .property('getBeanByName')
        .call([
          _str(method.isFactoryBean ? '&${method.beanName}' : method.beanName),
        ]);
    // A method that may return null: its NullBean is returned as null, as
    // Spring's BeanMethodInterceptor does.
    final mayBeNull =
        method.returnType.nullabilitySuffix == NullabilitySuffix.question;
    final lookup = mayBeNull
        ? _spring('NullBean')
              .property('orNull')
              .call(
                [bean],
                {},
                [
                  _anyType(
                    element.library!.typeSystem.promoteToNonNull(
                      method.returnType,
                    ),
                    element,
                  ),
                ],
              )
        : bean.asA(returnType);
    final hasParameters = method.parameters.isNotEmpty;
    final key = _str(method.beanName);
    final store = refer('this')
        .property(r'_$arguments')
        .index(key)
        .assign(refer(r'_$args'));
    // Spring: "stubbed null arguments just for reference purposes" of a
    // singleton are not used.
    final nullable = method.parameters.any(
      (p) => p.type.nullabilitySuffix == NullabilitySuffix.question,
    );
    return Method(
      (m) => m
        ..annotations.add(refer('override'))
        ..returns = returnType
        ..name = method.methodName
        ..requiredParameters.addAll([
          for (final parameter in method.parameters)
            if (!parameter.isNamed && parameter.isRequired)
              _overrideParameter(method, parameter, element),
        ])
        ..optionalParameters.addAll([
          for (final parameter in method.parameters)
            if (parameter.isNamed || !parameter.isRequired)
              _overrideParameter(method, parameter, element),
        ])
        ..lambda = !hasParameters
        ..body = hasParameters
            ? Block.of([
                declareFinal(r'_$args')
                    .assign(
                      literalList([
                        for (final parameter in method.parameters)
                          refer(parameter.name),
                      ], refer('Object?')),
                    )
                    .statement,
                if (method.isSingleton && nullable) ...[
                  const Code(r'if (!_$args.contains(null)) {'),
                  store.statement,
                  const Code('}'),
                ] else
                  store.statement,
                const Code('try {'),
                lookup.returned.statement,
                const Code('} finally {'),
                refer('this')
                    .property(r'_$arguments')
                    .property('remove')
                    .call([key])
                    .statement,
                const Code('}'),
              ])
            : lookup.code,
    );
  }

  Parameter _overrideParameter(
    EnhancedBeanMethod method,
    ProxyParameter parameter,
    Element element,
  ) {
    // A defaulted parameter the caller leaves out is resolved like the
    // container resolves it (a bean, else the Dart default), so the bean
    // is the same whoever creates it first: the override marks it absent
    // instead of passing the Dart default.
    final defaulted = method.defaults.containsKey(parameter.name);
    return Parameter(
      (p) => p
        ..name = parameter.name
        ..type = defaulted
            ? refer('Object?')
            : _anyType(parameter.type, element)
        ..named = parameter.isNamed
        ..required = parameter.isNamed && parameter.isRequired
        ..defaultTo = defaulted
            ? refer(absentClass).constInstance([]).code
            : null,
    );
  }

  // `_$foo(r)`: the original method, with the arguments of the inter-bean
  // call that is creating the bean, else with the injected ones.
  Method _beanMethodForContainer(EnhancedBeanMethod method, Element element) {
    Expression superCall(List<Expression> values) =>
        refer('super')
            .property(method.methodName)
            .call(
              [
                for (final (index, parameter) in method.parameters.indexed)
                  if (!parameter.isNamed) values[index],
              ],
              {
                for (final (index, parameter) in method.parameters.indexed)
                  if (parameter.isNamed) parameter.name: values[index],
              },
            );
    final injected = superCall([
      for (final argument in method.arguments) _lookup(argument.point, element),
    ]);
    return Method(
      (m) => m
        ..returns = _anyType(method.returnType, element)
        ..name = '_\$${method.methodName}'
        ..requiredParameters.add(
          Parameter(
            (p) => p
              ..name = 'r'
              ..type = _spring('DependencyResolver'),
          ),
        )
        ..lambda = method.parameters.isEmpty
        ..body = method.parameters.isEmpty
            ? injected.code
            : Block.of([
                declareFinal(r'_$args')
                    .assign(
                      refer('this')
                          .property(r'_$arguments')
                          .property('remove')
                          .call([_str(method.beanName)]),
                    )
                    .statement,
                const Code(r'if (_$args != null) {'),
                superCall([
                  for (final (index, parameter) in method.parameters.indexed)
                    if (method.defaults.containsKey(parameter.name))
                      refer(r'_$args')
                          .index(literalNum(index))
                          .isA(refer(absentClass))
                          .conditional(
                            _lookup(method.arguments[index].point, element),
                            refer(r'_$args')
                                .index(literalNum(index))
                                .asA(_anyType(parameter.type, element)),
                          )
                    else
                      refer(r'_$args')
                          .index(literalNum(index))
                          .asA(_anyType(parameter.type, element)),
                ]).returned.statement,
                const Code('}'),
                injected.returned.statement,
              ]),
    );
  }
}
