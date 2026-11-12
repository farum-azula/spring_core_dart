import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// Cupertino's form controls for widgets that draw a form without knowing
/// the design (the login form of `spring_boot_starter_flutter_security`):
/// a `CupertinoTextField` with its error below, a filled
/// `CupertinoButton`, iOS's destructive red for an error.
///
/// The starter's `CupertinoApp` gives them to its pages through a
/// [DesignScope]. An app with its own `CupertinoApp` does the same:
///
/// ```dart
/// CupertinoApp(
///   builder: (context, child) => DesignScope(
///     controls: const CupertinoDesignControls(),
///     textStyle: (context, style) => null,
///     selectable: (context, child) => child,
///     child: child!,
///   ),
///   home: const LoginPage(),
/// );
/// ```
final class CupertinoDesignControls implements DesignControls {
  /// The controls.
  const CupertinoDesignControls();

  /// A `CupertinoTextField` with [field]'s label as its placeholder, an
  /// eye button when the text can be shown, and the error in red below.
  @override
  Widget textField(BuildContext context, DesignTextField field) {
    final theme = CupertinoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CupertinoTextField(
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
          placeholder: field.label,
          suffix: field.toggleObscured == null
              ? null
              : Semantics(
                  label: field.toggleLabel,
                  button: true,
                  excludeSemantics: true,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(44, 44),
                    onPressed: field.enabled ? field.toggleObscured : null,
                    child: Icon(
                      field.obscureText
                          ? CupertinoIcons.eye
                          : CupertinoIcons.eye_slash,
                      size: 20,
                    ),
                  ),
                ),
        ),
        if (field.errorText case final error?)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, top: 4),
            child: Text(
              error,
              style: theme.textTheme.textStyle.copyWith(
                fontSize: 13,
                color: errorColor(context),
              ),
            ),
          ),
      ],
    );
  }

  /// A filled `CupertinoButton`: [button]'s label, or an activity
  /// indicator in its place while busy; with an icon, or a label that
  /// stays, the indicator takes the icon's place before the label.
  @override
  Widget filledButton(BuildContext context, DesignButton button) =>
      CupertinoButton.filled(
        onPressed: button.onPressed,
        child: button.icon == null && !button.keepsLabel
            ? _labelOrIndicator(button)
            : _labelAfterIcon(button),
      );

  static Widget _labelOrIndicator(DesignButton button) => button.busy
      ? Semantics(
          label: button.label,
          child: const CupertinoActivityIndicator(),
        )
      : Text(button.label);

  static Widget _labelAfterIcon(DesignButton button) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (button.busy) const CupertinoActivityIndicator() else ?button.icon,
      if (button.busy || button.icon != null) const SizedBox(width: 8),
      Flexible(child: Text(button.label)),
    ],
  );

  /// iOS's destructive red, light or dark as [context] is.
  @override
  Color errorColor(BuildContext context) =>
      CupertinoColors.destructiveRed.resolveFrom(context);

  /// [child] as it is: Cupertino's controls need nothing above them.
  @override
  Widget surface(BuildContext context, Widget child) => child;

  /// Whether a `CupertinoApp` is above [context]. Not its localizations:
  /// a `MaterialApp` has them too.
  @override
  bool isAppAbove(BuildContext context) =>
      context.findAncestorWidgetOfExactType<CupertinoApp>() != null;
}
