import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// The themes: those the app's own files declare or choose
/// (`SpringThemes.ownNames`, not the base themes a `source` brings), the
/// one shown selected; a tap shows another, `system` follows the device.
final class DebugThemeSection implements DebugPanelSection, Ordered {
  /// The section of [themes] and [selection].
  const DebugThemeSection(this.themes, this.selection);

  /// The themes.
  final SpringThemes themes;

  /// The theme shown.
  final ThemeSelection selection;

  @override
  String get title => 'Theme';

  @override
  int get order => 40;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selection,
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
                'system',
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
        ],
      );
    },
  );
}
