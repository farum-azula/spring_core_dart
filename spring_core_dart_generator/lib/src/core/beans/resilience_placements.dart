import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/annotation_placement.dart';

// `@Retryable` and `@ConcurrencyLimit` are advice. Dart cannot wait in a
// synchronous method, so a pause of a retry, a timeout, or a call that
// waits for a permit there fails the build; so does a limit below 1.

/// Recognises `@Retryable` of `spring_core_dart`.
const retryableChecker = TypeChecker.fromUrl(
  'package:spring_core_dart/src/resilience/retryable.dart#Retryable',
);

/// Recognises `@ConcurrencyLimit` of `spring_core_dart`.
const concurrencyLimitChecker = TypeChecker.fromUrl(
  'package:spring_core_dart/src/resilience/concurrency_limit.dart'
  '#ConcurrencyLimit',
);

/// Whether a member returning [type] returns before its work ends: a
/// `Future`, a `FutureOr` or a stream; a retry can wait there, and a
/// permit be held until it ends.
bool returnsLater(DartType type) =>
    type is InterfaceType &&
    (type.isDartAsyncFuture ||
        type.isDartAsyncFutureOr ||
        type.isDartAsyncStream ||
        type.allSupertypes.any(
          (supertype) =>
              supertype.isDartAsyncFuture || supertype.isDartAsyncStream,
        ));

// Whether [member] waits for its result: a stream does not (its call
// returns at once), a future does.
bool _awaits(DartType type) =>
    type is InterfaceType &&
    (type.isDartAsyncFuture ||
        type.isDartAsyncFutureOr ||
        type.allSupertypes.any((supertype) => supertype.isDartAsyncFuture));

// The public instance methods of a class a class-level annotation covers.
Iterable<MethodElement> _coveredMethods(Element element) => switch (element) {
  final InterfaceElement owner => owner.methods.where(
    (method) => method.isPublic && !method.isStatic && !method.isOperator,
  ),
  _ => const [],
};

DartType? _returnType(Element element) => switch (element) {
  final ExecutableElement executable => executable.returnType,
  _ => null,
};

// A const `Duration`'s length: its field is `inMicroseconds` (`_duration`
// in older SDKs).
int _microseconds(DartObject? duration) =>
    (duration?.getField('inMicroseconds') ?? duration?.getField('_duration'))
        ?.toIntValue() ??
    0;

/// `@Retryable`: advice; on a synchronous method, no pause and no timeout
/// (Dart cannot wait without returning).
final class RetryablePlacement extends AdvicePlacement {
  /// The placement.
  const RetryablePlacement()
    : super(const [retryableChecker], effect: 'nothing would be retried');

  @override
  String? problem(AnnotationSite site) =>
      super.problem(site) ?? _waitsInSyncMethod(site);

  String? _waitsInSyncMethod(AnnotationSite site) {
    final waits = _waitingAttributes(site.annotation);
    if (waits.isEmpty) {
      return null;
    }
    if (site.kind == PlaceKind.classDeclaration) {
      for (final method in _coveredMethods(site.element)) {
        if (!returnsLater(method.returnType) &&
            !retryableChecker.hasAnnotationOf(method)) {
          return '@Retryable on ${site.subject} with ${waits.join(', ')}, and '
              '${site.ownerName}.${method.displayName} is synchronous: Dart '
              'cannot wait in a method that returns its result at once, so '
              'it would be retried without the pause. Write delay: '
              'Duration.zero (and no jitter or timeout) on the class, give '
              '${method.displayName} a @Retryable of its own with delay: '
              'Duration.zero, or make it return a Future.';
        }
      }
      return null;
    }
    final returned = _returnType(site.element);
    if (returned == null || returnsLater(returned)) {
      return null;
    }
    return '@Retryable on ${site.subject} with ${waits.join(', ')}, and it is '
        'synchronous: Dart cannot wait in a method that returns its result '
        'at once, so it would be retried without the pause. Write delay: '
        'Duration.zero (and no jitter or timeout) to retry at once, or make '
        'it return a Future.';
  }

  // The attributes that make a retry wait: a delay (1 s unless written
  // as zero), a jitter, a timeout, or their texts.
  static List<String> _waitingAttributes(DartObject annotation) {
    final reader = ConstantReader(annotation);
    return [
      if (_microseconds(reader.peek('delay')?.objectValue) > 0)
        'a delay (1 second unless written)',
      if (reader.peek('delayString') != null) 'a delayString',
      if (_microseconds(reader.peek('jitter')?.objectValue) > 0) 'a jitter',
      if (reader.peek('jitterString') != null) 'a jitterString',
      if (_microseconds(reader.peek('timeout')?.objectValue) > 0) 'a timeout',
      if (reader.peek('timeoutString') != null) 'a timeoutString',
    ];
  }
}

/// `@ConcurrencyLimit`: advice; a limit of at least 1, and
/// `ThrottlePolicy.block` only on a method that returns a `Future` (a
/// call that waits for a permit needs one).
final class ConcurrencyLimitPlacement extends AdvicePlacement {
  /// The placement.
  const ConcurrencyLimitPlacement()
    : super(const [
        concurrencyLimitChecker,
      ], effect: 'the calls would not be limited');

  @override
  String? problem(AnnotationSite site) =>
      super.problem(site) ?? _limitProblem(site) ?? _blocksInSyncMethod(site);

  String? _limitProblem(AnnotationSite site) {
    final reader = ConstantReader(site.annotation);
    final limit = reader.peek('limit')?.intValue ?? 1;
    if (reader.peek('limitString') != null || limit >= 1) {
      return null;
    }
    return '@ConcurrencyLimit($limit) on ${site.subject}: the limit is how '
        'many calls may run at the same time, so it is at least 1.';
  }

  String? _blocksInSyncMethod(AnnotationSite site) {
    final policy = ConstantReader(
      site.annotation,
    ).peek('policy')?.objectValue.getField('_name')?.toStringValue();
    if (policy == 'reject') {
      return null;
    }
    final methods = site.kind == PlaceKind.classDeclaration
        ? [
            for (final method in _coveredMethods(site.element))
              if (!concurrencyLimitChecker.hasAnnotationOf(method)) method,
          ]
        : [site.element];
    for (final method in methods) {
      final returned = _returnType(method);
      if (returned == null || _awaits(returned)) {
        continue;
      }
      final name = site.kind == PlaceKind.classDeclaration
          ? '${site.ownerName}.${method.displayName}'
          : site.subject;
      return '@ConcurrencyLimit on ${site.subject} waits for a permit '
          '(ThrottlePolicy.block), and $name does not return a Future: Dart '
          'cannot wait in it without returning, so a call over the limit '
          'would fail. Make it return a Future, or write '
          'policy: ThrottlePolicy.reject.';
    }
    return null;
  }
}
