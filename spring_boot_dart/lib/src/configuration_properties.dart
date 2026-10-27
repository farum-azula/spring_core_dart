import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_boot_dart/src/binder.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Binding or validation of a `@ConfigurationProperties` bean (or a
/// [Binder.bind] call) failed.
///
/// Spring (Java): `BindException` / `BindValidationException` at startup.
class ConfigurationPropertiesBindException implements Exception {
  /// Creates the exception for [prefix] with the binding [errors].
  ConfigurationPropertiesBindException(this.prefix, this.beanName, this.errors);

  /// The property prefix, e.g. `db`.
  final String prefix;

  /// The bean being bound; `null` for a [Binder.bind] call.
  final String? beanName;

  /// One line per failed property, e.g. `db.max-size: must be at least 1`
  /// or `db.hosts[0]: failed to convert to int (was "x")`.
  final List<String> errors;

  @override
  String toString() =>
      "Binding to '$prefix' properties"
      "${beanName == null ? '' : " of bean '$beanName'"} failed: "
      '${errors.join('; ')}';
}

/// Binds `@ConfigurationProperties` beans to the environment, like Spring
/// Boot's `ConfigurationPropertiesBinder` and
/// `ConfigurationPropertiesBindingPostProcessor`, with a [Binder]: relaxed
/// names, lists, maps and nested objects.
///
/// Mutable classes are bound through their setters before their init
/// callbacks run; classes with a constructor that has parameters are
/// created bound by [bindOrCreate] (constructor binding, called by the
/// generated code through [ConstructorBound]). `@ConfigurationProperties`
/// on a `@Bean` method binds the returned object (a class of another
/// package too; the generator writes its introspection).
///
/// Validation, like Spring Boot's: a `Validator` bean named
/// `configurationPropertiesValidator` checks every bound object it
/// supports; constraint annotations are checked when the class (or the
/// `@Bean` method) is annotated `@Validated()`; an object that is itself a
/// `Validator` validates itself.
///
/// Registered by `SpringApplication`; see [ConfigurationProperties] for the
/// naming rules.
class ConfigurationPropertiesBinder extends BeanPostProcessor {
  /// Creates a binder reading [environment] and the metadata of
  /// [introspector]; [messageSource] renders validation messages.
  ConfigurationPropertiesBinder(
    this.environment,
    this.introspector, {
    MessageSource? messageSource,
    this.beanFactory,
  }) : messageSource = messageSource ?? StaticMessageSource();

  /// Name of the `Validator` bean applied to every bound object (Spring
  /// Boot's `ConfigurationPropertiesBinder.VALIDATOR_BEAN_NAME`).
  static const validatorBeanName = 'configurationPropertiesValidator';

  /// The bean factory: the annotations of `@Bean` methods and the
  /// [validatorBeanName] bean come from here (none without it).
  final ConfigurableListableBeanFactory? beanFactory;

  /// The properties are read from here (and converted with its
  /// conversion service).
  final ConfigurableEnvironment environment;

  /// Metadata of the property classes.
  final BeanIntrospector introspector;

  /// Renders validation errors.
  final MessageSource messageSource;

  // Beans created by bindOrCreate, already bound and validated.
  static final _constructed = Expando<bool>('constructor-bound');

  Binder get _binder => Binder(environment, introspector: introspector);

  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    // Expando keys cannot be numbers, strings, booleans or records, and
    // none of those is a @ConfigurationProperties class.
    if (bean is num || bean is String || bean is bool || bean is Record) {
      return bean;
    }
    if (_constructed[bean] ?? false) {
      return bean;
    }
    final introspection = introspector.findIntrospection(bean);
    // A `@Bean` method's annotations come first (Boot's
    // ConfigurationPropertiesBean: the factory method, then the type).
    final annotations = [
      ...?_definition(beanName)?.annotations,
      ...?introspection?.annotations,
    ];
    final annotation = annotations
        .whereType<ConfigurationProperties>()
        .firstOrNull;
    if (annotation == null) {
      return bean;
    }
    if (introspection == null) {
      throw StateError(
        "@ConfigurationProperties('${annotation.prefix}') bean '$beanName' "
        'is a ${bean.runtimeType} without introspection metadata: generated '
        'for @ConfigurationProperties classes and the return types of '
        '@ConfigurationProperties @Bean methods (or annotate the class '
        '@Introspected()).',
      );
    }
    final prefix = annotation.prefix;
    final root = ConfigurationPropertyName.of(prefix);
    final context = _context(annotation)
      ..bindProperties(bean, introspection, root);
    // Boot fails on the first error, so unbound ones come after.
    if (!annotation.ignoreUnknownFields && context.errors.isEmpty) {
      context.checkNoUnboundProperties(root);
    }
    context.throwIfFailed(prefix, beanName);
    _validate(bean, annotations, prefix, beanName);
    return bean;
  }

  // Boot's ConfigurationPropertiesBinder.getHandler: errors ignored with
  // `ignoreInvalidFields`.
  BindContext _context(ConfigurationProperties annotation) => BindContext(
    _binder,
    handler: annotation.ignoreInvalidFields
        ? const _IgnoreErrorsBindHandler()
        : BindHandler.defaultHandler,
  );

  BeanDefinition<Object>? _definition(String beanName) {
    final factory = beanFactory;
    return factory != null && factory.containsBeanDefinition(beanName)
        ? factory.getBeanDefinition(beanName)
        : null;
  }

  /// Creates the `@ConfigurationProperties` class [T] through its
  /// constructor, each parameter bound from its property (constructor
  /// binding), and validates it.
  ///
  /// Throws a [ConfigurationPropertiesBindException] when a property
  /// cannot be converted, a required parameter has no value or a
  /// constraint is violated.
  T bindOrCreate<T extends Object>(String beanName) {
    final introspection = introspector.forTypeArgument<T>();
    final annotation = introspection?.annotations
        .whereType<ConfigurationProperties>()
        .firstOrNull;
    if (introspection == null ||
        annotation == null ||
        introspection.constructor == null) {
      throw StateError(
        '$T is not a constructor-bound @ConfigurationProperties class '
        '(or its module is not registered).',
      );
    }
    final prefix = annotation.prefix;
    final root = ConfigurationPropertyName.of(prefix);
    final context = _context(annotation);
    final bean = context.bindConstructor(
      introspection,
      root,
      context.sources,
      requireAny: false,
    );
    // Boot fails on the first error, so unbound ones come after.
    if (!annotation.ignoreUnknownFields && context.errors.isEmpty) {
      context.checkNoUnboundProperties(root);
    }
    context.throwIfFailed(prefix, beanName);
    if (bean is! T) {
      throw ConfigurationPropertiesBindException(prefix, beanName, [
        '$prefix: could not create $T',
      ]);
    }
    _validate(bean, introspection.annotations, prefix, beanName);
    _constructed[bean] = true;
    return bean;
  }

  // Spring Boot's ConfigurationPropertiesBinder.getValidators: the
  // `configurationPropertiesValidator` bean, constraints for `@Validated`
  // ones, then the object itself when it is a Validator; each only when it
  // supports the object.
  void _validate(
    Object bean,
    List<Object> annotations,
    String prefix,
    String beanName,
  ) {
    final validators = [
      ?_configurationPropertiesValidator(),
      if (annotations.any((a) => a is Validated))
        BeanValidator(introspector: introspector),
      if (bean case final Validator self) self,
    ].where((validator) => validator.supports(bean));
    if (validators.isEmpty) {
      return;
    }
    final binder = DataBinder(
      bean,
      objectName: prefix,
      introspector: introspector,
      conversionService: environment.conversionService,
    );
    binder.validators.addAll(validators);
    binder.validate();
    final result = binder.bindingResult;
    if (result.hasErrors) {
      throw ConfigurationPropertiesBindException(prefix, beanName, [
        for (final error in result.allErrors)
          // One element, split for the line width.
          // ignore: no_adjacent_strings_in_list, lines_longer_than_80_chars
          '${error is FieldError ? '$prefix.${_dashedPath(error.field)}' : prefix}: '
              '${messageSource.getMessageFromResolvable(error)}'
              // A string that cannot be split without changing it.
              // ignore: lines_longer_than_80_chars
              '${error is FieldError && error.rejectedValue != null ? ' (was "${error.rejectedValue}")' : ''}',
      ]);
    }
  }

  Validator? _configurationPropertiesValidator() {
    final factory = beanFactory;
    if (factory == null || !factory.containsBean(validatorBeanName)) {
      return null;
    }
    return factory.getBeanByName(validatorBeanName) as Validator;
  }

  // `servers[0].maxSize` → `servers[0].max-size`.
  static String _dashedPath(String path) => path.replaceAllMapped(
    RegExp(r'[^.\[\]]+(?![^\[]*\])'),
    (match) => dashedForm(match[0]!),
  );
}

// Spring Boot's IgnoreErrorsBindHandler: a value that cannot be bound is
// left unbound (the field keeps its default).
final class _IgnoreErrorsBindHandler extends BindHandler {
  const _IgnoreErrorsBindHandler();

  @override
  bool onFailure(ConfigurationPropertyName name, String error) => false;
}

/// Creates constructor-bound `@ConfigurationProperties` beans: the
/// generated `create` of such a bean calls [from] (Spring Boot's
/// `ConstructorBound`).
///
/// ```dart
/// // Generated for `@ConfigurationProperties('db') class DbProperties`
/// // whose only constructor has parameters:
/// create: (r) => ConstructorBound.from<DbProperties>(r, r'dbProperties'),
/// ```
abstract final class ConstructorBound {
  /// The bean [beanName] of type [T], created bound from the context's
  /// environment.
  static T from<T extends Object>(
    DependencyResolver resolver,
    String beanName,
  ) => ConfigurationPropertiesBinder(
    resolver.dependency<ConfigurableEnvironment>(),
    resolver.dependency<BeanIntrospector>(),
    beanFactory: resolver.dependency<ConfigurableListableBeanFactory>(),
  ).bindOrCreate<T>(beanName);
}
