import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signal_widget_names.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_probe.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_queue.dart';
import 'package:spring_boot_starter_flutter_signals/src/widgets/signal_build_tracker.dart';

/// How long things took: the last, the average and the longest.
final class SignalTiming {
  int _count = 0;
  Duration _total = Duration.zero;

  /// The last.
  Duration last = Duration.zero;

  /// The longest.
  Duration max = Duration.zero;

  /// How many runs.
  int get count => _count;

  /// The average.
  Duration get average => _count == 0
      ? Duration.zero
      : Duration(microseconds: _total.inMicroseconds ~/ _count);

  void _add(Duration took) {
    _count++;
    _total += took;
    last = took;
    if (took > max) {
      max = took;
    }
  }
}

// Counts in slices of the window, so an old count falls out without a
// timestamp per event.
final class _WindowCount {
  _WindowCount(this.slices);

  final int slices;
  final Map<int, int> _bySlice = {};

  void add(int slice) => _bySlice[slice] = (_bySlice[slice] ?? 0) + 1;

  int total(int now) {
    _bySlice.removeWhere((slice, _) => slice <= now - slices);
    var sum = 0;
    for (final count in _bySlice.values) {
      sum += count;
    }
    return sum;
  }
}

/// What happened in one Flutter frame.
final class SignalFrame {
  /// The counts of a frame.
  const SignalFrame({this.ticks = 0, this.flushes = 0, this.effects = 0});

  /// Readers told of a change (publications).
  final int ticks;

  /// Queue flushes.
  final int flushes;

  /// Effect runs.
  final int effects;
}

/// What the Signals tab and the debug console's `signals` segment and
/// command show, collected only while
/// one of them shows ([use]): a [SignalProbe] attached then, detached
/// when the last of them hides.
final class SignalsDebugRecorder implements SignalProbe {
  /// The recorder over [readWindow] (read counts), timed by [clock] (a
  /// monotonic one by default: a test passes its own). With [names] the
  /// widgets are named only while it collects: each time it starts, those
  /// on the screen are built once again ([SignalWidgetNames.start]), so
  /// what they read is heard even when nothing changes while a tool shows.
  SignalsDebugRecorder({
    this.readWindow = const Duration(seconds: 5),
    this.countReads = true,
    this.names,
    Duration Function()? clock,
  }) : _clock = clock ?? _monotonic;

  /// The names of the widgets that read state, started and stopped with
  /// the collecting; `null` when no tool in the app shows widgets.
  final SignalWidgetNames? names;

  static final Stopwatch _since = Stopwatch()..start();
  static Duration _monotonic() => _since.elapsed;

  /// The window of [readsOf].
  final Duration readWindow;

  /// Whether reads are counted (they are the most frequent event).
  final bool countReads;

  final Duration Function() _clock;

  /// The time of the recorder's clock, which every time it gives is on.
  Duration get now => _clock();

  static const _slice = Duration(milliseconds: 100);

  int get _now => _clock().inMicroseconds ~/ _slice.inMicroseconds;

  int get _readSlices => readWindow.inMicroseconds ~/ _slice.inMicroseconds;

  int _users = 0;
  void Function()? _detach;

  /// Starts collecting until the returned function is called: the
  /// tab and the console's segment call it while they show. When the last
  /// of them calls it, everything collected is forgotten.
  void Function() use() {
    if (_users++ == 0) {
      _detach = SignalProbes.attach(this);
      _listenToFrames();
      names?.start();
    }
    var released = false;
    return () {
      if (released) {
        return;
      }
      released = true;
      if (--_users == 0) {
        _detach?.call();
        _detach = null;
        names?.stop();
        _forget();
      }
    };
  }

  // Nothing shows: nothing collected is kept, of a bean, a member or a
  // widget.
  void _forget() {
    for (final map in <Map<Object, Object?>>[
      _writes,
      _tells,
      _reads,
      _timings,
      _lit,
      _readsOf,
      _drops,
      _rebuilds,
      _toldAt,
      _changedAt,
      _wroteAt,
      _seenChanges,
      _changesAtTold,
    ]) {
      map.clear();
    }
    _readers.clear();
    frames.clear();
    _ticks = 0;
    _flushes = 0;
    _effects = 0;
    _lastLit = null;
    _wokenAt = null;
    _structure++;
  }

  /// Whether it collects now.
  bool get active => _users > 0;

  static bool _framesHooked = false;
  static final List<SignalsDebugRecorder> _recorders = [];

  void _listenToFrames() {
    if (!_recorders.contains(this)) {
      _recorders.add(this);
    }
    if (_framesHooked) {
      return;
    }
    SchedulerBinding? binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object {
      return;
    }
    _framesHooked = true;
    binding.addPersistentFrameCallback((_) {
      for (final recorder in _recorders) {
        if (recorder.active) {
          recorder.frameEnded();
        }
      }
    });
  }

