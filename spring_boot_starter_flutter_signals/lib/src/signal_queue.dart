import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_probe.dart';

const _log = SpringLog('spring.flutter.signals');

/// When a queue tells the readers of the writes it holds: called with the
/// queue's `flush` on every write, it calls `flush` when that is due and
/// returns what cancels it. The queue keeps what the last call returned
/// and calls it when it closes (what still waits is then told at once).
///
/// A schedule keeps its state in its closure, so it can wait for a quiet
/// moment:
///
/// ```dart
/// // Tells the readers 50 ms after the last write of a burst.
/// @Bean()
/// @Qualifier('search')
/// SignalFlushSchedule searchSchedule() {
///   Timer? timer;
///   return (flush) {
///     timer?.cancel();
///     final next = timer = Timer(const Duration(milliseconds: 50), flush);
///     return next.cancel;
///   };
/// }
/// ```
///
/// A bean of this type with `@Qualifier('<queue>')` is the schedule of the
/// queue of that name; the built-ins are [SignalFlushSchedules].
typedef SignalFlushSchedule = void Function() Function(void Function() flush);

void _nothing() {}

/// The built-in [SignalFlushSchedule]s, which `flush:` names. Each call
/// makes a schedule of its own for one queue: a write while a flush is
/// already due changes nothing and costs a check.
abstract final class SignalFlushSchedules {
  static final Expando<SignalFlush> _kinds = Expando('signal flush');

  static SignalFlushSchedule _tag(SignalFlush kind, SignalFlushSchedule s) {
    _kinds[s] = kind;
    return s;
  }

  /// The name of the built-in [schedule], `null` for one of the
  /// application's.
  static String? nameOf(SignalFlushSchedule schedule) => _kinds[schedule]?.name;

  /// Whether [schedule] tells at the assignment: the queue holds nothing.
  static bool isImmediate(SignalFlushSchedule schedule) =>
      _kinds[schedule] == SignalFlush.immediate;

  /// Whether a `@Computed` read must see what waits for [schedule].
  static bool flushesBeforeRead(SignalFlushSchedule schedule) =>
      _kinds[schedule] == SignalFlush.microtask;

  /// At the assignment.
  static SignalFlushSchedule immediate() =>
      _tag(SignalFlush.immediate, (flush) {
        flush();
        return _nothing;
      });

  /// In a microtask, so the writes of one synchronous run are one change.
  static SignalFlushSchedule microtask() {
    var due = false;
    void cancel() => due = false;
    return _tag(SignalFlush.microtask, (flush) {
      if (due) {
        return cancel;
      }
      due = true;
      scheduleMicrotask(() {
        if (due) {
          due = false;
          flush();
        }
      });
      return cancel;
    });
  }

  /// At the next frame.
  static SignalFlushSchedule frame() {
    var due = false;
    void cancel() => due = false;
    return _tag(SignalFlush.frame, (flush) {
      if (due) {
        return cancel;
      }
      due = true;
      void run() {
        if (due) {
          due = false;
          flush();
        }
      }

      SchedulerBinding? binding;
      try {
        binding = SchedulerBinding.instance;
      } on Object {
        binding = null;
      }
      if (binding == null) {
        Timer(const Duration(milliseconds: 16), run);
      } else {
        binding
          ..scheduleFrameCallback((_) => run())
          ..ensureVisualUpdate();
      }
      return cancel;
    });
  }

  /// [every] after the first write that found nothing due.
  static SignalFlushSchedule interval(Duration every) {
    Timer? timer;
    void cancel() {
      timer?.cancel();
      timer = null;
    }

    return _tag(SignalFlush.interval, (flush) {
      if (timer != null) {
        return cancel;
      }
      timer = Timer(every, () {
        timer = null;
        flush();
      });
      return cancel;
    });
  }

  /// A new built-in of [name] (`immediate`, `microtask`, `frame`,
  /// `interval`).
  static SignalFlushSchedule named(SignalFlush name, Duration every) =>
      switch (name) {
        SignalFlush.immediate => immediate(),
        SignalFlush.microtask => microtask(),
        SignalFlush.frame => frame(),
        SignalFlush.interval => interval(every),
      };
}

/// The built-in schedules by name, for `spring.flutter.signals.queue.flush`.
enum SignalFlush {
  /// [SignalFlushSchedules.immediate].
  immediate,

  /// [SignalFlushSchedules.microtask].
  microtask,

  /// [SignalFlushSchedules.frame].
  frame,

  /// [SignalFlushSchedules.interval].
  interval,
}

/// What a queue does with one more field when it holds `capacity`.
enum SignalOverflow {
  /// Tells what it holds now, and takes the write. While the queue is
  /// telling already (a reader that writes), it refuses the write as
  /// [dropNewest] does.
  flush,

  /// Drops the oldest write it holds (the field keeps its value from
  /// before that write), with a warning.
  dropOldest,

  /// Refuses this write (the field keeps its value), with a warning.
  dropNewest,
}

/// How one queue works: `spring.flutter.signals.queues.<name>.*`, or the
/// defaults `spring.flutter.signals.queue.*`.
final class SignalQueueSettings {
  /// The settings with these values.
  const SignalQueueSettings({
    this.schedule,
    this.capacity = 1024,
    this.onOverflow = SignalOverflow.flush,
  });

  /// When the readers are told; a new microtask schedule when not given.
  final SignalFlushSchedule? schedule;

  /// How many fields may wait to be told.
  final int capacity;

  /// What happens to one more.
  final SignalOverflow onOverflow;
}

