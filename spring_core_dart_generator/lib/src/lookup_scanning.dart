part of 'bean_scanner.dart';

// `@Lookup` methods (lookup method injection).
//
// Like Spring's CglibSubclassingInstantiationStrategy, a bean class with
// `@Lookup` methods is created as a generated subclass that overrides each
// of them to return a bean of the container (`getBean`), so a singleton
// can get a new prototype per call. Unlike other abstract classes, an
// abstract class with `@Lookup` methods is a candidate component (Spring's
// `isCandidateComponent` accepts it too).

extension _LookupScanning on BeanScanner {
  /// Whether [element] or one of its supertypes declares a `@Lookup`
  /// method (or a getter or field marked `@Lookup`, which
  /// [lookupClassModel] rejects).
  bool hasLookupMethods(ClassElement element) =>
      _hierarchy(element.thisType).any(
        (current) =>
            current.methods.any(_lookup.hasAnnotationOf) ||
            current.getters.any(
              (getter) =>
                  _lookup.hasAnnotationOf(getter) ||
                  _lookup.hasAnnotationOf(getter.variable),
            ),
      );

  /// The generated subclass overriding the `@Lookup` methods of [type]
  /// (the type of [element]), created through [constructor]; `null` when
  /// the class has none. Fails the build when a method or the class
  /// cannot be overridden from the generated library.
  LookupClassModel? lookupClassModel(
    ClassElement element,
    InterfaceType type,
    ConstructorElement? constructor, {
    required bool fullConfiguration,
  }) {
    final className = element.name!;
    final library = element.library;
    final methods = <LookupMethod>[];
    final seen = <String>{};
    for (final current in _hierarchy(type)) {
      for (final accessor in [...current.getters, ...current.setters]) {
        final annotated = _lookup.hasAnnotationOf(accessor)
            ? accessor
            : accessor.variable;
        if (_lookup.hasAnnotationOf(annotated)) {
          BeanScanner._fail(
            '@Lookup on ${current.name}.${accessor.displayName}: only '
            'methods can be lookup methods. Declare a method without '
            'parameters instead (`Command createCommand();`).',
            annotated,
          );
        }
      }
      for (final method in current.methods) {
        final annotation = _lookup.firstAnnotationOf(method);
        final name = method.name;
        if (annotation == null || name == null || !seen.add(name)) {
          continue;
        }
        final label = '@Lookup method ${current.name}.$name';
        if (method.isStatic) {
          BeanScanner._fail(
            '$label must not be static: the container overrides it in a '
            'generated subclass.',
            method,
          );
        }
        if (method.isPrivate) {
          BeanScanner._fail(
            '$label must be public: the generated subclass that overrides '
            'it lives in another library.',
            method,
          );
        }
        if (method.typeParameters.isNotEmpty) {
          BeanScanner._fail(
            '$label must not be generic: the bean is looked up by the '
            'declared return type. Remove its type parameters.',
            method,
          );
        }
        if (method.formalParameters.isNotEmpty) {
          BeanScanner._fail(
            '$label must not take parameters: Spring passes them to the '
            'constructor of the looked-up bean, which generated bean '
            'definitions cannot do. Inject an ObjectProvider<T> (or a '
            'factory bean) and pass the values yourself.',
            method,
          );
        }
        // The most derived declaration, with the type arguments of [type]
        // substituted.
        final declared =
            type.lookUpMethod(name, library) ??
            [
              type,
              ...type.allSupertypes,
            ].map((t) => t.getMethod(name)).nonNulls.firstOrNull ??
            method;
        final returnType = declared.returnType;
        _requireDefinedType(returnType, method, '$label returns');
        final beanName = ConstantReader(annotation).peek('value')?.stringValue;
        if (beanName != null && beanName.isEmpty) {
          BeanScanner._fail(
            '$label names an empty bean: give a bean name, or use @Lookup() '
            'to look the bean up by its return type.',
            method,
          );
        }
        if (!BeanScanner._isEmittable(returnType)) {
          BeanScanner._fail(
            '$label returns ${returnType.getDisplayString()}, a type the '
            'generated library cannot reference. Make the type public.',
            method,
          );
        }
        if (beanName == null &&
            (returnType is! InterfaceType ||
                returnType.isDartCoreObject ||
                returnType.isDartAsyncFuture ||
                returnType.isDartAsyncFutureOr)) {
          BeanScanner._fail(
            '$label returns ${returnType.getDisplayString()}: a lookup by '
            'type needs the bean class as return type. Return the bean '
            "type, or name the bean with @Lookup('name').",
            method,
          );
        }
        methods.add(
          LookupMethod(name: name, beanName: beanName, returnType: returnType),
        );
      }
    }
    if (methods.isEmpty) {
      return null;
    }
    // The generated subclass implements the lookup methods only: any other
    // abstract member would leave it abstract (Spring's CGLIB subclass
    // fails the same way at call time with an AbstractMethodError).
    if (element.isAbstract) {
      final abstract = <String>[];
      for (final member in element.interfaceMembers.values) {
        final name = member.name;
        if (name == null || member.isStatic || seen.contains(name)) {
          continue;
        }
        final concrete = switch (member) {
          MethodElement() => type.lookUpMethod(name, library, concrete: true),
          GetterElement() => type.lookUpGetter(name, library, concrete: true),
          SetterElement() => type.lookUpSetter(name, library, concrete: true),
          _ => member,
        };
        if (concrete == null) {
          abstract.add(switch (member) {
            GetterElement() => 'get $name',
            SetterElement() => 'set $name',
            _ => '$name()',
          });
        }
      }
      if (abstract.isNotEmpty) {
        BeanScanner._fail(
          '$className has @Lookup methods, which a generated subclass '
          'overrides to return beans of the container, but it also has the '
          'abstract member${abstract.length == 1 ? '' : 's'} '
          '${abstract.join(', ')}, which the generated subclass cannot '
          'implement: give ${abstract.length == 1 ? 'it a body' : 'them bodies'}'
          ' or make ${abstract.length == 1 ? 'it a @Lookup method' : 'them @Lookup methods'}.',
          element,
        );
      }
    }
    Never fail(String problem, String change, [Element? at]) =>
        BeanScanner._fail(
          '$className has @Lookup methods, which a generated subclass '
          'overrides to return beans of the container, but it $problem: '
          '$change.',
          at ?? element,
        );
    if (fullConfiguration) {
      fail(
        'is a full-mode @Configuration class (already created as a '
            'generated subclass)',
        'move the @Lookup methods to a @Component class, or use '
            '@Configuration(proxyBeanMethods: false)',
      );
    }
    final modifier = element.isSealed
        ? 'sealed'
        : element.isFinal
        ? 'final'
        : element.isInterface
        ? 'interface'
        : null;
    if (modifier != null || !element.isExtendableOutside) {
      fail(
        'cannot be extended${modifier == null ? '' : ' (it is $modifier)'}',
        modifier == null ? 'make it extendable' : 'remove `$modifier`',
      );
    }
    if (constructor == null) {
      fail(
        'is bound from properties through its constructor',
        'move the @Lookup methods to another bean',
      );
    }
    if (constructor.isFactory || constructor.isPrivate) {
      fail(
        'is created through the '
            '${constructor.isFactory ? 'factory' : 'private'} constructor '
            '${constructor.displayName}, which a subclass in the generated '
            'library cannot call',
        'add a public generative constructor',
        constructor,
      );
    }
    return LookupClassModel(
      className: module.uniqueClassName('_\$${className}Lookup'),
      type: type,
      constructorName: _constructorName(constructor),
      // Parameter types are public: the scanner checks every injection
      // point before coming here.
      constructorParameters: [
        for (final (index, parameter) in constructor.formalParameters.indexed)
          ProxyParameter(
            name: forwardedParameterName(constructor.formalParameters, index),
            type: parameter.type,
            isNamed: parameter.isNamed,
            isRequired: parameter.isRequired,
          ),
      ],
      isBase: element.isBase,
      methods: methods,
    );
  }
}
