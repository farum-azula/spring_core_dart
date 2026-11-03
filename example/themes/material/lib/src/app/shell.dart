import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/app/logs.dart';
import 'package:theme_showcase_material/src/app/theme_menu.dart';
import 'package:theme_showcase_material/src/pages/background_page.dart';
import 'package:theme_showcase_material/src/pages/colors_page.dart';
import 'package:theme_showcase_material/src/pages/components_page.dart';
import 'package:theme_showcase_material/src/pages/images_page.dart';
import 'package:theme_showcase_material/src/pages/motion_page.dart';
import 'package:theme_showcase_material/src/pages/states_page.dart';
import 'package:theme_showcase_material/src/pages/themes_page.dart';
import 'package:theme_showcase_material/src/pages/tokens_page.dart';
import 'package:theme_showcase_material/src/pages/type_page.dart';

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

/// The nine pages, in the order of the navigation.
final pages = <ShowcasePage>[
  ShowcasePage(
    'colors',
    Icons.palette_outlined,
    (m) => m.colors,
    (_) => const ColorsPage(),
  ),
  ShowcasePage(
    'type',
    Icons.text_fields,
    (m) => m.type,
    (_) => const TypePage(),
  ),
  ShowcasePage(
    'tokens',
    Icons.data_object,
    (m) => m.tokens,
    (_) => const TokensPage(),
  ),
  ShowcasePage(
    'components',
    Icons.widgets_outlined,
    (m) => m.components,
    (_) => const ComponentsPage(),
  ),
  ShowcasePage(
    'states',
    Icons.touch_app_outlined,
    (m) => m.states,
    (_) => const StatesPage(),
  ),
  ShowcasePage(
    'motion',
    Icons.animation,
    (m) => m.motion,
    (_) => const MotionPage(),
  ),
  ShowcasePage(
    'background',
    Icons.wallpaper,
    (m) => m.background,
    (_) => const BackgroundPage(),
  ),
  ShowcasePage(
    'images',
    Icons.image_outlined,
    (m) => m.images,
    (_) => const ImagesPage(),
  ),
  ShowcasePage(
    'themes',
    Icons.color_lens_outlined,
    (m) => m.themes,
    (_) => const ThemesPage(),
  ),
];

/// The window: a navigation rail on a wide screen, a drawer on a narrow
/// one, and the theme menu on top.
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
    final nav = context.messages.nav;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final extended = MediaQuery.sizeOf(context).width >= 1120;
    final page = pages[_index];
    // The page changes with the theme's own medium duration.
    final body = AnimatedSwitcher(
      duration: context.theme.motion.medium,
      switchInCurve: context.theme.motion.curves.out,
      child: KeyedSubtree(key: ValueKey(page.id), child: page.builder(context)),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.theme.tokens.brand.name),
        actions: const [ThemeMenu()],
      ),
      drawer: wide
          ? null
          : NavigationDrawer(
              selectedIndex: _index,
              onDestinationSelected: (index) {
                Navigator.of(context).pop();
                _open(index);
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
                  selectedIndex: _index,
                  onDestinationSelected: _open,
                  destinations: [
                    for (final item in pages)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        label: Text(item.label(nav)),
                      ),
                  ],
                ),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }
}
