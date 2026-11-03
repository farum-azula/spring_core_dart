import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/app/logs.dart';
import 'package:theme_showcase_cupertino/src/app/theme_menu.dart';
import 'package:theme_showcase_cupertino/src/pages/background_page.dart';
import 'package:theme_showcase_cupertino/src/pages/colors_page.dart';
import 'package:theme_showcase_cupertino/src/pages/controls_page.dart';
import 'package:theme_showcase_cupertino/src/pages/images_page.dart';
import 'package:theme_showcase_cupertino/src/pages/motion_page.dart';
import 'package:theme_showcase_cupertino/src/pages/styles_page.dart';
import 'package:theme_showcase_cupertino/src/pages/themes_page.dart';
import 'package:theme_showcase_cupertino/src/pages/tokens_page.dart';
import 'package:theme_showcase_cupertino/src/pages/type_page.dart';

/// One page of the showcase: its icon, its name (a typed message) and its
/// content.
class ShowcasePage {
  const ShowcasePage(this.id, this.icon, this.label, this.builder);

  /// The name of the page in logs and tests.
  final String id;
  final IconData icon;
  final String Function(AppMessagesNav) label;
  final WidgetBuilder builder;
}

/// The nine pages, in the order of the sidebar.
final pages = <ShowcasePage>[
  ShowcasePage(
    'colors',
    CupertinoIcons.paintbrush,
    (m) => m.colors,
    (_) => const ColorsPage(),
  ),
  ShowcasePage(
    'type',
    CupertinoIcons.textformat,
    (m) => m.type,
    (_) => const TypePage(),
  ),
  ShowcasePage(
    'tokens',
    CupertinoIcons.square_stack_3d_up,
    (m) => m.tokens,
    (_) => const TokensPage(),
  ),
  ShowcasePage(
    'styles',
    CupertinoIcons.hand_point_right,
    (m) => m.styles,
    (_) => const StylesPage(),
  ),
  ShowcasePage(
    'controls',
    CupertinoIcons.slider_horizontal_3,
    (m) => m.controls,
    (_) => const ControlsPage(),
  ),
  ShowcasePage(
    'motion',
    CupertinoIcons.waveform,
    (m) => m.motion,
    (_) => const MotionPage(),
  ),
  ShowcasePage(
    'background',
    CupertinoIcons.photo,
    (m) => m.background,
    (_) => const BackgroundPage(),
  ),
  ShowcasePage(
    'images',
    CupertinoIcons.photo_on_rectangle,
    (m) => m.images,
    (_) => const ImagesPage(),
  ),
  ShowcasePage(
    'themes',
    CupertinoIcons.circle_lefthalf_fill,
    (m) => m.themes,
    (_) => const ThemesPage(),
  ),
];

/// The pages that have a tab on a narrow screen; the others are in "More".
const tabIds = ['colors', 'type', 'controls', 'themes'];

/// The window: a sidebar and the page on a wide screen, a tab bar (with a
/// "More" tab) on a narrow one.
class Shell extends StatefulWidget {
  const Shell({super.key, this.initialPage = 0});

  final int initialPage;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _index = widget.initialPage;
  late final _tabs = CupertinoTabController(
    initialIndex: _tabOf(pages[widget.initialPage].id),
  );

  // The tab of a page; the last tab ("More") for a page without one.
  static int _tabOf(String id) =>
      tabIds.contains(id) ? tabIds.indexOf(id) : tabIds.length;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _opened(ShowcasePage page) => context.bean<PageLog>().opened(page.id);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return wide ? _wide(context) : _narrow(context);
  }

  Widget _wide(BuildContext context) {
    final theme = context.theme;
    final page = pages[_index];
    // The page changes with the theme's own medium duration.
    final body = AnimatedSwitcher(
      duration: theme.motion.medium,
      switchInCurve: theme.motion.curves.out,
      child: KeyedSubtree(key: ValueKey(page.id), child: page.builder(context)),
    );
    return ColoredBox(
      color: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          SizedBox(
            width: theme.tokens.layout.sidebarWidth,
            child: _Sidebar(
              selected: _index,
              onSelected: (index) {
                setState(() => _index = index);
                _opened(pages[index]);
              },
            ),
          ),
          Container(width: 0.5, color: theme.colors.outline),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _narrow(BuildContext context) {
    final nav = context.messages.nav;
    final tabPages = [
      for (final id in tabIds) pages.firstWhere((p) => p.id == id),
    ];
    final more = [
      for (final p in pages)
        if (!tabIds.contains(p.id)) p,
    ];
    return CupertinoTabScaffold(
      controller: _tabs,
      tabBar: CupertinoTabBar(
        onTap: (index) {
          if (index < tabPages.length) {
            _opened(tabPages[index]);
          }
        },
        items: [
          for (final p in tabPages)
            BottomNavigationBarItem(
              icon: Icon(p.icon),
              label: p.label(nav),
            ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.ellipsis_circle),
            label: nav.more,
          ),
        ],
      ),
      tabBuilder: (context, index) => CupertinoTabView(
        builder: (context) => index < tabPages.length
            ? tabPages[index].builder(context)
            : _More(
                pages: more,
                onOpen: (page) {
                  _opened(page);
                  Navigator.of(context).push<void>(
                    CupertinoPageRoute(
                      settings: RouteSettings(name: page.id),
                      builder: page.builder,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// The sidebar of a wide window: a translucent bar, as on macOS and iPadOS,
/// with a list of the pages.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

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
                for (var i = 0; i < pages.length; i++)
                  _SidebarItem(
                    icon: pages[i].icon,
                    label: pages[i].label(nav),
                    selected: i == selected,
                    onTap: () => onSelected(i),
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

/// The "More" tab: the pages with no tab of their own, as a list that
/// pushes them.
class _More extends StatelessWidget {
  const _More({required this.pages, required this.onOpen});

  final List<ShowcasePage> pages;
  final ValueChanged<ShowcasePage> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final nav = context.messages.nav;
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
                  for (final page in pages)
                    CupertinoListTile.notched(
                      backgroundColor: CupertinoColors.transparent,
                      leading: Icon(page.icon, color: theme.colors.primary),
                      title: Text(page.label(nav)),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => onOpen(page),
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
