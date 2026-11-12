// A CupertinoApp whose look is configuration: the primary color, the bar
// and the page backgrounds, a light and a dark theme
// (lib/resources/application.yml next to this file). A customizer changes,
// in code, what no property covers. The generator writes
// example.spring.dart (`dart run build_runner build`).
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

import 'spring_gen/example.spring.dart';

/// The text on the primary color, black or white, whichever reads better
/// on the primary color of each theme: a value computed in code, which a
/// property cannot say.
@Component()
class Contrast implements CupertinoThemeCustomizer {
  @override
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  ) => theme.copyWith(
    primaryContrastingColor: theme.primaryColor.computeLuminance() > 0.4
        ? CupertinoColors.black
        : CupertinoColors.white,
  );
}

/// The only page: the theme's colors, and a switch between the light and
/// the dark theme.
class ThemePage extends SpringStatelessWidget<(ThemeSelection,)> {
  /// The page.
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    final (selection,) = beans;
    final theme = CupertinoTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Themes from properties'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => selection.select(dark ? 'light' : 'dark'),
          child: Text(dark ? 'Light' : 'Dark'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('From application.yml'),
              children: [
                CupertinoListTile(
                  leading: Icon(
                    CupertinoIcons.paintbrush,
                    color: theme.primaryColor,
                  ),
                  title: const Text('primary-color'),
                ),
                const CupertinoListTile(
                  leading: Icon(CupertinoIcons.square_fill_on_square_fill),
                  title: Text('bar-background-color'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: () {},
              child: const Text('Filled'),
            ),
          ],
        ),
      ),
    );
  }
}

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    // No CupertinoApp in the code: the starter builds it from
    // spring.flutter.app.* and spring.flutter.theme.*.
    home: const ThemePage(),
  ),
);