/// Holds the writes of fields until their readers are told: the writes of
/// one run are told together, once, when its schedule says.
///
/// The field has its new value at once; only the telling waits. A queue
/// runs nothing of its own: it only holds and tells.
final class SignalQueue {
  /// The queue [name], working by [settings].
  SignalQueue(this.name, this.settings)
    : schedule = settings.schedule ?? SignalFlushSchedules.microtask();

  /// When it tells its readers.
  final SignalFlushSchedule schedule;

  /// How many writes wait in any queue: what a read asks first.
  static int pendingWrites = 0;

  /// Its name.
  final String name;

  /// How it works.
  final SignalQueueSettings settings;

  final LinkedHashSet<ValueMember> _pending = LinkedHashSet.identity();
  void Function()? _cancel;
  bool _flushing = false;
  bool _closed = false;

  /// Whether a write is told at the assignment.
  late final bool isImmediate = SignalFlushSchedules.isImmediate(schedule);

  /// Whether a `@Computed` read tells what waits here first.
  late final bool flushesBeforeRead = SignalFlushSchedules.flushesBeforeRead(
    schedule,
  );

  /// How many fields wait.
  int get pending => _pending.length;

  /// How many writes it dropped or refused, being full.
  int drops = 0;

  /// The name of its built-in schedule (`microtask`), or `custom`.
  String get scheduleName => SignalFlushSchedules.nameOf(schedule) ?? 'custom';

  /// Whether [member] may wait here. At the capacity [member] may push
  /// another out or be refused.
  bool admit(ValueMember member) {
    if (_pending.contains(member) || _pending.length < settings.capacity) {
      return true;
    }
    switch (settings.onOverflow) {
      // A reader that writes while the queue tells: no flush can make room
      // now, so the write is refused as with dropNewest.
      case SignalOverflow.flush when _flushing:
        return _refuse(member);
      case SignalOverflow.flush:
        flush();
        return true;
      case SignalOverflow.dropOldest:
        final oldest = _pending.first;
        _remove(oldest);
        oldest.dropPending();
        drops++;
        SignalProbes.current?.dropped(this, oldest);
        _log.warning(
          "The signal queue '$name' is full (${settings.capacity}): "
          'dropped the write of ${oldest.name}.',
        );
        return true;
      case SignalOverflow.dropNewest:
        return _refuse(member);
    }
  }

  bool _refuse(ValueMember member) {
    drops++;
    SignalProbes.current?.dropped(this, member);
    _log.warning(
      "The signal queue '$name' is full (${settings.capacity}): "
      'refused the write of ${member.name}.',
    );
    return false;
  }

  /// Holds [member] until the next flush; the schedule hears of every
  /// write.
  void enqueue(ValueMember member) {
    if (_pending.add(member)) {
      pendingWrites++;
    }
    if (!_closed) {
      _cancel = schedule(flush);
    }
  }

  void _remove(ValueMember member) {
    if (_pending.remove(member)) {
      pendingWrites--;
    }
  }

  /// Forgets [member], whose writes are not to be told.
  void forget(ValueMember member) => _remove(member);

  /// Tells the readers of [member] now.
  void flushMember(ValueMember member) {
    if (!_pending.contains(member)) {
      return;
    }
    _remove(member);
    member.publishPending();
  }

  /// Tells the readers of everything held, as one change.
  void flush() {
    _cancel = null;
    if (_flushing || _pending.isEmpty) {
      return;
    }
    _flushing = true;
    try {
      // A reader that writes adds to what is told next.
      while (_pending.isNotEmpty) {
        final members = _pending.toList();
        pendingWrites -= members.length;
        _pending.clear();
        SignalProbes.current?.flushed(this, members.length);
        signals.batch(() {
          for (final member in members) {
            member.publishPending();
          }
        });
      }
    } finally {
      _flushing = false;
    }
  }

  /// Stops: the schedule is cancelled, and what still waits is told now.
  void close() {
    _closed = true;
    _cancel?.call();
    _cancel = null;
    flush();
  }
}

/// The application's queues: the default one, and those of
/// `spring.flutter.signals.queues.*` and of the qualified
/// [SignalFlushSchedule] beans, by name.
final class SignalQueues {
  /// The default queue by [defaults]; the others by [named].
  SignalQueues(
    SignalQueueSettings defaults, [
    Map<String, SignalQueueSettings> named = const {},
  ]) : primary = SignalQueue('default', defaults),
       _named = {
         for (final MapEntry(:key, :value) in named.entries)
           key: SignalQueue(key, value),
       };

  /// The default queue.
  final SignalQueue primary;

  final Map<String, SignalQueue> _named;

  /// The queue [name]; the default one for `null`. An unknown name fails
  /// the start.
  SignalQueue of(String? name) {
    if (name == null || name == 'default') {
      return primary;
    }
    return _named[name] ??
        (throw StateError(
          "There is no signal queue '$name': declare it under "
          'spring.flutter.signals.queues.$name, or as a SignalFlushSchedule '
          "bean with @Qualifier('$name'), or remove it from "
          '@Signal(queue: ...). Known: '
          '${['default', ..._named.keys].join(', ')}.',
        ));
  }

  /// Every queue, the default one first.
  Iterable<SignalQueue> get all => [primary, ..._named.values];

  /// Tells what waits in the queues a `@Computed` read must see.
  void flushBeforeRead() {
    if (primary.flushesBeforeRead) {
      primary.flush();
    }
    for (final queue in _named.values) {
      if (queue.flushesBeforeRead) {
        queue.flush();
      }
    }
  }

  /// Tells what waits everywhere and stops.
  void close() {
    primary.close();
    for (final queue in _named.values) {
      queue.close();
    }
  }
}
