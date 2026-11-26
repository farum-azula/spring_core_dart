import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_dart/spring_boot_dart.dart'
    show SpringLog, TypeCapture;
import 'package:spring_boot_starter_flutter_signals/src/annotations.dart';
import 'package:spring_boot_starter_flutter_signals/src/follow_keeper.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_errors.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_buffer.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_probe.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_queue.dart';

const _log = SpringLog('spring.flutter.signals');

/// A generated subclass of a bean on signals.
abstract interface class SignalBeanHolder {
  /// The followed state of this bean.
  SignalBean get signalBean;

  /// Makes each followed member, by name.
  Map<String, SignalMember Function()> get signalMembers;

  /// The fields with `@Signal(eager: true)`, made with the bean.
  List<String> get eagerSignals;

  /// The queues its fields name: an unknown one fails the start.
  List<String> get signalQueues;
}

/// What the context gives its beans on signals: queues, buffers for
/// transactions, where errors go, and the defaults of the properties.
final class SignalRuntime {
  /// The runtime with these parts.
  SignalRuntime({
    required this.queues,
    SignalErrorReporter? errors,
    this.transactions,
    this.callerBound = true,
    this.eager = false,
    this.onScopeEnd = OnScopeEnd.discard,
    this.deferTimeout = const Duration(seconds: 5),
    this.allowAdvice = false,
    this.bufferPublishOnError = false,
  }) : errors = errors ?? SignalErrorReporter();

  /// The queues.
  final SignalQueues queues;

  /// Where the errors no caller waits for go.
  final SignalErrorReporter errors;

  /// The buffers of the transactions; `null` without the data starter, or
  /// with `transaction.mode: direct`.
  final SignalTransactionBuffers? transactions;

  /// `spring.flutter.signals.caller-bound`.
  final bool callerBound;

  /// `spring.flutter.signals.eager`.
  final bool eager;

  /// `spring.flutter.signals.on-scope-end`.
  final OnScopeEnd onScopeEnd;

  /// `spring.flutter.signals.defer-timeout`.
  final Duration deferTimeout;

  /// `spring.flutter.signals.allow-advice`.
  final bool allowAdvice;

  /// `spring.flutter.signals.buffer.on-error: publish`.
  final bool bufferPublishOnError;

  /// The queue of the field annotated with [options].
  SignalQueue queueOf(Signal options) => queues.of(options.queue);

  /// Runs [body] in a [SignalBuffer] with this application's
  /// `buffer.on-error`.
  Future<T> buffered<T>(Future<T> Function() body) =>
      SignalBuffer.run(body, publishOnError: bufferPublishOnError);

  /// Stops: what waits is told.
  void close() => queues.close();
}

/// One `@Effect` method of a bean: follows what its body reads, wherever
/// the advice around it runs that body (a transaction, after an `await` of
/// its own), and asks for a new run through the advice when it changes.
final class EffectFollower {
  /// The follower of the effect [name] that calls [onChange] for a new
  /// run.
  EffectFollower(this.onChange, {this.name = 'effect'});

  /// `Basket.save`: what the debug tools call it.
  final String name;

  /// The zone value that marks a run of an effect.
  static final Object zoneKey = Object();

  /// Asks for a new run.
  final void Function() onChange;

  final FollowKeeper _keeper = FollowKeeper();
  void Function()? _stop;
  bool _stopped = false;

  /// Runs [body], following what it reads until the next run.
  T track<T>(T Function() body) {
    if (_stopped) {
      return body();
    }
    _stop?.call();
    T? result;
    Object? failure;
    StackTrace? failureStack;
    var ran = false;
    _stop = signals.effect(() {
      if (ran) {
        // Still following it: the new run may be refused before its body.
        _keeper.followKept();
        signals.untracked(onChange);
        return;
      }
      ran = true;
      final probe = SignalProbes.current;
      final clock = probe == null ? null : (Stopwatch()..start());
      probe?.beginReader(this);
      try {
        result = _keeper.run(body);
        probe?.ran(this, clock!.elapsed, null);
      } on Object catch (error, stackTrace) {
        probe?.ran(this, clock!.elapsed, error);
        failure = error;
        failureStack = stackTrace;
      } finally {
        probe?.endReader();
      }
    });
    if (failure case final error?) {
      Error.throwWithStackTrace(error, failureStack!);
    }
    return result as T;
  }

  /// Whether it stopped following: its bean is closed.
  bool get stopped => _stopped;

