import 'package:flutter/material.dart';
import 'package:neon_books_app/src/account/login_page.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:neon_books_app/src/basket/basket.dart';
import 'package:neon_books_app/src/orders/order_service.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The beans of [BasketPage].
typedef BasketPageBeans = (
  Basket,
  Session,
  OrderService,
);

/// The Basket screen: the lines with their quantities, the total, and
/// "Order" (after a login). Reads the `Basket` and the `Session`, so it
/// rebuilds when either changes.
class BasketPage extends SpringStatelessWidget<BasketPageBeans> {
  const BasketPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (
      basket,
      session,
      orders,
    ) = beans;
    final items = basket.items;
    final space = SpringTheme.of(context).space('m');
    if (items.isEmpty) {
      return Center(child: Text(context.message('basket.empty')));
    }
    return ListView(
      padding: EdgeInsets.all(space),
      children: [
        for (final item in items)
          ListTile(
            title: Text(item.title),
            subtitle: Text('${item.quantity} × ${price(item.price)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () =>
                      basket.setQuantity(item.isbn, item.quantity - 1),
                  tooltip: context.message('basket.less'),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  onPressed: () =>
                      basket.setQuantity(item.isbn, item.quantity + 1),
                  tooltip: context.message('basket.more'),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        const Divider(),
        ListTile(
          title: Text(context.message('basket.total')),
          trailing: Text(
            price(basket.total),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        SizedBox(height: space),
        if (session.isLoggedIn)
          FilledButton.icon(
            onPressed: () => _order(context, orders),
            icon: const Icon(Icons.shopping_cart_checkout),
            label: Text(context.message('basket.order')),
          )
        else
          OutlinedButton.icon(
            onPressed: () => LoginPage.open(context),
            icon: const Icon(Icons.login),
            label: Text(context.message('basket.loginToOrder')),
          ),
      ],
    );
  }

  static Future<void> _order(BuildContext context, OrderService orders) async {
    final messenger = ScaffoldMessenger.of(context);
    String text;
    try {
      final order = await orders.placeOrder();
      text = context.mounted
          ? context.message('basket.ordered', args: [order.id])
          : '';
    } on FeignException catch (error) {
      text = context.mounted ? errorMessage(context, error) : '';
    }
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}
