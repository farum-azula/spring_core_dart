import 'dart:async';
import 'dart:collection';

import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_dart/spring_boot_dart.dart'
    show CallerBoundReads, DerivedFutures, SecretNames, TypeCapture;
import 'package:spring_boot_starter_flutter_signals/src/annotations.dart';
import 'package:spring_boot_starter_flutter_signals/src/async_value.dart';
import 'package:spring_boot_starter_flutter_signals/src/follow_keeper.dart';
import 'package:spring_boot_starter_flutter_signals/src/followed_collections.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_buffer.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_probe.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_queue.dart';

/// Runs [body] and throws what the bean's own code threw (in a computed
/// value, or in an effect run by a change), not the wrapper the signals
/// package puts around it: callers catch what they would without followed
/// state.
T unwrapped<T>(T Function() body) {
  try {
    return body();
  } on signals.SignalEffectException catch (wrapped) {
    final error = wrapped.error;
    if (error == null) {
      rethrow;
    }
    Error.throwWithStackTrace(error, wrapped.stackTrace ?? StackTrace.current);
  }
}

/// Makes every reader of something that depends on the caller (a security
/// decision, the current user) follow the caller: when the program's user
/// changes, what was built for the one before is built again.
abstract final class CallerFollowing {
  static final signals.Signal<int> _caller = signals.signal<int>(0);
  static bool _installed = false;

  static void _follow() => _caller.value;

  /// Makes the reader of the moment follow the caller: it is told when the
  /// program's user changes.
  static void follow() => _onRead();

  static void _onRead() {
    if (FollowKeeper.isNoting) {
      FollowKeeper.note(_follow);
    }
    _caller.value;
  }

  static void _onChange() => signals.untracked(
    () => _caller.value = _caller.peek() + 1,
  );

  /// Starts following; once for the program.
  static void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    CallerBoundReads.observe(onRead: _onRead, onChange: _onChange);
  }
}

/// One followed member of a bean: a `@Signal` field or a `@Computed`
/// value, by its name (`basket.items`).
sealed class SignalMember {
  /// The member called [name], of the bean [owner] when it has one.
  SignalMember(this.name, {this.owner});

  /// The bean's name and the member's: `basket.items`.
  final String name;

  /// The state of the bean this member belongs to; `null` for a member
  /// made on its own.
  final SignalBean? owner;

  final List<void Function(bool watched)> _watchers = [];

  /// Calls [watcher] with `true` when the member gets its first reader,
  /// and `false` when it loses its last one.
  void addWatcher(void Function(bool watched) watcher) =>
      _watchers.add(watcher);

  void _watched() {
    for (final watcher in _watchers) {
      watcher(true);
    }
  }

  void _unwatched() {
    for (final watcher in _watchers) {
      watcher(false);
    }
  }

  /// Whether the member's own name looks like it holds a secret
  /// (`SecretNames.looksSecret`: `accessToken`, `password`): its value
  /// is kept out of the debug tab and the log, as `hidden: true` keeps it.
  bool get secret => SecretNames.looksSecret(name.split('.').last);

  /// Whether it was disposed: its bean is closed, and nothing of it is
  /// followed any more.
  bool get disposed;

  /// Stops following; reads after it go to the bean's own field.
  void dispose();
}

/// A `@Signal` field. It holds the value, and a counter its readers follow:
/// an assignment changes the value at once, and the counter when its
/// queue tells the readers.
///
/// A `List`, `Set`, `Map` or `Queue` is handed out as a collection that
/// also tells its readers of a change in place (`items.add(book)`).
final class ValueMember extends SignalMember {
  /// The field [name], now holding [initial]; [arguments] are the type
  /// arguments of its type as the generator wrote them (the element type
  /// of a list), empty when it has none, and [type] is the name of that
  /// type (`List`): a collection is followed in place when the field is
  /// declared as a `List`, `Set`, `Map` or `Queue` itself, not as a class
  /// of its own that is one (a `HashSet`, an `UnmodifiableListView`),
  /// which the follower could not stand for. Without [type] the value
  /// decides.
  ValueMember(
    super.name,
    Object? initial, {
    super.owner,
    List<TypeCapture<Object?>> arguments = const [],
    String? type,
    bool hidden = false,
    this.options = const Signal(),
  }) : _hidden = hidden || options.hidden,
       _initial = null,
       _arguments = _followable(arguments, type, options) {
    _raw = initial;
    _view = _followed(initial);
  }

