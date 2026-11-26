import 'dart:collection';

import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugValueText;

import 'package:spring_boot_starter_flutter_signals/src/debug/signals_debug_recorder.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';

/// What a member or an effect is, in a row of the Signals tab.
enum SignalsRowKind {
  /// A `@Signal` field.
  signal,

  /// A `@Computed` value.
  computed,

  /// A `@Computed` value of a `Future` or a `Stream`.
  asynchronous,

  /// An `@Effect` method.
  effect,
}

/// How the value of a row is drawn.
enum SignalsValueTone {
  /// A value: the debug theme's `number` colour.
  value,

  /// A load running: amber.
  loading,

  /// A computation or a load that failed: red.
  failed,

  /// Not shown: a lock, with why in its hint ([SignalsRow.lock]).
  locked,

  /// Nothing to show (an effect, a `late` field not assigned): muted.
  none,
}

/// One row of the Signals tab, and what a node of the graph tells when
/// tapped: a member's or an effect's value, times and counts, read
/// without following anything.
final class SignalsRow {
  /// A row of these values.
  const SignalsRow({
    required this.node,
    required this.label,
    required this.kind,
    required this.value,
    this.tone = SignalsValueTone.value,
    this.lock,
    this.expandable,
    this.changedAt,
    this.toldAt,
    this.changes,
    this.writes,
    this.ticks,
    this.reads,
    this.timing,
    this.queue,
  });

  /// The row of [member], with the counts and times of [recorder].
  factory SignalsRow.member(
    SignalMember member,
    SignalsDebugRecorder? recorder,
  ) {
    final label = member.name.split('.').last;
    return switch (member) {
      final ValueMember value => _value(value, label, recorder),
      final AsyncMember async => _async(async, label, recorder),
      final ComputedMember computed => _computed(computed, label, recorder),
    };
  }

  /// The row of the effect [name] of [bean], which ran [runs] times.
  factory SignalsRow.effect(
    SignalBean bean,
    String name,
    int runs,
    SignalsDebugRecorder? recorder,
  ) {
    // Keyed by the effect of this bean, apart from another bean's.
    final effect = bean.effectFollowers[name];
    return SignalsRow(
      node: effect ?? '${bean.label}.$name',
      label: '$name()',
      kind: SignalsRowKind.effect,
      value: 'effect',
      tone: SignalsValueTone.none,
      changedAt: effect == null ? null : recorder?.litAt(effect),
      changes: runs,
      timing: effect == null ? null : recorder?.timingOf(effect),
    );
  }

  static SignalsRow _value(
    ValueMember member,
    String label,
    SignalsDebugRecorder? recorder,
  ) {
    final (value, tone, lock, expandable) = switch (member) {
      ValueMember(unset: true) => (
        'late, unset',
        SignalsValueTone.none,
        null,
        null,
      ),
      ValueMember(hidden: true) => (
        '',
        SignalsValueTone.locked,
        'hidden: @Signal(hidden: true) or a name that looks secret',
        null,
      ),
      _ => (
        SignalsValues.short(member.peek()),
        SignalsValueTone.value,
        null,
        SignalsValues.expandable(member.peek()),
      ),
    };
    return SignalsRow(
      node: member,
      label: label,
      kind: SignalsRowKind.signal,
      value: value,
      tone: tone,
      lock: lock,
      expandable: expandable,
      changedAt: recorder?.changedAt(member),
      toldAt: recorder?.toldAt(member),
      changes: member.changes,
      writes: recorder?.writesOf(member),
      ticks: recorder?.tellsOf(member),
      reads: recorder?.readsOf(member),
      queue: [
        member.options.queue ?? 'default',
        if (member.waiting) 'waiting',
      ].join(', '),
    );
  }

  static const _callers = "the caller's: kept for the user it was computed for";

  static const _secret = 'hidden: a name that looks secret';

  static SignalsRow _computed(
    ComputedMember member,
    String label,
    SignalsDebugRecorder? recorder,
  ) {
    final timing = recorder?.timingOf(member);
    final (value, tone, lock) = switch (member) {
      ComputedMember(secret: true) => ('', SignalsValueTone.locked, _secret),
      ComputedMember(callerBound: true) => (
        '',
        SignalsValueTone.locked,
        _callers,
      ),
      _ => _peeked(member),
    };
    return SignalsRow(
      node: member,
      label: label,
      kind: SignalsRowKind.computed,
      value: value,
      tone: tone,
      lock: lock,
      changedAt: recorder?.litAt(member),
      changes: timing?.count,
      reads: recorder?.readsOf(member),
      timing: timing,
    );
  }

  static (String, SignalsValueTone, String?) _peeked(ComputedMember member) {
    try {
      final value = member.peek();
      // The peek may have computed it, and so made it the caller's.
      if (member.callerBound) {
        return ('', SignalsValueTone.locked, _callers);
      }
      return (SignalsValues.short(value), SignalsValueTone.value, null);
    } on Object catch (error) {
      return (
        'failed: ${SignalsValues.short(error)}',
        SignalsValueTone.failed,
        null,
      );
    }
  }

