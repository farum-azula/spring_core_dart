import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_boot_dart/src/configuration_properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Reads a group of properties from the environment as one typed value: a
/// list, a map, a `Duration` or a whole settings object.
///
/// `environment.getProperty` returns one string. Some settings are not one
/// string: a list of hosts written as `app.hosts[0]`, `app.hosts[1]`, a map
/// of headers, or a nested object. The binder collects the properties
/// under a name and converts them to the requested type, with the same
/// rules as `@ConfigurationProperties` (which uses it). Applications use
/// `@ConfigurationProperties` classes; use the binder directly in code
/// that runs before beans exist, such as an `EnvironmentPostProcessor` or
/// a library's setup code, or to read one structured value without a
/// class.
///
/// The rules:
///
/// - **Relaxed names**: `app.max-size`, `app.maxSize`, `app.max_size` and
///   the environment variable `APP_MAXSIZE` are one property; the first
///   property source (in the environment's order) that has it wins.
/// - **Lists and sets**: a comma list (`app.hosts=a,b`) or indexed keys
///   (`app.hosts[0]=a`, YAML lists, `APP_HOSTS_0_=a`), also of nested
///   objects (`app.servers[0].port=80`). The first property source that has
///   the list supplies all of it: a list is replaced, not merged element by
///   element.
/// - **Maps**: entries from every source (`app.headers.x-a=1`,
///   `app.headers[x.y]=2` for keys with dots), the higher source winning
///   per key, also of nested objects (`app.backends.eu.url=...`). Keys keep
///   the form they are written in.
/// - **Nested objects**: `@Introspected` classes, set through their
///   setters (JavaBean binding) or created through their constructor when
///   it has parameters (constructor binding, [DefaultValue]).
///
/// ```dart
/// // In an EnvironmentPostProcessor, before any bean exists.
/// final hosts = Binder.get(environment)
///     .bind('app.hosts', const ListType<String>(ClassType<String>()))
///     .orElse(const []);
/// ```
///
/// A value that cannot be converted throws a
/// [ConfigurationPropertiesBindException] naming the property.
///
/// Spring (Java):
/// ```java
/// List<String> hosts = Binder.get(environment)
///     .bind("app.hosts", Bindable.listOf(String.class))
///     .orElse(List.of());
/// ```
final class Binder {
  /// A binder that reads [environment].
  ///
  /// [introspector] describes nested objects (default
  /// `BeanIntrospector.shared`, which knows every `@Introspected` class of
  /// the generated code); [conversionService] converts values (default:
  /// the environment's). Creating a binder is cheap; it holds no state
  /// between [bind] calls.
  Binder(
    this.environment, {
    BeanIntrospector? introspector,
    ConversionService? conversionService,
  }) : introspector = introspector ?? BeanIntrospector.shared,
       conversionService = conversionService ?? environment.conversionService;

  /// A binder that reads [environment], with the environment's conversion
  /// service; the same as the constructor, under Spring Boot's name.
  static Binder get(
    ConfigurableEnvironment environment, {
    BeanIntrospector? introspector,
  }) => Binder(environment, introspector: introspector);

  /// The environment whose property sources are read, in their order of
  /// precedence.
  final ConfigurableEnvironment environment;

  /// Describes the classes of nested objects: their setters or
  /// constructor parameters.
  final BeanIntrospector introspector;

  /// Converts property values (strings, mostly) to the target types.
  final ConversionService conversionService;

  /// Reads the properties at [name] as a value of type [target].
  ///
  /// [name] is in canonical form (lower case, dashes: `app.read-timeout`);
  /// every relaxed spelling in the sources is found. The result says
  /// whether anything was found ([BindResult.isBound]), so a missing
  /// property can get a default. Throws a
  /// [ConfigurationPropertiesBindException] that lists every property
  /// that could not be converted.
  ///
  /// [handler] is told about each property bound on the way and may change
  /// the result or ignore failures.
  ///
  /// ```dart
  /// final timeout = binder
  ///     .bind('app.timeout', const ClassType<Duration>())
  ///     .orElse(const Duration(seconds: 30));
  /// ```
  BindResult<T> bind<T>(
    String name,
    TypeInfo<T> target, {
    BindHandler handler = BindHandler.defaultHandler,
  }) {
    final context = BindContext(this, handler: handler);
    final value = context.bind(
      ConfigurationPropertyName.of(name),
      target,
      existing: null,
    );
    context.throwIfFailed(name);
    return identical(value, unbound)
        ? BindResult<T>._(null, isBound: false)
        : BindResult<T>._(value, isBound: true);
  }
}

/// The outcome of [Binder.bind]: the value, or the fact that no property
/// was set.
///
/// A property that is not set is different from one set to an empty value,
/// and the caller usually wants a default for the first case. The methods
/// here say what to do then: use a default ([orElse], [orElseGet]), fail
/// ([orElseThrow], [get]) or do nothing ([ifBound]).
///
/// ```dart
/// final port = Binder.get(environment)
///     .bind('app.port', const ClassType<int>())
///     .orElse(8080);
/// ```
///
/// Spring (Java): `BindResult`, with the same methods.
final class BindResult<T> {
  const BindResult._(this._value, {required this.isBound});

  final Object? _value;

  /// Whether at least one property was found and bound. A value can be
  /// bound and still be `null`.
  final bool isBound;

