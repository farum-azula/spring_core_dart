import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/app/logs.dart';
import 'package:theme_showcase_neon/src/app/theme_switcher.dart';
import 'package:theme_showcase_neon/src/pages/background_page.dart';
import 'package:theme_showcase_neon/src/pages/components_page.dart';
import 'package:theme_showcase_neon/src/pages/loaders_page.dart';
import 'package:theme_showcase_neon/src/pages/logs_page.dart';
import 'package:theme_showcase_neon/src/pages/motion_page.dart';
import 'package:theme_showcase_neon/src/pages/overview_page.dart';
import 'package:theme_showcase_neon/src/pages/states_page.dart';
import 'package:theme_showcase_neon/src/pages/themes_page.dart';
import 'package:theme_showcase_neon/src/pages/tokens_page.dart';

/// One page of the showcase: its id (logs and tests), its name (a typed
/// message) and its content.
class ShowcasePage {
  const ShowcasePage(this.id, this.label, this.builder);

  final String id;
  final String Function(AppMessagesNav) label;
  final WidgetBuilder builder;
}

/// The nine pages, in the order of the navigation.
final pages = <ShowcasePage>[
  ShowcasePage('overview', (m) => m.overview, (_) => const OverviewPage()),
  ShowcasePage(
    'components',
    (m) => m.components,
    (_) => const ComponentsPage(),
  ),
  ShowcasePage('states', (m) => m.states, (_) => const StatesPage()),
  ShowcasePage('motion', (m) => m.motion, (_) => const MotionPage()),
  ShowcasePage('loaders', (m) => m.loaders, (_) => const LoadersPage()),
  ShowcasePage(
    'background',
    (m) => m.background,
    (_) => const BackgroundPage(),
  ),
  ShowcasePage('tokens', (m) => m.tokens, (_) => const TokensPage()),
  ShowcasePage('logs', (m) => m.logs, (_) => const LogsPage()),
  ShowcasePage('themes', (m) => m.themes, (_) => const ThemesPage()),
];

/// The window: the logo, the navigation and the theme switcher, all neon_ui
/// widgets (chips, a panel), then the page. A column on the left of a wide
/// window, a strip on top of a narrow one.
class Shell extends StatefulWidget {
  const Shell({super.key, this.initialPage = 0});

  final int initialPage;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _index = widget.initialPage;

  void _open(int index) {
    setState(() => _index = index);
    context.bean<PageLog>().opened(pages[index].id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final nav = context.messages.nav;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final page = pages[_index];
    // The page changes with the theme's own medium duration (zero with
    // "reduce motion").
    final body = AnimatedSwitcher(
      duration: theme.motion.medium,
      switchInCurve: theme.motion.curves.out,
      child: KeyedSubtree(key: ValueKey(page.id), child: page.builder(context)),
    );
    final chips = [
      for (final (i, item) in pages.indexed)
        NeonChip(
          label: item.label(nav),
          selected: i == _index,
          onPressed: () => _open(i),
        ),
    ];
    const logo = NeonLogo(text: 'NEON');
    return wide
        ? Row(
            children: [
              SizedBox(
                width: 232,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(space.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      logo,
                      SizedBox(height: space.xs),
                      Text(
                        theme.tokens.showcase.tagline,
                        style: theme.typography.bodySmall.copyWith(
                          color: theme.colors.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: space.l),
                      for (final chip in chips) ...[
                        chip,
                        SizedBox(height: space.s),
                      ],
                      SizedBox(height: space.l),
                      const ThemeSwitcher(),
                    ],
                  ),
                ),
              ),
              Expanded(child: body),
            ],
          )
        : Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(space.m, space.m, space.m, 0),
                child: const Row(
                  children: [
                    logo,
                    Spacer(),
                    Flexible(child: ThemeSwitcher()),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.all(space.m),
                child: Row(
                  children: [
                    for (final chip in chips) ...[
                      chip,
                      SizedBox(width: space.s),
                    ],
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          );
  }
}