  static SignalsRow _async(
    AsyncMember member,
    String label,
    SignalsDebugRecorder? recorder,
  ) {
    final state = member.stateNow;
    final locked = member.secret
        ? _secret
        : member.callerBound
        ? _callers
        : null;
    final (value, tone, lock) = state.hasValue
        ? locked == null
              ? (
                  SignalsValues.short(state.value),
                  state.isLoading
                      ? SignalsValueTone.loading
                      : SignalsValueTone.value,
                  null,
                )
              : ('', SignalsValueTone.locked, locked)
        : state.hasError
        ? (
            locked == null
                ? 'failed: ${SignalsValues.short(state.error)}'
                : 'failed',
            SignalsValueTone.failed,
            null,
          )
        : ('loading', SignalsValueTone.loading, null);
    return SignalsRow(
      node: member,
      label: label,
      kind: SignalsRowKind.asynchronous,
      value: value,
      tone: tone,
      lock: lock,
      expandable: locked == null && state.hasValue
          ? SignalsValues.expandable(state.value)
          : null,
      changedAt: recorder?.litAt(member),
      changes: member.loads,
      reads: recorder?.readsOf(member),
      timing: recorder?.timingOf(member),
    );
  }

  /// The member, the effect of one bean ([EffectFollower]) or the
  /// widget's tracking it is of.
  final Object node;

  /// The member's name in its bean (`items`), an effect's (`save()`).
  final String label;

  /// What it is.
  final SignalsRowKind kind;

  /// The value, short ([SignalsValues.short]).
  final String value;

  /// How [value] is drawn.
  final SignalsValueTone tone;

  /// Why the value is not shown, for a [SignalsValueTone.locked] one.
  final String? lock;

  /// A collection whose items a tap on the value shows.
  final Object? expandable;

  /// When it last changed for real (a computed value: was computed; an
  /// effect: ran), on the recorder's clock.
  final Duration? changedAt;

  /// When its readers were last told (a `@Signal` field only).
  final Duration? toldAt;

  /// Real changes of a field, computations, loads, runs.
  final int? changes;

  /// Assignments of a field while collecting.
  final int? writes;

  /// Publications to the readers of a field while collecting.
  final int? ticks;

  /// Reads over the recorder's read window.
  final int? reads;

  /// The times of a computation or an effect.
  final SignalTiming? timing;

  /// The queue of a field, and whether a write waits in it.
  final String? queue;
}

/// How the Signals tab writes values: short.
abstract final class SignalsValues {
  /// [value] in at most [max] characters, as the debug tools write every
  /// value ([DebugValueText.shortOf]): a collection as `List(3)`, a text
  /// quoted with the secrets of its addresses masked, an object without a
  /// `toString` of its own as its type's name, one line cut with `…`.
  static String short(Object? value, {int max = 40}) =>
      DebugValueText.shortOf(value, max: max, objectText: true);

  /// [value] when its items can be shown at once (a list, set, queue or
  /// map), else `null`.
  static Object? expandable(Object? value) => switch (value) {
    Map<Object?, Object?>() ||
    List<Object?>() ||
    Set<Object?>() ||
    Queue<Object?>() => value,
    _ => null,
  };

  /// The first [count] items of [collection], each short, and how many
  /// more there are.
  static String items(Object collection, {int count = 20}) {
    final (parts, length) = switch (collection) {
      final Map<Object?, Object?> map => (
        [
          for (final MapEntry(:key, :value) in map.entries.take(count))
            '${short(key, max: 24)}: ${short(value, max: 24)}',
        ],
        map.length,
      ),
      final Iterable<Object?> items => (
        [for (final item in items.take(count)) short(item, max: 24)],
        items.length,
      ),
      _ => (const <String>[], 0),
    };
    final more = length - parts.length;
    return [...parts, if (more > 0) '… $more more'].join(', ');
  }

  /// How long ago [at] was at [now]: `0.4s`, `12s`, `3m`, `2h`; `—` for
  /// never.
  static String ago(Duration? at, Duration now) {
    if (at == null) {
      return '—';
    }
    final age = now - at;
    final micros = age.isNegative ? 0 : age.inMicroseconds;
    if (micros < 10 * Duration.microsecondsPerSecond) {
      return '${(micros / Duration.microsecondsPerSecond).toStringAsFixed(1)}s';
    }
    if (micros < Duration.microsecondsPerMinute) {
      return '${micros ~/ Duration.microsecondsPerSecond}s';
    }
    if (micros < Duration.microsecondsPerHour) {
      return '${micros ~/ Duration.microsecondsPerMinute}m';
    }
    return '${micros ~/ Duration.microsecondsPerHour}h';
  }

  /// A time taken: `12µs`, `1.4ms`; `—` for none.
  static String took(Duration? took) {
    if (took == null) {
      return '—';
    }
    final micros = took.inMicroseconds;
    return micros < 1000
        ? '$microsµs'
        : '${(micros / 1000).toStringAsFixed(1)}ms';
  }
}
