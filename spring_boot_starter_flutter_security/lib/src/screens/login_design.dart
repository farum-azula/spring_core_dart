import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The look the login widgets ([LoginForm], [OAuth2LoginButton]) draw
/// themselves in: the app's own design, so a login screen fits the rest
/// of the app.
///
/// They find it by themselves from the app widget above them, the one
/// `spring.flutter.app.type` chooses: a `MaterialApp` gives [material]
/// (text fields and filled buttons of Material 3, styled by the app's
/// `ThemeData`, so `spring.flutter.theme.components.input.*` and
/// `button.*` apply), a `CupertinoApp` gives [cupertino] (the iOS fields
/// and buttons, styled by the `CupertinoTheme`), a plain `WidgetsApp`
/// gives [widgets] (simple fields and buttons drawn from the colours of
/// the `SpringTheme`, needing neither Material nor Cupertino). Pass a
/// design to a widget only to override that choice.
///
/// Spring has no counterpart: its default login page is HTML of the
/// server.
enum LoginDesign {
  /// Material 3: `TextField`, `FilledButton`, `CircularProgressIndicator`.
  material,

  /// Cupertino: `CupertinoTextField`, `CupertinoButton.filled`,
  /// `CupertinoActivityIndicator`.
  cupertino,

  /// Plain widgets (`EditableText`, a button drawn here), coloured from
  /// the `SpringTheme`.
  widgets;

  /// The design of the app above [context]: [material] below a
  /// `MaterialApp` (its Material localizations), [cupertino] below a
  /// `CupertinoApp`, [widgets] otherwise.
  static LoginDesign of(BuildContext context) {
    if (Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) !=
        null) {
      return material;
    }
    if (Localizations.of<CupertinoLocalizations>(
          context,
          CupertinoLocalizations,
        ) !=
        null) {
      return cupertino;
    }
    return widgets;
  }
}

/// The text of message [code] from the app's messages files, in the
/// app's locale, or [fallback] (with `{0}`, ... filled from [args]) when
/// no file has it or there is no `SpringScope` above.
String loginMessage(
  BuildContext context,
  String code,
  String fallback, [
  List<Object?> args = const [],
]) {
  final spring = SpringScope.maybeOf(context, listen: false);
  if (spring == null) {
    var text = fallback;
    for (var i = 0; i < args.length; i++) {
      text = text.replaceAll('{$i}', '${args[i]}');
    }
    return text;
  }
  return spring.getMessage(
    code,
    args: args,
    defaultMessage: fallback,
    locale:
        (Localizations.maybeLocaleOf(context) ??
                PlatformDispatcher.instance.locale)
            .toString(),
  );
}

/// The colours of the plain [LoginDesign.widgets] design, from the
/// `SpringTheme` (Material 3's baseline without one).
ColorScheme loginColorScheme(BuildContext context) =>
    SpringTheme.maybeOf(context)?.colorScheme ??
    ThemeData(brightness: Brightness.light).colorScheme;

/// A small spinner of [color], drawn without Material or Cupertino: the
/// progress of the plain design and of the brand buttons.
class LoginSpinner extends StatefulWidget {
  /// A spinner [size] logical pixels wide.
  const LoginSpinner({required this.color, this.size = 16, super.key});

  /// The colour of the arc.
  final Color color;

  /// The width and height.
  final double size;

  @override
  State<LoginSpinner> createState() => _LoginSpinnerState();
}

class _LoginSpinnerState extends State<LoginSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    // Tests settle with animations off (`disableAnimations`): a still arc.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _turns.repeat();
      }
    });
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    // The button around it says it is busy; the arc itself is decoration.
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: widget.size,
      child: RotationTransition(
        turns: _turns,
        child: CustomPaint(painter: _ArcPainter(widget.color)),
      ),
    ),
  );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide / 8;
    canvas.drawArc(
      (Offset.zero & size).deflate(stroke / 2),
      0,
      math.pi * 1.5,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color;
}

/// A pressable area without Material: tap, Enter and Space, a hover and a
/// press overlay of [overlayColor], the focus for [builder] to draw, a
/// click cursor, and the semantics of a button. The plain design's button
/// and the brand buttons draw their own look inside it.
class LoginPressable extends StatefulWidget {
  /// A button calling [onPressed] (`null`: disabled), drawing [builder]'s
  /// look with the current overlay.
  const LoginPressable({
    required this.onPressed,
    required this.builder,
    required this.overlayColor,
    this.semanticsLabel,
    this.busy = false,
    this.autofocus = false,
    super.key,
  });

  /// Called on a tap, Enter or Space; `null` disables the button.
  final VoidCallback? onPressed;

  /// Draws the button, with [overlay] (transparent at rest) to lay over
  /// its background and whether it has the keyboard focus.
  final Widget Function(BuildContext context, Color overlay, bool focused)
  builder;

  /// The colour of the hover (8 %) and press (12 %) overlays: the colour
  /// of the button's text, as Material's state layers.
  final Color overlayColor;

  /// What a screen reader says; the texts inside otherwise.
  final String? semanticsLabel;

  /// Whether the action runs: said to screen readers.
  final bool busy;

  /// Whether the button takes the focus when it first appears.
  final bool autofocus;

  @override
  State<LoginPressable> createState() => _LoginPressableState();
}

class _LoginPressableState extends State<LoginPressable> {
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => widget.onPressed?.call(),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final overlay = !enabled
        ? const Color(0x00000000)
        : widget.overlayColor.withValues(
            alpha: _pressed ? 0.12 : (_hovered || _focused ? 0.08 : 0),
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel,
      // A screen reader hears the login is running.
      value: widget.busy ? '…' : null,
      child: FocusableActionDetector(
        enabled: enabled,
        autofocus: widget.autofocus,
        actions: _actions,
        shortcuts: _activateKeys,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          // The label says it all; the texts inside are not read twice.
          child: ExcludeSemantics(
            excluding: widget.semanticsLabel != null,
            child: widget.builder(context, overlay, _focused && enabled),
          ),
        ),
      ),
    );
  }
}

// Enter and Space press the button, also outside a `WidgetsApp` (whose
// shortcuts have them too).
const _activateKeys = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};
