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
/// generated code through [ConstructorBound]). Constraints are checked when
/// the class is annotated `@Validated()`.
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
  }) : messageSource = messageSource ?? StaticMessageSource();

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
    final annotation = introspection?.annotations
        .whereType<ConfigurationProperties>()
        .firstOrNull;
    if (introspection == null || annotation == null) {
      return bean;
    }
    final prefix = annotation.prefix;
    BindContext(_binder)
      ..bindProperties(
        bean,
        introspection,
        ConfigurationPropertyName.of(prefix),
      )
      ..throwIfFailed(prefix, beanName);
    _validate(bean, introspection, prefix, beanName);
    return bean;
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
    final context = BindContext(_binder);
    final bean = context.bindConstructor(
      introspection,
      ConfigurationPropertyName.of(prefix),
      context.sources,
      requireAny: false,
    );
    context.throwIfFailed(prefix, beanName);
    if (bean is! T) {
      throw ConfigurationPropertiesBindException(prefix, beanName, [
        '$prefix: could not create $T',
      ]);
    }
    _validate(bean, introspection, prefix, beanName);
    _constructed[bean] = true;
    return bean;
  }

  // Only `@Validated` classes are validated, like Spring Boot.
  void _validate(
    Object bean,
    BeanIntrospection<Object> introspection,
    String prefix,
    String beanName,
  ) {
    if (!introspection.annotations.any((a) => a is Validated)) {
      return;
    }
    final binder = DataBinder(
      bean,
      objectName: prefix,
      introspector: introspector,
      conversionService: environment.conversionService,
    );
    binder.validators.add(BeanValidator(introspector: introspector));
    binder.validate();
    final result = binder.bindingResult;
    if (result.hasErrors) {
      throw ConfigurationPropertiesBindException(prefix, beanName, [
        for (final error in result.allErrors)
          '${error is FieldError ? '$prefix.${_dashedPath(error.field)}' : prefix}: '
              '${messageSource.getMessageFromResolvable(error)}'
              '${error is FieldError && error.rejectedValue != null ? ' (was "${error.rejectedValue}")' : ''}',
      ]);
    }
  }

  // `servers[0].maxSize` → `servers[0].max-size`.
  static String _dashedPath(String path) => path.replaceAllMapped(
    RegExp(r'[^.\[\]]+(?![^\[]*\])'),
    (match) => dashedForm(match[0]!),
  );
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
  ).bindOrCreate<T>(beanName);
}
