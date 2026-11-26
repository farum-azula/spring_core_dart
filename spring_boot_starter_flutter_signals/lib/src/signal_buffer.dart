import 'dart:async';

import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/followed_collections.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';

const _log = SpringLog('spring.flutter.signals');

/// How a `@Signal` write in a transaction is told:
/// `spring.flutter.signals.transaction.mode`.
enum SignalTransactionMode {
  /// Held in a [SignalBuffer] until the commit and dropped by a rollback.
  buffered,

  /// Written at once, whatever the transaction does later.
  direct,
}

// One field's value in a buffer: what the buffer's own code sees.
final class _Held {
  _Held(this.raw, this.view, {required this.written});

  final Object? raw;
  final Object? view;
  final bool written;

  bool get changed =>
      written ||
      switch (view) {
        final FollowedCollection collection => collection.version.peek() != 0,
        _ => false,
      };
}

final class _BufferState {
  _BufferState(this.parent, {required this.publishOnError});

  final SignalBuffer? parent;
  final bool publishOnError;
  final Map<ValueMember, _Held> held = Map.identity();
  bool closed = false;
}

/// Holds `@Signal` writes for a piece of async work: the work's own code
/// reads what it wrote, everybody else (and every reader that follows the
/// fields) sees the values from before, and when the work ends its writes
/// are handed to their fields' queues as one change, or dropped.
///
/// As an annotation, on an async method of a bean on signals: the method
/// runs in a buffer (the generated subclass wraps it, so `this.save()` does
/// too). `@SignalBuffer(false)` takes one method out when
/// `spring.flutter.signals.buffer.async-methods` wraps them all.
///
/// ```dart
/// @SignalBuffer()
/// Future<void> checkout() async {
///   items = [];
///   total = 0;
///   await orders.send(...);   // readers see both changes after this
/// }
/// ```
///
/// For other code, [SignalBuffer.run]. A buffer opened inside another one
/// joins it; one opened inside a transaction joins the transaction's, which
/// is published by the commit and dropped by a rollback (a savepoint is a
/// buffer inside it, dropped alone by a rollback to it). A timer or a
/// future started inside a buffer and writing after it ended writes as any
/// code does.
final class SignalBuffer {
  /// Marks an async method that runs in a buffer; with `false`, one that
  /// does not.
  const SignalBuffer([this.enabled = true]) : _state = null;

  SignalBuffer._open(SignalBuffer? parent, {required bool publishOnError})
    : enabled = true,
      _state = _BufferState(parent, publishOnError: publishOnError);

  /// Whether the method runs in a buffer.
  final bool enabled;

  final _BufferState? _state;

  static final Object _zoneKey = Object();

  /// How many buffers are open now: a read asks this first, so code with
  /// no buffer pays nothing more.
  static int open = 0;

  static final Set<SignalBuffer> _opened = Set.identity();