  /// The `late` field [name], read before it was first assigned: there is
  /// no value yet, and whoever read it ([follow]) is told when there is.
  ValueMember.unset(
    super.name, {
    super.owner,
    List<TypeCapture<Object?>> arguments = const [],
    String? type,
    bool hidden = false,
    this.options = const Signal(),
    // ignore: prefer_initializing_formals, named parameters cannot be private
    Object? Function()? initial,
  }) : _hidden = hidden || options.hidden,
       _arguments = _followable(arguments, type, options),
       // ignore: prefer_initializing_formals
       _initial = initial,
       _unset = true;

  static const _followedTypes = {'List', 'Set', 'Map', 'Queue'};

  static List<TypeCapture<Object?>> _followable(
    List<TypeCapture<Object?>> arguments,
    String? type,
    Signal options,
  ) =>
      options.followCollection &&
          (type == null || _followedTypes.contains(type))
      ? arguments
      : const [];

  /// What the annotation of the field says.
  final Signal options;

  final List<TypeCapture<Object?>> _arguments;

  // Raises what the readers follow: the value itself is in [_view].
  late final signals.Signal<int> _ticks = signals.signal<int>(
    0,
    options: signals.SignalOptions<int>(
      name: name,
      watched: _watched,
      unwatched: _unwatched,
    ),
  );

  Object? _raw;
  Object? _view;
  bool _unset = false;
  bool _closed = false;
  final Object? Function()? _initial;

  // A write waits in [_queue]: what the readers were last told.
  bool _waiting = false;
  Object? _toldRaw;
  Object? _toldView;
  bool _toldUnset = false;
  SignalQueue? _queue;

  /// Whether the field is a `late` one that was read but never assigned.
  bool get unset => _unset;

  /// Whether a write waits to be told.
  bool get waiting => _waiting;

  /// The queue the write waits in.
  SignalQueue? get waitingIn => _waiting ? _queue : null;

  /// Tells the reader of the first assignment of a field that is [unset].
  void follow() {
    if (FollowKeeper.isNoting) {
      FollowKeeper.note(_refollow);
    }
    _ticks.value;
  }

  void _follow() => _ticks.value;

  // The same function each time, not one made for each read.
  late final void Function() _refollow = _follow;

  /// Whether the value is kept out of the debug tab and the log:
  /// `@Signal(hidden: true)`, or a field whose name looks secret ([secret]).
  late final bool hidden = _hidden || secret;

  final bool _hidden;

  /// How often the field was assigned a new value.
  int changes = 0;

  /// The value as the bean's readers get it; the reader is told of the
  /// next assignment (and, for a collection, of a change in place). In a
  /// buffer, the value it wrote.
  Object? read() {
    if (_closed) {
      return _view;
    }
    if (FollowKeeper.isNoting) {
      FollowKeeper.note(_refollow);
    }
    _ticks.value;
    final transactions = owner?.runtime?.transactions;
    if (transactions != null || SignalBuffer.open != 0) {
      // A collection is copied by the buffer that reads it, so that a
      // change in place stays there: it has to ask, also with no write.
      if (_view is FollowedCollection) {
        if (SignalBuffer.forWrite(transactions) case final buffer?) {
          return buffer.copyOnWrite(this);
        }
      } else if (SignalBuffer.forRead(transactions) case final buffer?
          when buffer.holds(this)) {
        return buffer.read(this);
      }
    }
    if (_unset) {
      return _initial?.call();
    }
    return _view;
  }