  /// The bound value. Throws a `StateError` when nothing was bound; use it
  /// when the property is known to be set.
  T get() => isBound ? _value as T : throw StateError('No value bound');

  /// The bound value, or the default [other] when nothing was bound.
  T orElse(T other) => isBound ? _value as T : other;

  /// The bound value, or the result of [other] when nothing was bound.
  /// [other] is only called then, so it suits a default that is costly to
  /// build.
  T orElseGet(T Function() other) => isBound ? _value as T : other();

  /// The bound value; when nothing was bound, throws what [error] returns.
  /// Use it for a required setting, with a message that says what to set.
  ///
  /// ```dart
  /// binder
  ///     .bind('app.port', const ClassType<int>())
  ///     .orElseThrow(() => StateError('app.port is required'));
  /// ```
  T orElseThrow(Object Function() error) =>
      // Throws whatever the supplier returns, like Optional.orElseThrow.
      // ignore: only_throw_errors
      isBound ? _value as T : throw error();

  /// Calls [action] with the bound value; does nothing when nothing was
  /// bound.
  void ifBound(void Function(T value) action) {
    if (isBound) {
      action(_value as T);
    }
  }

  /// A result holding the bound value transformed by [mapper]. When
  /// nothing was bound, [mapper] is not called and the result stays
  /// unbound.
  ///
  /// ```dart
  /// final port = binder
  ///     .bind('app.port', const ClassType<int>())
  ///     .map((port) => port + 1)
  ///     .orElse(8080);
  /// ```
  BindResult<R> map<R>(R Function(T value) mapper) => isBound
      ? BindResult<R>._(mapper(_value as T), isBound: true)
      : BindResult<R>._(null, isBound: false);
}

/// Hooks into a [Binder.bind] call, called for every property bound on the
/// way: the top-level name, then each nested property and element.
///
/// Use one to watch or adjust binding: log which properties were used,
/// skip some names, replace values, or decide that a value which cannot be
/// converted is not an error (`@ConfigurationProperties(ignoreInvalidFields:
/// true)` works this way). Extend it and override what you need; the
/// defaults change nothing. Most code never needs one.
///
/// ```dart
/// final class LoggingBindHandler extends BindHandler {
///   const LoggingBindHandler();
///
///   @override
///   Object? onSuccess(
///     ConfigurationPropertyName name,
///     TypeInfo<Object?> target,
///     Object? result,
///   ) {
///     log.info('bound $name');
///     return result;
///   }
/// }
///
/// binder.bind('app', appType, handler: const LoggingBindHandler());
/// ```
///
/// Spring (Java): `binder.bind("app", Bindable.of(App.class), handler)`.
/// One difference: [onFailure] gets the error message and decides whether
/// it counts, where Spring Boot's returns a replacement value or
/// rethrows.
class BindHandler {
  /// A handler that changes nothing; subclasses override some methods.
  const BindHandler();

  /// The handler [Binder.bind] uses when none is given: it binds as is and
  /// reports every failure.
  static const BindHandler defaultHandler = BindHandler();

  /// Called before [name] is bound to [target]. Return `false` to skip the
  /// name: it stays unbound, as if no property were set.
  bool onStart(ConfigurationPropertyName name, TypeInfo<Object?> target) =>
      true;

  /// Called after [name] was bound to [result]. Returns the value to use
  /// instead, which is [result] by default.
  Object? onSuccess(
    ConfigurationPropertyName name,
    TypeInfo<Object?> target,
    Object? result,
  ) => result;

  /// Called when [name] cannot be bound; [error] is the message that would
  /// be reported (`app.port: failed to convert to int (was "x")`).
  ///
  /// Return `true` (the default) to report it, which fails the bind, or
  /// `false` to ignore it: the name is left unbound and keeps its
  /// default.
  bool onFailure(ConfigurationPropertyName name, String error) => true;

  /// Called last for every name, bound or not; [result] is the final value,
  /// or `null` when nothing was bound.
  void onFinish(
    ConfigurationPropertyName name,
    TypeInfo<Object?> target,
    Object? result,
  ) {}
}

Type _typeOf<T>() => T;

/// The value the binding internals return when no property was found.
///
/// `null` cannot mean that, because `null` is a valid bound value for a
/// nullable target. Internal to `spring_boot_dart`; [BindResult] hides it
/// from callers of [Binder.bind].
const Object unbound = _Unbound();

final class _Unbound {
  const _Unbound();
}

/// The state of one binding run: the property sources read, the names
/// bound and the errors collected.
///
/// Errors are collected rather than thrown at once, so a failed start
/// lists every bad property together. Internal to `spring_boot_dart`:
/// [Binder.bind] and the `@ConfigurationProperties` binding create one per
/// run.
final class BindContext {
  /// A run over the property sources of [binder]'s environment, in order
  /// of precedence, reporting to [handler].
  BindContext(this.binder, {this.handler = BindHandler.defaultHandler})
    : sources = [
        for (final source in binder.environment.propertySources)
          if (source is! ConfigurationPropertySourcesPropertySource)
            BindSource(source),
      ];

  /// The binder whose environment, introspector and conversion service the
  /// run uses.
  final Binder binder;

  /// Told about every name bound; it may change values and ignore
  /// failures.
  final BindHandler handler;

