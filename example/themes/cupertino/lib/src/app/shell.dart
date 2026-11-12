import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/app/theme_menu.dart';

/// One page of the showcase: its address, icon and name (a typed message).
/// The page itself is the `@ScreenRoute` of its address
/// (lib/src/pages/).
class ShowcasePage {
  const ShowcasePage(this.id, this.path, this.icon, this.label);

  /// The name of the page in tests.
  final String id;

  /// Its address: `/<id>`. A page with no tab opens in the "More" tab
  /// (`branch: '/more'` on its `@ScreenRoute`).
  final String path;
  final IconData icon;
  final String Function(AppMessagesNav) label;
}

/// The ten pages, in the order of the sidebar.
final pages = <ShowcasePage>[
  ShowcasePage('colors', '/colors', CupertinoIcons.paintbrush, (m) => m.colors),
  ShowcasePage('type', '/type', CupertinoIcons.textformat, (m) => m.type),
  ShowcasePage(
    'tokens',
    '/tokens',
    CupertinoIcons.square_stack_3d_up,
    (m) => m.tokens,
  ),
  ShowcasePage(
    'styles',
    '/styles',
    CupertinoIcons.hand_point_right,
    (m) => m.styles,
  ),
  ShowcasePage(
    'controls',
    '/controls',
    CupertinoIcons.slider_horizontal_3,
    (m) => m.controls,
  ),
  ShowcasePage(
    'motion',
    '/motion',
    CupertinoIcons.waveform,
    (m) => m.motion,
  ),
  ShowcasePage(
    'loaders',
    '/loaders',
    CupertinoIcons.time,
    (m) => m.loaders,
  ),
  ShowcasePage(
    'background',
    '/background',
    CupertinoIcons.photo,
    (m) => m.background,
  ),
  ShowcasePage(
    'images',
    '/images',
    CupertinoIcons.photo_on_rectangle,
    (m) => m.images,
  ),
  ShowcasePage(
    'transitions',
    '/transitions',
    CupertinoIcons.arrow_right_arrow_left,
    (m) => m.transitions,
  ),
  ShowcasePage(
    'themes',
    '/themes',
    CupertinoIcons.circle_lefthalf_fill,
    (m) => m.themes,
  ),
];

/// The pages that have a tab on a narrow screen; the others are in "More".
const tabIds = ['colors', 'type', 'controls', 'themes'];

/// The window, the shell of the navigation: a branch per tab (`/colors`,
/// `/type`, `/controls`, `/themes`, `/more`), each with its own stack, so
/// switching tabs loses nothing. A sidebar of every page on a wide
/// screen, a tab bar with a "More" tab on a narrow one.
@RouteShell(branches: ['/colors', '/type', '/controls', '/themes', '/more'])
class Shell extends StatelessWidget {
  const Shell(this.shell, {super.key});

  /// The tab shown and the way to switch.
  final ShellState shell;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return wide ? _wide(context) : _narrow(context);
  }

  Widget _wide(BuildContext context) {
    final theme = context.theme;
    final route = context.bean<RouteTemplate>();
    return ColoredBox(
      color: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          SizedBox(
            width: theme.tokens.layout.sidebarWidth,
            // The page on top, as it changes (a page of "More" does not
            // switch the branch).
            child: StreamBuilder<RouteState>(
              stream: route.changes,
              builder: (context, _) => _Sidebar(
                selected: route.uri.path,
                // A menu switches pages at once: no transition.
                onSelected: (page) => unawaited(
                  route.go(page.path, transition: PageTransition.none),
                ),
              ),
            ),
          ),
          Container(width: 0.5, color: theme.colors.outline),
          Expanded(child: shell.child),
        ],
      ),
    );
  }

  // The layout of CupertinoTabScaffold, whose tabs would bring their own
  // navigators: the branch under a translucent tab bar, the content told
  // how much of it the bar covers.
  Widget _narrow(BuildContext context) {
    final nav = context.messages.nav;
    final tabPages = [
      for (final id in tabIds) pages.firstWhere((p) => p.id == id),
    ];
    final bar = CupertinoTabBar(
      currentIndex: shell.index,
      onTap: shell.select,
      items: [
        for (final p in tabPages)
          BottomNavigationBarItem(icon: Icon(p.icon), label: p.label(nav)),
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.ellipsis_circle),
          label: nav.more,
        ),
      ],
    );
    final media = MediaQuery.of(context);
    final covered = bar.preferredSize.height + media.padding.bottom;
    final opaque = bar.opaque(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).scaffoldBackgroundColor,
      ),
      child: Stack(
        children: [
          MediaQuery(
            data: opaque
                ? media.removePadding(removeBottom: true)
                : media.copyWith(
                    padding: media.padding.copyWith(bottom: covered),
                  ),
            child: Padding(
              padding: EdgeInsets.only(bottom: opaque ? covered : 0),
              child: shell.child,
            ),
          ),
          MediaQuery.withNoTextScaling(
            child: Align(alignment: Alignment.bottomCenter, child: bar),
          ),
        ],
      ),
    );
  }
}

