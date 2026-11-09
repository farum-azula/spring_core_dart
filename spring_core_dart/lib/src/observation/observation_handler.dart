/// What an [ObservationHandler] is told about one observation: its name,
/// tags, timing, error and parent.
///
/// The observation fills it in as it runs: [startedAt] when it starts,
/// [error] when the work fails, [duration] when it stops. A handler may
/// add tags in `onStart` (they are seen by the handlers after it).
///
/// Spring (Java): `io.micrometer.observation.Observation.Context`.
class ObservationContext {
  /// A context for the observation [name] (`http.client.requests`); [id]
  /// is unique within its registry, [parent] is the context of the
  /// observation it runs in.
  ObservationContext(
    this.name, {
    this.id = 0,
    this.parent,
    this.contextualName,
    Map<String, String> lowCardinalityKeyValues = const {},
  }) : lowCardinalityKeyValues = {...lowCardinalityKeyValues};

  /// The observation's name, dotted (`method.observed`): the same for
  /// every call of the same kind, so measurements can be grouped by it.
  final String name;

  /// The observation's number, unique within its registry; 0 for one made
  /// by hand.
  final int id;

  /// The context of the observation this one runs in; `null` at the top.
  final ObservationContext? parent;

  /// A readable name for this one call (`OrderService#place`), shown by a
  /// trace or a timeline; `null` when there is none.
  String? contextualName;

  /// Tags with few possible values (`class` = `OrderService`), in the
  /// order they were added.
  final Map<String, String> lowCardinalityKeyValues;

  /// When the observation started, on its registry's clock; `null` before
  /// it starts.
  Duration? startedAt;

  /// How long it ran; `null` while it runs.
  Duration? duration;

  /// What the observed work threw; `null` when it did not fail.
  Object? error;

  /// Where [error] was thrown.
  StackTrace? stackTrace;

  /// Whether the observation started and has not stopped.
  bool get isRunning => startedAt != null && duration == null;

  @override
  String toString() => [
    contextualName ?? name,
    for (final MapEntry(:key, :value) in lowCardinalityKeyValues.entries)
      '$key=$value',
    if (error != null) 'error=$error',
    '${duration?.inMicroseconds ?? '…'} µs',
  ].join(' ');
}

/// Told when an observation starts, fails and stops: it turns
/// observations into something (a log line, a metric, a span of a trace,
/// a bar of a debug timeline).
///
/// Every method does nothing by default; extend it and override what you
/// need. [supportsContext] picks the observations the handler is told
/// about; it is asked once, when the observation is created.
///
/// ```dart
/// // Logs every observation that takes longer than 100 ms.
/// class SlowCallLogger extends ObservationHandler {
///   @override
///   void onStop(ObservationContext context) {
///     if (context.duration! > const Duration(milliseconds: 100)) {
///       log.warning('slow: $context');
///     }
///   }
/// }
///
/// final registry = ObservationRegistry(handlers: [SlowCallLogger()]);
/// ```
///
/// Spring (Java): `io.micrometer.observation.ObservationHandler`.
abstract class ObservationHandler {
  /// Constant constructor for subclasses.
  const ObservationHandler();

  /// Whether the handler wants to hear about the observation [context];
  /// `true` by default.
  bool supportsContext(ObservationContext context) => true;

  /// The observation started: [ObservationContext.startedAt] is set.
  void onStart(ObservationContext context) {}

  /// The observed work threw: [ObservationContext.error] is set. Called
  /// before [onStop].
  void onError(ObservationContext context) {}

  /// The observation stopped: [ObservationContext.duration] is set.
  void onStop(ObservationContext context) {}
}
