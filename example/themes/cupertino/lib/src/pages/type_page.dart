import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// Typography: the text styles of the CupertinoThemeData, made from
/// `typography.*` and `cupertino.text-theme.*`; then spacing and shapes.
@ScreenRoute('/type', title: '#{nav.type}')
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final colors = theme.colors;
    final text = CupertinoTheme.of(context).textTheme;
    final small = text.textStyle.copyWith(
      fontSize: 13,
      color: colors.onSurfaceVariant,
    );
    // (name in CupertinoTextThemeData, the style, where the YAML says it)
    final styles = <(String, TextStyle, String)>[
      ('textStyle', text.textStyle, 'typography.body-large'),
      ('actionTextStyle', text.actionTextStyle, 'typography.label-large'),
      ('tabLabelTextStyle', text.tabLabelTextStyle, 'typography.label-small'),
      (
        'navTitleTextStyle',
        text.navTitleTextStyle,
        'cupertino.text-theme.nav-title-text-style',
      ),
      (
        'navLargeTitleTextStyle',
        text.navLargeTitleTextStyle,
        'typography.display-small',
      ),
      ('navActionTextStyle', text.navActionTextStyle, 'typography.label-large'),
      (
        'pickerTextStyle',
        text.pickerTextStyle,
        'cupertino.text-theme.picker-text-style',
      ),
      (
        'dateTimePickerTextStyle',
        text.dateTimePickerTextStyle,
        'cupertino.text-theme.date-time-picker-text-style',
      ),
    ];
    return PageFrame(
      title: context.messages.nav.type,
      intro:
          'A CupertinoApp reads its text from CupertinoTextThemeData. Write '
          'the sizes and weights once in `typography`, and the Cupertino '
          'styles take them; write one under `cupertino.text-theme` and it '
          'wins. Fonts stay the system font (San Francisco on Apple '
          'devices); name a family in the YAML to change it.',
      children: [
        Section(
          title: 'From typography.*',
          note:
              'The 15 Material style names (body-large, label-small...) are '
              'the names of the YAML, so one scale serves the whole theme. '
              'Cupertino takes body-large for text, label-large for '
              'actions, label-small for tab labels, display-small for large '
              'titles.',
          child: const YamlBox(
            'body-large: { size: 17, height: 1.3 }\n'
            'label-large: { size: 17, weight: 500 }\n'
            'label-small: { size: 10, weight: 500 }\n'
            'title-large: { size: 22, weight: bold }\n'
            'display-small: { size: 34, weight: bold, letter-spacing: 0.4 }\n'
            'code: { font-family: monospace, size: 13, letter-spacing: 0 }',
            label: 'application.yml: typography',
          ),
        ),
        Section(
          title: 'From cupertino.text-theme.*',
          note:
              'The navigation title, the picker and the date picker have '
              'a style of their own here: a size, a weight, a height or a '
              'letter spacing, or `style:` with one of the 15 names.',
          child: const YamlBox(
            'text-theme:\n'
            '  nav-title-text-style: { size: 17, weight: 600 }\n'
            '  picker-text-style: { size: 21 }\n'
            '  date-time-picker-text-style: { size: 21 }',
            label: 'application.yml: cupertino',
          ),
        ),
        Section(
          title: 'The eight styles of the Cupertino theme',
          note:
              'CupertinoTheme.of(context).textTheme, in the theme shown '
              'now. Switch to graphite: its large title is heavier.',
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(
                theme.tokens.layout.card.radius,
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < styles.length; i++) ...[
                  if (i > 0) Container(height: 0.5, color: colors.outline),
                  Padding(
                    padding: EdgeInsets.all(space.m),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i == 4 ? 'Large title' : 'Quick brown fox',
                                style: styles[i].$2,
                              ),
                              SizedBox(height: space.xs),
                              Text(
                                '${styles[i].$1}: ${styles[i].$2.fontSize?.toStringAsFixed(0)} pt, '
                                'w${styles[i].$2.fontWeight?.value ?? 400}',
                                style: theme.typography.code.copyWith(
                                  fontSize: 12,
                                  color: colors.onSurface,
                                ),
                              ),
                              Text(styles[i].$3, style: small),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Section(
          title: 'Spacing and shape',
          note:
              'spacing.* are the app\'s own units (context.theme.spacing.m); '
              'shape.* is the corner scale, here the iOS radii: tokens refer '
              'to it with \$shape.small.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'xs: 4\n'
                's: 8\n'
                'm: 16\n'
                'l: 24\n'
                'xl: 32\n'
                'small: 8\n'
                'medium: 10\n'
                'large: 14\n'
                'extra-large: 20',
                label: 'application.yml: spacing and shape',
              ),
              SizedBox(height: space.m),
              for (final (name, value) in [
                ('xs', space.xs),
                ('s', space.s),
                ('m', space.m),
                ('l', space.l),
                ('xl', space.xl),
              ])
                Padding(
                  padding: EdgeInsets.only(bottom: space.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          'spacing.$name',
                          style: theme.typography.code.copyWith(
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        width: value * 6,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      SizedBox(width: space.s),
                      Text('${value.round()}', style: small),
                    ],
                  ),
                ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.m,
                runSpacing: space.m,
                children: [
                  for (final (name, radius) in [
                    ('tokens.corner.tiny', theme.tokens.corner.tiny),
                    ('layout.card.radius', theme.tokens.layout.card.radius),
                    ('tokens.corner.roomy', theme.tokens.corner.roomy),
                  ])
                    Column(
                      children: [
                        Container(
                          width: 96,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.15),
                            border: Border.all(color: colors.primary, width: 2),
                            borderRadius: BorderRadius.circular(radius),
                          ),
                        ),
                        SizedBox(height: space.xs),
                        Text(
                          '$name: ${radius.round()}',
                          style: small.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
