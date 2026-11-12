import 'package:flutter/services.dart' show TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';

/// What the design library of the app gives the starter's own widgets:
/// the text styles of its theme and its way to make text selectable.
///
/// The starter's widgets (`MarkdownView`) know no design library. In a
/// `MaterialApp` they still follow Material's `Theme` and select text as
/// Material does, because the app widget of the design starter puts one of
/// these above its pages. Without one (an app of type `widgets`) they use
/// the `SpringTheme` and the starter's own selection handles.
///
/// A `SpringAppFactory` of your own design puts one in its builder:
///
/// ```dart
/// builder: (context, child) => DesignScope(
///   textStyle: (context, style) => OceanTheme.of(context).text[style],
///   selectable: (context, child) => OceanSelectionArea(child: child),
///   child: app.builder(context, child),
/// ),
/// ```
class DesignScope extends InheritedWidget {
  /// Gives [textStyle], [selectable] and [controls] to the widgets below.
  const DesignScope({
    required this.textStyle,
    required this.selectable,
    required super.child,
    this.controls,
    super.key,
  });

  /// The design's text field and button, for widgets that draw a form
  /// without knowing the design (the login form of
  /// `spring_boot_starter_flutter_security`); `null` when the design
  /// draws none, and such widgets draw their own plain ones.
  final DesignControls? controls;

  /// The text style named [style] (canonical, `titlelarge`) that the
  /// design's theme has at [context], with the sizes of the locale's
  /// script; `null` to use the `SpringTheme`'s.
  final TextStyle? Function(BuildContext context, String style) textStyle;

  /// [child] with its text selectable the way the design does it (its
  /// handles, its menu).
  final Widget Function(BuildContext context, Widget child) selectable;

  /// The scope above [context]; `null` in an app without a design.
  static DesignScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesignScope>();

  /// The controls of the design of the app above [context]: those of its
  /// [DesignScope], else, below an app widget written by hand (a
  /// `MaterialApp` of the app's own), the first [DesignControls] bean, in
  /// `@Order`, that finds its app above [context]; `null` when the app has
  /// no design library.
  static DesignControls? controlsOf(BuildContext context) =>
      maybeOf(context)?.controls ??
      SpringScope.maybeOf(context, listen: false)
          ?.getSortedBeans<DesignControls>()
          .where((controls) => controls.isAppAbove(context))
          .firstOrNull;

  @override
  bool updateShouldNotify(DesignScope oldWidget) =>
      oldWidget.textStyle != textStyle ||
      oldWidget.selectable != selectable ||
      oldWidget.controls != controls;
}

/// A text field for a design library to draw: what a form knows of one of
/// its fields, and nothing of how it looks.
@immutable
final class DesignTextField {
  /// The field labelled [label], editing [controller].
  const DesignTextField({
    required this.controller,
    required this.label,
    this.focusNode,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.toggleObscured,
    this.toggleLabel,
    this.autofillHints,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  /// The text being edited.
  final TextEditingController controller;

  /// What the field is for (`User name`).
  final String label;

  /// The field's focus; `null` for its own.
  final FocusNode? focusNode;

  /// What is wrong with the value; `null` when nothing is.
  final String? errorText;

  /// Whether the value can be edited.
  final bool enabled;

  /// Whether the field takes the focus when it first shows.
  final bool autofocus;

  /// Whether the text is hidden (a password).
  final bool obscureText;

  /// Shows or hides the text; with one the field has a button for it,
  /// `null` for a field without.
  final VoidCallback? toggleObscured;

  /// What that button does, for a screen reader and a tooltip.
  final String? toggleLabel;

  /// What the platform may fill the field with (`AutofillHints.password`).
  final Iterable<String>? autofillHints;

  /// The keyboard of the field.
  final TextInputType? keyboardType;

  /// The action key of the keyboard.
  final TextInputAction? textInputAction;

  /// Called with the text when the action key is pressed.
  final ValueChanged<String>? onSubmitted;
}

/// A filled button for a design library to draw.
@immutable
final class DesignButton {
  /// The button labelled [label].
  const DesignButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.keepsLabel = false,
  });

  /// The text of the button.
  final String label;

  /// Called on a tap; `null` for a disabled button.
  final VoidCallback? onPressed;

  /// Whether the button's work is going on: it shows a progress
  /// indicator.
  final bool busy;

  /// The icon before the label; `null` for none.
  final Widget? icon;

  /// Whether the label stays next to the progress indicator while [busy]
  /// in a design that can show both (Cupertino).
  final bool keepsLabel;
}

/// The form controls of a design library: its text field, its filled
/// button, its color of an error. A design starter gives them to the
/// widgets below its app through a [DesignScope].
abstract interface class DesignControls {
  /// Whether the app widget of this design is above [context] (Material's
  /// localizations are there in a `MaterialApp`), for an app widget that
  /// has no [DesignScope].
  bool isAppAbove(BuildContext context);

  /// [field] as the design draws a text field, with its label, its error
  /// and its button to show a hidden text.
  Widget textField(BuildContext context, DesignTextField field);

  /// [button] as the design draws its most prominent button.
  Widget filledButton(BuildContext context, DesignButton button);

  /// The design's color of an error message at [context].
  Color errorColor(BuildContext context);

  /// [child], which holds the design's controls, with what they need
  /// above them when [context] has none (Material's `Material`).
  Widget surface(BuildContext context, Widget child);
}
