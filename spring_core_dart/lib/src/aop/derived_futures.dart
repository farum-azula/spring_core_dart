/// How the future a caller holds came from the one a piece of advice
/// keeps.
///
/// Advice around a `Future` member hands out another future than the one
/// it was given (a value cast to the member's type, a filtered result).
/// Advice that keeps a future and says where it is ([track]) finds it again
/// from the one the caller holds ([of]), with what was done to its value
/// on the way.
abstract final class DerivedFutures {
  static final Expando<FutureDerivation> _derivations = Expando(
    'derived futures',
  );

  /// Marks [source] as a future whose derived futures are looked up.
  static void track(Future<Object?> source) =>
      _derivations[source] ??= FutureDerivation._(source, const []);

  /// Notes that [derived] gives the value of [from], through [transform]
  /// when given. Nothing is noted for a future nobody tracks.
  static void link(
    Future<Object?> derived,
    Future<Object?> from, {
    Object? Function(Object? value)? transform,
  }) {
    final origin =
        _derivations[from] ??
        (_recording > 0 ? FutureDerivation._(from, const []) : null);
    if (origin == null) {
      return;
    }
    _derivations[derived] = FutureDerivation._(
      origin.origin,
      transform == null ? origin.transforms : [...origin.transforms, transform],
      error: origin.error,
      stackTrace: origin.stackTrace,
    );
  }

  /// Runs [call] so that every [link] made while it runs counts, also from
  /// a future nobody tracks yet: for advice outside the advice that
  /// derives futures, which learns of the future the bean makes only later
  /// (a transaction starts the body after an `await` of its own).
  static T recording<T>(T Function() call) {
    _recording++;
    try {
      return call();
    } finally {
      _recording--;
    }
  }

  static int _recording = 0;

  /// Notes that [future] is the failure [error] of a call refused before
  /// there was anything to derive it from.
  static void refused(
    Future<Object?> future,
    Object error,
    StackTrace stackTrace,
  ) => _derivations[future] = FutureDerivation._(
    future,
    const [],
    error: error,
    stackTrace: stackTrace,
  );

  /// What is known of [future]; `null` when it comes from no tracked one.
  static FutureDerivation? of(Future<Object?> future) => _derivations[future];
}

/// Where a future came from: [DerivedFutures.of].
final class FutureDerivation {
  FutureDerivation._(
    this.origin,
    this.transforms, {
    this.error,
    this.stackTrace,
  });

  /// The future that was tracked.
  final Future<Object?> origin;

  /// What was done to its value, first applied first.
  final List<Object? Function(Object? value)> transforms;

  /// Why the call was refused; `null` when it was not.
  final Object? error;

  /// Where [error] was thrown.
  final StackTrace? stackTrace;

  /// [value] as the derived future gives it. Fails as the advice would.
  Object? apply(Object? value) {
    var current = value;
    for (final transform in transforms) {
      current = transform(current);
    }
    return current;
  }
}
