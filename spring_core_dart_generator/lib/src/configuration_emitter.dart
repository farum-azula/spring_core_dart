part of 'module_emitter.dart';

// Generated subclasses of full-mode `@Configuration` classes (see
// `ConfigurationClassModel`): every instance `@Bean` method returns the
// container's bean, and `_$method(r)` runs the original method for the
// container. Like Spring's `BeanMethodInterceptor`, the arguments of an
// inter-bean call are passed to the creation of the bean when that call
// creates it (`beanFactory.getBean(name, args)`): an existing singleton is
// returned as it is, a prototype is created with them, and a singleton
// ignores them when one is `null`.

extension _ConfigurationEmitter on ModuleEmitter {
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
    final parameters = model.constructorParameters;
    Parameter superParameter(int index, ProxyParameter parameter) => Parameter(
      (p) => p
        ..name = parameter.isNamed ? parameter.name : 'p$index'
        ..toSuper = true
        ..named = parameter.isNamed
        ..required = parameter.isNamed && parameter.isRequired,
    );
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
          Constructor(
            (k) => k
              ..requiredParameters.addAll([
                Parameter(
                  (p) => p
                    ..name = r'_$beanFactory'
                    ..toThis = true,
                ),
                for (final (index, parameter) in parameters.indexed)
                  if (!parameter.isNamed && parameter.isRequired)
                    superParameter(index, parameter),
              ])
              ..optionalParameters.addAll([
                for (final (index, parameter) in parameters.indexed)
                  if (parameter.isNamed || !parameter.isRequired)
                    superParameter(index, parameter),
              ])
              ..initializers.addAll([
                if (model.constructorName case final name?)
                  refer('super').property(name).call([]).code,
              ]),
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
    final returnType = _type(method.returnType, element);
    final lookup = refer(r'_$beanFactory')
        .property('getBeanByName')
        .call([
          _str(method.isFactoryBean ? '&${method.beanName}' : method.beanName),
        ])
        .asA(returnType);
    final hasParameters = method.parameters.isNotEmpty;
    final key = _str(method.beanName);
    final store = refer(r'_$arguments').index(key).assign(refer('arguments'));
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
                declareFinal('arguments')
                    .assign(
                      literalList([
                        for (final parameter in method.parameters)
                          refer(parameter.name),
                      ], refer('Object?')),
                    )
                    .statement,
                if (method.isSingleton && nullable) ...[
                  const Code('if (!arguments.contains(null)) {'),
                  store.statement,
                  const Code('}'),
                ] else
                  store.statement,
                const Code('try {'),
                lookup.returned.statement,
                const Code('} finally {'),
                refer(r'_$arguments').property('remove').call([key]).statement,
                const Code('}'),
              ])
            : lookup.code,
    );
  }

  Parameter _overrideParameter(
    EnhancedBeanMethod method,
    ProxyParameter parameter,
    Element element,
  ) => Parameter(
    (p) => p
      ..name = parameter.name
      ..type = _anyType(parameter.type, element)
      ..named = parameter.isNamed
      ..required = parameter.isNamed && parameter.isRequired
      ..defaultTo = switch (method.defaults[parameter.name]) {
        final value? => _constant(value, element).code,
        null => null,
      },
  );

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
        ..returns = _type(method.returnType, element)
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
                declareFinal('arguments')
                    .assign(
                      refer(r'_$arguments')
                          .property('remove')
                          .call([_str(method.beanName)]),
                    )
                    .statement,
                const Code('if (arguments != null) {'),
                superCall([
                  for (final (index, parameter) in method.parameters.indexed)
                    refer('arguments')
                        .index(literalNum(index))
                        .asA(_anyType(parameter.type, element)),
                ]).returned.statement,
                const Code('}'),
                injected.returned.statement,
              ]),
    );
  }
}
