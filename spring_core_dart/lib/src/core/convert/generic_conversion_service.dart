import 'package:spring_core_dart/src/core/convert/conversion_exceptions.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/lenient_enum.dart';

/// One registered conversion to a fixed target type.
final class _Converter {
  _Converter(this.accepts, this.acceptsType, this.convert);

  final bool Function(Object source) accepts;
  // Whether a source of type X is accepted (X a subtype of the source).
  final bool Function<X>() acceptsType;
  final Object? Function(Object source) convert;
}

/// Knows how to recognize instances of a target type, captured from a type
/// argument at registration time.
final class _Target {
  _Target(this.isInstance, this.isSupertypeOf);

  final bool Function(Object? value) isInstance;
  // Whether X is a subtype of the target.
  final bool Function<X>() isSupertypeOf;
  final List<_Converter> converters = [];
}

// Turns a type argument into a `Type` object; needed for types such as
// `T?` that cannot be written as a type literal.
Type _typeOf<T>() => T;

/// Registry-based [ConversionService], like Spring's
/// `GenericConversionService`. Starts empty; see `DefaultConversionService`
/// for the built-in converters.
///
/// Converters are looked up by exact target [Type]; among converters for
/// the same target the newest registration whose source type matches (via
/// `is`) wins.
///
/// ```dart
/// final service = GenericConversionService()
///   ..addConverter<String, Money>(Money.parse)
///   ..addConverter<Money, String>((money) => money.format());
/// final price = service.convert<Money>('9.99 EUR');
/// ```
///
/// Spring (Java):
/// ```java
/// GenericConversionService service = new GenericConversionService();
/// service.addConverter(String.class, Money.class, Money::parse);
/// service.addConverter(Money.class, String.class, Money::format);
/// Money price = service.convert("9.99 EUR", Money.class);
/// ```
///
/// Differences: no `ConverterFactory` / `GenericConverter` and no class
/// hierarchy search for targets (Dart has no runtime type introspection);
/// register each concrete target instead.
class GenericConversionService implements ConversionService, ConverterRegistry {
  // Target type (exact, including nullability) → its converters.
  final _targets = <Type, _Target>{};

  // The `v is T` closure is created here, while `T` is still a type
  // argument, so targets can later test instances by `Type` alone.
  _Target _target<T>() => _targets.putIfAbsent(
    T,
    () => _Target((v) => v is T, <X>() => <X>[] is List<T>),
  );

  @override
  void addConverter<S, T>(T? Function(S source) converter) {
    final entry = _Converter(
      (source) => source is S,
      <X>() => <X>[] is List<S>,
      (s) => converter(s as S),
    );
    // Same converter for `T` and `T?`; newest first (later registrations win).
    _target<T>().converters.insert(0, entry);
    _targets
        .putIfAbsent(
          _typeOf<T?>(),
          () => _Target((v) => v is T?, <X>() => <X>[] is List<T?>),
        )
        .converters
        .insert(0, entry);
  }

  @override
  void addEnum<E extends Enum>(List<E> values) {
    addConverter<String, E>((source) {
      final name = source.trim();
      if (name.isEmpty) {
        return null;
      }
      return findLenientEnum(values, name) ??
          (throw ArgumentError.value(
            source,
            'source',
            'No enum constant of $E',
          ));
    });
    addConverter<E, String>((source) => source.name);
    addCollectionConverters<E>();
  }

  @override
  void addCollectionConverters<E>() {
    List<E> elements(Iterable<Object?> items) => [
      for (final item in items) convert<E>(item),
    ];
    Iterable<String> split(String source) => source.trim().isEmpty
        ? const []
        : source.split(',').map((part) => part.trim());

    // Registered first, so the String and Iterable converters win.
    addConverter<Object, List<E>>((source) => [convert<E>(source)]);
    addConverter<Object, Set<E>>((source) => {convert<E>(source)});
    addConverter<String, List<E>>((source) => elements(split(source)));
    addConverter<String, Set<E>>((source) => elements(split(source)).toSet());
    addConverter<Iterable<Object?>, List<E>>(elements);
    addConverter<Iterable<Object?>, Set<E>>(
      (source) => elements(source).toSet(),
    );
  }

  @override
  void addMapConverters<K, V>() =>
      addConverter<Map<Object?, Object?>, Map<K, V>>(
        (source) => {
          for (final MapEntry(:key, :value) in source.entries)
            convert<K>(key): convert<V>(value),
        },
      );

  @override
  void removeConvertible<T>() {
    _targets[T]?.converters.clear();
    _targets[_typeOf<T?>()]?.converters.clear();
  }

  @override
  bool canConvert(Object? source, Type targetType) {
    if (source == null) {
      return true;
    }
    if (_isDirect(source, targetType)) {
      return true;
    }
    return _find(source, targetType) != null;
  }

  @override
  bool canConvertType<S>(Type targetType) {
    if (targetType == Object ||
        targetType == dynamic ||
        targetType == _typeOf<Object?>() ||
        S == targetType) {
      return true;
    }
    final target = _targets[targetType];
    if (target == null) {
      return false;
    }
    return target.isSupertypeOf<S>() ||
        target.converters.any((converter) => converter.acceptsType<S>());
  }

  @override
  T convert<T>(Object? source) {
    if (source is T) {
      return source;
    }
    final result = convertTo(source, T);
    if (result is T) {
      return result;
    }
    throw ConversionFailedException(source, T);
  }

  @override
  Object? convertTo(Object? source, Type targetType) {
    if (source == null || _isDirect(source, targetType)) {
      return source;
    }
    final converter = _find(source, targetType);
    if (converter == null) {
      throw ConverterNotFoundException(source.runtimeType, targetType);
    }
    try {
      return converter.convert(source);
    } on ConversionException {
      rethrow;
    } catch (error) {
      throw ConversionFailedException(source, targetType, error);
    }
  }

  // No conversion needed: the target accepts anything, or the source
  // already is an instance of a registered target type.
  bool _isDirect(Object source, Type targetType) =>
      targetType == Object ||
      targetType == dynamic ||
      targetType == _typeOf<Object?>() ||
      source.runtimeType == targetType ||
      (_targets[targetType]?.isInstance(source) ?? false);

  _Converter? _find(Object source, Type targetType) {
    for (final converter
        in _targets[targetType]?.converters ?? const <_Converter>[]) {
      if (converter.accepts(source)) {
        return converter;
      }
    }
    return null;
  }
}
