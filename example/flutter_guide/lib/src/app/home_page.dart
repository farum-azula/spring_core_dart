import 'package:flutter/material.dart';
import 'package:neon_books_app/src/account/account_button.dart';
import 'package:neon_books_app/src/app/app_properties.dart';
import 'package:neon_books_app/src/basket/basket_badge.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The app's sections, in the order of the shell's branches.
enum Section { catalog, basket, orders, stock, more }

/// The home of the app: an app bar and the sections, in a bottom bar on
/// phones and a rail on wide screens (`app.navigation`, set per platform
/// profile). It is the shell of the navigation: each section is a branch
/// (`/catalog`, `/basket`, ...) with its own stack, so switching sections
/// loses nothing; the screens over it (a book, the settings) open over
/// everything.
@RouteShell(branches: ['/catalog', '/basket', '/orders', '/stock', '/more'])
class HomePage extends SpringStatelessWidget<(AppProperties,)> {
  const HomePage(this.shell, {super.key});

  /// The section shown and the way to switch.
  final ShellState shell;

  @override
  Widget build(BuildContext context) {
    final (app,) = beans;
    final body = shell.child;
    final section = Section.values[shell.index];
    final destinations = [
      (Section.catalog, const Icon(Icons.menu_book_outlined)),
      (Section.basket, const BasketBadge()),
      (Section.orders, const Icon(Icons.receipt_long_outlined)),
      (Section.stock, const Icon(Icons.bolt_outlined)),
      (Section.more, const Icon(Icons.more_horiz)),
    ];
    String label(Section section) => context.message('section.${section.name}');
    void select(int index) => shell.select(index);

    // The desktop window has a transparent title bar
    // (application-desktop.properties): the window buttons are over the
    // app bar, so it leaves room for them, and its empty part moves the
    // window. Zero insets elsewhere.
    final insets = DesktopWindow.insetsOf(context);
    final bar = AppBar(
      title: insets.left == 0
          ? Text(app.title)
          : Padding(
              padding: EdgeInsets.only(left: insets.left),
              child: Text(app.title),
            ),
      actions: [
        const AccountButton(),
        // (a second action also turns off the centered title of Apple
        // platforms, so only where there are buttons to leave room for)
        if (insets.right > 0) SizedBox(width: insets.right),
      ],
    );
    // Dragging the bar's empty part moves the window.
    final appBar = PreferredSize(
      preferredSize: bar.preferredSize,
      child: WindowDragArea(child: bar),
    );
    if (app.navigation == NavigationStyle.rail) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: section.index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (section, icon) in destinations)
                  NavigationRailDestination(
                    icon: icon,
                    label: Text(label(section)),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: section.index,
        onDestinationSelected: select,
        destinations: [
          for (final (section, icon) in destinations)
            NavigationDestination(icon: icon, label: label(section)),
        ],
      ),
    );
  }
}