  /// [read] for a field with `queued: false`: no buffer to look for.
  Object? readDirect() {
    if (_closed) {
      return _view;
    }
    if (FollowKeeper.isNoting) {
      FollowKeeper.note(_refollow);
    }
    _ticks.value;
    if (_unset) {
      return _initial?.call();
    }
    return _view;
  }

  /// The value the field itself holds, without the reader being told of
  /// anything.
  Object? peek() => _raw;

  /// The value to keep for the assignment of [value]: what [read] handed
  /// out stands for the collection it follows (`items = items..add(book)`
  /// assigns the same list again).
  Object? unwrap(Object? value) =>
      value != null && identical(value, _view) ? _raw : value;

  /// The assignment of [value], through the buffer of the moment and the
  /// field's queue.
  void write(Object? value) {
    final raw = unwrap(value);
    if (_closed) {
      _keep(raw);
      return;
    }
    final runtime = owner?.runtime;
    final transactions = runtime?.transactions;
    if (transactions != null || SignalBuffer.open != 0) {
      if (SignalBuffer.forWrite(transactions) case final buffer?) {
        buffer.write(this, raw);
        return;
      }
    }
    _toQueue(raw, runtime);
  }

  // The write of [raw] through the field's queue.
  void _toQueue(Object? raw, SignalRuntime? runtime) {
    final queue = runtime?.queueOf(options);
    if (queue == null || queue.isImmediate) {
      writeDirect(raw);
      return;
    }
    if (!queue.admit(this)) {
      return;
    }
    final told = (_raw, _view, _unset);
    if (!_keep(raw)) {
      return;
    }
    if (!_waiting) {
      _waiting = true;
      _queue = queue;
      _toldRaw = told.$1;
      _toldView = told.$2;
      _toldUnset = told.$3;
    }
    queue.enqueue(this);
  }

  /// The assignment of [value], told at once.
  void writeDirect(Object? value) {
    final raw = unwrap(value);
    if (_keep(raw) && !_closed) {
      _tell();
    }
  }

  // Keeps [raw]; whether it is a change the readers are to be told of.
  bool _keep(Object? raw) {
    if (!_unset && identical(raw, _raw)) {
      return false;
    }
    final changed = _unset || !_sameValue(_raw, raw);
    if (changed) {
      changes++;
    }
    _unset = false;
    _raw = raw;
    _view = _followed(raw);
    return changed;
  }

  bool _sameValue(Object? previous, Object? next) =>
      options.equals?.call(previous, next) ?? previous == next;

  void _tell() => _ticks.value = _ticks.peek() + 1;

  /// Tells the readers of the write that waited.
  void publishPending() {
    if (!_waiting) {
      return;
    }
    _clearWaiting();
    if (!_closed) {
      _tell();
    }
    owner?.memberPublished(this);
  }

  /// Forgets the write that waited: the field has its last told value.
  void dropPending() {
    if (!_waiting) {
      return;
    }
    _raw = _toldRaw;
    _view = _toldView;
    _unset = _toldUnset;
    _clearWaiting();
  }

  void _clearWaiting() {
    _waiting = false;
    _toldRaw = null;
    _toldView = null;
    _queue = null;
  }

  /// [raw] as a buffer's code gets it.
  Object? viewOf(Object? raw) => _followed(raw);

  /// A copy of the collection for a buffer, and what hands it out.
  (Object?, Object?) bufferCopy() {
    final copy = switch (_raw) {
      final List<Object?> list => list.toList(),
      final Set<Object?> set => set.toSet(),
      final Queue<Object?> queue => queue.toList(),
      final Map<Object?, Object?> map => {...map},
      final other => other,
    };
    final raw = _retyped(copy);
    return (raw, _followed(raw));
  }

