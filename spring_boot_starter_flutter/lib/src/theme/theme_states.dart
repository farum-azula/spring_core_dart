import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_styles.dart';

/// A widget of the app's own that follows a [ThemeStyle]: it tracks hover,
/// focus, press and disabled, takes `selected` and `error` from its
/// arguments, handles the keyboard and the mouse cursor, and animates the
/// style's values over its `transition`.
///
/// ```dart
/// ThemeStates(
///   style: context.theme.styles.neonChip,
///   selected: selected,
///   onPressed: onPressed,
///   builder: (context, s) => Container(
///     padding: s.padding,
///     decoration: BoxDecoration(color: s.fill),
///     child: Text(label),
///   ),
/// )
/// ```
///
/// The widget is disabled when [onPressed] is `null`. Enter and Space (an
/// `ActivateIntent`) call [onPressed] when the widget has focus. With
/// `MediaQuery.disableAnimations` the values change at once.
class ThemeStates<V> extends StatefulWidget {
  /// Builds with the values of [style] for the current state.
  const ThemeStates({
    required this.style,
    required this.builder,
    super.key,
    this.selected = false,
    this.error = false,
    this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.mouseCursor,
    this.showFocusAlways = false,
  });

  /// The style whose values are shown.
  final ThemeStyle<V> style;

  /// Whether the widget is selected.
  final bool selected;

  /// Whether the widget is in error.
  final bool error;

  /// Called on a tap, a click, Enter or Space; `null` disables the widget.
  final VoidCallback? onPressed;

  /// The focus node to use; the widget makes its own without one.
  final FocusNode? focusNode;

  /// Whether the widget takes focus when it is first shown.
  final bool autofocus;

  /// The cursor over the widget; by default the click cursor, and the
  /// basic one when it is disabled.
  final MouseCursor? mouseCursor;

  /// Whether `focused` shows whatever way the focus came (a tap, a click),
  /// not only with the keyboard. For a text input: its frame must light up
  /// when the user taps it. Buttons leave it off, as Flutter does.
  final bool showFocusAlways;

  /// Builds the child from the values of the current state.
  final Widget Function(BuildContext context, V values) builder;

  @override
  State<ThemeStates<V>> createState() => _ThemeStatesState<V>();
}

class _ThemeStatesState<V> extends State<ThemeStates<V>> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _set(void Function() change) {
    if (mounted) {
      setState(change);
    }
  }

  Set<WidgetState> get _states => {
    if (!_enabled) WidgetState.disabled,
    if (widget.error) WidgetState.error,
    if (_pressed) WidgetState.pressed,
    if (_hovered) WidgetState.hovered,
    if (_focused) WidgetState.focused,
    if (widget.selected) WidgetState.selected,
  };

  @override
  void didUpdateWidget(ThemeStates<V> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style.style;
    final target = style.resolve(_states);
    final animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return FocusableActionDetector(
      enabled: _enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor:
          widget.mouseCursor ??
          (_enabled ? SystemMouseCursors.click : MouseCursor.defer),
      onShowFocusHighlight: widget.showFocusAlways
          ? null
          : (value) => _set(() => _focused = value),
      onFocusChange: widget.showFocusAlways
          ? (value) => _set(() => _focused = value)
          : null,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => _set(() => _hovered = true),
        onExit: (_) => _set(() => _hovered = false),
        child: Listener(
          onPointerDown: _enabled
              ? (event) {
                  if (event.buttons & kPrimaryButton != 0) {
                    _set(() => _pressed = true);
                  }
                }
              : null,
          onPointerUp: (_) => _set(() => _pressed = false),
          onPointerCancel: (_) => _set(() => _pressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: TweenAnimationBuilder<StyleValues>(
              tween: _StyleTween(end: target),
              duration: animate ? style.transition : Duration.zero,
              curve: style.transitionCurve,
              builder: (context, values, _) =>
                  widget.builder(context, widget.style.view(values)),
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleTween extends Tween<StyleValues> {
  _StyleTween({super.end});

  @override
  StyleValues lerp(double t) => StyleValues.lerp(begin ?? end!, end!, t);
}