  // The counts of the frame going on.
  int _ticks = 0;
  int _flushes = 0;
  int _effects = 0;

  /// The frames seen, newest last (at most [keptFrames]).
  final Queue<SignalFrame> frames = Queue();

  /// How many frames [frames] keeps.
  static const keptFrames = 120;

  /// The frame that ended last.
  SignalFrame get lastFrame =>
      frames.isEmpty ? const SignalFrame() : frames.last;

  /// Ends a frame: its counts join [frames]. Called at each frame (a test
  /// calls it itself).
  void frameEnded() {
    frames.add(
      SignalFrame(ticks: _ticks, flushes: _flushes, effects: _effects),
    );
    if (frames.length > keptFrames) {
      frames.removeFirst();
    }
    _ticks = 0;
    _flushes = 0;
    _effects = 0;
  }

  final Map<ValueMember, int> _writes = HashMap.identity();
  final Map<ValueMember, int> _tells = HashMap.identity();
  final Map<SignalMember, _WindowCount> _reads = HashMap.identity();
  final Map<Object, SignalTiming> _timings = HashMap.identity();
  final Map<Object, Duration> _lit = HashMap.identity();
  final Map<Object, Set<SignalMember>> _readsOf = HashMap.identity();
  final List<(Object, Set<SignalMember>)> _readers = [];
  final Map<String, int> _drops = {};
  final Map<Object, _WindowCount> _rebuilds = HashMap.identity();
  final Map<ValueMember, Duration> _toldAt = HashMap.identity();
  final Map<ValueMember, Duration> _changedAt = HashMap.identity();
  final Map<ValueMember, Duration> _wroteAt = HashMap.identity();
  final Map<ValueMember, int> _seenChanges = HashMap.identity();
  final Map<ValueMember, int> _changesAtTold = HashMap.identity();
  int _structure = 0;

  /// How often [member] was assigned while collecting.
  int writesOf(ValueMember member) => _writes[member] ?? 0;

  /// How often the readers of [member] were told while collecting.
  int tellsOf(ValueMember member) => _tells[member] ?? 0;

  /// How often [member] was read within [readWindow].
  int readsOf(SignalMember member) => _reads[member]?.total(_now) ?? 0;

  /// How often the widget of [reader] (its tracking) was built within
  /// [readWindow].
  int rebuildsOf(Object reader) => _rebuilds[reader]?.total(_now) ?? 0;

  /// When the readers of [member] were last told ([now]'s clock), `null`
  /// when not while collecting.
  Duration? toldAt(ValueMember member) => _toldAt[member];

  /// When [member] last changed for real (a new value, not an equal one;
  /// a collection changed in place), `null` when not while collecting.
  Duration? changedAt(ValueMember member) {
    _settle(member);
    return _changedAt[member];
  }

  /// When [node] (a member, an effect of one bean, a widget's tracking)
  /// last changed, ran or was built, `null` when not while collecting.
  Duration? litAt(Object node) => _lit[node];

  /// Counts up when what reads what changes: a reader seen first, one that
  /// read something else than in its last run, one that ended. The graph
  /// is laid out again only then.
  int get structure => _structure;

  /// Forgets what ended: the widgets that left the screen, the members of
  /// closed beans and the effects that stopped with them. The tab, the
  /// graph layer and the console's segment call it while they show.
  void pruneEnded() {
    var changed = false;
    for (final MapEntry(key: reader, value: read) in _readsOf.entries) {
      if (!_ended(reader) && read.any(_endedMember)) {
        read.removeWhere(_endedMember);
        changed = true;
      }
    }
    final before = _readsOf.length;
    _readsOf.removeWhere((reader, _) => _ended(reader));
    changed = changed || _readsOf.length != before;
    for (final map in <Map<Object, Object?>>[
      _writes,
      _tells,
      _reads,
      _timings,
      _lit,
      _rebuilds,
      _toldAt,
      _changedAt,
      _wroteAt,
      _seenChanges,
      _changesAtTold,
    ]) {
      map.removeWhere((node, _) => _ended(node));
    }
    if (changed) {
      _structure++;
    }
  }

  static bool _ended(Object node) => switch (node) {
    final SignalMember member => _endedMember(member),
    final SignalTracking tracking => tracking.disposed,
    final EffectFollower effect => effect.stopped,
    _ => false,
  };

  static bool _endedMember(SignalMember member) =>
      member.disposed || (member.owner?.closed ?? false);

  /// How long [reader] (a computed member, an effect of one bean) took.
  SignalTiming? timingOf(Object reader) => _timings[reader];

