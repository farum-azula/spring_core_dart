import 'dart:async';
import 'dart:collection';

import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_dart/spring_boot_dart.dart' show TypeCapture;
import 'package:spring_boot_starter_flutter_signals/src/async_value.dart';
import 'package:spring_boot_starter_flutter_signals/src/follow_keeper.dart';
import 'package:spring_boot_starter_flutter_signals/src/followed_collections.dart';

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

/// One followed member of a bean: a `@Signal` field or a `@Computed`
/// value, by its name (`basket.items`).
sealed class SignalMember {
  /// The member called [name].
  SignalMember(this.name);

  /// The bean's name and the member's: `basket.items`.
  final String name;

  /// Stops following; reads after it go to the bean's own field.
  void dispose();
}

/// A `@Signal` field: its value, mirrored in a signal so that readers are
/// told of an assignment. The field itself keeps the value too.
///
/// A `List`, `Set`, `Map` or `Queue` is handed out as a collection that
/// also tells its readers of a change in place (`items.add(book)`); the
/// field keeps the collection itself, and both are the same elements.
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
    List<TypeCapture<Object?>> arguments = const [],
    String? type,
    this.hidden = false,
    // ignore: prefer_initializing_formals, named parameters cannot be private
  }) : _arguments = type == null || _followedTypes.contains(type)
           ? arguments
           : const [],
       _signal = signals.signal<Object?>(
         null,
         options: signals.SignalOptions<Object?>(name: name),
       ) {
    _raw = initial;
    _signal.value = _followed(initial);
  }

  /// The `late` field [name], read before it was first assigned: there is
  /// no value yet, and whoever read it ([follow]) is told when there is.
  ValueMember.unset(
    super.name, {
    List<TypeCapture<Object?>> arguments = const [],
    String? type,
    this.hidden = false,
    // ignore: prefer_initializing_formals, named parameters cannot be private
  }) : _arguments = type == null || _followedTypes.contains(type)
           ? arguments
           : const [],
       _unset = true,
       _signal = signals.signal<Object?>(
         _unassigned,
         options: signals.SignalOptions<Object?>(name: name),
       );

  static const _followedTypes = {'List', 'Set', 'Map', 'Queue'};
  static const Object _unassigned = _Unassigned();

  final List<TypeCapture<Object?>> _arguments;
  final signals.Signal<Object?> _signal;
  Object? _raw;
  bool _unset = false;

  /// Whether the field is a `late` one that was read but never assigned.
  bool get unset => _unset;

  /// Tells the reader of the first assignment of a field that is [unset].
  void follow() {
    FollowKeeper.note(_follow);
    _signal.value;
  }

  void _follow() => _signal.value;

  /// Whether the value is kept out of the debug tab and the log.
  final bool hidden;

  /// How often the field was assigned a new value.
  int changes = 0;

  /// The value as the bean's readers get it; the reader is told of the
  /// next assignment (and, for a collection, of a change in place).
  Object? read() {
    FollowKeeper.note(_follow);
    return _signal.value;
  }

  /// The value the field itself holds, without the reader being told of
  /// anything.
  Object? peek() => _raw;

  /// The value to keep in the field for the assignment of [value]: what
  /// [read] handed out stands for the collection it follows
  /// (`items = items..add(book)` assigns the same list again).
  Object? unwrap(Object? value) =>
      value != null && identical(value, _signal.peek()) ? _raw : value;

  /// The assignment of [value] (as the field keeps it).
  void write(Object? value) {
    if (!_unset && identical(value, _raw)) {
      return;
    }
    if (_unset || value != _raw) {
      changes++;
    }
    _unset = false;
    _raw = value;
    // The follower of the collection there was is left to its last
    // readers: code may still hold it.
    _signal.value = _followed(value);
  }

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
  void dispose() {
    if (_signal.peek() case final FollowedCollection collection) {
      collection.disposeFollower();
    }
    _signal.dispose();
  }
}

final class _Unassigned {
  const _Unassigned();
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
final class ComputedMember extends SignalMember {
  /// The value [name], computed by [compute].
  ComputedMember(super.name, Object? Function() compute) : _compute = compute;

  final Object? Function() _compute;
  final FollowKeeper _keeper = FollowKeeper();
  _Failure? _failure;

