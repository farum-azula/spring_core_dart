import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_boot_dart/src/configuration_properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Binds properties of an environment to typed values, like Spring Boot's
/// `Binder`: what `@ConfigurationProperties` uses, and usable directly.
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
/// final hosts = Binder.get(environment)
///     .bind('app.hosts', const ListType<String>(ClassType<String>()))
///     .orElse(const []);
/// ```
///
/// Spring (Java):
/// ```java
/// List<String> hosts = Binder.get(environment)
///     .bind("app.hosts", Bindable.listOf(String.class))
///     .orElse(List.of());
/// ```
final class Binder {
  /// A binder reading [environment]; nested objects are described by
  /// [introspector] (default `BeanIntrospector.shared`), values converted
  /// by [conversionService] (default: the environment's).
  Binder(
    this.environment, {
    BeanIntrospector? introspector,
    ConversionService? conversionService,
  }) : introspector = introspector ?? BeanIntrospector.shared,
       conversionService = conversionService ?? environment.conversionService;

  /// Like the constructor, as Spring Boot's `Binder.get(environment)`.
  static Binder get(
    ConfigurableEnvironment environment, {
    BeanIntrospector? introspector,
  }) => Binder(environment, introspector: introspector);

  /// The properties are read from here.
  final ConfigurableEnvironment environment;

  /// Metadata of the nested classes.
  final BeanIntrospector introspector;

  /// Converts property values to the target types.
  final ConversionService conversionService;

  /// Binds the properties at [name] (a canonical name such as
  /// `app.hosts`) to [target]; unbound when none of them exists. Throws a
  /// [ConfigurationPropertiesBindException] naming every property that
  /// could not be converted.
  ///
  /// ```dart
  /// binder.bind('app.timeout', const ClassType<Duration>()).get();
  /// ```
  ///
  /// [handler] is told about each property bound on the way (Spring Boot's
  /// `BindHandler`).
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

/// The result of [Binder.bind], like Spring Boot's `BindResult`.
final class BindResult<T> {
  const BindResult._(this._value, {required this.isBound});

  final Object? _value;

  /// Whether any property was bound.
  final bool isBound;

  /// The bound value; throws a `StateError` when nothing was bound.
  T get() => isBound ? _value as T : throw StateError('No value bound');

  /// The bound value, or [other] when nothing was bound.
  T orElse(T other) => isBound ? _value as T : other;

  /// The bound value, or the result of [other] when nothing was bound.
  T orElseGet(T Function() other) => isBound ? _value as T : other();

  /// The bound value; throws the result of [error] when nothing was bound.
  ///
  /// ```dart
  /// binder
  ///     .bind('app.port', const ClassType<int>())
  ///     .orElseThrow(() => StateError('app.port is required'));
  /// ```
  T orElseThrow(Object Function() error) =>
      isBound ? _value as T : throw error();

  /// Calls [action] with the bound value, if any.
  void ifBound(void Function(T value) action) {
    if (isBound) {
      action(_value as T);
    }
  }

  /// The bound value mapped through [mapper]; unbound stays unbound.
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

/// Callbacks of a [Binder.bind] run for every property bound on the way
/// (the top-level name, then nested properties and elements), like Spring
/// Boot's `BindHandler`; extend it and override what you need.
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
///     print('bound $name');
///     return result;
///   }
/// }
///
/// binder.bind('app', appType, handler: const LoggingBindHandler());
/// ```
///
/// Spring (Java): `binder.bind("app", Bindable.of(App.class), handler)`.
///
/// Differences: [onFailure] gets the error message and decides whether it
/// counts (Boot's returns a replacement value or rethrows).
class BindHandler {
  /// A handler that changes nothing.
  const BindHandler();

  /// The default: binds as is and reports every failure.
  static const BindHandler defaultHandler = BindHandler();

  /// Before [name] is bound to [target]; `false` skips it (unbound).
  bool onStart(ConfigurationPropertyName name, TypeInfo<Object?> target) =>
      true;

  /// After [name] was bound to [result]; returns the value to use.
  Object? onSuccess(
    ConfigurationPropertyName name,
    TypeInfo<Object?> target,
    Object? result,
  ) => result;

  /// When [name] cannot be bound ([error] describes why); `true` (the
  /// default) reports the failure, `false` ignores it (left unbound).
  bool onFailure(ConfigurationPropertyName name, String error) => true;

  /// After [name] was bound or not ([result] `null` when unbound).
  void onFinish(
    ConfigurationPropertyName name,
    TypeInfo<Object?> target,
    Object? result,
  ) {}
}

Type _typeOf<T>() => T;

/// Marks "nothing bound" (a bound value may be `null`).
const Object unbound = _Unbound();

final class _Unbound {
  const _Unbound();
}

/// One binding run: the property sources and the errors found (internal
/// to `spring_boot_dart`).
final class BindContext {
  /// Takes the property sources of [binder]'s environment, in order.
  BindContext(this.binder, {this.handler = BindHandler.defaultHandler})
    : sources = [
        for (final source in binder.environment.propertySources)
          if (source is! ConfigurationPropertySourcesPropertySource)
            BindSource(source),
      ];

  /// The binder this run belongs to.
  final Binder binder;

