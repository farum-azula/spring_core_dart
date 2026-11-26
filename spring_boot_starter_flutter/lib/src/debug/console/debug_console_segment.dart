import 'dart:async';

import 'package:flutter/foundation.dart';

/// A compact value in the header of the debug console (`fps 60`,
/// `lost 0`): a bean, picked by its name in
/// `spring.flutter.debug.console.segments` (the build's) and
/// `spring.flutter.debug.console.header` (shown at the start, in its
/// order; the debug panel's Console tab switches them while the app runs):
/// the one its
/// `@ConsoleSegment` gives when it has one, else [name] (a segment
/// registered as a plain bean or made by hand). A [name] that disagrees
/// with the annotation fails the build (and, for one the build cannot
/// read, the start).
///
/// The console starts it when it shows and stops it when it hides, so a
/// segment measures nothing while hidden; [start]'s `changed` asks the
/// console to read it again, which it does at most once a frame, however
/// often it is called.
///
/// The framework's own (this starter's `fps`, `frames-lost`, `filter`,
/// `isolates`, `memory`, `timeline`, `net`, and the other starters') are
/// beans like an application's, and like it each is in the build only
/// when `segments` names it or holds `*`; not set, its module says
/// whether it is in (this starter's `fps`, `frames-lost` and `filter`
/// are, and a starter documents its own):
///
/// ```dart
/// @ConsoleSegment('ping', order: 50)
/// class PingSegment extends DebugConsoleSegment {
///   PingSegment(this.client);
///
///   final PingClient client;
///
///   @override
///   void Function() start(void Function() changed) =>
///       client.addListener(changed);
///
///   @override
///   DebugConsoleValue? read() =>
///       DebugConsoleValue('${client.lastMs}', label: 'ping');
/// }
/// ```
///
/// [SampledDebugConsoleSegment] reads a value on a timer instead.
///
/// Spring has no counterpart.
abstract class DebugConsoleSegment {
  /// A segment.
  const DebugConsoleSegment();

  /// Its name in `spring.flutter.debug.console.segments` when no
  /// `@ConsoleSegment` names it; `null` (the default): the annotation's.
  String? get name => null;

  /// Starts what the segment measures, while the console shows: [changed]
  /// whenever its value may have changed. Returns what stops it.
  void Function() start(void Function() changed);

  /// What it shows now; `null`: nothing (a segment of frames while
  /// nothing draws them).
  DebugConsoleValue? read();
}

/// How a segment's value is drawn.
enum DebugConsoleTone {
  /// A number, in the theme's primary colour, so it stands out.
  number,

  /// Text, in the console's own colour.
  text,

  /// A good state, green.
  good,

  /// A warning, amber.
  warning,

  /// A bad state, red.
  bad,

  /// A value of no interest now, such as a zero, in the muted colour.
  muted,
}

/// What a [DebugConsoleSegment] shows: a muted [label] and its [value],
/// drawn by [tone].
@immutable
final class DebugConsoleValue {
  /// [value] after [label], drawn as [tone] says.
  const DebugConsoleValue(
    this.value, {
    this.label,
    this.tone = DebugConsoleTone.number,
    this.unit,
  }) : parts = const [];

  /// A value of several [parts] after [label], each drawn by its own tone
  /// and after its own label, muted, when it has one
  /// (`signals 3 ticks · 0 flushes · 2 effects`, `mem 182 MB · img 34 MB`).
  const DebugConsoleValue.of(this.parts, {this.label})
    : value = '',
      tone = DebugConsoleTone.text,
      unit = null;

  /// The value (`60`).
  final String value;

  /// What it is (`fps`), muted before it; `null`: the value alone.
  final String? label;

  /// How the value is drawn.
  final DebugConsoleTone tone;

  /// What the value counts (`ticks`), muted after it; `null`: nothing.
  final String? unit;

  /// The parts of a value of several ([DebugConsoleValue.of]); empty for
  /// one value.
  final List<DebugConsoleValue> parts;

  @override
  bool operator ==(Object other) =>
      other is DebugConsoleValue &&
      other.value == value &&
      other.label == label &&
      other.tone == tone &&
      other.unit == unit &&
      listEquals(other.parts, parts);

  @override
  int get hashCode =>
      Object.hash(value, label, tone, unit, Object.hashAll(parts));

  @override
  String toString() {
    final shown = parts.isEmpty ? [value, ?unit].join(' ') : parts.join(' · ');
    return label == null ? shown : '$label $shown';
  }
}

/// A [DebugConsoleSegment] read every [interval] while the console shows:
/// the console is asked to draw it again only when [read] gives another
/// value.
abstract class SampledDebugConsoleSegment extends DebugConsoleSegment {
  /// A segment read every [interval].
  const SampledDebugConsoleSegment({
    this.interval = const Duration(milliseconds: 250),
  });

  /// How often it is read while the console shows.
  final Duration interval;

  /// Called when the console shows, before the first read: what the
  /// segment starts to measure, and what stops it.
  void Function()? open() => null;

  @override
  void Function() start(void Function() changed) {
    final close = open();
    var last = read();
    final timer = Timer.periodic(interval, (_) {
      final value = read();
      if (value != last) {
        last = value;
        changed();
      }
    });
    return () {
      timer.cancel();
      close?.call();
    };
  }
}
