import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/app/logs.dart';
import 'package:theme_showcase_neon/src/app/theme_switcher.dart';

/// One page of the showcase: its id (its address `/<id>`, the logs, the
/// tests) and its name (a typed message). The page itself is the
/// `@ScreenRoute('/<id>')` widget of lib/src/pages/.
class ShowcasePage {
  const ShowcasePage(this.id, this.label);

  final String id;
  final String Function(AppMessagesNav) label;

  /// The page's address, a branch of the [Shell].
  String get path => '/$id';
}

/// The nine pages, in the order of the navigation.
final pages = <ShowcasePage>[
  ShowcasePage('overview', (m) => m.overview),
  ShowcasePage('components', (m) => m.components),
  ShowcasePage('states', (m) => m.states),
  ShowcasePage('motion', (m) => m.motion),
  ShowcasePage('loaders', (m) => m.loaders),
  ShowcasePage('background', (m) => m.background),
  ShowcasePage('tokens', (m) => m.tokens),
  ShowcasePage('logs', (m) => m.logs),
  ShowcasePage('transitions', (m) => m.transitions),
  ShowcasePage('themes', (m) => m.themes),
];

/// The window: the logo, the navigation and the theme switcher, all neon_ui
/// widgets (chips, a panel), then the page. A column on the left of a wide
/// window, a strip on top of a narrow one.
/// The shell of the navigation: each page is a branch (`/overview`,
/// `/components`, ...), so a page keeps its state when another one is shown,
/// and every page has its own address in the browser.
@RouteShell(
  branches: [
    '/overview',
    '/components',
    '/states',
    '/motion',
    '/loaders',
    '/background',
    '/tokens',
    '/logs',
    '/transitions',
    '/themes',
  ],
)
class Shell extends StatelessWidget {
  const Shell(this.shell, {super.key});

  /// The page shown and the way to switch.
  final ShellState shell;

  void _open(BuildContext context, int index) {
    shell.select(index);
    context.bean<PageLog>().opened(pages[index].id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final nav = context.messages.nav;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = shell.child;
    final chips = [
      for (final (i, item) in pages.indexed)
        NeonChip(
          label: item.label(nav),
          selected: i == shell.index,
          onPressed: () => _open(context, i),
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
