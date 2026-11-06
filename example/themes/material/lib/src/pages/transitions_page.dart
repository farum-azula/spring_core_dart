import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// Transitions: how a screen comes in. None by default, in every app
/// type; a theme turns one on for every screen (`motion.page-transition`:
/// zoom in neon), a screen or one navigation for itself. The rail switches
/// pages at once (each page is a branch of the shell).
@ScreenRoute('/transitions', title: '#{nav.transitions}')
class TransitionsPage extends StatelessWidget {
  const TransitionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final space = context.theme.spacing;
    Widget open(String label, String path) => Padding(
      padding: EdgeInsets.only(top: space.m),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: () => context.route.push<void>(path),
          child: Text(label),
        ),
      ),
    );
    return PageFrame(
      title: context.messages.nav.transitions,
      intro:
          'A screen shows at once unless something asks for a transition: '
          'the theme for every screen (motion.page-transition), a screen for '
          'itself, or one navigation. The light and dark themes ask for '
          'none; neon zooms. Switching pages in the rail never animates: '
          'each page is a branch of the shell.',
      children: [
        Section(
          title: 'The default: none',
          note:
              'Not set in application.yml: none. A theme sets its own: switch '
              'to neon in the menu and open the screen again.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const YamlBox(
                'motion:\n  page-transition: zoom',
                label: 'themes/neon.yml',
              ),
              SizedBox(height: space.s),
              const YamlBox(
                'motion:\n  page-transition: none',
                label: 'themes/high-contrast.yml',
              ),
              SizedBox(height: space.s),
              const MarkdownView.code(
                '# Tuned: the kind, its duration and its curve.\n'
                'motion:\n'
                '  page-transition: { type: fade-upwards, duration: 300ms, '
                'curve: ease-out }',
                language: 'yaml',
              ),
              open('Open with the default', TransitionThemePage.path),
            ],
          ),
        ),
        Section(
          title: "The platform's",
          note: "PageTransition.platform: Material's own transition.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MarkdownView.code(
                "@ScreenRoute('/transitions/platform', "
                'transition: PageTransition.platform)',
                language: 'dart',
              ),
              open("Open with the platform's", TransitionPlatformPage.path),
            ],
          ),
        ),
        Section(
          title: 'A custom one',
          note: "A fade, the screen's own; the theme can set its duration.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MarkdownView.code(
                "@ScreenRoute('/transitions/fade', "
                'transition: PageTransition.fade)',
                language: 'dart',
              ),
              open('Open with a fade', TransitionFadePage.path),
            ],
          ),
        ),
        const Section(
          title: 'One navigation',
          note: 'go and push take a transition for that navigation only.',
          child: MarkdownView.code(
            'context.route.go(path, transition: PageTransition.none);',
            language: 'dart',
          ),
        ),
      ],
    );
  }
}

/// A screen with the theme's transition: none in light, zoom in neon.
@ScreenRoute(TransitionThemePage.path, title: 'With the default')
class TransitionThemePage extends StatelessWidget {
  const TransitionThemePage({super.key});

  static const path = '/transitions/default';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: 'With the default',
    text: "It came in the theme's way: at once, or zooming in neon.",
  );
}

/// A screen with Material's own transition.
@ScreenRoute(
  TransitionPlatformPage.path,
  title: "With the platform's",
  transition: PageTransition.platform,
)
class TransitionPlatformPage extends StatelessWidget {
  const TransitionPlatformPage({super.key});

  static const path = '/transitions/platform';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: "With the platform's",
    text: "It came in with Material's own transition.",
  );
}

/// A screen that fades in.
@ScreenRoute(
  TransitionFadePage.path,
  title: 'With a fade',
  transition: PageTransition.fade,
)
class TransitionFadePage extends StatelessWidget {
  const TransitionFadePage({super.key});

  static const path = '/transitions/fade';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: 'With a fade',
    text: 'It faded in: its own transition.',
  );
}

class _Demo extends StatelessWidget {
  const _Demo({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: title,
    intro: text,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: () => context.route.pop(),
          child: const Text('Back'),
        ),
      ),
    ],
  );
}