  // The copy with the element types of the field.
  Object? _retyped(Object? copy) => switch ((copy, _arguments)) {
    (final List<Object?> list, [final element]) when _raw is! Queue =>
      element.run(<E>() => list.cast<E>().toList()),
    (final List<Object?> list, [final element]) => element.run(
      <E>() => ListQueue<E>.of(list.cast<E>()),
    ),
    (final Set<Object?> set, [final element]) => element.run(
      <E>() => set.cast<E>().toSet(),
    ),
    (final Map<Object?, Object?> map, [final key, final content]) => key.run(
      <K>() => content.run(<V>() => map.cast<K, V>().map(MapEntry<K, V>.new)),
    ),
    _ => copy,
  };

  /// The value a buffer held for the field, handed to its queue when the
  /// buffer ends.
  void publishFromBuffer(Object? raw) {
    if (_closed) {
      _keep(raw);
      bufferDropped();
      return;
    }
    _toQueue(raw, owner?.runtime);
    // Told at once (an immediate queue), nothing to tell (the same value)
    // or refused by a full queue: no write of it waits any more.
    if (!_waiting) {
      bufferDropped();
    }
  }

  /// A buffer that held a value of the field ended without telling it.
  void bufferDropped() => owner?.bufferReleased(this);

  // [value] as it is handed out: a collection that follows its own
  // changes, when it is one and its element types are known.
  Object? _followed(Object? value) {
    final name = this.name;
    return switch ((value, _arguments)) {
      (final List<Object?> list, [final element]) => element.run(
        <E>() => FollowedList<E>(list as List<E>, name),
      ),
      (final Set<Object?> set, [final element]) => element.run(
        <E>() => FollowedSet<E>(set as Set<E>, name),
      ),
      (final Queue<Object?> queue, [final element]) => element.run(
        <E>() => FollowedQueue<E>(queue as Queue<E>, name),
      ),
      (final Map<Object?, Object?> map, [final key, final content]) => key.run(
        <K>() => content.run(
          <V>() => FollowedMap<K, V>(map as Map<K, V>, name),
        ),
      ),
      _ => value,
    };
  }

  @override
  bool get disposed => _closed;

  @override
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_view case final FollowedCollection collection) {
      collection.disposeFollower();
    }
    // From now on the plain value: nothing is followed.
    _view = _raw;
    _ticks.dispose();
  }
}

// What a computed value keeps in place of a value when its computation
// threw. The same one stands for the same failure again, so a value that
// fails as it did before tells its readers of no change.
final class _Failure {
  _Failure(this.error, this.stackTrace);

  Object error;
  StackTrace stackTrace;

  bool isLike(Object other) =>
      other.runtimeType == error.runtimeType && '$other' == '$error';
}

/// A `@Computed` value: computed once, kept until something it read
/// changes.
///
/// A computation that throws is not kept: the reader of the moment gets
/// the error, and the next read computes again (what it failed for may be
/// the caller, as a refused one, and not the state). It still follows
/// what it followed before it failed.
///
/// A value whose computation depended on the caller (it crossed method
/// security, or read the current user) is kept for that caller only:
/// anyone else gets a computation of their own, and it is computed again
/// when the program's user changes.
final class ComputedMember extends SignalMember {
  /// The value [name], computed by [compute].
  ComputedMember(super.name, Object? Function() compute, {super.owner})
    : _compute = compute;

  final Object? Function() _compute;
  final FollowKeeper _keeper = FollowKeeper();
  _Failure? _failure;

  // What the computation last gave (a value or a [_Failure]), kept as a
  // plain field for the reads after [dispose].
  Object? _last;
  bool _disposed = false;

  // Whose value is kept; `null` when it depends on nobody.
  List<Object?>? _caller;

  // The bean's code for the value, run by the computation.
  Object? _evaluate() => _keeper.run(_compute);