  /// Stops following.
  void stop() {
    _stopped = true;
    _stop?.call();
    _stop = null;
  }
}

/// The followed state of one bean: its `@Signal` fields and `@Computed`
/// values as they are first used, and its running `@Effect` methods.
final class SignalBean {
  /// The state of a bean of the class [label].
  SignalBean(this.label, [this.bean]);

  /// The bean as the container hands it out (its proxy when it has one);
  /// `null` until the container has finished it.
  Object? bean;

  /// The bean's class, for the names of its members (`Basket.items`).
  final String label;

  /// The bean's name and scope in the container, once it is made
  /// (`basket`, `singleton`): for the debug tab.
  String? beanName;

  /// See [beanName].
  String? scope;

  /// What the context gives the bean; `null` while it is being made.
  SignalRuntime? runtime;

  /// The members used so far, by name.
  final Map<String, SignalMember> members = {};

  /// The `@Effect` methods, by name, with how often each ran.
  final Map<String, int> effectRuns = {};

  /// The running `@Effect` methods of this bean, by name: what the debug
  /// tools key an effect by, apart from the same effect of another bean of
  /// the class.
  final Map<String, EffectFollower> effectFollowers = {};

  final List<void Function()> _stops = [];
  final Set<ValueMember> _deferred = {};
  Timer? _deferTimer;
  bool _closed = false;

  /// Whether the bean is being destroyed: nothing is followed any more,
  /// and its members read and write the bean's own fields.
  bool get closed => _closed;

  /// The field [name], made on first use from [initial] (the field of the
  /// class).
  ValueMember field(
    String name,
    Object? Function() initial, {
    List<TypeCapture<Object?>> arguments = const [],
    String? type,
    Signal options = const Signal(),
  }) {
    final label = '${this.label}.$name';
    ValueMember member;
    try {
      member = _value(
        label,
        initial(),
        arguments: arguments,
        type: type,
        options: options,
      );
    } on Error {
      // A late field not assigned yet: reading it fails as always, and
      // its reader is told of the first assignment.
      member = _unsetValue(
        label,
        arguments: arguments,
        type: type,
        options: options,
        initial: initial,
      );
    }
    return _keep(name, member);
  }

  // A member first used once the bean is closed (a `@PreDestroy` method
  // reading it) is made closed: it reads and writes the bean's own field
  // or code, and nothing of it is left to free.
  T _keep<T extends SignalMember>(String name, T member) {
    members[name] = member;
    if (_closed) {
      member.dispose();
    }
    return member;
  }

  ValueMember _value(
    String label,
    Object? initial, {
    required List<TypeCapture<Object?>> arguments,
    required String? type,
    required Signal options,
  }) => ValueMember(
    label,
    initial,
    owner: this,
    arguments: arguments,
    type: type,
    options: options,
  );

  ValueMember _unsetValue(
    String label, {
    required List<TypeCapture<Object?>> arguments,
    required String? type,
    required Signal options,
    required Object? Function() initial,
  }) => ValueMember.unset(
    label,
    owner: this,
    arguments: arguments,
    type: type,
    options: options,
    initial: initial,
  );

  /// The value [name], made by [compute].
  ComputedMember computed(String name, Object? Function() compute) =>
      _keep(name, _computed('$label.$name', compute));

  /// The asynchronous value [name], made by [compute].
  AsyncMember asynchronous(String name, Object? Function() compute) =>
      _keep(name, _asynchronous('$label.$name', compute));

  ComputedMember _computed(String label, Object? Function() compute) =>
      ComputedMember(label, compute, owner: this);

  AsyncMember _asynchronous(String label, Object? Function() compute) =>
      AsyncMember(label, compute, owner: this);

  /// Runs [body], the bean's own `@Effect` method [method]: in a run the
  /// container started for it ([EffectFollower.zoneKey]), it follows what
  /// [body] reads, inside whatever advice runs it; called by anyone else,
  /// it is a plain call.
  T effectBody<T>(String method, T Function() body) {
    if (Zone.current[EffectFollower.zoneKey]
        case (
          final SignalBean state,
          final String name,
          final EffectFollower follower,
        )
        when identical(state, this) && name == method) {
      // A call of the same method from its own body is a plain call.
      return runZoned(
        () => follower.track(body),
        zoneValues: {EffectFollower.zoneKey: null},
      );
    }
    return body();
  }

  /// Runs [body], an async method of the bean, in a [SignalBuffer].
  Future<T> buffered<T>(Future<T> Function() body) =>
      runtime?.buffered(body) ?? SignalBuffer.run(body);

