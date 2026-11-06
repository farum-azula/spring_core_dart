import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// The theme's background: a color, an image, a gradient over them, and a
/// slow effect. SpringApp puts it under every screen by itself.
@ScreenRoute('/background', title: '#{nav.background}')
class BackgroundPage extends StatelessWidget {
  const BackgroundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final background = theme.background;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget box(String title, Widget child) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.typography.code),
          SizedBox(height: space.s),
          ClipRRect(
            borderRadius: BorderRadius.circular(space.m),
            child: SizedBox(
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(space.m),
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
    Widget label(String value) => Center(
      child: Container(
        padding: EdgeInsets.all(space.m),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(space.s),
        ),
        child: Text(value, style: text.titleSmall),
      ),
    );
    return PageFrame(
      title: context.messages.nav.background,
      intro:
          'A theme can have a background: SpringApp paints it under every '
          'screen and makes the Material scaffolds see-through. neon has an '
          'image that drifts; ocean-night has a gradient; light, dark and '
          'high-contrast have none. Switch themes to see it change.',
      children: [
        Section(
          title: background == null
              ? 'This theme has no background'
              : 'This theme\'s background',
          note: background == null
              ? 'Pick neon or ocean-night from the menu on top.'
              : 'You are looking at it: it is under this whole window.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'background:\n'
                r'  color: $colors.surface-container-lowest'
                '\n'
                '  image:\n'
                '    source: assets/images/neon-grid.png\n'
                '    fit: cover\n'
                '    alignment: center\n'
                '    opacity: 0.9\n'
                '    blur: 0\n'
                '  overlay:\n'
                r"    gradient: { type: linear, begin: top, end: bottom, colors: [transparent, '#CC0A0C12'] }"
                '\n'
                '  animation: background-drift\n'
                '  effect: drift\n'
                '  transition: 400ms ease-out',
                label:
                    'themes/neon.yml (the animation is in application.yml: '
                    'background-drift: { duration: 24s, ... repeat: reverse })',
              ),
              SizedBox(height: space.m),
              if (background == null)
                const Text('background: null')
              else
                Wrap(
                  spacing: space.l,
                  children: [
                    for (final (name, value) in [
                      ('color', background.color),
                      ('image', background.image?.image?.source),
                      (
                        'overlay gradient',
                        background.overlay?.gradient?.type.name,
                      ),
                      ('animation', background.animation),
                      ('effect', background.effect?.name),
                      ('screens', background.screens.keys.join(', ')),
                    ])
                      Chip(label: Text('$name: ${value ?? '-'}')),
                  ],
                ),
            ],
          ),
        ),
        Section(
          title: 'Three ways to show a screen',
          note:
              'ThemeBackground(child:) shows the theme\'s own. '
              '.screen(\'showcase\') adds a screen\'s override over it. '
              '.none gives a plain surface (a login or a reader, say).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'screens:\n'
                '  showcase:\n'
                '    overlay:\n'
                r'      gradient: { type: radial, begin: center, colors: [{ color: $colors.tertiary, alpha: 35% }, transparent] }',
                label: 'themes/neon.yml',
              ),
              SizedBox(height: space.m),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  box(
                    'ThemeBackground',
                    ThemeBackground(child: label('the theme\'s own')),
                  ),
                  SizedBox(width: space.m),
                  box(
                    'ThemeBackground.screen(\'showcase\')',
                    // Only neon has this screen; asking another theme for it
                    // is an error in debug.
                    SpringTheme.of(context).background?.screens.containsKey(
                              'showcase',
                            ) ??
                            false
                        ? ThemeBackground.screen(
                            'showcase',
                            child: label('screens.showcase'),
                          )
                        : label('this theme has no screens'),
                  ),
                  SizedBox(width: space.m),
                  box(
                    'ThemeBackground.none',
                    ThemeBackground.none(child: label('plain surface')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Section(
          title: 'Effects and the animation behind them',
          note:
              'effect: drift (a slow slide), zoom or pulse reads the '
              'animation named by `animation`. With reduce motion on, the '
              'background stands still and changes without a fade.',
          child: Text(
            background?.effect == null
                ? 'No effect in this theme.'
                : 'Effect: ${background!.effect!.name}, animation: ${background.animation}',
          ),
        ),
      ],
    );
  }
}
