import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

/// The themes this app can show: the library's `neon` and our own
/// `neon-ice`, by the names the generator wrote in `AppThemes`. (`light`
/// and `dark` exist in every app, but they are not NEON themes: the widgets
/// would find no `tokens.neon` there.)
const showcaseThemes = [AppThemes.neon, AppThemes.neonIce];

/// Switches the theme with `ThemeSelection.select`. The whole app changes at
/// once: colors, the glow, the background.
class ThemeSwitcher extends SpringStatelessWidget<(ThemeSelection,)> {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final (selection,) = beans;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeonLabel(context.messages.themes.active(selection.active)),
        SizedBox(height: context.theme.spacing.s),
        Wrap(
          spacing: context.theme.spacing.s,
          runSpacing: context.theme.spacing.s,
          children: [
            for (final name in showcaseThemes)
              NeonChip(
                label: name,
                selected: selection.active == name,
                onPressed: () => selection.select(name),
              ),
          ],
        ),
      ],
    );
  }
}