  // Raised to compute again after a failure.
  late final signals.Signal<int> _retry = signals.signal<int>(0);

  late final signals.Computed<Object?> _computed = signals.computed<Object?>(
    () {
      _retry.value;
      try {
        final value = _keeper.run(_compute);
        _failure = null;
        return value;
      } on Object catch (error, stackTrace) {
        final thrown = error is signals.SignalEffectException
            ? error.error ?? error
            : error;
        final trace = error is signals.SignalEffectException
            ? error.stackTrace ?? stackTrace
            : stackTrace;
        final before = _failure;
        if (before != null && before.isLike(thrown)) {
          return before
            ..error = thrown
            ..stackTrace = trace;
        }
        return _failure = _Failure(thrown, trace);
      }
    },
    options: signals.ComputedOptions<Object?>(name: name),
  );

  /// The value; the reader is told when it is computed again. Fails with
  /// what the computation threw.
  Object? read() {
    FollowKeeper.note(_subscribe);
    _retryAfterFailure();
    return _valueOf(unwrapped(() => _computed.value));
  }

  /// The value, without the reader being told of anything. Fails with
  /// what the computation threw.
  Object? peek() {
    _retryAfterFailure();
    return _valueOf(unwrapped(_computed.peek));
  }

  void _subscribe() => _computed.value;

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
  void recompute() => _computed.recompute();

  @override
  void dispose() {
    _computed.dispose();
    _retry.dispose();
  }
}

/// A `@Computed` value that is a `Future` or a `Stream`: the future or
/// stream itself (made again when what it read before its first `await`
/// changes), and where it is: loading, the data, the error.
final class AsyncMember extends ComputedMember {
  /// The asynchronous value [name], made by [compute].
  AsyncMember(super.name, super.compute)
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

  final signals.Signal<AsyncValue<Object?>> _state;
  Object? _current;
  StreamSubscription<Object?>? _subscription;
  bool _keep = false;
  Completer<void>? _settled;

  /// How often it was loaded.
  int loads = 0;

  /// The future or stream of the moment, made again when what it read
  /// before its first `await` has changed. Reading it starts the load.
  @override
  Object? read() {
    final source = super.read();
    signals.untracked(() => _follow(source));
    return source;
  }

  /// Where the value is; the reader is told when it moves.
  AsyncValue<Object?> get state => _state.value;

  /// Where the value is, without the reader being told of anything.
  AsyncValue<Object?> get stateNow => _state.peek();

  /// Loads again and keeps the last value meanwhile. Completes when the
  /// new load ends (for a stream: with its first event).
  Future<void> refresh() => _again(keep: true);

  /// Loads again from nothing: the state is `loading` meanwhile.
  Future<void> reload() => _again(keep: false);

  Future<void> _again({required bool keep}) {
    _keep = keep;
    final settled = _settled = Completer<void>();
    recompute();
    // Whether or not anything reads it now, the new load is followed.
    _follow(peek());
    return settled.future;
  }

  void _follow(Object? source) {
    if (identical(source, _current)) {
      return;
    }
    unawaited(_subscription?.cancel());
    _subscription = null;
    _current = source;
    loads++;
    _state.value = _state.peek().toLoading(keep: _keep);
    _keep = false;
    switch (source) {
      case final Future<Object?> future:
        _members[future] = this;
        future.then(
          (value) => _settle(future, AsyncValue<Object?>.data(value)),
          onError: (Object error, StackTrace stackTrace) => _settle(
            future,
            _state.peek().toError(error, stackTrace),
          ),
        );
      case final Stream<Object?> stream:
        _members[stream] = this;
        _subscription = stream.listen(
          (value) => _settle(stream, AsyncValue<Object?>.data(value)),
          onError: (Object error, StackTrace stackTrace) => _settle(
            stream,
            _state.peek().toError(error, stackTrace),
          ),
        );
      default:
        _state.value = AsyncValue<Object?>.data(source);
    }
  }

  // An answer that came after a newer request was made is dropped.
  void _settle(Object source, AsyncValue<Object?> state) {
    if (!identical(source, _current)) {
      return;
    }
    _state.value = state;
    final settled = _settled;
    if (settled != null && !settled.isCompleted) {
      settled.complete();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _current = null;
    _state.dispose();
    super.dispose();
  }
}