  // Annotations of the field or constructor parameter being bound
  // (`@DurationUnit`, `@DataSizeUnit`), applied to its value and elements.
  List<Object> _annotations = const [];

  /// The environment's property sources, highest precedence first.
  final List<BindSource> sources;

  /// One line per property that could not be bound and that the handler
  /// did not ignore.
  final errors = <String>[];

  // Every failure, also those the handler ignored.
  int _failures = 0;

  /// The names bound so far; used to find properties that bound to
  /// nothing.
  final boundNames = <ConfigurationPropertyName>{};

  // Data object types being bound, against endless recursion through
  // sources that cannot list their names.
  final _binding = <Type>[];

  /// Throws a [ConfigurationPropertiesBindException] for [prefix] (and
  /// [beanName], when a bean was bound) listing all [errors]; does nothing
  /// when there are none.
  void throwIfFailed(String prefix, [String? beanName]) {
    if (errors.isNotEmpty) {
      throw ConfigurationPropertiesBindException(
        prefix,
        beanName,
        List.of(errors),
      );
    }
  }

  void _error(ConfigurationPropertyName name, String message, [Object? value]) {
    final error = '$name: $message${value == null ? '' : ' (was "$value")'}';
    _failures++;
    if (handler.onFailure(name, error)) {
      errors.add(error);
    }
  }

  /// Binds [name] to [type] and returns the value, or [unbound] when no
  /// property applies.
  ///
  /// [existing] is the current value of the field being bound: a nested
  /// object is bound into it and a map is merged with it. [only] limits
  /// the sources read (all of them by default).
  Object? bind(
    ConfigurationPropertyName name,
    TypeInfo<Object?> type, {
    required Object? existing,
    List<BindSource>? only,
  }) {
    if (!handler.onStart(name, type)) {
      return unbound;
    }
    var result = type.accept(
      _BindVisitor(this, name, existing, only ?? sources),
    );
    if (!identical(result, unbound)) {
      boundNames.add(name);
      result = handler.onSuccess(name, type, result);
    }
    handler.onFinish(name, type, identical(result, unbound) ? null : result);
    return result;
  }

  // Binds with [annotations] as the annotations of the bound member.
  Object? _withAnnotations(List<Object> annotations, Object? Function() bind) {
    final previous = _annotations;
    _annotations = annotations;
    try {
      return bind();
    } finally {
      _annotations = previous;
    }
  }

  // `@Name('x')` of a member, else its Dart name, in dashed form.
  static String _memberName(String name, List<Object> annotations) =>
      dashedForm(annotations.whereType<Name>().firstOrNull?.value ?? name);

  /// Sets the properties under [name] on [bean] through its setters, and
  /// returns whether any was set.
  ///
  /// This is how a mutable `@ConfigurationProperties` class is bound. A
  /// field without a setter whose value is a mutable list, set or map is
  /// filled in place; an unmodifiable one is left as it is.
  bool bindProperties(
    Object bean,
    BeanIntrospection<Object> introspection,
    ConfigurationPropertyName name, {
    List<BindSource>? only,
  }) {
    final scope = only ?? sources;
    var bound = false;
    for (final property in introspection.properties) {
      final propertyName = name.append(
        _memberName(property.name, property.annotations),
      );
      Object? current;
      try {
        current = property.getValue(bean);
      } on Object catch (_) {
        current = null;
      }
      final typeInfo = property.typeInfo;
      final value = _withAnnotations(
        property.annotations,
        () => typeInfo != null
            ? bind(propertyName, typeInfo, existing: current, only: scope)
            : _bindRaw(propertyName, property.type, current, scope),
      );
      if (identical(value, unbound)) {
        continue;
      }
      bound = true;
      boundNames.add(propertyName);
      if (identical(value, current)) {
        continue; // a nested object bound in place
      }
      if (property.isWritable) {
        try {
          property.setValue(bean, value);
        } on Object catch (error) {
          _error(propertyName, 'could not be set: $error', value);
        }
      } else {
        _fillInPlace(current, value);
      }
    }
    return bound;
  }

  // Read-only collections and maps are filled in place when mutable, like
  // Spring Boot (a getter is enough for them).
  static void _fillInPlace(Object? current, Object? value) {
    try {
      if (current is List<Object?> && value is Iterable<Object?>) {
        current
          ..clear()
          ..addAll(value);
      } else if (current is Set<Object?> && value is Iterable<Object?>) {
        current
          ..clear()
          ..addAll(value);
      } else if (current is Map<Object?, Object?> &&
          value is Map<Object?, Object?>) {
        current.addAll(value);
      }
    } on UnsupportedError {
      // Unmodifiable: left as it is, like a property without a setter.
    }
  }

  // Hand-written introspections without a TypeInfo: nested objects by
  // their introspection, everything else converted as a whole.
  Object? _bindRaw(
    ConfigurationPropertyName name,
    Type type,
    Object? existing,
    List<BindSource> scope,
  ) {
    final introspection = binder.introspector.forType(type);
    if (introspection != null) {
      return bindDataObject(introspection, name, existing, scope);
    }
    final raw = findProperty(name, scope);
    if (raw == null) {
      return unbound;
    }
    return _convert(name, raw, type);
  }

