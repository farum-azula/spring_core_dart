import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_queue.dart';

/// What the debug tools hear of followed state: written, told, read,
/// computed, run. Nothing calls it unless a debug tool is attached
/// ([SignalProbes.current]), and the debug tools attach only while they
/// show: without them a member pays one check of a static field.
abstract interface class SignalProbe {
  /// [member] was assigned (its value may wait in a queue).
  void wrote(ValueMember member);

  /// The readers of [member] were told of a change.
  void told(ValueMember member);

  /// [member] was read.
  void read(SignalMember member);

  /// [queue] told [count] fields at once.
  void flushed(SignalQueue queue, int count);

  /// [queue] dropped or refused the write of [member] (it was full).
  void dropped(SignalQueue queue, ValueMember member);

  /// [member] was computed, in [took]; [error] when it failed.
  void computed(ComputedMember member, Duration took, Object? error);

  /// The [effect] of one bean ran, in [took]; [error] when it failed.
  void ran(EffectFollower effect, Duration took, Object? error);

  /// A reader starts a run ([reader]: a member, an effect of one bean
  /// ([EffectFollower]), a widget's tracking): what it reads from now on
  /// is what it follows.
  void beginReader(Object reader);

  /// The run of the reader begun last ended.
  void endReader();
}

/// The probe attached now, if any.
abstract final class SignalProbes {
  static final List<SignalProbe> _attached = [];

  /// The probe to tell, `null` when no debug tool listens: what the
  /// members check.
  static SignalProbe? current;

  /// Attaches [probe] until the returned function is called.
  static void Function() attach(SignalProbe probe) {
    _attached.add(probe);
    _update();
    return () {
      if (_attached.remove(probe)) {
        _update();
      }
    };
  }

  static void _update() => current = switch (_attached) {
    [] => null,
    [final only] => only,
    final all => _Many(List.of(all)),
  };
}

final class _Many implements SignalProbe {
  _Many(this.probes);

  final List<SignalProbe> probes;

  @override
  void wrote(ValueMember member) {
    for (final probe in probes) {
      probe.wrote(member);
    }
  }

  @override
  void told(ValueMember member) {
    for (final probe in probes) {
      probe.told(member);
    }
  }

  @override
  void read(SignalMember member) {
    for (final probe in probes) {
      probe.read(member);
    }
  }

  @override
  void flushed(SignalQueue queue, int count) {
    for (final probe in probes) {
      probe.flushed(queue, count);
    }
  }

  @override
  void dropped(SignalQueue queue, ValueMember member) {
    for (final probe in probes) {
      probe.dropped(queue, member);
    }
  }

  @override
  void computed(ComputedMember member, Duration took, Object? error) {
    for (final probe in probes) {
      probe.computed(member, took, error);
    }
  }

  @override
  void ran(EffectFollower effect, Duration took, Object? error) {
    for (final probe in probes) {
      probe.ran(effect, took, error);
    }
  }

  @override
  void beginReader(Object reader) {
    for (final probe in probes) {
      probe.beginReader(reader);
    }
  }

  @override
  void endReader() {
    for (final probe in probes) {
      probe.endReader();
    }
  }
}
