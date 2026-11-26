/// Says who is calling, for code that keeps values: a value made from
/// what only this caller may see belongs to this caller.
///
/// The security package implements it over its context. Whatever it
/// returns is compared by identity.
///
/// Spring has no counterpart: it keeps no values between callers unless a
/// cache is asked to, whose key then says whose they are.
abstract interface class CallerIdentitySource {
  /// The caller of the moment; `null` for nobody.
  Object? currentCaller();
}

/// What a kept value needs to know of the caller, without depending on
/// where callers come from.
///
/// Code that depends on the caller (a security decision, a read of the
/// current user) calls [note]. Code that keeps a computed value compares
/// [reads] before and after computing it: when the count moved, the value
/// is the caller's. It then keeps [capture] beside it and hands it out only
/// while [isCurrent] holds.
///
/// ```dart
/// final before = CallerBoundReads.reads;
/// final value = compute();
/// final owner = CallerBoundReads.reads == before
///     ? null
///     : CallerBoundReads.capture();
/// ```
abstract final class CallerBoundReads {
  static final List<CallerIdentitySource> _sources = [];
  static final List<void Function()> _readObservers = [];
  static final List<void Function()> _changeObservers = [];
  static int _reads = 0;
  static bool _capturing = false;

  /// How many reads that depend on the caller were made so far.
  static int get reads => _reads;

  /// Whether anything has said who the caller is.
  static bool get isActive => _sources.isNotEmpty;

  /// Notes a read that depends on the caller, who [source] says.
  static void note(CallerIdentitySource source) {
    if (_capturing) {
      return;
    }
    if (!_sources.contains(source)) {
      _sources.add(source);
    }
    noteRead();
  }

  /// Notes that a kept value that depends on the caller was read again.
  static void noteRead() {
    if (_capturing) {
      return;
    }
    _reads++;
    for (final observer in _readObservers) {
      observer();
    }
  }

  /// Runs [body] without its reads counting as reads of the caller: the
  /// framework's own, while it stores a new user.
  static T quietly<T>(T Function() body) {
    final outer = _capturing;
    _capturing = true;
    try {
      return body();
    } finally {
      _capturing = outer;
    }
  }

  /// Tells everybody who depends on the caller that it has changed.
  static void callerChanged() {
    for (final observer in List.of(_changeObservers)) {
      observer();
    }
  }

  /// Calls [onRead] at each [note] and [onChange] at each [callerChanged].
  static void observe({
    required void Function() onRead,
    required void Function() onChange,
  }) {
    _readObservers.add(onRead);
    _changeObservers.add(onChange);
  }

  /// The caller of the moment, as [isCurrent] compares it.
  static List<Object?> capture() {
    if (_sources.isEmpty) {
      return const [];
    }
    return quietly(
      () => [for (final source in _sources) source.currentCaller()],
    );
  }

  /// Whether the caller of the moment is the one of [captured].
  static bool isCurrent(List<Object?> captured) {
    if (captured.length != _sources.length) {
      return false;
    }
    final outer = _capturing;
    _capturing = true;
    try {
      for (var index = 0; index < captured.length; index++) {
        if (!identical(captured[index], _sources[index].currentCaller())) {
          return false;
        }
      }
      return true;
    } finally {
      _capturing = outer;
    }
  }
}

/// Captures who the caller is and runs code as that caller later: what a
/// reader that runs again (an effect run by a change) needs, so it runs as
/// whoever it belongs to and never as whoever made the change.
///
/// The security package implements it over its context.
abstract interface class CallerContextPropagation {
  /// The caller of the moment, to run as later.
  Object? capture();

  /// Runs [body] as [captured], a value of [capture].
  R runAs<R>(Object? captured, R Function() body);
}

/// The [CallerContextPropagation]s the packages registered.
///
/// ```dart
/// final owner = CallerContexts.capture();      // when a reader is made
/// CallerContexts.runAs(owner, rerun);          // each time it runs again
/// ```
abstract final class CallerContexts {
  static final List<CallerContextPropagation> _all = [];

  /// Adds [propagation]; once.
  static void register(CallerContextPropagation propagation) {
    if (!_all.contains(propagation)) {
      _all.add(propagation);
    }
  }

  /// Who the caller is now, for [runAs].
  static List<Object?> capture() => [
    for (final propagation in _all) propagation.capture(),
  ];

  /// Runs [body] as the caller of [captured].
  static R runAs<R>(List<Object?> captured, R Function() body) {
    var run = body;
    for (
      var index = 0;
      index < captured.length && index < _all.length;
      index++
    ) {
      final propagation = _all[index];
      final value = captured[index];
      final inner = run;
      run = () => propagation.runAs(value, inner);
    }
    return run();
  }
}
