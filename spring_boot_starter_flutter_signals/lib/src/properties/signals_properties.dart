import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/annotations.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_buffer.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_queue.dart';

/// The followed state of the app's beans, `spring.flutter.signals.*`.
@ConfigurationProperties('spring.flutter.signals')
final class SignalsProperties {
  /// Settings with these values.
  const SignalsProperties({
    this.debug = const SignalsDebugProperties(),
    this.queue = const SignalsQueueProperties(),
    this.queues = const {},
    this.buffer = const SignalsBufferProperties(),
    this.onScopeEnd = OnScopeEnd.discard,
    this.deferTimeout = const Duration(seconds: 5),
    this.eager = false,
    this.callerBound = true,
    this.allowAdvice = false,
    this.transaction = const SignalsTransactionProperties(),
  });

  /// The state's tab of the debug panel.
  final SignalsDebugProperties debug;

  /// The default queue, which holds writes until their readers are told.
  final SignalsQueueProperties queue;

  /// More queues, by name, for `@Signal(queue: ...)`.
  final Map<String, SignalsQueueProperties> queues;

  /// The buffers of async methods.
  final SignalsBufferProperties buffer;

  /// What happens to writes not told yet when a bean's scope ends.
  final OnScopeEnd onScopeEnd;

  /// How long `on-scope-end: defer` waits for them.
  final Duration deferTimeout;

  /// Whether every signal is made with its bean rather than on first use.
  final bool eager;

  /// Whether a value computed through method security or from the current
  /// user is kept for that user only. Turning it off lets one user's value
  /// reach another.
  final bool callerBound;

  /// Whether a bean with followed state may carry advice. Read by the build
  /// too: without it, such advice is a build error.
  final bool allowAdvice;

  /// How writes behave in a transaction.
  final SignalsTransactionProperties transaction;
}

/// `spring.flutter.signals.transaction.*`.
final class SignalsTransactionProperties {
  /// Settings with these values.
  const SignalsTransactionProperties({
    this.mode = SignalTransactionMode.buffered,
  });

  /// Whether writes wait for the commit.
  final SignalTransactionMode mode;
}

/// What a `@SignalBuffer` does with the writes of a method that failed.
enum SignalBufferOnError {
  /// They are dropped.
  discard,

  /// They are told as if it had succeeded.
  publish,
}

/// `spring.flutter.signals.buffer.*`.
final class SignalsBufferProperties {
  /// Settings with these values.
  const SignalsBufferProperties({
    this.asyncMethods = false,
    this.onError = SignalBufferOnError.discard,
  });

  /// Whether every async method of a bean on signals runs in a buffer
  /// (read by the build: `@SignalBuffer(false)` takes one out).
  final bool asyncMethods;

  /// What happens to the writes of a method that failed.
  final SignalBufferOnError onError;
}

/// One queue, `spring.flutter.signals.queue.*` or
/// `spring.flutter.signals.queues.<name>.*`.
final class SignalsQueueProperties {
  /// Settings with these values.
  const SignalsQueueProperties({
    this.flush,
    this.interval = const Duration(milliseconds: 100),
    this.capacity = 1024,
    this.onOverflow = SignalOverflow.flush,
  });

  /// The built-in schedule that tells its readers; `microtask` when not
  /// set. A `SignalFlushSchedule` bean with the queue's `@Qualifier` is
  /// the other way, and both for one queue fail the start.
  final SignalFlush? flush;

  /// How often, for `flush: interval`.
  final Duration interval;

  /// How many fields may wait.
  final int capacity;

  /// What happens to one more.
  final SignalOverflow onOverflow;
}

/// The debug tools of followed state, `spring.flutter.signals.debug.*`:
/// none of them collects anything unless it is in the build and shows.
final class SignalsDebugProperties {
  /// Settings with these values.
  const SignalsDebugProperties({
    this.enabled,
    this.log = const SignalsDebugLogProperties(),
    this.readWindow = const Duration(seconds: 5),
    this.reads = true,
  });

  /// Whether the app has the Signals tab (and the activity log): `true` in
  /// every build, `false` in none (the build leaves its code out), not
  /// set in debug builds only (a release build compiles it
  /// away).
  final bool? enabled;

  /// The DEBUG log of signal activity.
  final SignalsDebugLogProperties log;

  /// The window of the read counts.
  final Duration readWindow;

  /// Whether reads are counted while a tool shows (they are the most
  /// frequent event).
  final bool reads;
}

/// The DEBUG log of signal activity, `spring.flutter.signals.debug.log.*`,
/// under the logger `spring.flutter.signals.activity`.
final class SignalsDebugLogProperties {
  /// Settings with these values.
  const SignalsDebugLogProperties({this.enabled = false, this.reads = false});

  /// Whether it logs (in the build with the Signals tab).
  final bool enabled;

  /// Whether it logs every read too.
  final bool reads;
}
