import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';
import 'package:theme_showcase_neon/src/widgets/swatch.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// Tokens: nested groups, a list of colors, references and expressions.
@ScreenRoute('/tokens', title: '#{nav.tokens}')
class TokensPage extends StatelessWidget {
  const TokensPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final neon = theme.tokens.neon;
    return PageFrame(
      kicker: 'TOKENS',
      title: 'Tokens and references',
      intro:
          'Values of the design system\'s own. They nest, they can be lists, '
          'and a value can name another one: the accent says '
          r'$colors.primary, so a theme that changes the primary color '
          'changes it.',
      children: [
        Section(
          title: 'The palette',
          note: 'tokens.neon.yellow ... green: read as context.theme.tokens.neon.*',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              Swatch('yellow', neon.yellow),
              Swatch('cyan', neon.cyan),
              Swatch('pink', neon.pink),
              Swatch('lavender', neon.lavender),
              Swatch('green', neon.green),
              Swatch('accent', neon.accent),
              Swatch('glow', neon.glow),
            ],
          ),
        ),
        Section(
          title: 'A list of colors',
          note: 'tokens.neon.modal.border.colors is a List<Color>.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (final (i, color) in neon.modal.border.colors.indexed)
                Swatch('colors[$i]', color),
            ],
          ),
        ),
        Section(
          title: 'Color expressions',
          note:
              'A badge\'s soft fill is its color at 12 percent: tone-soft. '
              'Nothing in Dart computes it.',
          child: Wrap(
            spacing: space.s,
            runSpacing: space.s,
            children: [
              for (final tone in NeonTone.values)
                NeonBadge('${tone.name} + soft', tone: tone),
            ],
          ),
        ),
        const Section(
          title: 'In the theme',
          child: YamlBox(
            label: 'neon_ui/lib/resources/themes/neon.yml',
            r'''
tokens:
  neon:
    yellow: '#F2E35B'
    accent: $colors.primary
    glow: { color: $neon.accent, alpha: 35% }
    panel-border: { color: white, alpha: 15% }
    tone-soft:
      cyan: { color: $neon.cyan, alpha: 12% }
      pink: { color: $neon.pink, alpha: 12% }''',
          ),
        ),
        Section(
          title: 'In the app',
          note: 'The app has tokens of its own next to the library\'s.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'showcase.content-width: '
                '${theme.tokens.showcase.contentWidth.round()}',
                style: theme.typography.code,
              ),
              SizedBox(height: space.m),
              const YamlBox(
                label: 'lib/resources/application.yml',
                r'''
tokens:
  showcase:
    content-width: 980
    tile-height: 150''',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