  /// Binds a nested object of [introspection] at [name] and returns it,
  /// or [unbound] when no property under [name] is set.
  ///
  /// A class whose constructor has parameters is created through it. Any
  /// other class is bound through its setters, into [existing] when there
  /// is one, else into a new instance.
  Object? bindDataObject(
    BeanIntrospection<Object> introspection,
    ConfigurationPropertyName name,
    Object? existing,
    List<BindSource> scope,
  ) {
    final type = introspection.beanType;
    if (!_mayHaveDescendants(name, scope, recursive: _binding.contains(type))) {
      return unbound;
    }
    _binding.add(type);
    try {
      if (isValueObject(introspection)) {
        return bindConstructor(introspection, name, scope, requireAny: true);
      }
      final target =
          existing ??
          (introspection.isInstantiable ? introspection.instantiate() : null);
      if (target == null) {
        return unbound;
      }
      final bound = bindProperties(target, introspection, name, only: scope);
      return bound ? target : unbound;
    } finally {
      _binding.removeLast();
    }
  }

  /// Whether [introspection]'s class is bound through its constructor:
  /// true when the constructor has parameters (Spring Boot's value
  /// objects).
  static bool isValueObject(BeanIntrospection<Object> introspection) =>
      introspection.constructor?.parameters.isNotEmpty ?? false;

  /// Creates an instance of [introspection]'s class through its
  /// constructor, each parameter bound from `name.<parameter-name>`
  /// (constructor binding).
  ///
  /// A parameter without a property gets its [DefaultValue], else its Dart
  /// default value, else `null` when it is nullable. For a required
  /// parameter without any of them, a collection is empty and a nested
  /// object is created with its own defaults; anything else is an error
  /// that names the property.
  ///
  /// With [requireAny], the result is [unbound] when no parameter was
  /// bound, and missing ones are not reported. This is how a nullable
  /// nested object none of whose keys is set stays `null`, as with Spring
  /// Boot's `ValueObjectBinder`.
  Object? bindConstructor(
    BeanIntrospection<Object> introspection,
    ConfigurationPropertyName name,
    List<BindSource> scope, {
    required bool requireAny,
  }) {
    final constructor = introspection.constructor!;
    final positional = <Object?>[];
    final omittedPositional = <int>{};
    final named = <Symbol, Object?>{};
    var bound = false;
    var failed = false;
    // Missing-parameter errors (and those of nested objects created with
    // their defaults), reported only when something was bound.
    final missing = <String>[];
    for (final parameter in constructor.parameters) {
      final parameterName = name.append(
        _memberName(parameter.name, parameter.annotations),
      );
      var value = _withAnnotations(
        parameter.annotations,
        () => bind(parameterName, parameter.type, existing: null, only: scope),
      );
      var omit = false;
      if (identical(value, unbound)) {
        final defaultValue = parameter.annotations
            .whereType<DefaultValue>()
            .firstOrNull;
        if (defaultValue != null) {
          value = _withAnnotations(
            parameter.annotations,
            () => _defaultValue(
              parameterName,
              parameter.type,
              defaultValue,
              scope,
            ),
          );
        } else if (!parameter.isRequired) {
          omit = true; // the Dart default value
        } else if (parameter.type.nullable) {
          value = null;
        } else {
          final errorsBefore = errors.length;
          value = parameter.type.accept(
            _EmptyVisitor(this, parameterName, scope),
          );
          missing.addAll(errors.sublist(errorsBefore));
          errors.removeRange(errorsBefore, errors.length);
        }
        if (identical(value, unbound) && !omit) {
          if (!failed) {
            final error =
                '$parameterName: no value bound for the required '
                "constructor parameter '${parameter.name}' of "
                '${introspection.beanType} (set the property, give the '
                'parameter a @DefaultValue or a default, or make it '
                'nullable)';
            if (handler.onFailure(parameterName, error)) {
              missing.add(error);
            }
          }
          failed = true;
          value = null;
        }
      } else {
        bound = true;
      }
      if (parameter.isNamed) {
        if (!omit) {
          named[parameter.symbol!] = value;
        }
      } else {
        if (omit) {
          omittedPositional.add(positional.length);
        }
        positional.add(omit ? null : value);
      }
    }
    if (requireAny && !bound) {
      return unbound;
    }
    errors.addAll(missing);
    if (failed) {
      return unbound;
    }
    // Omitted optional positional parameters can only be left out at the
    // end; before a given one they are passed as null.
    while (positional.isNotEmpty &&
        omittedPositional.contains(positional.length - 1)) {
      positional.removeLast();
    }
    try {
      return constructor.newInstance(positional, named);
    } on Object catch (error) {
      _error(name, 'could not create ${introspection.beanType}: $error');
      return unbound;
    }
  }

  Object? _defaultValue(
    ConfigurationPropertyName name,
    TypeInfo<Object?> type,
    DefaultValue annotation,
    List<BindSource> scope,
  ) {
    final values = switch (annotation.value) {
      final String value => [value],
      final List<Object?> values => [for (final v in values) '$v'],
      _ => const <String>[],
    };
    return type.accept(_DefaultVisitor(this, name, values, scope));
  }

