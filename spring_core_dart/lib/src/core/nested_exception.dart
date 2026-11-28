/// An exception that carries the error behind it: a failure that wraps a
/// lower-level one, as a bean that could not be created wraps the error
/// its constructor threw.
///
/// Dart's exceptions have no cause of their own; the family's exceptions
/// that wrap another implement this, so that code which looks behind an
/// exception (the retries match `includes` and `excludes` along the
/// chain) finds the cause whatever the family. Implement it in your own
/// exception that wraps another.
///
/// ```dart
/// class ImportFailed implements NestedException {
///   ImportFailed(this.cause);
///
///   @override
///   final Object? cause;
/// }
///
/// NestedExceptionUtils.causeChain(ImportFailed(TimeoutException('slow')));
/// // ImportFailed, then the TimeoutException
/// ```
///
/// Spring (Java): `Throwable.getCause()`, which every exception has.
abstract interface class NestedException {
  /// The error behind this one; `null` when there is none.
  Object? get cause;
}

/// Reads the causes of [NestedException]s.
///
/// Spring (Java): `org.springframework.core.NestedExceptionUtils`.
abstract final class NestedExceptionUtils {
  /// The most causes followed: a longer chain is cut there.
  static const int maxDepth = 32;

  /// [error], then its cause, the cause's cause and so on, while each is a
  /// [NestedException] with a cause; a cause seen before (a cycle) ends
  /// the chain.
  static Iterable<Object> causeChain(Object error) sync* {
    final seen = Set<Object>.identity();
    Object? current = error;
    while (current != null && seen.length < maxDepth && seen.add(current)) {
      yield current;
      current = current is NestedException ? current.cause : null;
    }
  }

  /// The last error of [causeChain]: the one that started it all, or
  /// [error] itself when it has no cause.
  static Object rootCause(Object error) => causeChain(error).last;
}
