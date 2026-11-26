import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/theme/debug_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// The themes: those the app's own files declare or choose
/// (`SpringThemes.ownNames`, not the base themes a `source` brings), the
/// one shown selected; a tap shows another, `system` follows the device
/// (offered only to an app that starts so). Under them, in a row of
/// their own, the debug themes ([debugThemes]: the built-in `default`,
/// those of `spring.flutter.debug.themes` and the `DebugTheme` beans), the
/// one the debug tools are drawn in selected; a tap draws them in another
/// at once.
final class DebugThemeSection implements GroupedDebugPanelSection, Ordered {
  /// The section of [themes] and [selection], and of [debugThemes].
  const DebugThemeSection(this.themes, this.selection, {this.debugThemes});

  /// The themes.
  final SpringThemes themes;

  /// The theme shown.
  final ThemeSelection selection;

  /// The debug themes.
  final DebugThemes? debugThemes;

  @override
  String get title => 'Theme';

  @override
  int get order => 40;

  @override
  String get group => 'Tools';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([selection, ?debugThemes]),
    builder: (context, _) {
      final style = DebugStyle.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme: ${selection.active}', style: style.text),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final name in {
                if (themes.offersSystem) 'system',
                ...themes.ownNames,
                if (selection.active != 'system') selection.active,
              })
                DebugChip(
                  name,
                  selected: selection.active == name,
                  onTap: () => selection.select(name),
                ),
            ],
          ),
          if (debugThemes case final debug?) ...[
            const SizedBox(height: 12),
            Text('Debug theme: ${debug.selected}', style: style.text),
            const SizedBox(height: 8),
            Wrap(
              key: const ValueKey('debug-themes'),
              children: [
                for (final name in debug.names)
                  DebugChip(
                    name,
                    selected: debug.selected == name,
                    onTap: () => debug.select(name),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
}
