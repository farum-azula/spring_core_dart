import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';

/// Transitions: how a screen comes in. None by default, in every app
/// type; an app of type `widgets` has no platform transition either. The
/// theme turns one on for every screen (`motion.page-transition`), a
/// screen or one navigation for itself. The chips switch pages at once
/// (each page is a branch).
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
        child: NeonButton(
          label: label,
          onPressed: () => context.route.push<void>(path),
        ),
      ),
    );
    return PageFrame(
      kicker: 'PAGE TRANSITIONS',
      title: 'Transitions',
      intro:
          'A screen shows at once unless something asks for a transition: '
          'the theme for every screen (motion.page-transition), a screen for '
          'itself, or one navigation. The neon theme asks for none, and an '
          'app of type widgets has no platform transition of its own.',
      children: [
        Section(
          title: 'The default: none',
          note:
              'motion.page-transition is not set: the screen is there at once.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NeonCode(
                '# Turn one on for every screen, and tune it:\n'
                'motion:\n'
                r'  page-transition: { type: fade, duration: $motion.durations.fast, curve: ease-out }',
                language: 'yaml',
              ),
              open('OPEN WITH THE DEFAULT', TransitionThemePage.path),
            ],
          ),
        ),
        Section(
          title: "The platform's",
          note:
              'PageTransition.platform: the app type\'s own, and an app of '
              'type widgets has none: still at once.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NeonCode(
                "@ScreenRoute('/transitions/platform', "
                'transition: PageTransition.platform)',
                language: 'dart',
              ),
              open("OPEN WITH THE PLATFORM'S", TransitionPlatformPage.path),
            ],
          ),
        ),
        Section(
          title: 'A custom one',
          note: "A zoom, the screen's own, in an app with no Material at all.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NeonCode(
                "@ScreenRoute('/transitions/zoom', "
                'transition: PageTransition.zoom)',
                language: 'dart',
              ),
              open('OPEN WITH A ZOOM', TransitionZoomPage.path),
            ],
          ),
        ),
        const Section(
          title: 'One navigation',
          note: 'go and push take a transition for that navigation only.',
          child: NeonCode(
            'context.route.go(path, transition: PageTransition.fade);',
            language: 'dart',
          ),
        ),
      ],
    );
  }
}

/// A screen with the theme's transition: none.
@ScreenRoute(TransitionThemePage.path, title: 'With the default')
class TransitionThemePage extends StatelessWidget {
  const TransitionThemePage({super.key});

  static const path = '/transitions/default';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: 'With the default',
    text: 'It was there at once: the theme asks for no transition.',
  );
}

/// A screen with the platform's transition: none in an app of type
/// widgets.
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
    text: 'It was there at once: a WidgetsApp has no transition of its own.',
  );
}

/// A screen that zooms in.
@ScreenRoute(
  TransitionZoomPage.path,
  title: 'With a zoom',
  transition: PageTransition.zoom,
)
class TransitionZoomPage extends StatelessWidget {
  const TransitionZoomPage({super.key});

  static const path = '/transitions/zoom';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: 'With a zoom',
    text: 'It zoomed in: its own transition.',
  );
}

class _Demo extends StatelessWidget {
  const _Demo({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => PageFrame(
    kicker: 'PAGE TRANSITIONS',
    title: title,
    intro: text,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: NeonButton(label: 'BACK', onPressed: () => context.route.pop()),
      ),
    ],
  );
}
