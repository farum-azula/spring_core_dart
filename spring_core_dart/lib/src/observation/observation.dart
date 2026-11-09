import 'dart:async';

import 'package:spring_core_dart/src/observation/observation_handler.dart';

/// One measured piece of work: started, maybe failed, stopped, with a
/// name and tags. Its handlers turn it into a log line, a metric or a bar
/// of a timeline.
///
/// Most code calls [observe], which starts the observation, runs the work
/// with it as the current one, records what the work throws and stops it
/// when the work is done, also when the work returns a `Future`:
///
/// ```dart
/// final orders = await registry
///     .observation('orders.load')
///     .lowCardinalityKeyValue('source', 'remote')
///     .observe(() => api.loadOrders());
/// ```
///
/// An observation created while another one is current (inside its
/// [observe] or [scoped], across `await`s too, since the current
/// observation is kept in a `Zone`) has that one as its parent.
///
/// Spring (Java): `io.micrometer.observation.Observation`.
abstract interface class Observation {
  /// The observation that records nothing; [ObservationRegistry.noop]
  /// gives it.
  static const Observation noop = _NoopObservation();

  /// What the handlers are told: name, tags, timing, error, parent.
  ObservationContext get context;

  /// Whether this is [noop].
  bool get isNoop;

  /// Sets the readable name of this call (`OrderService#place`).
  Observation contextualName(String? name);

  /// Adds the tag [key] = [value]; use few distinct values (a class, an
  /// outcome), not ids.
  Observation lowCardinalityKeyValue(String key, String value);

  /// Starts the observation and tells the handlers; a second call does
  /// nothing.
  Observation start();

  /// Records that the observed work threw [error] and tells the handlers.
  Observation error(Object error, [StackTrace? stackTrace]);

  /// Stops the observation and tells the handlers, in reverse order; does
  /// nothing before [start] or after the first call.
  void stop();

  /// Runs [body] with this observation as the current one, without
  /// starting or stopping it: observations created inside, also after an
  /// `await`, are its children.
  T scoped<T>(T Function() body);

  /// Starts the observation, runs [body] in its scope and stops it when
  /// [body] returns. When [body] returns a `Future`, the observation stops
  /// when the future completes, and the future returned is one of the
  /// same type that completes the same way. An error thrown (or completed
  /// with) is recorded and passed on.
  T observe<T>(T Function() body);
}

/// Creates observations and holds the [ObservationHandler]s they report
/// to.
///
/// [ObservationRegistry.noop] records nothing and costs nothing (no zone,
/// no clock); a registry made with handlers measures. A library observes
/// through the registry it is given, so the application decides whether
/// anything is recorded.
///
/// ```dart
/// final registry = ObservationRegistry(handlers: [SlowCallLogger()]);
/// final total = registry.observe(
///   'basket.total',
///   () => basket.total(),
///   lowCardinalityKeyValues: {'currency': 'EUR'},
/// );
/// ```
///
/// Spring (Java): `io.micrometer.observation.ObservationRegistry`.
abstract interface class ObservationRegistry {
  /// A registry reporting to [handlers] (more can be added with
  /// [addHandler]); [clock] is for tests, a monotonic stopwatch by
  /// default. While it has no handler it creates [Observation.noop].
  factory ObservationRegistry({
    Iterable<ObservationHandler> handlers,
    Duration Function()? clock,
  }) = _SimpleObservationRegistry;

  /// The registry that records nothing: every observation is
  /// [Observation.noop] and [observe] just runs the work.
  static const ObservationRegistry noop = _NoopObservationRegistry();

  /// Whether this registry records nothing.
  bool get isNoop;

  /// The handlers, in the order they were added.
  List<ObservationHandler> get handlers;

  /// Adds [handler] for the observations created from now on; throws an
  /// [UnsupportedError] on [noop].
  void addHandler(ObservationHandler handler);

  /// The observation whose scope the caller runs in; `null` outside any.
  Observation? get currentObservation;

  /// An observation named [name], not started. Its parent is [parent],
  /// else [currentObservation].
  Observation observation(
    String name, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues,
    Observation? parent,
  });

  /// An observation named [name], started; stop it with
  /// [Observation.stop].
  Observation start(
    String name, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues,
    Observation? parent,
  });

  /// Runs [body] in a new observation named [name] (see
  /// [Observation.observe]) and returns what it returns.
  T observe<T>(
    String name,
    T Function() body, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues,
  });
}

final class _NoopObservationRegistry implements ObservationRegistry {
  const _NoopObservationRegistry();

  @override
  bool get isNoop => true;

  @override
  List<ObservationHandler> get handlers => const [];

  @override
  void addHandler(ObservationHandler handler) => throw UnsupportedError(
    'ObservationRegistry.noop records nothing; create an '
    'ObservationRegistry to add handlers',
  );