  /// A buffer that held a write of [member] ended, or handed it on with
  /// nothing left to wait for (a member whose writes were deferred past the
  /// end of the scope is then freed).
  void bufferReleased(ValueMember member) {
    if (!member.waiting) {
      _freeDeferred(member);
    }
  }

  /// Keeps [stop], which ends a running effect or watch.
  void addEffect(void Function() stop) => _stops.add(stop);

  /// A write of [member] that waited has been told.
  void memberPublished(ValueMember member) => _freeDeferred(member);

  // Frees [member] when its writes were deferred past the end of the
  // scope and none waits any more, in a queue or a buffer.
  void _freeDeferred(ValueMember member) {
    if (!_closed ||
        SignalBuffer.anyHolds(member) ||
        !_deferred.remove(member)) {
      return;
    }
    member.dispose();
    if (_deferred.isEmpty) {
      _deferTimer?.cancel();
      _deferTimer = null;
    }
  }

  /// Ends the effects and frees every member, as the fields say for the
  /// writes not told yet. The bean's own `@PreDestroy` methods run after
  /// this and still read its fields.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final stop in _stops) {
      stop();
    }
    _stops.clear();
    final discarded = <String>[];
    for (final member in members.values) {
      if (member is ValueMember &&
          (member.waiting || SignalBuffer.anyHolds(member))) {
        switch (member.options.onScopeEnd ?? runtime?.onScopeEnd) {
          case OnScopeEnd.flush:
            SignalBuffer.release(member, publish: true);
            member.waitingIn?.flushMember(member);
          case OnScopeEnd.defer:
            _deferred.add(member);
            continue;
          case OnScopeEnd.discard:
          case null:
            SignalBuffer.release(member, publish: false);
            member.waitingIn?.forget(member);
            member.dropPending();
            discarded.add(member.name);
        }
      }
      member.dispose();
    }
    if (discarded.isNotEmpty) {
      _log.warning(
        'The scope of $label ended with writes not told yet: '
        '${discarded.join(', ')} went back to their last told value '
        '(on-scope-end: discard).',
      );
    }
    if (_deferred.isNotEmpty) {
      _deferTimer = Timer(
        runtime?.deferTimeout ?? const Duration(seconds: 5),
        _discardDeferred,
      );
    }
  }

  void _discardDeferred() {
    final names = [for (final member in _deferred) member.name];
    for (final member in _deferred) {
      SignalBuffer.release(member, publish: false);
      member.waitingIn?.forget(member);
      member.dropPending();
      member.dispose();
    }
    _deferred.clear();
    if (names.isNotEmpty) {
      _log.warning(
        'The writes of ${names.join(', ')} were not told within '
        'defer-timeout after the scope of $label ended: discarded.',
      );
    }
  }
}

/// A [SignalBean] whose members the debug tools hear of: what the
/// generated subclass of a bean makes when a debug tool of the signals is
/// in the application's build (`spring.flutter.signals.debug.enabled`,
/// `debug.overlay.enabled`), behind a constant the compiler folds, so an
/// application without one has neither this class nor a probe call.
final class ProbedSignalBean extends SignalBean {
  /// The state of a bean of the class [label].
  ProbedSignalBean(super.label, [super.bean]);

  @override
  ValueMember _value(
    String label,
    Object? initial, {
    required List<TypeCapture<Object?>> arguments,
    required String? type,
    required Signal options,
  }) => ProbedValueMember(
    label,
    initial,
    owner: this,
    arguments: arguments,
    type: type,
    options: options,
  );

  @override
  ValueMember _unsetValue(
    String label, {
    required List<TypeCapture<Object?>> arguments,
    required String? type,
    required Signal options,
    required Object? Function() initial,
  }) => ProbedValueMember.unset(
    label,
    owner: this,
    arguments: arguments,
    type: type,
    options: options,
    initial: initial,
  );

  @override
  ComputedMember _computed(String label, Object? Function() compute) =>
      ProbedComputedMember(label, compute, owner: this);

  @override
  AsyncMember _asynchronous(String label, Object? Function() compute) =>
      ProbedAsyncMember(label, compute, owner: this);
}

/// Calls a method when the members it lists get their first watcher or
/// lose their last one (`@OnWatched`, `@OnUnwatched`).
final class SignalWatch {
  /// The watch of [members] calling [call] when they get a watcher
  /// ([onWatched]) or lose it.
  SignalWatch({
    required List<SignalMember> members,
    required this.onWatched,
    required this.each,
    required this.delay,
    required this.call,
  }) {
    for (final member in members) {
      member.addWatcher((watched) => _changed(member, watched));
    }
  }

