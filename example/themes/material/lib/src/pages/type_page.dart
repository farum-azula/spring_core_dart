import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// Typography, spacing and the shape scale.
@ScreenRoute('/type', title: '#{nav.type}')
class TypePage extends StatelessWidget {
  const TypePage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final theme = context.theme;
    final space = theme.spacing;
    final spring = SpringTheme.of(context);
    final styles = <(String, TextStyle?)>[
      ('display-large', text.displayLarge),
      ('display-small', text.displaySmall),
      ('headline-medium', text.headlineMedium),
      ('title-large', theme.typography.titleLarge),
      ('title-medium', text.titleMedium),
      ('body-large', text.bodyLarge),
      ('body-medium', theme.typography.bodyMedium),
      ('label-large', text.labelLarge),
      ('label-small', text.labelSmall),
      ('code', theme.typography.code),
    ];
    final spaces = <(String, double)>[
      ('xs', space.xs),
      ('s', space.s),
      ('m', space.m),
      ('l', space.l),
      ('xl', space.xl),
      ('gutter', space.gutter),
    ];
    final shapes = [
      'extra-small',
      'small',
      'medium',
      'large',
      'extra-large',
    ];
    return PageFrame(
      title: context.messages.nav.type,
      intro:
          'Text styles, spacing steps and the shape scale are properties too. '
          'Nothing here is set in Dart.',
      children: [
        Section(
          title: 'Typography',
          note:
              'The 15 Material styles exist; a key adjusts one, a group '
              '(display, headline) adjusts several. `code` is ours.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'defaults: { letter-spacing: 0.1 }\n'
                'display: { weight: bold }\n'
                'headline: { weight: semibold }\n'
                'title-large: { size: 24, weight: semibold }\n'
                'body-medium: { height: 1.5 }\n'
                'code: { font-family: monospace, size: 13 }',
                label: 'application.yml: typography',
              ),
              SizedBox(height: space.m),
              for (final (name, style) in styles)
                Padding(
                  padding: EdgeInsets.only(bottom: space.s),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          name,
                          style: theme.typography.code.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Sphinx of black quartz, judge my vow',
                          style: style,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Section(
          title: 'Spacing',
          note:
              'context.theme.spacing.m is 16. Names are ours: add `gutter` '
              'and it becomes a getter.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'xs: 4\ns: 8\nm: 16\nl: 24\nxl: 32\ngutter: 20',
                label: 'application.yml: spacing',
              ),
              SizedBox(height: space.m),
              for (final (name, value) in spaces)
                Padding(
                  padding: EdgeInsets.only(bottom: space.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text('$name  ${value.round()}'),
                      ),
                      Container(
                        width: value * 6,
                        height: space.m,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Section(
          title: 'Shape scale',
          note:
              'Radii of Material 3. Changing medium and large reaches every '
              'component that follows the scale (cards, dialogs...).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'medium: 16\nlarge: 24',
                label: 'application.yml: shape',
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.m,
                runSpacing: space.m,
                children: [
                  for (final name in shapes)
                    Column(
                      children: [
                        Container(
                          width: 96,
                          height: 72,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(
                              spring.shape(name),
                            ),
                          ),
                        ),
                        SizedBox(height: space.xs),
                        Text('$name ${spring.shape(name).round()}'),
                      ],
                    ),
                ],
              ),
              SizedBox(height: space.l),
              const YamlBox(
                r'tiny: $shape.extra-small'
                '\n'
                r'roomy: $shape.extra-large',
                label: 'application.yml: tokens.corner (shapes by reference)',
              ),
              SizedBox(height: space.m),
              Row(
                children: [
                  for (final (name, radius) in [
                    ('corner.tiny', theme.tokens.corner.tiny),
                    ('corner.roomy', theme.tokens.corner.roomy),
                  ])
                    Padding(
                      padding: EdgeInsets.only(right: space.m),
                      child: Container(
                        padding: EdgeInsets.all(space.m),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(radius),
                        ),
                        child: Text('$name = ${radius.round()}'),
                      ),
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