/// Logs the page on top each time it changes (Spring's logger, never
/// print).
@Component()
@Log(topic: 'theme_showcase_cupertino.pages')
class PageLog {
  PageLog(RouteTemplate route) {
    route.changes.listen(
      (state) => log.info('page opened', fields: {'page': state.uri.path}),
    );
  }
}

/// The sidebar of a wide window: a translucent bar, as on macOS and iPadOS,
/// with a list of the pages.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelected});

  /// The address on top.
  final String selected;
  final ValueChanged<ShowcasePage> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final nav = context.messages.nav;
    final cupertino = CupertinoTheme.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ColoredBox(
          color: cupertino.barBackgroundColor,
          child: SafeArea(
            right: false,
            child: ListView(
              key: const Key('sidebar'),
              padding: EdgeInsets.all(theme.spacing.m),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    theme.spacing.s,
                    theme.spacing.m,
                    theme.spacing.s,
                    theme.spacing.xs,
                  ),
                  child: Text(
                    theme.tokens.brand.name,
                    style: cupertino.textTheme.navLargeTitleTextStyle,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    theme.spacing.s,
                    0,
                    theme.spacing.s,
                    theme.spacing.m,
                  ),
                  child: Text(
                    theme.tokens.brand.tagline,
                    style: cupertino.textTheme.textStyle.copyWith(
                      fontSize: 13,
                      color: theme.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final page in pages)
                  _SidebarItem(
                    icon: page.icon,
                    label: page.label(nav),
                    selected: page.path == selected,
                    onTap: () => onSelected(page),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: EdgeInsets.only(bottom: theme.spacing.xs),
      child: CupertinoButton(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.m - 4,
          vertical: theme.spacing.s,
        ),
        minimumSize: Size.zero,
        color: selected ? theme.tokens.palette.soft : null,
        borderRadius: BorderRadius.circular(theme.tokens.corner.tiny),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? theme.colors.primary : theme.colors.onSurface,
            ),
            SizedBox(width: theme.spacing.s + 4),
            Expanded(
              child: Text(
                label,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? theme.colors.primary
                      : theme.colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "More" tab: the pages with no tab of their own, as a list; each
/// opens over it, in the same tab (`/motion`, `branch: '/more'`).
@ScreenRoute('/more', title: '#{nav.more}')
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final nav = context.messages.nav;
    final more = [
      for (final p in pages)
        if (!tabIds.contains(p.id)) p,
    ];
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(nav.more),
            trailing: const ThemeMenu(),
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverToBoxAdapter(
              child: CupertinoListSection.insetGrouped(
                backgroundColor: CupertinoColors.transparent,
                separatorColor: theme.colors.outline,
                decoration: BoxDecoration(
                  color: theme.colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(
                    theme.tokens.layout.card.radius,
                  ),
                ),
                children: [
                  for (final page in more)
                    CupertinoListTile.notched(
                      backgroundColor: CupertinoColors.transparent,
                      leading: Icon(page.icon, color: theme.colors.primary),
                      title: Text(page.label(nav)),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => context.route.go(page.path),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An address with no page: its name and the way to the first page.
@ScreenRoute.notFound()
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No page at ${context.route.uri.path}'),
          CupertinoButton(
            onPressed: () => context.route.go('/colors'),
            child: Text(context.messages.nav.colors),
          ),
        ],
      ),
    ),
  );
}