  /// How many computations run now: a flush cannot happen inside one, a
  /// computed value must not change state.
  static int evaluating = 0;

  /// How often the value was computed.
  int computations = 0;

  /// Whether the kept value belongs to one caller.
  bool get callerBound => _caller != null;

  // Raised to compute again after a failure.
  late final signals.Signal<int> _retry = signals.signal<int>(0);

  late final signals.Computed<Object?> _computed = signals.computed<Object?>(
    () {
      _retry.value;
      final readsBefore = CallerBoundReads.reads;
      computations++;
      evaluating++;
      try {
        final value = _evaluate();
        _failure = null;
        _caller = _ownerAfter(readsBefore);
        return _last = value;
      } on Object catch (error, stackTrace) {
        _caller = null;
        final thrown = error is signals.SignalEffectException
            ? error.error ?? error
            : error;
        final trace = error is signals.SignalEffectException
            ? error.stackTrace ?? stackTrace
            : stackTrace;
        final before = _failure;
        if (before != null && before.isLike(thrown)) {
          return _last = before
            ..error = thrown
            ..stackTrace = trace;
        }
        return _last = _failure = _Failure(thrown, trace);
      } finally {
        evaluating--;
      }
    },
    options: signals.ComputedOptions<Object?>(
      name: name,
      watched: _watched,
      unwatched: _unwatched,
    ),
  );

  // What an earlier write still waits to tell, seen before this read; in
  // a buffer that wrote, its own value, never kept for anyone else.
  bool get _readsOwnWrites {
    final runtime = owner?.runtime;
    if (runtime == null) {
      return false;
    }
    if (SignalQueue.pendingWrites != 0 && evaluating == 0) {
      runtime.queues.flushBeforeRead();
    }
    return SignalBuffer.forRead(runtime.transactions)?.hasWrites ?? false;
  }

  /// The value; the reader is told when it is computed again. Fails with
  /// what the computation threw. After [dispose], the last value, with
  /// nothing followed.
  Object? read() {
    if (_disposed) {
      return _closedRead();
    }
    if (_readsOwnWrites) {
      return unwrapped(() => signals.untracked(_compute));
    }
    if (FollowKeeper.isNoting) {
      FollowKeeper.note(_resubscribe);
    }
    _retryAfterFailure();
    final value = unwrapped(() => _computed.value);
    _announceFirst();
    final caller = _caller;
    if (caller == null) {
      return _valueOf(value);
    }
    CallerBoundReads.noteRead();
    return CallerBoundReads.isCurrent(caller)
        ? _valueOf(value)
        : unwrapped(_compute);
  }

  /// The value, without the reader being told of anything. Fails with
  /// what the computation threw.
  Object? peek() {
    if (_disposed) {
      return _closedRead();
    }
    if (_readsOwnWrites) {
      return unwrapped(() => signals.untracked(_compute));
    }
    _retryAfterFailure();
    final value = unwrapped(_computed.peek);
    final caller = _caller;
    return caller == null || CallerBoundReads.isCurrent(caller)
        ? _valueOf(value)
        : unwrapped(() => signals.untracked(_compute));
  }

  /// Follows what the last computation read, for a read that advice
  /// answered without computing (a cache hit) or refused.
  ///
  /// Refused before the value was ever computed, the reader cannot follow
  /// what it is made of: it is told when the user changes, and when the
  /// value is first computed by a caller who may read it; from then on it
  /// follows what the value reads.
  void followLast() {
    if (_disposed) {
      return;
    }
    if (_keeper.hasKept) {
      _keeper.followKept();
      return;
    }
    _firstComputed.value;
    CallerFollowing.follow();
  }

  // Raised once, after the first computation: what refused readers wait
  // for. Raised in a microtask, as a reader may itself be computing.
  late final signals.Signal<int> _firstComputed = signals.signal<int>(0);
  bool _announced = false;

