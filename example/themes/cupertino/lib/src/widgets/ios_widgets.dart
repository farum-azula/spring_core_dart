import 'package:flutter/cupertino.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';

// The app's own widgets. The Cupertino widgets get their look from the
// `cupertino.*` block; these have no Flutter theme, so their looks are the
// `styles.*` of the YAML and ThemeStates follows hover, focus, press,
// selected, disabled and error for them. They are built from Cupertino
// and basic widgets only.

/// A pill that can be selected: `styles.ios-chip`.
class IosChip extends StatelessWidget {
  const IosChip(
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
    style: context.theme.styles.iosChip,
    selected: selected,
    error: error,
    onPressed: onPressed,
    builder: (context, s) => Opacity(
      opacity: s.opacity,
      child: Container(
        padding: s.padding,
        decoration: BoxDecoration(
          color: s.fill,
          borderRadius: BorderRadius.circular(s.radius),
          border: Border.all(color: s.border),
        ),
        child: Text(
          label,
          style: context.theme.typography.labelLarge.copyWith(
            fontSize: 15,
            color: s.text,
          ),
        ),
      ),
    ),
  );
}

/// A filled button: `styles.ios-button`. A press fades it, as on iOS.
class IosButton extends StatelessWidget {
  const IosButton(this.label, {super.key, this.onPressed});

  final String label;

  /// Null: the button is disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ThemeStates(
    style: context.theme.styles.iosButton,
    onPressed: onPressed,
    builder: (context, s) => Opacity(
      opacity: s.opacity,
      child: Container(
        padding: s.padding,
        decoration: BoxDecoration(
          color: s.fill,
          borderRadius: BorderRadius.circular(s.radius),
          border: Border.all(color: s.border, width: 2),
        ),
        child: Text(
          label,
          style: context.theme.typography.labelLarge.copyWith(color: s.text),
        ),
      ),
    ),
  );
}

/// A text field in a frame that follows the states: `styles.ios-field`. The
/// frame is ours, the text field inside is Cupertino's.
class IosField extends StatefulWidget {
  const IosField({
    required this.placeholder,
    super.key,
    this.error = false,
    this.enabled = true,
    this.initialText = '',
  });

  final String placeholder;
  final bool error;
  final bool enabled;
  final String initialText;

  @override
  State<IosField> createState() => _IosFieldState();
}

class _IosFieldState extends State<IosField> {
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
    style: context.theme.styles.iosField,
    error: widget.error,
    focusNode: _frame,
    mouseCursor: SystemMouseCursors.text,
    onPressed: widget.enabled ? _input.requestFocus : null,
    builder: (context, s) => Container(
      padding: s.padding,
      decoration: BoxDecoration(
        color: s.fill,
        borderRadius: BorderRadius.circular(s.radius),
        border: Border.all(color: s.border, width: s.width),
      ),
      child: CupertinoTextField(
        controller: _controller,
        focusNode: _input,
        enabled: widget.enabled,
        placeholder: widget.placeholder,
        padding: EdgeInsets.zero,
        // The frame draws the box; the field inside draws only the text.
        decoration: null,
      ),
    ),
  );
}

/// A card that is selected on tap: `styles.ios-card`.
class IosCard extends StatelessWidget {
  const IosCard({
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
    style: context.theme.styles.iosCard,
    selected: selected,
    onPressed: onPressed,
    builder: (context, s) => Opacity(
      opacity: s.opacity,
      child: Container(
        padding: s.padding,
        decoration: BoxDecoration(
          color: s.fill,
          borderRadius: BorderRadius.circular(s.radius),
          border: Border.all(color: s.border, width: s.width),
        ),
        child: child,
      ),
    ),
  );
}
