/// One step of the application's start, measured: created by
/// [ApplicationStartup.start], tagged with what it is about, ended with
/// [end].
///
/// ```dart
/// final step = startup.start('spring.beans.instantiate')
///   ..tag('beanName', 'catalog');
/// // ... create the bean ...
/// step.end();
/// ```
///
/// Spring (Java): `org.springframework.core.metrics.StartupStep`.
abstract interface class StartupStep {
  /// The step's name, dotted (`spring.beans.instantiate`).
  String get name;

  /// The step's number, unique for the start.
  int get id;

  /// The number of the step that was running when this one began; `null`
  /// at the top.
  int? get parentId;

  /// Adds a tag (`beanName` = `catalog`) and returns this step.
  StartupStep tag(String key, Object? value);

  /// The tags, in the order they were added.
  List<(String, Object?)> get tags;

  /// Ends the step; a second call does nothing.
  void end();
}

/// Where the steps of the start go: none by default, so measuring costs
/// nothing until an application chooses a startup that records them
/// ([BufferingApplicationStartup], or one of its own that logs or sends
/// them).
///
/// The framework starts steps around the work of the start (the
/// environment, the context's refresh, each bean's creation); an
/// application or a library adds its own the same way.
///
/// Spring (Java): `org.springframework.core.metrics.ApplicationStartup`.
abstract interface class ApplicationStartup {
  /// The startup that records nothing; the default.
  static const ApplicationStartup none = _NoStartup();

  /// Starts the step [name]; end it with [StartupStep.end].
  StartupStep start(String name);
}

final class _NoStartup implements ApplicationStartup {
  const _NoStartup();

  @override
  StartupStep start(String name) => const _NoStep();
}

final class _NoStep implements StartupStep {
  const _NoStep();

  @override
  String get name => '';

  @override
  int get id => 0;

  @override
  int? get parentId => null;

  @override
  StartupStep tag(String key, Object? value) => this;

  @override
  List<(String, Object?)> get tags => const [];

  @override
  void end() {}
}

/// A step that [BufferingApplicationStartup] recorded: when it began and
/// how long it ran.
final class RecordedStartupStep implements StartupStep {
  RecordedStartupStep._(
    this.name,
    this.id,
    this.parentId,
    this.startedAt,
    this._owner,
  );

  @override
  final String name;

  @override
  final int id;

  @override
  final int? parentId;

  /// When the step began, from the start of the startup.
  final Duration startedAt;

  /// How long it ran; `null` while it runs.
  Duration? duration;

  final BufferingApplicationStartup _owner;

  final _tags = <(String, Object?)>[];

  @override
  List<(String, Object?)> get tags => List.unmodifiable(_tags);

  @override
  StartupStep tag(String key, Object? value) {
    _tags.add((key, value));
    return this;
  }

  @override
  void end() {
    if (duration != null) {
      return;
    }
    duration = _owner._clock() - startedAt;
    _owner._ended(this);
  }

  @override
  String toString() {
    final tagged = [for (final (key, value) in _tags) '$key=$value'];
    return [
      name,
      ...tagged,
      '${duration?.inMilliseconds ?? '…'} ms',
    ].join(' ');
  }
}

/// Records the steps of the start, up to [capacity], for a report, a log
/// or a test: [steps] in the order they began. [onEnd] is told each step
/// that ends (a listener that logs it, marks it in the browser's
/// performance timeline).
///
/// ```dart
/// final startup = BufferingApplicationStartup(
///   onEnd: (step) => log.info('$step'),
/// );
/// final app = SpringApplication([appBeans], applicationStartup: startup);
/// ```
///
/// Spring (Java): `BufferingApplicationStartup` of Spring Boot.
class BufferingApplicationStartup implements ApplicationStartup {
  /// A startup keeping at most [capacity] steps; [clock] is for tests.
  BufferingApplicationStartup({
    this.capacity = 10000,
    this.onEnd,
    Duration Function()? clock,
  }) : _clock = clock ?? _stopwatch();

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// The most steps kept; the later ones are not recorded.
  final int capacity;

  /// Told each step that ends.
  final void Function(RecordedStartupStep step)? onEnd;

  final Duration Function() _clock;
  final _steps = <RecordedStartupStep>[];
  final _running = <RecordedStartupStep>[];
  var _next = 1;

  /// The steps, in the order they began.
  List<RecordedStartupStep> get steps => List.unmodifiable(_steps);

  @override
  StartupStep start(String name) {
    if (_steps.length >= capacity) {
      return ApplicationStartup.none.start(name);
    }
    final step = RecordedStartupStep._(
      name,
      _next++,
      _running.lastOrNull?.id,
      _clock(),
      this,
    );
    _steps.add(step);
    _running.add(step);
    return step;
  }

  /// Records a step that already ran, from [startedAt] for [duration], at
  /// the top (not inside a running step), with [tags]: what happened before
  /// the startup existed, or a moment (an event) of no length. [steps]
  /// stay in the order they began.
  RecordedStartupStep? record(
    String name, {
    required Duration startedAt,
    Duration duration = Duration.zero,
    List<(String, Object?)> tags = const [],
  }) {
    if (_steps.length >= capacity) {
      return null;
    }
    final step = RecordedStartupStep._(name, _next++, null, startedAt, this)
      ..duration = duration;
    step._tags.addAll(tags);
    var at = _steps.length;
    while (at > 0 && _steps[at - 1].startedAt > startedAt) {
      at--;
    }
    _steps.insert(at, step);
    onEnd?.call(step);
    return step;
  }

  void _ended(RecordedStartupStep step) {
    _running.remove(step);
    onEnd?.call(step);
  }
}