  /// The value of [name] in the first source of [scope] that has it, in
  /// any relaxed spelling, or `null`.
  ///
  /// `${...}` placeholders in a string value are resolved; unresolvable
  /// ones are kept as they are, as in Spring Boot.
  Object? findProperty(ConfigurationPropertyName name, List<BindSource> scope) {
    for (final source in scope) {
      final value = source.valueOf(name);
      if (value != null) {
        return _resolve(value);
      }
    }
    return null;
  }

  Object? _resolve(Object value) =>
      value is String ? binder.environment.resolvePlaceholders(value) : value;

  bool _mayHaveDescendants(
    ConfigurationPropertyName name,
    List<BindSource> scope, {
    required bool recursive,
  }) => scope.any(
    (source) =>
        source.isEnumerable ? source.containsDescendantOf(name) : !recursive,
  );

  /// Converts [raw] to [type], applying the `@DurationUnit` or
  /// `@DataSizeUnit` of the field being bound to plain numbers.
  ///
  /// Returns [unbound] when the value cannot be converted (an error is
  /// recorded) or when the conversion gives nothing (blank input for a
  /// non-string type).
  Object? _convert(ConfigurationPropertyName name, Object raw, Type type) {
    try {
      // `@DurationUnit` / `@DataSizeUnit` give plain numbers their unit.
      if ((raw is String && raw.trim().isNotEmpty) || raw is int) {
        if (type == Duration || type == _typeOf<Duration?>()) {
          final unit = _annotations.whereType<DurationUnit>().firstOrNull;
          if (unit != null) {
            return DurationStyle.parse('$raw', unit: unit.value);
          }
        } else if (type == DataSize || type == _typeOf<DataSize?>()) {
          final unit = _annotations.whereType<DataSizeUnit>().firstOrNull;
          if (unit != null) {
            return DataSize.parse('$raw', unit: unit.value);
          }
        }
      }
      final converted = binder.conversionService.convertTo(raw, type);
      return converted ?? unbound;
    } on Object {
      _error(name, 'failed to convert to $type', raw);
      return unbound;
    }
  }

  /// Converts [raw] to [T] and checks the result's type, so the elements
  /// of a `List<T>` come out typed. Returns [unbound], with an error
  /// recorded, when that fails.
  Object? convertTyped<T>(ConfigurationPropertyName name, Object raw) {
    if (raw is T) {
      return raw;
    }
    final converted = _convert(name, raw, T);
    if (identical(converted, unbound)) {
      return unbound;
    }
    if (converted is! T) {
      _error(name, 'failed to convert to $T', raw);
      return unbound;
    }
    return converted;
  }

  /// The value of [values] that [raw] names, ignoring case and
  /// separators: `MY_VALUE`, `my-value` and `myValue` all find `myValue`,
  /// as with Spring Boot's lenient enum conversion.
  ///
  /// Blank input gives [unbound]. An unknown name is an error that lists
  /// the allowed values.
  Object? convertEnum<E extends Enum>(
    ConfigurationPropertyName name,
    Object raw,
    List<E> values,
  ) {
    if (raw is E) {
      return raw;
    }
    final text = '$raw'.trim();
    if (text.isEmpty) {
      return unbound;
    }
    final wanted = _lenient(text);
    for (final value in values) {
      if (_lenient(value.name) == wanted) {
        return value;
      }
    }
    _error(
      name,
      'failed to convert to $E (one of '
      '${values.map((v) => v.name).join(', ')})',
      raw,
    );
    return unbound;
  }

  static String _lenient(String text) =>
      text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// Splits a property value into list elements: a string at its commas
  /// (each part trimmed; a blank string gives none), an iterable as it is,
  /// anything else as one element.
  static List<Object?> elementsOf(Object raw) => switch (raw) {
    final String text when text.trim().isEmpty => const [],
    final String text => [for (final part in text.split(',')) part.trim()],
    final Iterable<Object?> items => items.toList(),
    _ => [raw],
  };

  /// Binds the list elements at [name], or returns [unbound] when no
  /// source has any.
  ///
  /// The elements come from one source only, the first that has either a
  /// comma list (`app.hosts=a,b`) or indexed keys (`app.hosts[0]=a`): a
  /// higher source replaces the whole list. Indexes must start at 0
  /// without gaps; other indexes are reported as unbound. With a comma
  /// list, one invalid element fails the whole list, so
  /// `ignoreInvalidFields` keeps the field's default rather than the valid
  /// part.
  Object? bindIndexed(
    ConfigurationPropertyName name,
    TypeInfo<Object?> element,
    List<BindSource> scope,
  ) {
    for (final source in scope) {
      final whole = source.valueOf(name);
      if (whole != null) {
        final items = <Object?>[];
        final raw = _resolve(whole)!;
        final failuresBefore = _failures;
        for (final (index, item) in elementsOf(raw).indexed) {
          final value = item == null
              ? unbound
              : element.accept(
                  _ScalarVisitor(this, name.append('[$index]'), item),
                );
          if (!identical(value, unbound)) {
            items.add(value);
          }
        }
        // One conversion of the whole value in Boot: an invalid element
        // fails the list, so `ignoreInvalidFields` keeps the default
        // instead of the valid part.
        return _failures > failuresBefore ? unbound : items;
      }
      final items = <Object?>[];
      var index = 0;
      for (; ; index++) {
        final errorsBefore = errors.length;
        final value = bind(
          name.append('[$index]'),
          element,
          existing: null,
          only: [source],
        );
        if (identical(value, unbound)) {
          if (errors.length > errorsBefore) {
            continue; // present but invalid: reported already
          }
          break;
        }
        items.add(value);
      }
      _checkNoUnboundElements(source, name, index);
      if (items.isNotEmpty) {
        return items;
      }
    }
    return unbound;
  }

