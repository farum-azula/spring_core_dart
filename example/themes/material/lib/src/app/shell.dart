import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/app/logs.dart';
import 'package:theme_showcase_material/src/app/theme_menu.dart';

/// One page of the showcase in the navigation: its address, icon and name
/// (a typed message). The page itself is the `@ScreenRoute` screen at
/// [path].
class ShowcasePage {
  const ShowcasePage(this.id, this.icon, this.label);

  /// The name of the page in logs and tests.
  final String id;
  final IconData icon;
  final String Function(AppMessagesNav) label;

  /// The page's address, the first screen of its branch.
  String get path => '/$id';
}

/// The eleven pages, in the order of the navigation and of the branches of
/// [Shell].
final pages = <ShowcasePage>[
  ShowcasePage('colors', Icons.palette_outlined, (m) => m.colors),
  ShowcasePage('type', Icons.text_fields, (m) => m.type),
  ShowcasePage('tokens', Icons.data_object, (m) => m.tokens),
  ShowcasePage('components', Icons.widgets_outlined, (m) => m.components),
  ShowcasePage('states', Icons.touch_app_outlined, (m) => m.states),
  ShowcasePage('motion', Icons.animation, (m) => m.motion),
  ShowcasePage('loaders', Icons.hourglass_empty, (m) => m.loaders),
  ShowcasePage('background', Icons.wallpaper, (m) => m.background),
  ShowcasePage('images', Icons.image_outlined, (m) => m.images),
  ShowcasePage('transitions', Icons.swap_horiz, (m) => m.transitions),
  ShowcasePage('themes', Icons.color_lens_outlined, (m) => m.themes),
];

/// The window: a navigation rail on a wide screen, a drawer on a narrow
/// one, and the theme menu on top. It is the shell of the navigation: each
/// page is a branch (`/colors`, `/type`, ...), so a page keeps its scroll
/// and state while another one is shown, and the browser shows the page's
/// address.
@RouteShell(
  branches: [
    '/colors',
    '/type',
    '/tokens',
    '/components',
    '/states',
    '/motion',
    '/loaders',
    '/background',
    '/images',
    '/transitions',
    '/themes',
  ],
)
class Shell extends StatelessWidget {
  const Shell(this.shell, {super.key});

  /// The page shown and the way to switch.
  final ShellState shell;

  @override
  Widget build(BuildContext context) {
    final nav = context.messages.nav;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final extended = MediaQuery.sizeOf(context).width >= 1120;
    void open(int index) {
      shell.select(index);
      context.bean<PageLog>().opened(pages[index].id);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.theme.tokens.brand.name),
        actions: const [ThemeMenu()],
      ),
      drawer: wide
          ? null
          : NavigationDrawer(
              selectedIndex: shell.index,
              onDestinationSelected: (index) {
                Navigator.of(context).pop();
                open(index);
              },
              children: [
                SizedBox(height: context.theme.spacing.m),
                for (final item in pages)
                  NavigationDrawerDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label(nav)),
                  ),
              ],
            ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  extended: extended,
                  labelType: extended ? NavigationRailLabelType.none : null,
                  selectedIndex: shell.index,
                  onDestinationSelected: open,
                  destinations: [
                    for (final item in pages)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        label: Text(item.label(nav)),
                      ),
                  ],
                ),
                Expanded(child: shell.child),
              ],
            )
          : shell.child,
    );
  }
}

/// An address the app has no page for (on the web, a typed or old link).
@ScreenRoute.notFound()
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No page at ${context.route.uri.path}'),
          SizedBox(height: context.theme.spacing.m),
          FilledButton(
            onPressed: () => context.route.go(pages.first.path),
            child: Text(context.messages.nav.colors),
          ),
        ],
      ),
    ),
  );
}