  void _announceFirst() {
    if (_announced || computations == 0 || _failure != null) {
      return;
    }
    _announced = true;
    scheduleMicrotask(() {
      if (!_firstComputed.disposed) {
        _firstComputed.value = 1;
      }
    });
  }

  // Who the value just computed belongs to; nobody when the application
  // turned it off (`spring.flutter.signals.caller-bound: false`).
  List<Object?>? _ownerAfter(int readsBefore) {
    if (!(owner?.runtime?.callerBound ?? true)) {
      return null;
    }
    return CallerBoundReads.reads == readsBefore
        ? null
        : CallerBoundReads.capture();
  }

  void _subscribe() => _computed.value;

  // The same function each time, not one made for each read.
  late final void Function() _resubscribe = _subscribe;

  // A failure is not kept: this read computes again.
  void _retryAfterFailure() {
    if (_failure != null) {
      signals.untracked(() => _retry.value = _retry.peek() + 1);
    }
  }

  static Object? _valueOf(Object? value) => value is _Failure
      ? Error.throwWithStackTrace(value.error, value.stackTrace)
      : value;

  /// Computes the value again though nothing it read has changed.
  void recompute() {
    if (!_disposed) {
      _computed.recompute();
    }
  }

  // A read once the bean is closed: the last value, without a signal read
  // or written. The bean's own code answers when there is none to give: it
  // was never computed, it failed (a failure is not kept), or it was
  // computed for another caller.
  Object? _closedRead() {
    final caller = _caller;
    if (computations == 0 ||
        _last is _Failure ||
        (caller != null && !CallerBoundReads.isCurrent(caller))) {
      return unwrapped(() => signals.untracked(_compute));
    }
    return _last;
  }

  @override
  bool get disposed => _disposed;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _computed.dispose();
    _retry.dispose();
    _firstComputed.dispose();
  }
}

/// A `@Computed` value that is a `Future` or a `Stream`: the future or
/// stream itself (made again when what it read before its first `await`
/// changes), and where it is: loading, the data, the error.
///
/// What runs after an `await` cannot be watched, so a load is always kept
/// for the caller it was made for: another caller loads again.
final class AsyncMember extends ComputedMember {
  /// The asynchronous value [name], made by [compute].
  AsyncMember(super.name, super.compute, {super.owner})
    : _state = signals.signal<AsyncValue<Object?>>(
        const AsyncValue.loading(),
        options: signals.SignalOptions<AsyncValue<Object?>>(
          name: '$name.state',
        ),
      );

  /// The member behind [source], a future or stream a `@Computed` getter
  /// gave; `null` for any other.
  static AsyncMember? of(Object source) => _members[source];

  static final Expando<AsyncMember> _members = Expando('signal members');

  /// Makes [source], the future advice hands out for this value, one whose
  /// state is this member's.
  void bind(Future<Object?> source) => _members[source] ??= this;

  final signals.Signal<AsyncValue<Object?>> _state;
  // What [_state] holds, as a plain field: read after [dispose].
  AsyncValue<Object?> _stateNow = const AsyncValue.loading();
  Object? _current;
  StreamSubscription<Object?>? _subscription;
  bool _keep = false;
  Completer<void>? _settled;

  /// How often it was loaded.
  int loads = 0;

  /// The future or stream of the moment, made again when what it read
  /// before its first `await` has changed. Reading it starts the load.
  /// After [dispose], the last one, with no load started.
  @override
  Object? read() {
    if (_disposed) {
      return _closedRead();
    }
    CallerBoundReads.noteRead();
    if (!_isCallers) {
      signals.untracked(() => _retry.value = _retry.peek() + 1);
    }
    final source = super.read();
    signals.untracked(() => _follow(source));
    return source;
  }

  // Before the first load nothing is kept, so anybody may start it.
  bool get _isCallers {
    final owner = _caller;
    return owner == null || CallerBoundReads.isCurrent(owner);
  }