  // Indexes must start at 0 and have no gaps (Spring Boot's
  // UnboundConfigurationPropertiesException).
  void _checkNoUnboundElements(
    BindSource source,
    ConfigurationPropertyName name,
    int bound,
  ) {
    final left = <String>{};
    final position = name.numberOfElements;
    for (final candidate in source.names) {
      if (!name.isAncestorOf(candidate)) {
        continue;
      }
      final index = int.tryParse(candidate.getElement(position));
      if (index != null && index >= bound) {
        left.add('${name.append('[$index]')}');
      }
    }
    if (left.isNotEmpty) {
      final error =
          'The elements [${left.join(', ')}] were left unbound '
          '(list indexes must start at 0 and have no gaps).';
      if (handler.onFailure(name, error)) {
        errors.add(error);
      }
    }
  }

  // Sources whose names are never reported as unbound (Boot's
  // UnboundElementsSourceFilter).
  static const Set<String> _benignSources = {
    SystemEnvironmentPropertySource.defaultName,
    'systemProperties',
  };

  /// Records an error listing the properties under [root] that bound to
  /// nothing, usually typos such as `db.urll`.
  ///
  /// Used for `@ConfigurationProperties(ignoreUnknownFields: false)`. OS
  /// environment variables are not checked (an unrelated variable could
  /// look like a property), and neither are sources that cannot list
  /// their names. List elements replaced by a whole list from a
  /// higher-precedence source do not count as unbound.
  void checkNoUnboundProperties(ConfigurationPropertyName root) {
    final left = <String>{};
    for (final source in sources) {
      if (!source.isEnumerable || _benignSources.contains(source.source.name)) {
        continue;
      }
      for (final name in source.names) {
        if (root.isAncestorOf(name) &&
            !boundNames.contains(name) &&
            !_isOverriddenElement(root, name)) {
          left.add('$name');
        }
      }
    }
    if (left.isNotEmpty) {
      final error =
          'The elements [${(left.toList()..sort()).join(', ')}] '
          'were left unbound.';
      if (handler.onFailure(root, error)) {
        errors.add(error);
      }
    }
  }

  // `a.hosts[1]` (or `a.servers[0].host`) when `a.hosts` was bound as a
  // whole from another source.
  bool _isOverriddenElement(
    ConfigurationPropertyName root,
    ConfigurationPropertyName name,
  ) {
    for (var i = root.numberOfElements + 1; i < name.numberOfElements; i++) {
      if (name.isIndexed(i) && boundNames.contains(name.chop(i))) {
        return true;
      }
    }
    return false;
  }

  /// Binds the map entries under [name], or returns [unbound] when there
  /// are none.
  ///
  /// Entries come from every source: the first source that has a key
  /// wins for that key. Keys keep the form they are written in. For a map
  /// of plain values the whole rest of the name is the key
  /// (`app.headers.a.b=1` gives `a.b`); for a map of objects or maps the
  /// key is one element.
  Object? bindMap(
    ConfigurationPropertyName name,
    TypeInfo<Object?> keyType,
    TypeInfo<Object?> valueType,
    List<BindSource> scope,
  ) {
    final kind = valueType.accept(_KindVisitor(binder.introspector));
    final entries = <Object?, Object?>{};
    final seen = <String>{};
    for (final source in scope) {
      for (final candidate in source.names) {
        if (!name.isAncestorOf(candidate)) {
          continue;
        }
        final entryName = _entryName(name, candidate, kind);
        final key = [
          for (
            var i = name.numberOfElements;
            i < entryName.numberOfElements;
            i++
          )
            entryName.getElement(i),
        ].join('.');
        if (!seen.add(key)) {
          continue;
        }
        final convertedKey = keyType.accept(
          _ScalarVisitor(this, entryName, key),
        );
        if (identical(convertedKey, unbound)) {
          continue;
        }
        final value = bind(entryName, valueType, existing: null, only: scope);
        if (!identical(value, unbound)) {
          entries[convertedKey] = value;
        }
      }
    }
    return entries.isEmpty ? unbound : entries;
  }

  // Scalars take the whole rest of the name as the key (`a.b.x.y` → `x.y`);
  // collections end before their index; objects and maps take one element.
  static ConfigurationPropertyName _entryName(
    ConfigurationPropertyName root,
    ConfigurationPropertyName name,
    _Kind kind,
  ) {
    switch (kind) {
      case _Kind.scalar:
        return name;
      case _Kind.collection:
        for (
          var i = root.numberOfElements + 1;
          i < name.numberOfElements;
          i++
        ) {
          if (_digits.hasMatch(name.getElement(i))) {
            return name.chop(i);
          }
        }
        return name;
      case _Kind.nested:
        return name.chop(root.numberOfElements + 1);
    }
  }

  static final _digits = RegExp(r'^[0-9]+$');
}

/// One property source of the environment, read by property name in any
/// relaxed spelling.
///
/// Internal to `spring_boot_dart`: [BindContext] wraps every source of
/// the environment in one.
final class BindSource {
  /// A wrapper that reads [source].
  BindSource(this.source);

