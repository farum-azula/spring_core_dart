import 'package:flutter/cupertino.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/swatch.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// The theme's background: a color, an image, a gradient over them, and a
/// slow effect. SpringApp puts it under every screen by itself.
@ScreenRoute('/background', title: '#{nav.background}', branch: '/more')
class BackgroundPage extends StatelessWidget {
  const BackgroundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final colors = theme.colors;
    final background = theme.background;
    final text = CupertinoTheme.of(context).textTheme;
    final small = text.textStyle.copyWith(
      fontSize: 13,
      color: colors.onSurfaceVariant,
    );
    Widget box(String title, Widget child) => SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.typography.code.copyWith(
              fontSize: 11,
              color: colors.onSurface,
            ),
          ),
          SizedBox(height: space.s),
          Container(
            height: 150,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: colors.outline),
              borderRadius: BorderRadius.circular(space.m),
            ),
            child: child,
          ),
        ],
      ),
    );
    Widget label(String value) => Center(
      child: Container(
        padding: EdgeInsets.all(space.m),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(space.s),
        ),
        child: Text(value, style: text.navTitleTextStyle),
      ),
    );
    final scaffold = CupertinoTheme.of(context).scaffoldBackgroundColor;
    return PageFrame(
      title: context.messages.nav.background,
      intro:
          'A theme can have a background: SpringApp paints it under every '
          'screen and makes the Cupertino scaffolds see-through. sunset has '
          'a picture that drifts; graphite has a gradient; light and dark '
          'have none. Switch themes to see it change.',
      children: [
        Section(
          title: background == null
              ? 'This theme has no background'
              : 'This theme\'s background',
          note: background == null
              ? 'Pick sunset or graphite from the theme menu.'
              : 'You are looking at it: it is under this whole window.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'background:\n'
                r'  color: $colors.surface'
                '\n'
                '  image:\n'
                '    source: assets/images/sunset-sky.png\n'
                '    fit: cover\n'
                '    alignment: center\n'
                '    opacity: 0.9\n'
                '  overlay:\n'
                r"    gradient: { type: linear, begin: top, end: bottom, colors: ['#66FFF1E6', transparent] }"
                '\n'
                '  animation: background-drift\n'
                '  effect: drift\n'
                '  transition: 400ms ease-out',
                label:
                    'themes/sunset.yml (the animation is in application.yml: '
                    'background-drift: { duration: 30s, ... repeat: reverse })',
              ),
              SizedBox(height: space.m),
              if (background == null)
                Text('background: null', style: small)
              else
                Wrap(
                  spacing: space.l,
                  runSpacing: space.xs,
                  children: [
                    for (final (name, value) in [
                      (
                        'color',
                        background.color == null
                            ? null
                            : Swatch.hex(background.color!),
                      ),
                      ('image', background.image?.image?.source),
                      (
                        'overlay gradient',
                        background.overlay?.gradient?.type.name,
                      ),
                      ('animation', background.animation),
                      ('effect', background.effect?.name),
                      ('screens', background.screens.keys.join(', ')),
                    ])
                      Text('$name: ${value ?? '-'}', style: small),
                  ],
                ),
            ],
          ),
        ),
        Section(
          title: 'See-through scaffolds',
          note:
              'With a background, the CupertinoThemeData is made with a '
              'transparent scaffold-background-color (a color you write '
              'in cupertino.* is kept). The bars are translucent too, with '
              'the blur of iOS, so the picture shows under them.',
          child: Wrap(
            spacing: space.l,
            runSpacing: space.m,
            children: [
              Swatch(scaffold, 'scaffoldBackgroundColor'),
              Swatch(
                CupertinoTheme.of(context).barBackgroundColor,
                'barBackgroundColor',
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
                r'      gradient: { type: radial, begin: center, colors: [{ color: $colors.tertiary, alpha: 30% }, transparent] }',
                label: 'themes/sunset.yml',
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.m,
                runSpacing: space.m,
                children: [
                  box(
                    'ThemeBackground',
                    ThemeBackground(child: label('the theme\'s own')),
                  ),
                  box(
                    'ThemeBackground.screen',
                    ThemeBackground.screen(
                      'showcase',
                      child: label('screens.showcase'),
                    ),
                  ),
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
            style: small,
          ),
        ),
      ],
    );
  }
}
