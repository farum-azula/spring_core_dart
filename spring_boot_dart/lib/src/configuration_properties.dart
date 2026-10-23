import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Binding or validation of a `@ConfigurationProperties` bean failed.
///
/// Spring (Java): `BindValidationException` / `BindException` at startup.
class ConfigurationPropertiesBindException implements Exception {
  /// Creates the exception for [prefix] with the binding [errors].
  ConfigurationPropertiesBindException(this.prefix, this.beanName, this.errors);

  /// The property prefix, e.g. `db`.
  final String prefix;

  /// The bean being bound.
  final String beanName;

  /// One line per failed property, e.g. `db.max-size: must be at least 1`.
  final List<String> errors;

  @override
  String toString() =>
      "Binding to '$prefix' properties of bean '$beanName' failed: "
      '${errors.join('; ')}';
}

/// Binds `@ConfigurationProperties` beans to the environment before their
/// init callbacks run, like Spring Boot's
/// `ConfigurationPropertiesBindingPostProcessor`.
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

  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    final introspection = introspector.findIntrospection(bean);
    final annotation = introspection?.annotations
        .whereType<ConfigurationProperties>()
        .firstOrNull;
    if (introspection == null || annotation == null) {
      return bean;
    }
    final prefix = annotation.prefix;
    final values = <String, Object?>{};
    _collect(introspection, prefix, '', values, depth: 0);

    final binder = DataBinder(
      bean,
      objectName: prefix,
      introspector: introspector,
      conversionService: environment.conversionService,
    );
    // Only `@Validated` classes are validated, like Spring Boot.
    if (introspection.annotations.any((a) => a is Validated)) {
      binder.validators.add(BeanValidator(introspector: introspector));
    }
    binder
      ..bind(values)
      ..validate();
    final result = binder.bindingResult;
    if (result.hasErrors) {
      throw ConfigurationPropertiesBindException(prefix, beanName, [
        for (final error in result.allErrors)
          '${error is FieldError ? '$prefix.${_kebabPath(error.field)}' : prefix}: '
              '${messageSource.getMessageFromResolvable(error)}'
              '${error is FieldError && error.rejectedValue != null ? ' (was "${error.rejectedValue}")' : ''}',
      ]);
    }
    return bean;
  }

  // Walks the writable properties (and nested introspected objects) and
  // records the values present in the environment, keyed by property path.
  void _collect(
    BeanIntrospection<Object> introspection,
    String keyPrefix,
    String pathPrefix,
    Map<String, Object?> values, {
    required int depth,
  }) {
    for (final property in introspection.properties) {
      final key = '$keyPrefix.${kebabCase(property.name)}';
      final path = '$pathPrefix${property.name}';
      final nested = introspector.forType(property.type);
      if (nested != null && depth < 8) {
        _collect(nested, key, '$path.', values, depth: depth + 1);
        continue;
      }
      if (!property.isWritable) {
        continue;
      }
      final value = _lookup(key, '$keyPrefix.${property.name}');
      if (value != null) {
        values[path] = value;
      }
    }
  }

  String? _lookup(String kebabKey, String camelKey) =>
      environment.getProperty(kebabKey) ??
      environment.getProperty(camelKey) ??
      environment.getProperty(
        kebabKey.replaceAll('.', '_').replaceAll('-', '').toUpperCase(),
      );

  static String _kebabPath(String path) =>
      path.split('.').map(kebabCase).join('.');

  /// `maxSize` → `max-size`, like Spring Boot's canonical property names.
  static String kebabCase(String name) => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => '-${match.group(0)!.toLowerCase()}',
  );
}