  /// The wrapped property source.
  final AbstractPropertySource<Object> source;

  /// Whether the source can list its property names. Lists, maps and
  /// unbound-property checks need that; other sources only answer for
  /// names asked directly.
  bool get isEnumerable => source is EnumerablePropertySource<Object>;

  /// The value of [name] in any relaxed spelling (`app.max-size`,
  /// `app.maxSize`, `APP_MAXSIZE`, ...), or `null` when the source does
  /// not have it.
  Object? valueOf(ConfigurationPropertyName name) =>
      ConfigurationPropertySources.getProperty(source, name);

  /// Whether the source has a property below [name], which tells whether
  /// a nested object at [name] is worth binding.
  ///
  /// For OS environment variables, the dashes of [name] also count as
  /// dots, so `APP_MAIN_SERVER_HOST` is below `app.main-server`, as with
  /// Spring Boot's legacy check in `SystemEnvironmentPropertyMapper`.
  bool containsDescendantOf(ConfigurationPropertyName name) {
    if (names.any(name.isAncestorOf)) {
      return true;
    }
    if (source is! SystemEnvironmentPropertySource) {
      return false;
    }
    final legacy = _legacyName(name);
    return legacy != null && names.any(legacy.isAncestorOf);
  }

  // `app.main-server[0]` → `app.main.server[0]`; `null` without dashes.
  static ConfigurationPropertyName? _legacyName(
    ConfigurationPropertyName name,
  ) {
    var dashed = false;
    final parts = <String>[];
    for (var i = 0; i < name.numberOfElements; i++) {
      if (name.isIndexed(i)) {
        parts.add('[${name.getElement(i)}]');
        continue;
      }
      final element = name.getElement(
        i,
        form: ConfigurationPropertyNameForm.dashed,
      );
      dashed = dashed || element.contains('-');
      parts.add(
        '${parts.isEmpty ? '' : '.'}'
        '${element.split('-').where((part) => part.isNotEmpty).join('.')}',
      );
    }
    return dashed ? ConfigurationPropertyName.ofIfValid(parts.join()) : null;
  }

  /// The names of every property of the source; empty when the source
  /// cannot list them.
  Iterable<ConfigurationPropertyName> get names => switch (source) {
    final EnumerablePropertySource<Object> enumerable =>
      ConfigurationPropertySources.propertyNames(enumerable).keys,
    _ => const [],
  };
}

enum _Kind { scalar, collection, nested }

final class _KindVisitor implements TypeInfoVisitor<_Kind> {
  const _KindVisitor(this.introspector);

  final BeanIntrospector introspector;

  @override
  _Kind visitClass<T>(ClassType<T> type) =>
      introspector.forType(T) == null ? _Kind.scalar : _Kind.nested;

  @override
  _Kind visitDynamic(DynamicType type) => _Kind.nested;

  @override
  _Kind visitEnum<E extends Enum>(EnumType<E> type) => _Kind.scalar;

  @override
  _Kind visitGeneric<T>(GenericType<T> type) => _Kind.scalar;

  @override
  _Kind visitList<E>(ListType<E> type) => _Kind.collection;

  @override
  _Kind visitMap<K, V>(MapType<K, V> type) => _Kind.nested;

  @override
  _Kind visitSet<E>(SetType<E> type) => _Kind.collection;
}

// Binds a name to a type, dispatching on the kind of type.
final class _BindVisitor implements TypeInfoVisitor<Object?> {
  _BindVisitor(this.context, this.name, this.existing, this.scope);

  final BindContext context;
  final ConfigurationPropertyName name;
  final Object? existing;
  final List<BindSource> scope;

  @override
  Object? visitClass<T>(ClassType<T> type) {
    final introspection = context.binder.introspector.forType(T);
    final raw = context.findProperty(name, scope);
    if (introspection == null) {
      return raw == null ? unbound : context.convertTyped<T>(name, raw);
    }
    if (raw != null && context.binder.conversionService.canConvert(raw, T)) {
      return context.convertTyped<T>(name, raw);
    }
    // A nested object: bound into the current value; a value object is
    // created anew.
    final current = existing is T ? existing : null;
    if (current != null && BindContext.isValueObject(introspection)) {
      return context.bindDataObject(introspection, name, null, scope);
    }
    return context.bindDataObject(introspection, name, current, scope);
  }

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) {
    final raw = context.findProperty(name, scope);
    return raw == null ? unbound : context.convertEnum(name, raw, type.values);
  }

  @override
  Object? visitList<E>(ListType<E> type) {
    final items = context.bindIndexed(name, type.element, scope);
    return identical(items, unbound)
        ? unbound
        : type.create(items! as List<Object?>);
  }

  @override
  Object? visitSet<E>(SetType<E> type) {
    final items = context.bindIndexed(name, type.element, scope);
    return identical(items, unbound)
        ? unbound
        : type.create(items! as List<Object?>);
  }

  @override
  Object? visitMap<K, V>(MapType<K, V> type) {
    final entries = context.bindMap(name, type.key, type.value, scope);
    if (identical(entries, unbound)) {
      return unbound;
    }
    final bound = entries! as Map<Object?, Object?>;
    // Merged into the current map, like Spring Boot's MapBinder.
    final current = existing;
    return type.create([
      if (current is Map<Object?, Object?>)
        for (final entry in current.entries)
          if (!bound.containsKey(entry.key)) entry,
      ...bound.entries,
    ]);
  }

  @override
  Object? visitGeneric<T>(GenericType<T> type) {
    final raw = context.findProperty(name, scope);
    return raw == null ? unbound : context.convertTyped<T>(name, raw);
  }

  @override
  Object? visitDynamic(DynamicType type) {
    final raw = context.findProperty(name, scope);
    if (raw != null) {
      return raw;
    }
    // `Map<String, Object>` values: nested maps.
    return context.bindMap(
      name,
      const ClassType<String>(),
      const DynamicType(),
      scope,
    );
  }
}

