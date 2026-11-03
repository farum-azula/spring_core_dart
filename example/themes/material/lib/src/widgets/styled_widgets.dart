import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

// The app's own widgets. Flutter's widgets get their look from
// `components.*`; these have no Flutter theme, so their looks are the
// `styles.*` of the YAML and ThemeStates follows hover, focus, press,
// selected, disabled and error for them.

/// A pill that can be selected: `styles.pill`.
class PillChip extends StatelessWidget {
  const PillChip(
    this.label, {
    super.key,
    this.selected = false,
    this.error = false,
    this.onPressed,
  });

  final String label;
  final bool selected;
  final bool error;

  /// Null: the chip is disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ThemeStates(
    style: context.theme.styles.pill,
    selected: selected,
    error: error,
    onPressed: onPressed,
    builder: (context, s) => Container(
      padding: s.padding,
      decoration: BoxDecoration(
        color: s.fill,
        borderRadius: BorderRadius.circular(s.radius),
        border: Border.all(color: s.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: s.text),
      ),
    ),
  );
}

/// A button with a glow: `styles.action`.
class ActionButton extends StatelessWidget {
  const ActionButton(this.label, {super.key, this.onPressed});

  final String label;

  /// Null: the button is disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ThemeStates(
    style: context.theme.styles.action,
    onPressed: onPressed,
    builder: (context, s) => Container(
      padding: s.padding,
      decoration: BoxDecoration(
        color: s.fill,
        borderRadius: BorderRadius.circular(s.radius),
        border: Border.all(color: s.border, width: 2),
        boxShadow: [
          if (s.glow > 0)
            BoxShadow(
              color: s.fill.withValues(alpha: 0.7),
              blurRadius: s.glow,
              spreadRadius: s.glow / 6,
            ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: s.text,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

/// A text field in a frame that glows when focused or wrong:
/// `styles.field`. The frame follows the states, the text field inside
/// is Flutter's.
class BoxField extends StatefulWidget {
  const BoxField({
    required this.label,
    super.key,
    this.error = false,
    this.enabled = true,
    this.initialText = '',
  });

  final String label;
  final bool error;
  final bool enabled;
  final String initialText;

  @override
  State<BoxField> createState() => _BoxFieldState();
}

class _BoxFieldState extends State<BoxField> {
  final _frame = FocusNode(skipTraversal: true);
  final _input = FocusNode();
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _frame.dispose();
    _input.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ThemeStates(
    style: context.theme.styles.field,
    error: widget.error,
    focusNode: _frame,
    mouseCursor: SystemMouseCursors.text,
    onPressed: widget.enabled ? _input.requestFocus : null,
    builder: (context, s) => Container(
      padding: s.padding,
      decoration: BoxDecoration(
        color: s.fill,
        borderRadius: BorderRadius.circular(s.radius),
        border: Border.all(color: s.border, width: 2),
        boxShadow: [
          if (s.glow > 0)
            BoxShadow(
              color: s.border.withValues(alpha: 0.5),
              blurRadius: s.glow,
            ),
        ],
      ),
      child: TextField(
        controller: _controller,
        focusNode: _input,
        enabled: widget.enabled,
        decoration: InputDecoration.collapsed(hintText: widget.label),
      ),
    ),
  );
}

/// A card that is selected on tap: `styles.tile`.
class TileCard extends StatelessWidget {
  const TileCard({
    required this.child,
    super.key,
    this.selected = false,
    this.onPressed,
  });

  final Widget child;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ThemeStates(
    style: context.theme.styles.tile,
    selected: selected,
    onPressed: onPressed,
    builder: (context, s) => Container(
      padding: s.padding,
      decoration: BoxDecoration(
        color: s.fill,
        borderRadius: BorderRadius.circular(s.radius),
        border: Border.all(color: s.border, width: 1.5),
        boxShadow: [
          if (s.glow > 0)
            BoxShadow(
              color: s.border.withValues(alpha: 0.45),
              blurRadius: s.glow,
            ),
        ],
      ),
      child: child,
    ),
  );
}

/// A ring of color that turns around [child]: the animation `border-spin`
/// (`repeat: loop`) drives the angle of a sweep gradient.
class GlowBorder extends StatelessWidget {
  const GlowBorder({required this.child, super.key, this.width = 3});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.tokens.chart.colors;
    final radius = context.theme.tokens.layout.card.radius;
    return ThemeAnimation(
      context.theme.animations.borderSpin,
      builder: (context, t) => AnimatedBuilder(
        animation: t,
        builder: (context, _) => Container(
          padding: EdgeInsets.all(width),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: SweepGradient(
              transform: GradientRotation(t.value * 2 * 3.14159265),
              colors: [...colors, colors.first],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - width),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
