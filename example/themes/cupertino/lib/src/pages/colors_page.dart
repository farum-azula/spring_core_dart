import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/swatch.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// Colors: the CupertinoThemeData palette from `cupertino.*`, the colors we
/// declare, references and expressions, and iOS's own dynamic colors.
@ScreenRoute('/colors', title: '#{nav.colors}')
class ColorsPage extends StatelessWidget {
  const ColorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cupertino = CupertinoTheme.of(context);
    final colors = context.theme.colors;
    final palette = context.theme.tokens.palette;
    final space = context.theme.spacing;
    Widget wrap(List<Widget> children) =>
        Wrap(spacing: space.m, runSpacing: space.m, children: children);
    return PageFrame(
      title: context.messages.nav.colors,
      intro:
          'The colors of a Cupertino app: the CupertinoThemeData palette '
          'comes from `cupertino.*`, the app\'s own from `colors.*`. Any '
          'color can refer to another with a dollar sign. The boxes quote '
          'the shared (root) YAML; the active theme may change a value, the '
          'swatches show what it really is.',
      children: [
        Section(
          title: 'The Cupertino palette',
          note:
              'cupertino.* is the CupertinoThemeData: CupertinoTheme.of('
              'context) gives these. The bar is see-through, so the page '
              'shows under it.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                r'primary-color: $colors.primary'
                '\n'
                r'primary-contrasting-color: $colors.on-primary'
                '\n'
                r'scaffold-background-color: $colors.surface'
                '\n'
                r'bar-background-color: { color: $colors.surface, alpha: 80% }'
                '\n'
                r'selection-handle-color: $colors.tertiary',
                label: 'application.yml: cupertino',
              ),
              SizedBox(height: space.m),
              wrap([
                Swatch(cupertino.primaryColor, 'primaryColor'),
                Swatch(
                  cupertino.primaryContrastingColor,
                  'primaryContrastingColor',
                ),
                Swatch(
                  cupertino.scaffoldBackgroundColor,
                  'scaffoldBackgroundColor',
                ),
                Swatch(cupertino.barBackgroundColor, 'barBackgroundColor'),
                Swatch(
                  cupertino.selectionHandleColor,
                  'selectionHandleColor',
                ),
              ]),
            ],
          ),
        ),
        Section(
          title: 'Declared colors',
          note:
              'A hex value, or a name from Flutter\'s colors. Read in Dart '
              'as context.theme.colors.secondary. iOS has no secondary or '
              'tertiary color: these are the app\'s own (green and orange).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                "primary: '#007AFF'\n"
                "secondary: '#34C759'\n"
                "tertiary: '#FF9500'\n"
                "error: '#FF3B30'\n"
                "surface: '#F2F2F7'\n"
                "surface-container-lowest: '#FFFFFF'",
                label: 'application.yml: colors (light)',
              ),
              SizedBox(height: space.m),
              wrap([
                Swatch(colors.primary, 'colors.primary'),
                Swatch(colors.secondary, 'colors.secondary'),
                Swatch(colors.tertiary, 'colors.tertiary'),
                Swatch(colors.error, 'colors.error'),
                Swatch(colors.surface, 'colors.surface'),
                Swatch(
                  colors.surfaceContainerLowest,
                  'colors.surfaceContainerLowest',
                  width: 168,
                ),
                Swatch(
                  colors.surfaceContainerHigh,
                  'colors.surfaceContainerHigh',
                  width: 168,
                ),
                Swatch(colors.onSurface, 'colors.onSurface'),
                Swatch(
                  colors.onSurfaceVariant,
                  'colors.onSurfaceVariant',
                  width: 168,
                ),
              ]),
            ],
          ),
        ),
        Section(
          title: 'References and color expressions',
          note:
              r'A reference reads another color of the same theme. alpha '
              'makes it see-through, mix blends it with another color. The '
              'chain is followed: deep refers to hover, which refers to '
              'primary.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                r'outline-variant: { color: $colors.outline, alpha: 50% }'
                '\n'
                r'soft: { color: $colors.primary, alpha: 12% }'
                '\n'
                r'hover: { color: $colors.primary, mix: { with: white, amount: 20% } }'
                '\n'
                r'deep: { color: $palette.hover, mix: { with: black, amount: 30% } }'
                '\n'
                r'container: $colors.surface-container'
                '\n'
                r'edge: $colors.outline',
                label: 'application.yml: colors and tokens.palette',
              ),
              SizedBox(height: space.m),
              wrap([
                Swatch(colors.outline, 'colors.outline'),
                Swatch(colors.outlineVariant, 'outline-variant, alpha 50%'),
                Swatch(colors.primary, 'colors.primary'),
                Swatch(palette.soft, 'palette.soft, alpha 12%'),
                Swatch(palette.hover, 'palette.hover, + white'),
                Swatch(palette.deep, 'palette.deep, chained'),
                Swatch(palette.container, 'palette.container'),
                Swatch(palette.edge, 'palette.edge'),
              ]),
              SizedBox(height: space.s),
              Text(
                'palette.container refers to surface-container, a role '
                'nobody declared: the palette made from seed-color makes '
                'it and the reference reads it.',
                style: CupertinoTheme.of(context).textTheme.textStyle
                    .copyWith(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Section(
          title: 'iOS\'s own colors follow the brightness',
          note:
              'CupertinoColors.systemRed, label, separator... change with '
              'the brightness of the theme: `brightness: dark` (here the '
              'theme dark, which extends light) is all it takes. These are '
              'resolved for the theme shown now.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'extends: light\nbrightness: dark',
                label: 'application.yml: themes.dark',
              ),
              SizedBox(height: space.m),
              wrap([
                for (final (name, color) in [
                  ('systemRed', CupertinoColors.systemRed),
                  ('systemGreen', CupertinoColors.systemGreen),
                  ('systemIndigo', CupertinoColors.systemIndigo),
                  ('label', CupertinoColors.label),
                  ('separator', CupertinoColors.separator),
                  ('systemFill', CupertinoColors.systemFill),
                ])
                  Swatch(color.resolveFrom(context), name),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