  @override
  List<Object?>? _ownerAfter(int readsBefore) =>
      (owner?.runtime?.callerBound ?? true) ? CallerBoundReads.capture() : null;

  @override
  Object? _closedRead() =>
      _isCallers ? _current ?? super._closedRead() : super._closedRead();

  /// Where the value is; the reader is told when it moves. Nothing of a
  /// load made for another caller.
  /// After [dispose], the last state, with nothing followed.
  AsyncValue<Object?> get state {
    CallerBoundReads.noteRead();
    final state = _disposed ? _stateNow : _state.value;
    return _isCallers ? state : const AsyncValue<Object?>.loading();
  }

  /// Where the value is, without the reader being told of anything.
  AsyncValue<Object?> get stateNow => _stateNow;

  void _moveTo(AsyncValue<Object?> state) {
    _stateNow = state;
    _state.value = state;
  }

  /// Loads again and keeps the last value meanwhile. Completes when the
  /// new load ends (for a stream: with its first event, or its end
  /// without one; for a plain value or the same future again: at once
  /// when it has ended), with the newer load when asked for again
  /// meanwhile, and when the bean closes before the load ends. Fails once
  /// the bean is closed.
  Future<void> refresh() => _again(keep: true);

  /// Loads again from nothing: the state is `loading` meanwhile. Completes
  /// as [refresh] does. Fails once the bean is closed.
  Future<void> reload() => _again(keep: false);

  /// The call through the bean's advice, when it has any: a load asked
  /// for again runs its transaction and its checks as a read does.
  Object? Function()? advisedCall;

  Future<void> _again({required bool keep}) {
    if (_disposed) {
      final bean = owner?.beanName ?? owner?.label ?? name.split('.').first;
      return Future<void>.error(
        StateError(
          'The bean $bean is closed: $name cannot load again. Read it from '
          'the bean of the scope that is open now.',
        ),
      );
    }
    final advised = advisedCall;
    // Inside the advice: nobody's check would run for this caller.
    if (advised == null && !_isCallers) {
      return Future<void>.error(
        StateError(
          'This load was made for another user: read the value from the '
          'bean again, as the current user, before asking for it again.',
        ),
      );
    }
    _keep = keep;
    final settled = Completer<void>();
    // A load asked for again while one runs: the earlier caller waits for
    // the newer load, as the answer of its own is dropped.
    if (_settled case final earlier? when !earlier.isCompleted) {
      earlier.complete(settled.future);
    }
    _settled = settled;
    if (advised == null) {
      recompute();
      // Whether or not anything reads it now, the new load is followed.
      _follow(peek());
      return settled.future;
    }
    signals.untracked(() => _retry.value = _retry.peek() + 1);
    void failed(Object error, StackTrace stackTrace) {
      if (!settled.isCompleted) {
        settled.completeError(error, stackTrace);
      }
    }

    try {
      if (advised() case final Future<Object?> running) {
        running.then<void>((_) {}, onError: failed);
      }
    } on Object catch (error, stackTrace) {
      failed(error, stackTrace);
    }
    return settled.future;
  }

  void _follow(Object? source) {
    if (identical(source, _current)) {
      // The same load again (a kept future): it ended already, or its end
      // ends the refresh too.
      if (_currentEnded) {
        _endRefresh();
      }
      return;
    }
    unawaited(_subscription?.cancel());
    _subscription = null;
    _current = source;
    _currentEnded = false;
    loads++;
    _moveTo(_stateNow.toLoading(keep: _keep));
    _keep = false;
    switch (source) {
      case final Future<Object?> future:
        _members[future] = this;
        DerivedFutures.track(future);
        future.then(
          (value) => _settle(future, AsyncValue<Object?>.data(value)),
          onError: (Object error, StackTrace stackTrace) => _settle(
            future,
            _stateNow.toError(error, stackTrace),
          ),
        );
      case final Stream<Object?> stream:
        _members[stream] = this;
        _subscription = stream.listen(
          (value) => _settle(stream, AsyncValue<Object?>.data(value)),
          onError: (Object error, StackTrace stackTrace) => _settle(
            stream,
            _stateNow.toError(error, stackTrace),
          ),
          // Done without an event: nothing more comes.
          onDone: () {
            if (identical(stream, _current)) {
              _currentEnded = true;
              _endRefresh();
            }
          },
        );
      default:
        _currentEnded = true;
        _moveTo(AsyncValue<Object?>.data(source));
        _endRefresh();
    }
  }