  @override
  Observation? get currentObservation => null;

  @override
  Observation observation(
    String name, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues = const {},
    Observation? parent,
  }) => Observation.noop;

  @override
  Observation start(
    String name, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues = const {},
    Observation? parent,
  }) => Observation.noop;

  @override
  T observe<T>(
    String name,
    T Function() body, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues = const {},
  }) => body();
}

final class _SimpleObservationRegistry implements ObservationRegistry {
  _SimpleObservationRegistry({
    Iterable<ObservationHandler> handlers = const [],
    Duration Function()? clock,
  }) : _handlers = [...handlers],
       _clock = clock ?? _stopwatch();

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  final List<ObservationHandler> _handlers;
  final Duration Function() _clock;
  // The zone value holding the current observation of this registry.
  final Object _scope = Object();
  var _next = 1;

  @override
  bool get isNoop => false;

  @override
  List<ObservationHandler> get handlers => List.unmodifiable(_handlers);

  @override
  void addHandler(ObservationHandler handler) => _handlers.add(handler);

  @override
  Observation? get currentObservation => Zone.current[_scope] as Observation?;

  @override
  Observation observation(
    String name, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues = const {},
    Observation? parent,
  }) {
    if (_handlers.isEmpty) {
      return Observation.noop;
    }
    final parentContext = (parent ?? currentObservation)?.context;
    final context = ObservationContext(
      name,
      id: _next++,
      parent: parentContext,
      contextualName: contextualName,
      lowCardinalityKeyValues: lowCardinalityKeyValues,
    );
    return _SimpleObservation(this, context, [
      for (final handler in _handlers)
        if (handler.supportsContext(context)) handler,
    ]);
  }

  @override
  Observation start(
    String name, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues = const {},
    Observation? parent,
  }) => observation(
    name,
    contextualName: contextualName,
    lowCardinalityKeyValues: lowCardinalityKeyValues,
    parent: parent,
  ).start();

  @override
  T observe<T>(
    String name,
    T Function() body, {
    String? contextualName,
    Map<String, String> lowCardinalityKeyValues = const {},
  }) => observation(
    name,
    contextualName: contextualName,
    lowCardinalityKeyValues: lowCardinalityKeyValues,
  ).observe(body);
}

final class _SimpleObservation implements Observation {
  _SimpleObservation(this._registry, this.context, this._handlers);

  final _SimpleObservationRegistry _registry;
  final List<ObservationHandler> _handlers;

  @override
  final ObservationContext context;

  @override
  bool get isNoop => false;

  @override
  Observation contextualName(String? name) {
    context.contextualName = name;
    return this;
  }

  @override
  Observation lowCardinalityKeyValue(String key, String value) {
    context.lowCardinalityKeyValues[key] = value;
    return this;
  }

  @override
  Observation start() {
    if (context.startedAt != null) {
      return this;
    }
    context.startedAt = _registry._clock();
    for (final handler in _handlers) {
      handler.onStart(context);
    }
    return this;
  }

  @override
  Observation error(Object error, [StackTrace? stackTrace]) {
    context
      ..error = error
      ..stackTrace = stackTrace;
    for (final handler in _handlers) {
      handler.onError(context);
    }
    return this;
  }

  @override
  void stop() {
    final startedAt = context.startedAt;
    if (startedAt == null || context.duration != null) {
      return;
    }
    context.duration = _registry._clock() - startedAt;
    for (final handler in _handlers.reversed) {
      handler.onStop(context);
    }
  }

  @override
  T scoped<T>(T Function() body) =>
      runZoned(body, zoneValues: {_registry._scope: this});

  @override
  T observe<T>(T Function() body) {
    start();
    final T result;
    try {
      result = scoped(body);
    } catch (e, s) {
      error(e, s);
      stop();
      rethrow;
    }
    if (result is Future<Object?>) {
      // `catchError` and `whenComplete` keep the future's own type.
      return result
              .catchError((Object e, StackTrace s) {
                error(e, s);
                Error.throwWithStackTrace(e, s);
              })
              .whenComplete(stop)
          as T;
    }
    stop();
    return result;
  }

  @override
  String toString() => 'Observation($context)';
}

final class _NoopObservation implements Observation {
  const _NoopObservation();

  static final ObservationContext _context = ObservationContext('noop');

  @override
  ObservationContext get context => _context;

  @override
  bool get isNoop => true;

  @override
  Observation contextualName(String? name) => this;

  @override
  Observation lowCardinalityKeyValue(String key, String value) => this;

  @override
  Observation start() => this;

  @override
  Observation error(Object error, [StackTrace? stackTrace]) => this;

  @override
  void stop() {}

  @override
  T scoped<T>(T Function() body) => body();

  @override
  T observe<T>(T Function() body) => body();

  @override
  String toString() => 'Observation.noop';
}
