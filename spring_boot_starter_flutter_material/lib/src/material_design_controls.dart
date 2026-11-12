import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// Material's form controls for the widgets that draw a form without
/// knowing the design (the login form of
/// `spring_boot_starter_flutter_security`): a `TextField`, a
/// `FilledButton`, the palette's error color.
///
/// The `MaterialApp` the starter builds has them in its [DesignScope]. A
/// `MaterialApp` of your own gives them the same way:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => DesignScope(
///     controls: const MaterialDesignControls(),
///     textStyle: (context, style) => null,
///     selectable: (context, child) => SelectionArea(child: child),
///     child: child!,
///   ),
/// );
/// ```
final class MaterialDesignControls implements DesignControls, Ordered {
  /// The controls.
  const MaterialDesignControls();

  static const _spinner = SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  @override
  Widget textField(BuildContext context, DesignTextField field) => TextField(
    controller: field.controller,
    focusNode: field.focusNode,
    enabled: field.enabled,
    autofocus: field.autofocus,
    obscureText: field.obscureText,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: field.autofillHints,
    keyboardType: field.keyboardType,
    textInputAction: field.textInputAction,
    onSubmitted: field.onSubmitted,
    decoration: InputDecoration(
      labelText: field.label,
      errorText: field.errorText,
      suffixIcon: field.toggleObscured == null
          ? null
          : IconButton(
              onPressed: field.enabled ? field.toggleObscured : null,
              tooltip: field.toggleLabel,
              icon: Icon(
                field.obscureText ? Icons.visibility : Icons.visibility_off,
              ),
            ),
    ),
  );

  @override
  Widget filledButton(BuildContext context, DesignButton button) =>
      button.icon == null
      ? FilledButton(
          onPressed: button.onPressed,
          child: button.busy
              ? Semantics(label: button.label, child: _spinner)
              : Text(button.label),
        )
      : FilledButton.icon(
          onPressed: button.onPressed,
          icon: button.busy ? _spinner : button.icon,
          label: Text(button.label),
        );

  @override
  Color errorColor(BuildContext context) => Theme.of(context).colorScheme.error;

  // A Material field needs a Material above it; a screen without a
  // Scaffold gets a transparent one.
  @override
  bool isAppAbove(BuildContext context) =>
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) !=
      null;

  /// Before Cupertino's: a `MaterialApp` has Cupertino's localizations too.
  @override
  int get order => -100;

  @override
  Widget surface(BuildContext context, Widget child) =>
      Material.maybeOf(context) == null
      ? Material(type: MaterialType.transparency, child: child)
      : child;
}
