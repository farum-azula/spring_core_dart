import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_boot_dart/src/binder.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// The error thrown when configuration values are invalid: a value that
/// cannot be converted, a required value that is missing, or a validation
/// constraint that fails.
///
/// It carries every bad property at once, one line each, so the
/// developer can fix them all in one go. It is thrown while binding a
/// `@ConfigurationProperties` bean, by [Binder.bind], and by
/// `SpringApplication` for invalid `logging.level.*` and
/// `spring.main.banner-mode` values. A failed start turns it into a
/// `Binding to target properties under '...' failed` report. Catch it
/// only in code that binds by hand and can fall back to defaults.
///
/// Spring (Java): `BindException` / `BindValidationException`, which
/// Spring Boot reports in the same way at startup.
class ConfigurationPropertiesBindException implements Exception {
  /// An exception for the properties under [prefix], bound for the bean
  /// [beanName] (null outside a bean), with one line per problem in
  /// [errors].
  ConfigurationPropertiesBindException(this.prefix, this.beanName, this.errors);

  /// The prefix of the properties being bound, such as `db`.
  final String prefix;

  /// The name of the bean being bound, or `null` when no bean was bound
  /// (a [Binder.bind] call, for example).
  final String? beanName;

  /// One line per problem, naming the property: `db.max-size: must be at
  /// least 1` or `db.hosts[0]: failed to convert to int (was "x")`.
  final List<String> errors;

  @override
  String toString() =>
      "Binding to '$prefix' properties"
      "${beanName == null ? '' : " of bean '$beanName'"} failed: "
      '${errors.join('; ')}';
}

/// The machinery that fills `@ConfigurationProperties` beans from the
/// environment and validates them.
///
/// `SpringApplication` registers it in every context, so applications
/// never create it: they annotate a class with [ConfigurationProperties]
/// and get it filled. Reach for it only when building a context without
/// `SpringApplication` that should still bind such beans.
///
/// A mutable class is bound through its setters as a bean
/// post-processor, before its init callbacks run. A class whose
/// constructor has parameters is created already bound by [bindOrCreate]
/// (constructor binding; the generated code calls it through
/// [ConstructorBound]). `@ConfigurationProperties` on a `@Bean` method
/// binds the object the method returns, also of a class from another
/// package, whose introspection the generator writes. The rules for names,
/// lists, maps and nested objects are those of [Binder].
///
/// After binding, the object is validated by every validator that
/// supports it:
///
/// - the `Validator` bean named [validatorBeanName], when there is one;
/// - the constraint annotations (`@NotBlank()`, `@Min(1)`, ...), when the
///   class or the `@Bean` method is annotated `@Validated()`;
/// - the object itself, when it is a `Validator`.
///
/// Spring (Java): `ConfigurationPropertiesBinder` and
/// `ConfigurationPropertiesBindingPostProcessor`, with the same
/// validation rules.
class ConfigurationPropertiesBinder extends BeanPostProcessor {
  /// A binder reading [environment] and the class metadata of
  /// [introspector].
  ///
  /// [messageSource] turns validation errors into text (default: an empty
  /// `StaticMessageSource`, which uses the constraints' default messages).
  /// [beanFactory] gives access to the annotations of `@Bean` methods and
  /// to the [validatorBeanName] bean; without it neither is used.
  ConfigurationPropertiesBinder(
    this.environment,
    this.introspector, {
    MessageSource? messageSource,
    this.beanFactory,
  }) : messageSource = messageSource ?? StaticMessageSource();

  /// The name a `Validator` bean must have to check every bound
  /// properties object it supports, `configurationPropertiesValidator`
  /// (Spring Boot's `ConfigurationPropertiesBinder.VALIDATOR_BEAN_NAME`).
  ///
  /// Declare one for checks that span several fields or several classes.
  static const validatorBeanName = 'configurationPropertiesValidator';

  /// The bean factory the annotations of `@Bean` methods and the
  /// [validatorBeanName] bean come from; null when there is none.
  final ConfigurableListableBeanFactory? beanFactory;

  /// The environment the properties are read from; its conversion
  /// service converts them.
  final ConfigurableEnvironment environment;

  /// Describes the properties classes: their fields, setters, constructor
  /// and annotations.
  final BeanIntrospector introspector;

  /// Turns validation errors into the text of the error lines.
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
  /// binding), validates it, and returns it as the bean [beanName].
  ///
  /// The generated code calls it through [ConstructorBound]. Throws a
  /// [ConfigurationPropertiesBindException] when a property cannot be
  /// converted, a required parameter has no value or a constraint fails,
  /// and a `StateError` when [T] is not a constructor-bound
  /// `@ConfigurationProperties` class known to the introspector.
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

/// The hook the generated code uses to create a
/// `@ConfigurationProperties` bean whose class has constructor
/// parameters.
///
/// Such a class cannot be created first and filled later, so its bean
/// definition creates it already bound. Applications never call it; it
/// matters only to hand-written bean definitions.
///
/// ```dart
/// // Generated for `@ConfigurationProperties('db') class DbProperties`
/// // whose only constructor has parameters:
/// create: (r) => ConstructorBound.from<DbProperties>(r, r'dbProperties'),
/// ```
///
/// Spring (Java): the `ConstructorBound` binding of Spring Boot's
/// `ConfigurationPropertiesBean`.
abstract final class ConstructorBound {
  /// Creates the bean [beanName] of type [T], bound from the context's
  /// environment and validated, using the environment, introspector and
  /// bean factory that [resolver] provides.
  static T from<T extends Object>(
    DependencyResolver resolver,
    String beanName,
  ) => ConfigurationPropertiesBinder(
    resolver.dependency<ConfigurableEnvironment>(),
    resolver.dependency<BeanIntrospector>(),
    beanFactory: resolver.dependency<ConfigurableListableBeanFactory>(),
  ).bindOrCreate<T>(beanName);
}
