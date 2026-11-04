import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/properties/properties_beans.dart';

/// A value of a property that could not be converted to the type of its
/// field, as [bindSettings] found it.
final class InvalidProperty {
  /// A failure of [property] (its full name) whose value was [value]; [type]
  /// is the type the binder named, such as `int`, `bool`, `Duration` or the
  /// enum, null when the failure was another one.
  const InvalidProperty(this.property, this.value, this.type, this.message);

  /// The full name of the property (`spring.datasource.pool.max-size`).
  final String property;

  /// The value as it is written; empty when it cannot be read again.
  final String value;

  /// The name of the type, such as `int`, `bool` or `Duration`.
  final String? type;

  /// What the binder said.
  final String message;

  /// What the value should have been, in words, for the usual types; the
  /// binder's own text for the others.
  String get expected => switch (type) {
    'int' => 'a number',
    'bool' => 'true or false',
    'Duration' => 'a duration such as 500ms, 10s or 2m',
    _ => message,
  };
}

// Collects the first value that cannot be converted and leaves the field at
// its default, so the caller reports it in its own words.
final class _FirstInvalid extends BindHandler {
  _FirstInvalid(this._environment);

  final Environment _environment;
  final failures = <InvalidProperty>[];

  @override
  bool onFailure(ConfigurationPropertyName name, String error) {
    final property = '$name';
    final type = RegExp(r'failed to convert to (\w+)').firstMatch(error)?[1];
    failures.add(
      InvalidProperty(
        property,
        _environment.getProperty(property) ?? '',
        type,
        error,
      ),
    );
    return false;
  }
}

/// Reads the properties below [prefix] of [environment] into a [T] (a
/// class of `lib/src/properties/`), or null when none of them is set.
///
/// The prefix is the one of a data source (`spring.datasources.shop`), so
/// one class serves the primary data source and every named one. A value
/// that cannot be converted is given to [onInvalid], which throws the
/// error of the reader; when it returns, the field keeps its default (the
/// reader that does not care, such as the one that only asks whether a
/// URL is set, passes none).
T? bindSettingsOrNull<T extends Object>(
  Environment environment,
  String prefix, {
  void Function(InvalidProperty failure)? onInvalid,
}) {
  if (environment is! ConfigurableEnvironment) {
    throw StateError(
      'The properties of $prefix need a ConfigurableEnvironment, not '
      '${environment.runtimeType}',
    );
  }
  final binder = Binder.get(
    environment,
    introspector: BeanIntrospector(
      introspections: dataConfigBeans.introspections,
    ),
  );
  final handler = _FirstInvalid(environment);
  final result = binder.bind<T>(prefix, ClassType<T>(), handler: handler);
  if (onInvalid != null) {
    handler.failures.forEach(onInvalid);
  }
  return result.isBound ? result.get() : null;
}

/// [bindSettingsOrNull], with [fallback] (the class's defaults) when
/// no property is set.
T bindSettings<T extends Object>(
  Environment environment,
  String prefix, {
  required T fallback,
  void Function(InvalidProperty failure)? onInvalid,
}) =>
    bindSettingsOrNull<T>(environment, prefix, onInvalid: onInvalid) ??
    fallback;
