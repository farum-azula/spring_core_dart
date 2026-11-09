import 'package:spring_core_dart/src/aop/annotations.dart';
import 'package:spring_core_dart/src/aop/join_point.dart';
import 'package:spring_core_dart/src/observation/observation.dart';

/// Measures the calls of a method, or of every method of a class: each
/// call runs in an [Observation] of the application's
/// [ObservationRegistry], through the [ObservedAspect].
///
/// [name] defaults to `method.observed`, [contextualName] to
/// `Class#method`; the observation is tagged `class` (the bean's class)
/// and `method`, plus [lowCardinalityKeyValues], given as key, value,
/// key, value. On a class, it applies to every method (not getters or
/// setters); one on a method wins over the class's.
///
/// ```dart
/// @Service()
/// class OrderService {
///   @Observed(name: 'orders.place', lowCardinalityKeyValues: ['kind', 'web'])
///   Future<Order> place(Basket basket) async { ... }
/// }
/// ```
///
/// Nothing is measured unless an `ObservedAspect` bean is registered.
///
/// Spring (Java): `io.micrometer.observation.annotation.Observed`.
class Observed {
  /// Marks the method, or every method of the class, as observed.
  const Observed({
    this.name,
    this.contextualName,
    this.lowCardinalityKeyValues = const [],
  });

  /// The observation's name; `method.observed` when `null`.
  final String? name;

  /// The readable name of each call; `Class#method` when `null`.
  final String? contextualName;

  /// Extra tags, as key, value, key, value; an odd length throws an
  /// [ArgumentError] when the method is called.
  final List<String> lowCardinalityKeyValues;
}

/// The aspect behind [Observed]: runs each call of an observed method in
/// an [Observation] of [registry], stopped when the call returns or, for
/// a method returning a `Future`, when the future completes; an error is
/// recorded and passed on.
///
/// Register it as a bean to turn `@Observed` on:
///
/// ```dart
/// @Configuration()
/// class ObservationConfig {
///   @Bean()
///   ObservationRegistry observationRegistry() =>
///       ObservationRegistry(handlers: [SlowCallLogger()]);
///
///   @Bean()
///   ObservedAspect observedAspect(ObservationRegistry registry) =>
///       ObservedAspect(registry);
/// }
/// ```
///
/// Spring (Java): `io.micrometer.observation.aop.ObservedAspect`.
@Aspect()
class ObservedAspect {
  /// An aspect observing into [registry].
  ObservedAspect(this.registry);

  /// The name of an observation whose `@Observed` gives none.
  static const String defaultName = 'method.observed';

  /// The annotation this aspect matches; the build's proxy pruning keeps a
  /// proxy for the beans that carry it.
  static const List<Type> annotationTypes = [Observed];

  /// Where the observations go.
  final ObservationRegistry registry;

  /// Runs the call of a method marked `@Observed`, or of a method of a
  /// class marked `@Observed`, in an observation.
  @Around('@annotation(Observed) || (@within(Observed) && execution(* *(..)))')
  Object? observe(ProceedingJoinPoint call) {
    if (registry.isNoop) {
      return call.proceed();
    }
    final signature = call.signature;
    final observed = _observedOf(signature);
    final className = signature.targetType;
    final observation = registry.observation(
      observed?.name ?? defaultName,
      contextualName:
          observed?.contextualName ?? '$className#${signature.name}',
      lowCardinalityKeyValues: {
        'class': className,
        'method': signature.name,
        ..._pairs(observed?.lowCardinalityKeyValues ?? const []),
      },
    );
    return observation.observe(call.proceed);
  }

  // The method's own @Observed, else its class's.
  static Observed? _observedOf(MethodSignature signature) =>
      signature.annotations.whereType<Observed>().firstOrNull ??
      (signature.implementingTypeAnnotations ?? signature.targetAnnotations)
          .whereType<Observed>()
          .firstOrNull ??
      signature.targetAnnotations.whereType<Observed>().firstOrNull;

  static Map<String, String> _pairs(List<String> keyValues) {
    if (keyValues.length.isOdd) {
      throw ArgumentError.value(
        keyValues,
        'lowCardinalityKeyValues',
        'must hold key, value pairs',
      );
    }
    return {
      for (var i = 0; i < keyValues.length; i += 2)
        keyValues[i]: keyValues[i + 1],
    };
  }
}
