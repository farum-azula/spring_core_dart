import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/swatch.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// Colors: the palette made from one seed, colors we declare, and colors
/// that refer to other colors.
@ScreenRoute('/colors', title: '#{nav.colors}')
class ColorsPage extends StatelessWidget {
  const ColorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.theme.colors;
    final palette = context.theme.tokens.palette;
    final space = context.theme.spacing;
    Widget wrap(List<Widget> children) =>
        Wrap(spacing: space.m, runSpacing: space.m, children: children);
    return PageFrame(
      title: context.messages.nav.colors,
      intro:
          'One seed color makes the Material 3 palette. Declared colors win '
          'over it, and any color can refer to another with a dollar sign. '
          'The boxes quote the shared (root) YAML; the active theme may '
          'change a value, the swatches show what it really is.',
      children: [
        Section(
          title: 'Roles from the seed',
          note:
              'Nothing is declared here: seed-color and scheme-variant make '
              'every role. `Theme.of(context).colorScheme` has them.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                "seed-color: '#3F51B5'\nscheme-variant: tonalSpot",
                label: 'application.yml',
              ),
              SizedBox(height: space.m),
              wrap([
                Swatch(scheme.primary, 'primary'),
                Swatch(scheme.onPrimary, 'on-primary'),
                Swatch(scheme.primaryContainer, 'primary-container'),
                Swatch(scheme.onPrimaryContainer, 'on-primary-container'),
                Swatch(scheme.secondaryContainer, 'secondary-container'),
                Swatch(scheme.onSecondaryContainer, 'on-secondary-container'),
                Swatch(scheme.tertiaryContainer, 'tertiary-container'),
                Swatch(scheme.surface, 'surface'),
                Swatch(scheme.onSurface, 'on-surface'),
                Swatch(scheme.onSurfaceVariant, 'on-surface-variant'),
                Swatch(
                  scheme.surfaceContainerLowest,
                  'surface-container-lowest',
                ),
                Swatch(scheme.surfaceContainer, 'surface-container'),
                Swatch(
                  scheme.surfaceContainerHighest,
                  'surface-container-highest',
                ),
                Swatch(scheme.outline, 'outline'),
                Swatch(scheme.inverseSurface, 'inverse-surface'),
              ]),
            ],
          ),
        ),
        Section(
          title: 'Declared colors',
          note:
              'A hex value, or a name from Flutter\'s Colors. Read in Dart '
              'as context.theme.colors.secondary (only declared roles have '
              'a typed getter).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                "secondary: '#00897B'\n"
                "error: '#B3261E'\n"
                'surface-container-low: grey.shade100',
                label: 'application.yml: colors',
              ),
              SizedBox(height: space.m),
              wrap([
                Swatch(colors.secondary, 'colors.secondary'),
                Swatch(colors.error, 'colors.error'),
                Swatch(
                  colors.surfaceContainerLow,
                  'colors.surfaceContainerLow',
                ),
              ]),
            ],
          ),
        ),
        Section(
          title: 'References and color expressions',
          note:
              r'$colors.outline is a role nobody declared: the palette '
              'makes it, the reference reads it. alpha and mix make new colors.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                r'outline-variant: { color: $colors.outline, alpha: 50% }'
                '\n'
                r'tertiary: { color: $colors.secondary, mix: { with: white, amount: 35% } }',
                label: 'application.yml: colors',
              ),
              SizedBox(height: space.m),
              wrap([
                Swatch(colors.outline, 'outline (palette role)'),
                Swatch(colors.outlineVariant, 'outline-variant, alpha 50%'),
                Swatch(colors.secondary, 'secondary'),
                Swatch(colors.tertiary, 'tertiary, secondary + white'),
              ]),
            ],
          ),
        ),
        Section(
          title: 'In tokens: chains and undeclared roles',
          note:
              r'A token can refer to a token ($palette.hover), which '
              'refers to a color: the chain is followed.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                r'soft: { color: $colors.primary, alpha: 12% }'
                '\n'
                r'hover: { color: $colors.primary, mix: { with: white, amount: 14% } }'
                '\n'
                r'deep: { color: $palette.hover, mix: { with: black, amount: 30% } }'
                '\n'
                r'edge: $colors.outline'
                '\n'
                r'lowest: $colors.surface-container-lowest',
                label: 'application.yml: tokens.palette',
              ),
              SizedBox(height: space.m),
              wrap([
                Swatch(scheme.primary, 'primary'),
                Swatch(palette.soft, 'palette.soft'),
                Swatch(palette.hover, 'palette.hover'),
                Swatch(palette.deep, 'palette.deep (chained)'),
                Swatch(palette.edge, 'palette.edge'),
                Swatch(palette.lowest, 'palette.lowest'),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