  /// Whether the method is for getting a watcher, not losing it.
  final bool onWatched;

  /// Whether each member counts on its own.
  final bool each;

  /// How long the state must last before the call.
  final Duration delay;

  /// Calls the method.
  final void Function() call;

  final Set<SignalMember> _watching = {};
  final Map<Object, bool> _active = {};
  final Map<Object, int> _attempts = {};
  final Map<Object, Timer> _timers = {};
  bool _stopped = false;

  void _changed(SignalMember member, bool watched) {
    if (_stopped) {
      return;
    }
    if (watched) {
      _watching.add(member);
    } else {
      _watching.remove(member);
    }
    final Object key = each ? member : this;
    final active = each ? watched : _watching.isNotEmpty;
    if (_active[key] == active) {
      return;
    }
    _active[key] = active;
    final attempt = _attempts[key] = (_attempts[key] ?? 0) + 1;
    _timers.remove(key)?.cancel();
    if (active != onWatched) {
      return;
    }
    // Losing a watcher may be a rebuild that takes it back in this frame.
    _afterSettling(() {
      if (_stopped || _attempts[key] != attempt) {
        return;
      }
      if (delay == Duration.zero) {
        call();
      } else {
        _timers[key] = Timer(delay, () {
          if (!_stopped && _attempts[key] == attempt) {
            call();
          }
        });
      }
    });
  }

  void _afterSettling(void Function() body) {
    if (onWatched) {
      scheduleMicrotask(body);
      return;
    }
    SchedulerBinding? binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object {
      binding = null;
    }
    if (binding != null && binding.schedulerPhase != SchedulerPhase.idle) {
      binding.addPostFrameCallback((_) => body());
    } else {
      scheduleMicrotask(body);
    }
  }

  /// Stops calling.
  void stop() {
    _stopped = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// Every bean with followed state that lives now: what the debug tab
/// reads. It notifies its listeners when a bean comes or goes, not for a
/// change of state.
final class SignalBeans extends ChangeNotifier {
  /// The state of the context's beans; what depends on the caller is told
  /// when the caller changes ([CallerFollowing]).
  SignalBeans() {
    CallerFollowing.install();
  }

  final Expando<SignalBean> _states = Expando('signal beans');

  // Held weakly: the container never destroys a prototype, so its state
  // must go when the last reference to the bean does.
  final List<WeakReference<SignalBean>> _live = [];

  // How many beans were kept since the references whose state is gone were
  // last dropped.
  int _addedSincePrune = 0;

  // Every this many new beans the references whose state is gone are
  // dropped, so that prototypes made without end keep no list growing.
  static const _pruneEvery = 64;

  /// The beans with followed state, in the order they were made. A
  /// prototype nobody holds any more is no longer among them.
  Iterable<SignalBean> get live {
    _pruneDead();
    return [for (final reference in _live) ?reference.target];
  }

  /// How many states it keeps a reference to, those nobody holds that are
  /// not dropped yet included.
  @visibleForTesting
  int get keptStates => _live.length;

  void _pruneDead() {
    _addedSincePrune = 0;
    _live.removeWhere((reference) => reference.target == null);
  }

  /// Keeps [state], the state of [bean] as the container hands it out.
  SignalBean adopt(Object bean, SignalBean state, SignalRuntime runtime) {
    state
      ..bean = bean
      ..runtime = runtime;
    _states[bean] = state;
    if (++_addedSincePrune >= _pruneEvery) {
      _pruneDead();
    }
    _live.add(WeakReference(state));
    _changed();
    return state;
  }

  /// The state of [bean], `null` when it has none.
  SignalBean? find(Object bean) => _states[bean];

  /// Ends the state of [bean] when it is destroyed.
  void close(Object bean) {
    final state = _states[bean];
    if (state == null) {
      return;
    }
    state.close();
    _live.removeWhere(
      (reference) => reference.target == null || reference.target == state,
    );
    _changed();
  }

  bool _scheduled = false;
  bool _disposed = false;

  // Beans come and go while widgets are built: the listeners hear after,
  // unless the context closed meanwhile.
  void _changed() {
    if (_scheduled || _disposed) {
      return;
    }
    _scheduled = true;
    Future.microtask(() {
      _scheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
