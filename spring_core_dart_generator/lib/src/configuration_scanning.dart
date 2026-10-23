part of 'bean_scanner.dart';

// Full-mode `@Configuration` classes.
//
// Like Spring's CGLIB-enhanced configuration classes, a `@Configuration`
// class (`proxyBeanMethods: true`, the default) is instantiated as a
// generated subclass whose instance `@Bean` methods return the container's
// bean, so one `@Bean` method calling another gets the singleton. With
// `@Configuration(proxyBeanMethods: false)` (and for `@Component` classes
// with `@Bean` methods, imported plain classes and `@AutoConfiguration`)
// the methods are called as written ("lite" mode).

extension _ConfigurationScanning on BeanScanner {
  /// Whether [element] is a full-mode `@Configuration` class.
  bool isFullConfiguration(ClassElement element) {
    final annotation = _configuration.firstAnnotationOf(element);
    if (annotation == null) {
      return false;
    }
    return ConstantReader(annotation).peek('proxyBeanMethods')?.boolValue ??
        true;
  }

  /// The generated subclass of the full-mode configuration class
  /// [element], created through [constructor]. Fails the build when the
  /// generated library cannot extend the class.
  ConfigurationClassModel configurationClassModel(
    ClassElement element,
    ConstructorElement constructor,
  ) {
    final name = element.name!;
    Never fail(String problem, String change, [Element? at]) =>
        BeanScanner._fail(
          '@Configuration class $name $problem. Its @Bean methods are '
          'intercepted by a generated subclass (Spring\'s proxyBeanMethods) '
          'so that a @Bean method calling another one gets the bean of the '
          'container: $change, or use @Configuration(proxyBeanMethods: '
          'false) to call the methods as written.',
          at ?? element,
        );
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
    return ConfigurationClassModel(
      className: module.uniqueClassName('_\$${name}Configuration'),
      type: element.thisType,
      constructorName: _constructorName(constructor),
      constructorParameters: [
        for (final parameter in constructor.formalParameters)
          if (BeanScanner._isEmittable(parameter.type))
            ProxyParameter(
              name: parameter.name ?? 'p',
              type: parameter.type,
              isNamed: parameter.isNamed,
              isRequired: parameter.isRequired,
            )
          else
            fail(
              'has a constructor parameter of the private type '
                  '${parameter.type.getDisplayString()}',
              'make the type public',
              parameter,
            ),
      ],
      isBase: element.isBase,
    );
  }

  /// The override of the instance `@Bean` method [method] (bean
  /// [beanName]) in [model].
  EnhancedBeanMethod enhancedBeanMethod(
    ConfigurationClassModel model,
    MethodElement method, {
    required String beanName,
    required InterfaceType declaredType,
    required bool isFactoryBean,
    required bool isSingleton,
    required List<Argument> arguments,
  }) {
    final className = model.type.element.name;
    final methodName = method.name!;
    Never fail(String problem) => BeanScanner._fail(
      '@Bean method $className.$methodName $problem, so the generated '
      'subclass of the full-mode @Configuration class cannot override it: '
      'change that, or use @Configuration(proxyBeanMethods: false) to call '
      'the methods as written.',
      method,
    );
    if (!BeanScanner._isEmittable(declaredType)) {
      fail('returns the private type ${declaredType.getDisplayString()}');
    }
    final parameters = <ProxyParameter>[];
    final defaults = <String, DartObject>{};
    for (final parameter in method.formalParameters) {
      final parameterName = parameter.name!;
      if (!BeanScanner._isEmittable(parameter.type)) {
        fail(
          'has the parameter $parameterName of the private type '
          '${parameter.type.getDisplayString()}',
        );
      }
      if (parameter.hasDefaultValue) {
        defaults[parameterName] =
            parameter.computeConstantValue() ??
            fail('has a default value of $parameterName that is not constant');
      }
      parameters.add(
        ProxyParameter(
          name: parameterName,
          type: parameter.type,
          isNamed: parameter.isNamed,
          isRequired: parameter.isRequired,
        ),
      );
    }
    final enhanced = EnhancedBeanMethod(
      className: model.className,
      methodName: methodName,
      beanName: beanName,
      returnType: declaredType,
      parameters: parameters,
      defaults: defaults,
      arguments: arguments,
      isFactoryBean: isFactoryBean,
      isSingleton: isSingleton,
    );
    model.beanMethods.add(enhanced);
    return enhanced;
  }
}
