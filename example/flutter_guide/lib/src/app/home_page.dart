import 'package:flutter/material.dart';
import 'package:neon_books_app/src/account/account_button.dart';
import 'package:neon_books_app/src/app/app_properties.dart';
import 'package:neon_books_app/src/app/more_page.dart';
import 'package:neon_books_app/src/basket/basket_badge.dart';
import 'package:neon_books_app/src/basket/basket_page.dart';
import 'package:neon_books_app/src/catalog/catalog_page.dart';
import 'package:neon_books_app/src/orders/orders_page.dart';
import 'package:neon_books_app/src/stock/live_stock_page.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The app's sections.
enum Section { catalog, basket, orders, stock, more }

/// The home of the app: an app bar and the sections, in a bottom bar on
/// phones and a rail on wide screens (`app.navigation`, set per platform
/// profile). Its state is only the section shown; everything else is in
/// beans, so switching sections loses nothing.
class HomePage extends SpringStatefulWidget<(AppProperties,)> {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends SpringState<HomePage, (AppProperties,)> {
  var _section = Section.catalog;

  @override
  Widget build(BuildContext context) {
    final (app,) = beans;
    final body = switch (_section) {
      Section.catalog => const CatalogPage(),
      Section.basket => const BasketPage(),
      Section.orders => const OrdersPage(),
      Section.stock => const LiveStockPage(),
      Section.more => const MorePage(),
    };
    final destinations = [
      (Section.catalog, const Icon(Icons.menu_book_outlined)),
      (Section.basket, const BasketBadge()),
      (Section.orders, const Icon(Icons.receipt_long_outlined)),
      (Section.stock, const Icon(Icons.bolt_outlined)),
      (Section.more, const Icon(Icons.more_horiz)),
    ];
    String label(Section section) => context.message('section.${section.name}');
    void select(int index) => setState(() => _section = Section.values[index]);

    final appBar = AppBar(
      title: Text(app.title),
      actions: const [AccountButton()],
    );
    if (app.navigation == NavigationStyle.rail) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _section.index,
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
        selectedIndex: _section.index,
        onDestinationSelected: select,
        destinations: [
          for (final (section, icon) in destinations)
            NavigationDestination(icon: icon, label: label(section)),
        ],
      ),
    );
  }
}
