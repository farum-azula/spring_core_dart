import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/theme/debug_theme.dart';

/// Gives the debug tools under it the debug theme [themes] selects:
/// [DebugStyle.of] reads it, and a widget that did is drawn again when
/// another is selected, nothing else is.
class DebugThemeScope extends InheritedNotifier<ValueListenable<DebugTheme>> {
  /// The debug theme of [themes] over [child].
  const DebugThemeScope({
    required ValueListenable<DebugTheme> themes,
    required super.child,
    super.key,
  }) : super(notifier: themes);

  /// The style of the debug theme selected above [context]; `null` with
  /// no scope (a build without debug themes).
  static DebugStyle? styleOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DebugThemeScope>()
      ?.notifier
      ?.value
      .styleOf(context);
}