  /// Told about every bind (Spring Boot's `BindHandler`).
  final BindHandler handler;

  // Annotations of the field or constructor parameter being bound
  // (`@DurationUnit`, `@DataSizeUnit`), applied to its value and elements.
  List<Object> _annotations = const [];

  /// The environment's property sources, in precedence order.
  final List<BindSource> sources;

  /// One line per property that could not be bound.
  final errors = <String>[];

  // Data object types being bound, against endless recursion through
  // sources that cannot list their names.
  final _binding = <Type>[];

  /// Throws a [ConfigurationPropertiesBindException] for [prefix] when
  /// there are [errors].
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
    if (handler.onFailure(name, error)) {
      errors.add(error);
    }
  }

  /// Binds [name] to [type]; [existing] is the current value of a JavaBean
  /// property (nested objects are bound into it, maps merged with it).
  /// Returns [unbound] when no property applies.
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

  /// Binds the properties under [name] into [bean] through its setters
  /// (JavaBean binding); whether any property was bound.
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
      } catch (_) {
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
      if (identical(value, current)) {
        continue; // a nested object bound in place
      }
      if (property.isWritable) {
        try {
          property.setValue(bean, value);
        } catch (error) {
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

  /// Binds a nested object of [introspection] at [name]: into [existing]
  /// (JavaBean), a new instance through setters, or through its
  /// constructor (constructor binding); [unbound] when nothing applies.
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

  /// Whether instances of [introspection] are created through their
  /// constructor (it has parameters), like Spring Boot's value objects.
  static bool isValueObject(BeanIntrospection<Object> introspection) =>
      introspection.constructor?.parameters.isNotEmpty ?? false;

  /// Creates an instance of [introspection] through its constructor, each
  /// parameter bound from `name.<parameter-name>` (constructor binding).
  /// A parameter without a property gets its [DefaultValue], else its Dart
  /// default value, else `null` when nullable; a missing collection is
  /// empty and a missing nested object is created with its own defaults;
  /// any other missing parameter is an error. With [requireAny], [unbound]
  /// when no parameter was bound.
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
          value = parameter.type.accept(
            _EmptyVisitor(this, parameterName, scope),
          );
        }
        if (identical(value, unbound) && !omit) {
          if (!failed) {
            _error(
              parameterName,
              'no value bound for the required constructor parameter '
              "'${parameter.name}' of ${introspection.beanType} (set the "
              'property, give the parameter a @DefaultValue or a default, '
              'or make it nullable)',
            );
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
    } catch (error) {
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

  /// The raw value of [name] in the first of [scope] that has it, with
  /// `${...}` placeholders resolved (unresolvable ones are kept, as in
  /// Spring Boot).
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

  /// Converts [raw] to [type]; [unbound] (with an error recorded) when it
  /// cannot be converted, and for blank input of non-string types.
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
    } catch (error) {
      _error(name, 'failed to convert to $type', raw);
      return unbound;
    }
  }

  /// Like [_convert] with the static type [T], so `List<T>` elements come
  /// out typed.
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

  /// [raw] as a value of enum [values], ignoring case and separators
  /// (`MY_VALUE`, `my-value` and `myValue` are `myValue`), like Spring
  /// Boot's lenient enum conversion.
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
      'failed to convert to $E (one of ${values.map((v) => v.name).join(', ')})',
      raw,
    );
    return unbound;
  }

  static String _lenient(String text) =>
      text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// The elements of a comma list or an iterable value.
  static List<Object?> elementsOf(Object raw) => switch (raw) {
    final String text when text.trim().isEmpty => const [],
    final String text => [for (final part in text.split(',')) part.trim()],
    final Iterable<Object?> items => items.toList(),
    _ => [raw],
  };

  /// Binds a list at [name]: a comma list or indexed keys, from the first
  /// source that has either (Spring Boot's `IndexedElementsBinder`);
  /// [unbound] when none has.
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
        return items;
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
      errors.add(
        'The elements [${left.join(', ')}] were left unbound '
        '(list indexes must start at 0 and have no gaps).',
      );
    }
  }

  /// Binds a map at [name]: an entry per key under it, from every source
  /// (the first source that has a key wins; Spring Boot's `MapBinder`);
  /// [unbound] when there is none. Keys keep their original form.
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

/// A property source of the environment, read with relaxed names
/// (internal to `spring_boot_dart`).
final class BindSource {
  /// Reads [source].
  BindSource(this.source);

  /// The property source.
  final AbstractPropertySource<Object> source;

  /// Whether the source can list its property names.
  bool get isEnumerable => source is EnumerablePropertySource<Object>;

  /// The value of [name] in any relaxed form, or `null`.
  Object? valueOf(ConfigurationPropertyName name) =>
      ConfigurationPropertySources.getProperty(source, name);

  /// Whether the source has a property below [name]. For system
  /// environment variables also below [name] with its dashes read as dots
  /// (`APP_MAIN_SERVER_HOST` is below `app.main-server`), like Spring
  /// Boot's legacy check in `SystemEnvironmentPropertyMapper`.
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

  /// Every property of the source (empty when it cannot be listed).
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

/// `maxSize` → `max-size`, Spring Boot's dashed form of a property or
/// parameter name (`DataObjectPropertyName.toDashedForm`; `_` becomes `-`).
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