// Converts one element of a comma list or a map key.
final class _ScalarVisitor implements TypeInfoVisitor<Object?> {
  _ScalarVisitor(this.context, this.name, this.raw);

  final BindContext context;
  final ConfigurationPropertyName name;
  final Object raw;

  @override
  Object? visitClass<T>(ClassType<T> type) =>
      context.convertTyped<T>(name, raw);

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) =>
      context.convertEnum(name, raw, type.values);

  @override
  Object? visitGeneric<T>(GenericType<T> type) =>
      context.convertTyped<T>(name, raw);

  @override
  Object? visitDynamic(DynamicType type) => raw;

  @override
  Object? visitList<E>(ListType<E> type) => _unsupported(type);

  @override
  Object? visitSet<E>(SetType<E> type) => _unsupported(type);

  @override
  Object? visitMap<K, V>(MapType<K, V> type) => _unsupported(type);

  Object? _unsupported(TypeInfo<Object?> type) {
    context._error(name, 'failed to convert to $type', raw);
    return unbound;
  }
}

// `@DefaultValue` of a constructor parameter.
final class _DefaultVisitor implements TypeInfoVisitor<Object?> {
  _DefaultVisitor(this.context, this.name, this.values, this.scope);

  final BindContext context;
  final ConfigurationPropertyName name;
  final List<String> values;
  final List<BindSource> scope;

  Object? _single(TypeInfo<Object?> type) => values.isEmpty
      ? (type.nullable ? null : unbound)
      : type.accept(_ScalarVisitor(context, name, values.join(',')));

  List<Object?> _items(TypeInfo<Object?> element) => [
    for (final value in values.expand(BindContext.elementsOf))
      if (value != null) element.accept(_ScalarVisitor(context, name, value)),
  ]..removeWhere((item) => identical(item, unbound));

  @override
  Object? visitClass<T>(ClassType<T> type) {
    final introspection = context.binder.introspector.forType(T);
    if (introspection != null && values.isEmpty) {
      // `@DefaultValue()` on a nested object: an instance with defaults.
      return _EmptyVisitor(context, name, scope).visitClass(type);
    }
    return _single(type);
  }

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) => _single(type);

  @override
  Object? visitGeneric<T>(GenericType<T> type) => _single(type);

  @override
  Object? visitDynamic(DynamicType type) =>
      values.isEmpty ? null : values.join(',');

  @override
  Object? visitList<E>(ListType<E> type) => type.create(_items(type.element));

  @override
  Object? visitSet<E>(SetType<E> type) => type.create(_items(type.element));

  @override
  Object? visitMap<K, V>(MapType<K, V> type) => type.create(const []);
}

// A required constructor parameter without a property: empty collections
// and nested objects with their own defaults; [unbound] otherwise.
final class _EmptyVisitor implements TypeInfoVisitor<Object?> {
  _EmptyVisitor(this.context, this.name, this.scope);

  final BindContext context;
  final ConfigurationPropertyName name;
  final List<BindSource> scope;

  @override
  Object? visitClass<T>(ClassType<T> type) {
    final introspection = context.binder.introspector.forType(T);
    if (introspection == null) {
      return unbound;
    }
    if (BindContext.isValueObject(introspection)) {
      return context.bindConstructor(
        introspection,
        name,
        scope,
        requireAny: false,
      );
    }
    return introspection.isInstantiable ? introspection.instantiate() : unbound;
  }

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) => unbound;

  @override
  Object? visitGeneric<T>(GenericType<T> type) => unbound;

  @override
  Object? visitDynamic(DynamicType type) => null;

  @override
  Object? visitList<E>(ListType<E> type) => type.create(const []);

  @override
  Object? visitSet<E>(SetType<E> type) => type.create(const []);

  @override
  Object? visitMap<K, V>(MapType<K, V> type) => type.create(const []);
}

/// The property name for a Dart field or parameter name: `maxSize` gives
/// `max-size`, and `_` becomes `-`.
///
/// Used to find the property of each field of a `@ConfigurationProperties`
/// class and to name it in error messages. Spring Boot's
/// `DataObjectPropertyName.toDashedForm`.
String dashedForm(String name) {
  final result = StringBuffer();
  var last = '';
  for (final char in name.split('')) {
    final ch = char == '_' ? '-' : char;
    final isUpper = ch != ch.toLowerCase();
    if (isUpper && result.isNotEmpty && last != '-') {
      result.write('-');
    }
    last = ch.toLowerCase();
    result.write(last);
  }
  return result.toString();
}
