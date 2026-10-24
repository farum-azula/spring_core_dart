part of 'module_emitter.dart';

// Generated subclasses of bean classes with `@Lookup` methods (see
// `LookupClassModel`): every lookup method returns a bean of the container
// per call, like Spring's LookupOverrideMethodInterceptor. A subclass AOP
// proxy of such a bean extends this class (see `_subclassProxyClass`).

extension _LookupEmitter on ModuleEmitter {
  /// The subclass of [model].
  Class lookupClass(LookupClassModel model) {
    final element = model.type.element;
    return Class(
      (c) => c
        ..docs.add(
          '/// `${element.name}` whose `@Lookup` methods return beans of the '
          'container.',
        )
        ..modifier = model.isBase ? ClassModifier.final$ : null
        ..name = model.className
        ..extend = _type(model.type, element)
        ..fields.add(
          Field(
            (f) => f
              ..name = r'_$beanFactory'
              ..modifier = FieldModifier.final$
              ..type = _spring('BeanFactory'),
          ),
        )
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
          for (final method in model.methods) _lookupOverride(method, element),
        ]),
    );
  }

  /// A constructor taking [first] (if any), then forwarding [parameters]
  /// to the super constructor [constructorName] as super parameters.
  Constructor _forwardingConstructor(
    String? constructorName,
    List<ProxyParameter> parameters, [
    Parameter? first,
  ]) {
    Parameter superParameter(int index, ProxyParameter parameter) => Parameter(
      (p) => p
        ..name = parameter.isNamed ? parameter.name : 'p$index'
        ..toSuper = true
        ..named = parameter.isNamed
        ..required = parameter.isNamed && parameter.isRequired,
    );
    return Constructor(
      (k) => k
        ..requiredParameters.addAll([
          ?first,
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
          if (constructorName case final name?)
            refer('super').property(name).call([]).code,
        ]),
    );
  }

  // `createCommand()` returns `getBean<Command>()` (`findBean` for a
  // nullable type), or the named bean.
  Method _lookupOverride(LookupMethod method, Element element) {
    final returnType = method.returnType;
    final nullable = returnType.nullabilitySuffix == NullabilitySuffix.question;
    final nonNull = _anyType(
      element.library!.typeSystem.promoteToNonNull(returnType),
      element,
    );
    final factory = refer('this').property(r'_$beanFactory');
    final Expression body;
    if (method.beanName case final name?) {
      final bean = factory.property('getBeanByName').call([_str(name)]);
      // A bean that may be null: its NullBean is returned as null.
      body = nullable
          ? _spring('NullBean').property('orNull').call([bean], {}, [nonNull])
          : bean.asA(nonNull);
    } else {
      body = factory.property(nullable ? 'findBean' : 'getBean').call([], {}, [
        nonNull,
      ]);
    }
    return Method(
      (m) => m
        ..annotations.add(refer('override'))
        ..returns = _anyType(returnType, element)
        ..name = method.name
        ..lambda = true
        ..body = body.code,
    );
  }
}
