import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';
import 'package:theme_showcase_neon/src/widgets/tile_grid.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// What this app is: a design system that is a library and a theme file.
@ScreenRoute('/overview', title: '#{nav.overview}')
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return PageFrame(
      kicker: 'THEME SHOWCASE',
      title: 'A design system without Material',
      intro:
          'Every control on this screen is a widget of neon_ui, a design '
          'system shipped as a library. There is no Scaffold, no '
          'ThemeData, no Cupertino. The look is YAML in the library; this '
          'app imports it and adds a theme of its own.',
      children: [
        Section(
          title: 'What is on screen',
          child: Wrap(
            spacing: space.s,
            runSpacing: space.s,
            children: const [
              NeonBadge('app type widgets'),
              NeonBadge('no Material', tone: NeonTone.cyan),
              NeonBadge('no Cupertino', tone: NeonTone.pink),
              NeonBadge('theme from a library', tone: NeonTone.lavender),
              NeonBadge('typed keys', tone: NeonTone.green),
            ],
          ),
        ),
        const Section(
          title: 'A WidgetsApp, and the library\'s theme',
          note:
              'neon_ui embeds its lib/resources/ in its auto-configuration, so '
              'the app imports themes/neon.yml as if it were its own file.',
          child: YamlBox(
            label: 'lib/resources/application.yml',
            '''
spring:
  config:
    import: resources:themes/neon.yml, resources:themes/code.yml
  flutter:
    app:
      type: widgets
    theme:
      active: neon''',
          ),
        ),
        Section(
          title: 'The pieces',
          note:
              'Each page of this app shows one of them next to the YAML that '
              'makes it.',
          child: const TileGrid(
            children: [
              _Piece(
                'Components',
                'Buttons, chips, badges, fields, code, panels and a '
                    'resizable grip. Looks per state: styles.*',
              ),
              _Piece(
                'States',
                'Hover, focus, press, disabled, selected and error by '
                    'ThemeStates, with a transition.',
              ),
              _Piece(
                'Motion',
                'The glow modal: its border turns by animations.border-spin '
                    'and stands still with reduce motion.',
              ),
              _Piece(
                'Background',
                'A picture with a veil under every screen, a stage screen '
                    'and an opaque one.',
              ),
              _Piece(
                'Tokens',
                'Nested groups, lists of colors, color objects and '
                    'references.',
              ),
              _Piece(
                'Themes',
                'neon (the library\'s) and neon-ice (ours, extends neon), '
                    'switched at run time.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Piece extends StatelessWidget {
  const _Piece(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return NeonPanel(
      title: title,
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.m),
        child: Text(
          text,
          style: theme.typography.bodyMedium.copyWith(
            color: theme.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
