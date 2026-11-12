import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';

/// Transitions: how a screen comes in. As in Flutter, the app type's own
/// (the iOS slide in a `CupertinoApp`) unless the theme names one for every
/// screen (`motion.page-transition`); a screen or one navigation chooses
/// for itself.
@ScreenRoute('/transitions', title: '#{nav.transitions}', branch: '/more')
class TransitionsPage extends StatelessWidget {
  const TransitionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final space = context.theme.spacing;
    Widget open(String label, String path) => Padding(
      padding: EdgeInsets.only(top: space.m),
      child: CupertinoButton.filled(
        onPressed: () => context.route.push<void>(path),
        child: Text(label),
      ),
    );
    return PageFrame(
      title: context.messages.nav.transitions,
      intro:
          "As in Flutter, a screen comes in with the app type's own "
          'transition (in a CupertinoApp the iOS slide, with the swipe back) '
          'unless the theme names one for every screen '
          '(motion.page-transition); a screen for itself, or one navigation, '
          'can choose too. This theme names no transition, so its screens '
          'slide; none makes pages switch at once, as the sidebar asks for '
          'each of its switches.',
      children: [
        Section(
          title: "The default: the platform's",
          note:
              'motion.page-transition is not set: the iOS slide. A theme that '
              'writes none has its screens there at once.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MarkdownView.code(
                '# Name one for every screen, and tune it:\n'
                'motion:\n'
                '  page-transition: { type: cupertino, duration: 300ms, '
                'curve: ease-out }',
                language: 'yaml',
              ),
              open('Open with the default', TransitionThemePage.path),
            ],
          ),
        ),
        Section(
          title: "The platform's",
          note: 'PageTransition.platform: the iOS slide, with the swipe back.',
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
          note: 'The sidebar passes none to go: switching pages never slides.',
          child: MarkdownView.code(
            'route.go(page.path, transition: PageTransition.none);',
            language: 'dart',
          ),
        ),
      ],
    );
  }
}

/// A screen with the theme's transition: the platform's here, the iOS
/// slide.
@ScreenRoute(
  TransitionThemePage.path,
  title: 'With the default',
  branch: '/more',
)
class TransitionThemePage extends StatelessWidget {
  const TransitionThemePage({super.key});

  static const path = '/transitions/default';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: 'With the default',
    text:
        'It came in with the iOS slide: the theme names no transition, so '
        "it has the platform's.",
  );
}

/// A screen with the platform's transition, the iOS slide.
@ScreenRoute(
  TransitionPlatformPage.path,
  title: "With the platform's",
  branch: '/more',
  transition: PageTransition.platform,
)
class TransitionPlatformPage extends StatelessWidget {
  const TransitionPlatformPage({super.key});

  static const path = '/transitions/platform';

  @override
  Widget build(BuildContext context) => const _Demo(
    title: "With the platform's",
    text: 'It came in with the iOS slide; swipe back from the edge.',
  );
}

/// A screen that fades in.
@ScreenRoute(
  TransitionFadePage.path,
  title: 'With a fade',
  branch: '/more',
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
      CupertinoButton.filled(
        onPressed: () => context.route.pop(),
        child: const Text('Back'),
      ),
    ],
  );
}