  // Whether the load of [_current] gave its answer, or can give none.
  bool _currentEnded = false;

  // An answer that came after a newer request was made, or after the bean
  // closed, is dropped.
  void _settle(Object source, AsyncValue<Object?> state) {
    if (_disposed || !identical(source, _current)) {
      return;
    }
    _currentEnded = true;
    _moveTo(state);
    _endRefresh();
  }

  // The refresh or reload waiting for the load ends.
  void _endRefresh() {
    final settled = _settled;
    if (settled != null && !settled.isCompleted) {
      settled.complete();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    // A refresh waiting for a load whose answer will be dropped ends now.
    _endRefresh();
    unawaited(_subscription?.cancel());
    _subscription = null;
    // [_current] stays: what a read after this hands out.
    _state.dispose();
    super.dispose();
  }
}

/// A [ValueMember] the debug tools hear of ([SignalProbes]). Only a bean
/// whose application has a debug tool in its build makes these
/// ([ProbedSignalBean]); without one the class is never made, and a
/// release build compiles it away with every probe call.
final class ProbedValueMember extends ValueMember {
  /// See [ValueMember.new].
  ProbedValueMember(
    super.name,
    super.initial, {
    super.owner,
    super.arguments,
    super.type,
    super.hidden,
    super.options,
  });

  /// See [ValueMember.unset].
  ProbedValueMember.unset(
    super.name, {
    super.owner,
    super.arguments,
    super.type,
    super.hidden,
    super.options,
    super.initial,
  }) : super.unset();

  @override
  Object? read() {
    SignalProbes.current?.read(this);
    return super.read();
  }

  @override
  Object? readDirect() {
    SignalProbes.current?.read(this);
    return super.readDirect();
  }

  @override
  void write(Object? value) {
    SignalProbes.current?.wrote(this);
    super.write(value);
  }

  @override
  void _tell() {
    SignalProbes.current?.told(this);
    super._tell();
  }
}

// What the debug tools hear of a computed value: its reads, and each
// computation with its time and what it read.
base mixin _ComputedProbe on ComputedMember {
  @override
  Object? read() {
    // A closed member is not counted: the debug tools would keep it.
    if (!_disposed) {
      SignalProbes.current?.read(this);
    }
    return super.read();
  }

  @override
  Object? _evaluate() {
    final probe = SignalProbes.current;
    if (probe == null) {
      return super._evaluate();
    }
    final clock = Stopwatch()..start();
    probe.beginReader(this);
    try {
      final value = super._evaluate();
      probe.computed(this, clock.elapsed, null);
      return value;
    } on Object catch (error) {
      probe.computed(this, clock.elapsed, error);
      rethrow;
    } finally {
      probe.endReader();
    }
  }
}

/// A [ComputedMember] the debug tools hear of: see [ProbedValueMember].
final class ProbedComputedMember extends ComputedMember with _ComputedProbe {
  /// See [ComputedMember.new].
  ProbedComputedMember(super.name, super.compute, {super.owner});
}

/// An [AsyncMember] the debug tools hear of: see [ProbedValueMember].
final class ProbedAsyncMember extends AsyncMember with _ComputedProbe {
  /// See [AsyncMember.new].
  ProbedAsyncMember(super.name, super.compute, {super.owner});
}
