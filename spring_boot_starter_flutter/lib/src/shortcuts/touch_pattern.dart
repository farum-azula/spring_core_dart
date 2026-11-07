import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_keys.dart';

/// A shortcut done on a touch screen (or with a mouse) rather than a
/// keyboard: a number of quick taps, then, optionally, one press held.
/// `taps:4+hold:3s` is four quick taps and a fifth press held three
/// seconds.
@immutable
final class TouchPattern {
  /// [taps] quick taps, then a press held [hold] when it is set.
  const TouchPattern(this.taps, {this.hold});

  /// The quick taps.
  final int taps;

  /// How long the press after the taps is held; `null`: none, the last
  /// tap ends the pattern.
  final Duration? hold;

  @override
  bool operator ==(Object other) =>
      other is TouchPattern && other.taps == taps && other.hold == hold;

  @override
  int get hashCode => Object.hash(taps, hold);

  @override
  String toString() =>
      hold == null ? '$taps taps' : '$taps taps, hold ${_seconds(hold!)}';

  static String _seconds(Duration duration) =>
      duration.inMilliseconds % 1000 == 0
      ? '${duration.inSeconds} s'
      : '${duration.inMilliseconds} ms';
}

/// Shortcut keys that are a [TouchPattern], not keys: the starter listens
/// for them over the whole app.
abstract interface class ShortcutGesture implements ShortcutKeys {
  /// The pattern.
  TouchPattern get pattern;
}

/// `taps:4` or `taps:4+hold:3s`: quick taps anywhere on the screen, then,
/// with `hold`, one press held that long (`ms` or `s`). The same on every
/// platform: a finger, a pen or a mouse.
final class TouchPatternNotation implements ShortcutNotation {
  /// The notation of touch patterns.
  const TouchPatternNotation();

  static const _prefix = 'taps:';

  @override
  bool supports(String text) => text.startsWith(_prefix);

  @override
  ShortcutKeys parse(String text, TargetPlatform platform) {
    final match = RegExp(
      r'^taps:(\d+)(?:\+hold:(\d+)(ms|s))?$',
    ).firstMatch(text.replaceAll(' ', ''));
    final taps = match == null ? null : int.parse(match.group(1)!);
    if (match == null || taps == null || taps < 1 || taps > 10) {
      throw const FormatException(
        'taps:<1 to 10>, or taps:<n>+hold:<duration> as taps:4+hold:3s',
      );
    }
    final amount = match.group(2);
    Duration? hold;
    if (amount != null) {
      final value = int.parse(amount);
      hold = match.group(3) == 'ms'
          ? Duration(milliseconds: value)
          : Duration(seconds: value);
      if (hold == Duration.zero) {
        throw const FormatException('hold takes a duration over zero');
      }
    }
    return _Gesture(TouchPattern(taps, hold: hold));
  }
}

final class _Gesture implements ShortcutGesture {
  const _Gesture(this.pattern);

  @override
  final TouchPattern pattern;

  @override
  ShortcutActivator get activator => const _NoKeys();

  @override
  String label(TargetPlatform platform) => '$pattern';
}

// A gesture is no keys: it never matches a key event.
final class _NoKeys extends ShortcutActivator {
  const _NoKeys();

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) => false;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => const [];

  @override
  String debugDescribeKeys() => 'touch';
}

/// Listens for [patterns] over [child] and calls [onMatch] with the action
/// of the one done. It only listens: every touch still reaches the app.
class TouchPatternDetector extends StatefulWidget {
  /// Listens for [patterns] (by action) over [child].
  const TouchPatternDetector({
    required this.patterns,
    required this.onMatch,
    required this.child,
    super.key,
  });

  /// The patterns of each action.
  final Map<String, List<TouchPattern>> patterns;

  /// Called with the action whose pattern was done.
  final void Function(String action, BuildContext context) onMatch;

  /// The app below.
  final Widget child;

  /// The longest a tap lasts.
  static const tapTime = Duration(milliseconds: 300);

  /// The longest pause between two taps.
  static const tapGap = Duration(milliseconds: 400);

  /// How far a finger may move and still tap or hold.
  static const slop = 18.0;

  @override
  State<TouchPatternDetector> createState() => _TouchPatternDetectorState();
}

class _TouchPatternDetectorState extends State<TouchPatternDetector> {
  int _taps = 0;
  int? _pointer;
  Offset _start = Offset.zero;
  // Timers, not clocks, so a test's fake time drives them too: a press
  // that outlives [TouchPatternDetector.tapTime] is no tap, a pause that
  // outlives [TouchPatternDetector.tapGap] starts the taps again.
  bool _long = false;
  Timer? _pressTimer;
  Timer? _gapTimer;
  final _holds = <Timer>[];

  int get _most => widget.patterns.values
      .expand((patterns) => patterns)
      .fold(0, (most, pattern) => pattern.taps > most ? pattern.taps : most);

  void _reset() {
    _taps = 0;
    _pointer = null;
    _gapTimer?.cancel();
    _cancelHolds();
  }

  void _cancelHolds() {
    for (final hold in _holds) {
      hold.cancel();
    }
    _holds.clear();
  }

  @override
  void dispose() {
    _pressTimer?.cancel();
    _gapTimer?.cancel();
    _cancelHolds();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) {
      _reset(); // a second finger: no pattern
      return;
    }
    _gapTimer?.cancel();
    _pointer = event.pointer;
    _start = event.position;
    _long = false;
    _pressTimer?.cancel();
    _pressTimer = Timer(TouchPatternDetector.tapTime, () => _long = true);
    _cancelHolds();
    for (final MapEntry(key: action, value: patterns)
        in widget.patterns.entries) {
      for (final pattern in patterns) {
        final hold = pattern.hold;
        if (hold != null && _taps == pattern.taps) {
          _holds.add(
            Timer(hold, () {
              if (mounted && _pointer != null) {
                _reset();
                widget.onMatch(action, context);
              }
            }),
          );
        }
      }
    }
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer == _pointer &&
        (event.position - _start).distance > TouchPatternDetector.slop) {
      _reset(); // a drag or a scroll
    }
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _pressTimer?.cancel();
    _cancelHolds();
    if (_long) {
      _taps = 0;
      return;
    }
    _taps = (_taps + 1).clamp(0, _most);
    _gapTimer = Timer(TouchPatternDetector.tapGap, () => _taps = 0);
    for (final MapEntry(key: action, value: patterns)
        in widget.patterns.entries) {
      for (final pattern in patterns) {
        if (pattern.hold == null && _taps == pattern.taps) {
          _reset();
          widget.onMatch(action, context);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: (_) => _reset(),
    child: widget.child,
  );
}
