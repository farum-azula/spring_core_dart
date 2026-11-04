import 'package:flutter/material.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/swatch.dart';
import 'package:theme_showcase_material/src/widgets/theme_picture.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// Tokens: values of our own, in groups, with lists, durations and images.
class TokensPage extends StatefulWidget {
  const TokensPage({super.key});

  @override
  State<TokensPage> createState() => _TokensPageState();
}

class _TokensPageState extends State<TokensPage> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = theme.tokens;
    final space = theme.spacing;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bars = tokens.chart.bars;
    final top = bars.reduce((a, b) => a > b ? a : b);
    return PageFrame(
      title: context.messages.nav.tokens,
      intro:
          'Tokens are the values Material has no place for. Groups nest as '
          'deep as you like, and a token is typed by what it looks like: '
          'a color, a number, text, a duration, a list or an image.',
      children: [
        Section(
          title: 'Groups',
          note:
              'tokens.brand.name is a String, tokens.brand.accent a Color '
              '(it refers to the primary), both generated.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'name: Theme Showcase\n'
                'tagline: Every look in this app is a line of YAML\n'
                r'accent: $colors.primary',
                label: 'application.yml: tokens.brand',
              ),
              SizedBox(height: space.m),
              Container(
                padding: EdgeInsets.all(tokens.layout.card.padding),
                decoration: BoxDecoration(
                  color: tokens.brand.accent,
                  borderRadius: BorderRadius.circular(
                    tokens.layout.card.radius,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tokens.brand.name,
                            style: text.headlineMedium?.copyWith(
                              color: scheme.onPrimary,
                            ),
                          ),
                          Text(
                            tokens.brand.tagline,
                            style: text.bodyLarge?.copyWith(
                              color: scheme.onPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Nested groups',
          note:
              'layout.card.padding and layout.card.radius are two levels '
              'deep. The card above uses them.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'content-width: 980\n'
                'card:\n'
                '  padding: 20\n'
                r'  radius: $shape.large',
                label: 'application.yml: tokens.layout',
              ),
              SizedBox(height: space.s),
              Text(
                'content-width ${tokens.layout.contentWidth.round()}, '
                'card padding ${tokens.layout.card.padding.round()}, '
                'card radius ${tokens.layout.card.radius.round()}',
              ),
            ],
          ),
        ),
        Section(
          title: 'Lists',
          note: 'List<double> bars, List<String> days, List<Color> colors.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                r'colors: [$colors.primary, $colors.secondary, $colors.tertiary, $palette.deep]'
                '\n'
                'bars: [4, 9, 6, 11, 7]\n'
                'days: [Mon, Tue, Wed, Thu, Fri]',
                label: 'application.yml: tokens.chart',
              ),
              SizedBox(height: space.m),
              SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < bars.length; i++)
                      Padding(
                        padding: EdgeInsets.only(right: space.m),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 44,
                              height: 100 * bars[i] / top,
                              decoration: BoxDecoration(
                                color: tokens
                                    .chart
                                    .colors[i % tokens.chart.colors.length],
                                borderRadius: BorderRadius.circular(
                                  tokens.corner.tiny,
                                ),
                              ),
                            ),
                            SizedBox(height: space.xs),
                            Text(tokens.chart.days[i]),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Durations',
          note:
              'timing.intro is 600ms; timing.stagger refers to the motion '
              'duration `fast`. Press the button.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'intro: 600ms\n'
                r'stagger: $motion.durations.fast',
                label: 'application.yml: tokens.timing',
              ),
              SizedBox(height: space.m),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => setState(() => _open = !_open),
                    child: Text(
                      'Animate over ${tokens.timing.intro.inMilliseconds} ms',
                    ),
                  ),
                  SizedBox(width: space.m),
                  Text('stagger = ${tokens.timing.stagger.inMilliseconds} ms'),
                ],
              ),
              SizedBox(height: space.m),
              AnimatedContainer(
                duration: tokens.timing.intro,
                curve: theme.motion.curves.emphasized,
                height: space.l,
                width: _open ? 520 : 120,
                decoration: BoxDecoration(
                  color: scheme.tertiary,
                  borderRadius: BorderRadius.circular(space.s),
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'An image token',
          note:
              'A token with a `source` is a ThemeImage: an asset here, an '
              'https URL on the Images page.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'badge: { source: assets/images/badge.png }',
                label: 'application.yml: tokens.brand',
              ),
              SizedBox(height: space.m),
              ClipRRect(
                borderRadius: BorderRadius.circular(tokens.corner.roomy),
                child: ThemePicture(
                  tokens.brand.badge,
                  width: 120,
                  height: 120,
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Colors in a list, as swatches',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (var i = 0; i < tokens.chart.colors.length; i++)
                Swatch(tokens.chart.colors[i], 'chart.colors[$i]'),
            ],
          ),
        ),
      ],
    );
  }
}