  /// How many writes [queue] dropped while collecting.
  int dropsOf(SignalQueue queue) => _drops[queue.name] ?? 0;

  /// What [reader] (a computed member, an effect of one bean, a widget's
  /// tracking) read in its last run.
  Set<SignalMember> readBy(Object reader) => _readsOf[reader] ?? const {};

  /// The readers seen, with what each read last.
  Map<Object, Set<SignalMember>> get readers => _readsOf;

  /// How lit [node] is, from 1 (it changed or ran now) to 0 (more than
  /// [fade] ago).
  double lampOf(Object node, {Duration fade = const Duration(seconds: 1)}) =>
      lampAt(node, _clock(), fade: fade);

  /// [lampOf] at the time [now], read once for many nodes.
  double lampAt(
    Object node,
    Duration now, {
    Duration fade = const Duration(seconds: 1),
  }) {
    final at = _lit[node];
    if (at == null) {
      return 0;
    }
    final age = now - at;
    if (age >= fade) {
      return 0;
    }
    return 1 - age.inMicroseconds / fade.inMicroseconds;
  }

  /// When anything last changed, ran or was built.
  Duration? get lastLit => _lastLit;
  Duration? _lastLit;

  final List<VoidCallback> _wakers = [];
  Duration? _wokenAt;
  bool _waking = false;

  /// Calls [wake] soon after something changes, runs or is built while
  /// collecting, at most once in a tenth of a second: a view that animates
  /// the changes starts its frames then, and stops them when nothing is lit
  /// ([lastLit]). The returned function stops the calls.
  void Function() onActivity(VoidCallback wake) {
    _wakers.add(wake);
    return () => _wakers.remove(wake);
  }

  void _light(Object key) {
    final now = _clock();
    _lit[key] = now;
    _lastLit = now;
    if (_wakers.isEmpty || _waking) {
      return;
    }
    final woken = _wokenAt;
    if (woken != null && now - woken < const Duration(milliseconds: 100)) {
      return;
    }
    _wokenAt = now;
    _waking = true;
    scheduleMicrotask(() {
      _waking = false;
      for (final wake in List.of(_wakers)) {
        wake();
      }
    });
  }

  // Notes when [member] changed for real: a count of changes that grew
  // since it was last seen came with its last write.
  void _settle(ValueMember member) {
    final seen = _seenChanges[member];
    final changes = member.changes;
    if (seen == changes) {
      return;
    }
    if (seen != null) {
      _changedAt[member] = _wroteAt[member] ?? _clock();
    }
    _seenChanges[member] = changes;
  }

  @override
  void wrote(ValueMember member) {
    _settle(member);
    _writes[member] = (_writes[member] ?? 0) + 1;
    _wroteAt[member] = _clock();
  }

  @override
  void told(ValueMember member) {
    _ticks++;
    _tells[member] = (_tells[member] ?? 0) + 1;
    final now = _clock();
    _toldAt[member] = now;
    final last = _changesAtTold[member];
    final changes = member.changes;
    _changesAtTold[member] = changes;
    if (last == changes) {
      // Told with no new value since the last time: a collection changed
      // in place.
      _changedAt[member] = now;
      _seenChanges[member] = changes;
    } else {
      _settle(member);
      _changedAt[member] ??= _wroteAt[member] ?? now;
    }
    _light(member);
  }

  @override
  void read(SignalMember member) {
    if (_readers.isNotEmpty) {
      _readers.last.$2.add(member);
    }
    if (countReads) {
      (_reads[member] ??= _WindowCount(_readSlices)).add(_now);
    }
  }

  @override
  void flushed(SignalQueue queue, int count) => _flushes++;

  @override
  void dropped(SignalQueue queue, ValueMember member) =>
      _drops[queue.name] = (_drops[queue.name] ?? 0) + 1;

  @override
  void computed(ComputedMember member, Duration took, Object? error) {
    (_timings[member] ??= SignalTiming())._add(took);
    _light(member);
  }

  @override
  void ran(EffectFollower effect, Duration took, Object? error) {
    _effects++;
    (_timings[effect] ??= SignalTiming())._add(took);
    _light(effect);
  }

  @override
  void beginReader(Object reader) {
    _readers.add((reader, <SignalMember>{}));
    if (reader is! ComputedMember && reader is! EffectFollower) {
      (_rebuilds[reader] ??= _WindowCount(_readSlices)).add(_now);
      _light(reader);
    }
  }

  @override
  void endReader() {
    if (_readers.isEmpty) {
      return;
    }
    final (reader, read) = _readers.removeLast();
    final before = _readsOf[reader];
    if (before == null ||
        before.length != read.length ||
        !before.containsAll(read)) {
      _structure++;
    }
    _readsOf[reader] = read;
  }
}
