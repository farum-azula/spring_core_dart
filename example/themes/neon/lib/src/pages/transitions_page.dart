import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';

/// Transitions: how a screen comes in. As in Flutter, the app type's own
/// unless the theme names one for every screen (`motion.page-transition`),
/// and an app of type `widgets` has none, as Flutter's `WidgetsApp`: the
/// screens show at once. A screen or one navigation chooses for itself.
/// The chips switch pages at once (each page is a branch).
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
          "As in Flutter, a screen comes in with the app type's own "
          'transition unless the theme names one for every screen '
          '(motion.page-transition); a screen for itself, or one navigation, '
          'can choose too. The neon theme names none, and an app of type '
          "widgets has no transition of its own, as Flutter's WidgetsApp: "
          'the screen is there at once, as with none.',
      children: [
        Section(
          title: "The default: the platform's, none here",
          note:
              "motion.page-transition is not set: the platform's, and an app "
              'of type widgets has none, so the screen is there at once.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NeonCode(
                '# Name one for every screen, and tune it:\n'
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
          title: "A screen's own",
          note:
              'A fade with a slide upwards, one of the transitions that need '
              'no design library (zoom is Material\'s, cupertino '
              'Cupertino\'s: each comes with its starter).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NeonCode(
                "@ScreenRoute('/transitions/fade-upwards', "
                'transition: PageTransition.fadeUpwards)',
                language: 'dart',
              ),
              open('OPEN WITH A FADE UPWARDS', TransitionFadeUpwardsPage.path),
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

/// A screen with the theme's transition: the platform's, none in an app
/// of type widgets.
@ScreenRoute(TransitionThemePage.path, title: 'With the default')
class TransitionThemePage extends StatelessWidget {
  const TransitionThemePage({super.key});

  static const path = '/transitions/default';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: 'With the default',
    text:
        "It was there at once: the theme names no transition, and the "
        "platform's is none in a WidgetsApp.",
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

/// A screen that fades in while it slides upwards.
@ScreenRoute(
  TransitionFadeUpwardsPage.path,
  title: 'With a fade upwards',
  transition: PageTransition.fadeUpwards,
)
class TransitionFadeUpwardsPage extends StatelessWidget {
  const TransitionFadeUpwardsPage({super.key});

  static const path = '/transitions/fade-upwards';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: 'With a fade upwards',
    text: 'It faded in from below: its own transition.',
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
