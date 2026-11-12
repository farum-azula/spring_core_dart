import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/ios_widgets.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

typedef ThemesPageBeans = (
  ThemeSelection,
  SpringThemes,
);

/// Every theme of the app, side by side. Picking one is
/// `ThemeSelection.select(AppThemes.graphite)`.
@ScreenRoute('/themes', title: '#{nav.themes}')
class ThemesPage extends SpringStatelessWidget<ThemesPageBeans> {
  const ThemesPage({super.key});

  /// The themes the app shows buttons for, by the constants of `AppThemes`.
  static const shown = [
    AppThemes.light,
    AppThemes.dark,
    AppThemes.graphite,
    AppThemes.sunset,
  ];

  @override
  Widget build(BuildContext context) {
    final (
      selection,
      themes,
    ) = beans;
    final theme = context.theme;
    final space = theme.spacing;
    final colors = theme.colors;
    final text = CupertinoTheme.of(context).textTheme;
    return PageFrame(
      title: context.messages.nav.themes,
      intro:
          'Four themes, one set of widgets. A theme holds only what it '
          'changes; `extends` starts it from another. The constants of '
          'AppThemes are generated, so a renamed theme stops compiling.',
      children: [
        Section(
          title: context.messages.themes.active(selection.active),
          note:
              'The segments and the cards call '
              'ThemeSelection.select(AppThemes.name). system follows the '
              'device (light or dark).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoSlidingSegmentedControl<String>(
                groupValue: shown.contains(selection.active)
                    ? selection.active
                    : null,
                backgroundColor: colors.surfaceContainerHigh,
                thumbColor: colors.surfaceContainerLowest,
                onValueChanged: (name) {
                  if (name != null) {
                    selection.select(name);
                  }
                },
                children: {
                  for (final name in shown)
                    name: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        name,
                        style: text.textStyle.copyWith(fontSize: 14),
                      ),
                    ),
                },
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.m,
                runSpacing: space.m,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final name in shown)
                    _ThemeCard(
                      name: name,
                      data: themes.data(name),
                      selected: selection.active == name,
                      onPressed: () => selection.select(name),
                    ),
                  IosChip(
                    'system',
                    selected: selection.active == AppThemes.system,
                    onPressed: () => selection.select(AppThemes.system),
                  ),
                ],
              ),
            ],
          ),
        ),
        Section(
          title: 'light and dark',
          note:
              'light is the shared root; dark extends it, turns the '
              'brightness around and swaps the colors for iOS\'s dark ones. '
              'The Cupertino brightness follows, so CupertinoColors.label '
              'and the others change with it.',
          child: const YamlBox(
            'dark:\n'
            '  extends: light\n'
            '  brightness: dark\n'
            '  colors:\n'
            "    primary: '#0A84FF'\n"
            "    surface: '#000000'",
            label: 'application.yml: themes',
          ),
        ),
        Section(
          title: 'extends, in a file of its own',
          note:
              'graphite is dark with an orange tint and a gradient behind '
              'it; sunset is light, see-through, over a picture. Each is a '
              'file in themes/, imported with spring.config.import.',
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              YamlBox(
                'import: >-\n'
                '  resources:themes/graphite.yml, resources:themes/sunset.yml',
                label: 'application.yml: spring.config',
              ),
              SizedBox(height: 12),
              YamlBox(
                'graphite:\n'
                '  extends: dark\n'
                '  colors:\n'
                "    primary: '#FF9F0A'\n"
                "    surface: '#141416'",
                label: 'themes/graphite.yml',
              ),
              SizedBox(height: 12),
              YamlBox(
                'sunset:\n'
                '  extends: light\n'
                '  colors:\n'
                "    primary: '#FF5E3A'\n"
                '    # An 8 digit color is #AARRGGBB: 80% white.\n'
                "    surface-container-lowest: '#CCFFFFFF'\n"
                'cupertino:\n'
                "  bar-background-color: '#B3FFF1E6'",
                label: 'themes/sunset.yml',
              ),
            ],
          ),
        ),
        Section(
          title: 'A theme from a URL',
          note:
              'A theme file can live on a server: it is downloaded, '
              'checked against a hash, cached, and replaced in the '
              'background. This app stays offline; the block is in '
              'application-network.yml, commented out.',
          child: const YamlBox(
            'themes:\n'
            '  brand:\n'
            '    source: https://themes.example.com/theme-showcase-cupertino/brand.yml\n'
            '    refresh: 1h\n'
            '  brand-dark:\n'
            '    extends: brand\n'
            '    brightness: dark',
            label: 'application-network.yml',
          ),
        ),
        Section(
          title: 'Typed messages',
          note:
              'The texts of the navigation and of the theme menu come from '
              'messages.properties through context.messages, generated '
              'like the theme keys.',
          child: Text(
            '${context.messages.themes.switch$} '
            '(context.messages.themes.switch\$)',
            style: text.textStyle,
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.name,
    required this.data,
    required this.selected,
    required this.onPressed,
  });

  final String name;
  final SpringThemeData data;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = CupertinoTheme.of(context).textTheme;
    final dark = data.brightness == Brightness.dark;
    return SizedBox(
      width: 170,
      child: IosCard(
        selected: selected,
        onPressed: onPressed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final role in [
                  'primary',
                  'secondary',
                  'tertiary',
                  'surface',
                ])
                  Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: data.colors[role] ?? const Color(0xFF808080),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.theme.colors.outline,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: context.theme.spacing.s),
            Text(name, style: text.navTitleTextStyle),
            Text(
              dark ? 'dark' : 'light',
              style: text.textStyle.copyWith(
                fontSize: 13,
                color: context.theme.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
