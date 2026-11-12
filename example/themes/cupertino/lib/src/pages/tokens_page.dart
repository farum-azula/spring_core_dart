import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/swatch.dart';
import 'package:theme_showcase_cupertino/src/widgets/theme_picture.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// Tokens: values of our own, in groups, with lists, durations and images.
@ScreenRoute('/tokens', title: '#{nav.tokens}', branch: '/more')
class TokensPage extends StatefulWidget {
  const TokensPage({super.key});

  @override
  State<TokensPage> createState() => _TokensPageState();
}

class _TokensPageState extends State<TokensPage> {
  bool _open = false;
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = theme.tokens;
    final space = theme.spacing;
    final colors = theme.colors;
    final text = CupertinoTheme.of(context).textTheme;
    final bars = tokens.chart.bars;
    final top = bars.reduce((a, b) => a > b ? a : b);
    return PageFrame(
      title: context.messages.nav.tokens,
      intro:
          'Tokens are the values a CupertinoThemeData has no place for. '
          'Groups nest as deep as you like, and a token is typed by what it '
          'looks like: a color, a number, text, a duration, a list or an '
          'image.',
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
                'name: Light\n'
                'tagline: The iOS look, written in YAML\n'
                r'accent: $colors.primary',
                label: 'application.yml: tokens.brand (light)',
              ),
              SizedBox(height: space.m),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(tokens.layout.card.padding),
                decoration: BoxDecoration(
                  color: tokens.brand.accent,
                  borderRadius: BorderRadius.circular(
                    tokens.layout.card.radius,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tokens.brand.name,
                      style: text.navLargeTitleTextStyle.copyWith(
                        color: colors.onPrimary,
                      ),
                    ),
                    Text(
                      tokens.brand.tagline,
                      style: text.textStyle.copyWith(color: colors.onPrimary),
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
                'content-width: 720\n'
                'sidebar-width: 280\n'
                'card:\n'
                '  padding: 16\n'
                r'  radius: $shape.large',
                label: 'application.yml: tokens.layout',
              ),
              SizedBox(height: space.s),
              Text(
                'content-width ${tokens.layout.contentWidth.round()}, '
                'sidebar-width ${tokens.layout.sidebarWidth.round()}, '
                'card padding ${tokens.layout.card.padding.round()}, '
                'card radius ${tokens.layout.card.radius.round()}',
                style: text.textStyle.copyWith(
                  fontSize: 13,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Lists',
          note:
              'List<double> bars, List<String> days, List<Color> colors. '
              'The bars grow with timing.intro, one after the other, '
              'timing.stagger apart.',
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
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < bars.length; i++)
                      Padding(
                        padding: EdgeInsets.only(right: space.m),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TweenAnimationBuilder<double>(
                              key: ValueKey('bar-$i-$_replay'),
                              tween: Tween(begin: 0, end: bars[i] / top),
                              duration:
                                  tokens.timing.intro +
                                  tokens.timing.stagger * i,
                              curve: theme.motion.curves.ios,
                              builder: (context, t, _) => Container(
                                width: 44,
                                height: 100 * t,
                                decoration: BoxDecoration(
                                  color: tokens
                                      .chart
                                      .colors[i % tokens.chart.colors.length],
                                  borderRadius: BorderRadius.circular(
                                    tokens.corner.tiny,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: space.xs),
                            Text(
                              tokens.chart.days[i],
                              style: text.textStyle.copyWith(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: space.s),
              CupertinoButton.tinted(
                onPressed: () => setState(() => _replay++),
                child: const Text('Grow again'),
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
                  CupertinoButton.filled(
                    onPressed: () => setState(() => _open = !_open),
                    child: Text(
                      'Animate over ${tokens.timing.intro.inMilliseconds} ms',
                    ),
                  ),
                  SizedBox(width: space.m),
                  Flexible(
                    child: Text(
                      'stagger = ${tokens.timing.stagger.inMilliseconds} ms',
                      style: text.textStyle.copyWith(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: space.m),
              LayoutBuilder(
                builder: (context, box) => AnimatedContainer(
                  duration: tokens.timing.intro,
                  curve: theme.motion.curves.ios,
                  height: space.l,
                  width: _open ? box.maxWidth : 120,
                  decoration: BoxDecoration(
                    color: colors.tertiary,
                    borderRadius: BorderRadius.circular(space.s),
                  ),
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