  /// Runs [body] in a buffer: what it writes is told when it completes, or
  /// dropped when it fails (unless [publishOnError]). Inside a buffer,
  /// [body] joins it; inside a transaction its writes go to the
  /// transaction's buffer, which the commit publishes.
  static Future<T> run<T>(
    Future<T> Function() body, {
    bool publishOnError = false,
  }) {
    if (_innermostOpen() != null) {
      return body();
    }
    final buffer = _root._inside(publishOnError: publishOnError);
    final state = buffer._state!;
    return runZoned(
      () => Future.sync(body),
      zoneValues: {_zoneKey: buffer},
    ).then(
      (value) {
        buffer._close(publish: true);
        return value;
      },
      onError: (Object error, StackTrace stackTrace) {
        buffer._close(publish: state.publishOnError);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  // A closed buffer stands for "no outer buffer": one inside it hands its
  // writes to the queues.
  static final SignalBuffer _root = () {
    final root = SignalBuffer._open(null, publishOnError: false);
    root._state!.closed = true;
    return root;
  }();

  // The innermost buffer of the zone that is still open.
  static SignalBuffer? _innermostOpen() {
    if (open == 0) {
      return null;
    }
    var buffer = Zone.current[_zoneKey] as SignalBuffer?;
    while (buffer != null && buffer._state!.closed) {
      buffer = buffer._state.parent;
    }
    return buffer;
  }

  /// The buffer a write of the current code goes into: the transaction's
  /// of [transactions] (made on first use), else the zone's; `null` for
  /// none.
  static SignalBuffer? forWrite(SignalTransactionBuffers? transactions) =>
      transactions?.current(create: true) ?? _innermostOpen();

  /// The buffer the current code reads through, `null` for none.
  static SignalBuffer? forRead(SignalTransactionBuffers? transactions) {
    if (open == 0) {
      return null;
    }
    return transactions?.current() ?? _innermostOpen();
  }

  _Held? _find(ValueMember member) {
    for (SignalBuffer? buffer = this; buffer != null;) {
      final state = buffer._state!;
      if (state.held[member] case final held?) {
        return held;
      }
      buffer = state.parent;
    }
    return null;
  }

  /// Whether this buffer, or one it is inside, wrote anything.
  bool get hasWrites {
    for (SignalBuffer? buffer = this; buffer != null;) {
      final state = buffer._state!;
      if (state.held.values.any((held) => held.changed)) {
        return true;
      }
      buffer = state.parent;
    }
    return false;
  }

  /// Whether the buffer has its own value of [member].
  bool holds(ValueMember member) => _find(member) != null;

  /// What the buffer's code reads of [member].
  Object? read(ValueMember member) => _find(member)?.view;

  /// The buffer's own copy of the collection in [member], so a change in
  /// place stays in it.
  Object? copyOnWrite(ValueMember member) {
    final existing = _find(member);
    if (existing != null) {
      return existing.view;
    }
    final (raw, view) = member.bufferCopy();
    _state!.held[member] = _Held(raw, view, written: false);
    return view;
  }

  /// Keeps the write of [value].
  void write(ValueMember member, Object? value) {
    final before = _find(member);
    final raw = before != null && identical(value, before.view)
        ? before.raw
        : value;
    _state!.held[member] = _Held(raw, member.viewOf(raw), written: true);
  }

  /// Drops what is held for [member] (its bean's scope ended); with
  /// [publish], tells it at once instead.
  static void release(ValueMember member, {required bool publish}) {
    for (final buffer in _opened) {
      final held = buffer._state!.held.remove(member);
      if (held != null && held.changed && publish) {
        member.writeDirect(held.raw);
      }
    }
  }

  /// The open buffers and how many fields each holds, for the debug tab.
  static List<int> get openSizes => [
    for (final buffer in _opened) buffer._state!.held.length,
  ];

  /// Whether an open buffer holds a write of [member].
  static bool anyHolds(ValueMember member) =>
      _opened.any((buffer) => buffer._state!.held[member]?.changed ?? false);

  SignalBuffer _inside({required bool publishOnError}) {
    final buffer = SignalBuffer._open(this, publishOnError: publishOnError);
    open++;
    _opened.add(buffer);
    return buffer;
  }

  void _close({required bool publish}) {
    final state = _state!;
    if (state.closed) {
      return;
    }
    state.closed = true;
    if (_opened.remove(this)) {
      open--;
    }
    final parent = state.parent;
    if (parent != null && !parent._state!.closed) {
      if (publish) {
        parent._state.held.addAll(state.held);
      } else {
        _dropped(state.held.keys);
      }
      return;
    }
    if (!publish) {
      _dropped(state.held.keys);
      return;
    }
    // Handed to each field's queue, as one change.
    try {
      signals.batch(() {
        for (final MapEntry(key: member, value: held) in state.held.entries) {
          if (held.changed) {
            member.publishFromBuffer(held.raw);
          } else {
            member.bufferDropped();
          }
        }
      });
    } on Object catch (error, stackTrace) {
      _log.error(
        'A reader failed after a buffer was published',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void _dropped(Iterable<ValueMember> members) {
    for (final member in members.toList()) {
      member.bufferDropped();
    }
  }
}

/// Opens a [SignalBuffer] for each transaction of the application that
/// writes a `@Signal`, from the events of its
/// [TransactionLifecycleRegistry]: published on commit, dropped on
/// rollback, a savepoint as a buffer inside it.
final class SignalTransactionBuffers {
  /// The buffers over [registry].
  SignalTransactionBuffers(this.registry);

  /// What says which transaction runs.
  final TransactionLifecycleRegistry registry;

  final Expando<_TransactionBuffer> _byTransaction = Expando('signal buffers');

  /// The buffer of the current transaction; with [create] it is made on
  /// its first use. `null` outside a transaction and after it ended.
  SignalBuffer? current({bool create = false}) {
    final key = registry.transactionKey;
    if (key == null) {
      return null;
    }
    final existing = _byTransaction[key];
    if (existing != null) {
      return existing.ended ? null : existing.top;
    }
    if (!create) {
      return null;
    }
    final transaction = _TransactionBuffer(
      SignalBuffer._innermostOpen() ?? SignalBuffer._root,
    );
    _byTransaction[key] = transaction;
    registry.registerListener(transaction);
    return transaction.top;
  }
}

// The buffers of one transaction: its own, and one per savepoint.
final class _TransactionBuffer implements TransactionLifecycleListener {
  _TransactionBuffer(SignalBuffer outer)
    : _layers = [(null, outer._inside(publishOnError: false))];

  final List<(Object?, SignalBuffer)> _layers;
  bool ended = false;

  SignalBuffer get top => _layers.last.$2;

  @override
  void savepoint(Object savepoint) =>
      _layers.add((savepoint, top._inside(publishOnError: false)));

  @override
  void savepointRollback(Object savepoint) {
    final index = _layers.lastIndexWhere(
      (layer) => identical(layer.$1, savepoint),
    );
    // Registered after the savepoint: everything held came after it.
    final from = index < 0 ? 0 : index;
    for (final (_, buffer) in _layers.sublist(from).reversed) {
      buffer._close(publish: false);
    }
    final below = _layers[from].$2._state!.parent!;
    _layers
      ..removeRange(from, _layers.length)
      ..add((
        index < 0 ? null : savepoint,
        below._inside(publishOnError: false),
      ));
  }

  @override
  void afterCommit() => _end(publish: true);

  @override
  void afterRollbackOrUnknown() => _end(publish: false);

  void _end({required bool publish}) {
    if (ended) {
      return;
    }
    ended = true;
    for (final (_, buffer) in _layers.reversed) {
      buffer._close(publish: publish);
    }
  }
}
