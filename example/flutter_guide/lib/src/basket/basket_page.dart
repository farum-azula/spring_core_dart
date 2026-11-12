import 'package:material_ui/material_ui.dart';
import 'package:neon_books_app/spring_gen/main.spring.dart';
import 'package:neon_books_app/src/account/login_page.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:neon_books_app/src/basket/basket.dart';
import 'package:neon_books_app/src/orders/order_service.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
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
@ScreenRoute('/basket', title: '#{section.basket}')
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
    final space = context.theme.spacing.m;
    if (items.isEmpty) {
      return Center(child: Text(context.messages.basket.empty));
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
                  tooltip: context.messages.basket.less,
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  onPressed: () =>
                      basket.setQuantity(item.isbn, item.quantity + 1),
                  tooltip: context.messages.basket.more,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        const Divider(),
        ListTile(
          title: Text(context.messages.basket.total),
          trailing: Text(
            price(basket.total),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        SizedBox(height: space),
        if (session.isLoggedIn)
          _OrderButton(orders)
        else
          OutlinedButton.icon(
            onPressed: () => LoginPage.open(context),
            icon: const Icon(Icons.login),
            label: Text(context.messages.basket.loginToOrder),
          ),
      ],
    );
  }
}

/// "Order": while the order is on its way to the server the button is off
/// and a bar (`loaders.bar`) runs under it.
class _OrderButton extends StatefulWidget {
  const _OrderButton(this.orders);

  final OrderService orders;

  @override
  State<_OrderButton> createState() => _OrderButtonState();
}

class _OrderButtonState extends State<_OrderButton> {
  bool _sending = false;

  Future<void> _order() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    String text;
    try {
      final order = await widget.orders.placeOrder();
      text = mounted ? context.messages.basket.ordered(order.id) : '';
    } on FeignException catch (error) {
      text = mounted ? errorMessage(context, error) : '';
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: _sending ? null : _order,
        icon: const Icon(Icons.shopping_cart_checkout),
        label: Text(context.messages.basket.order),
      ),
      if (_sending)
        Padding(
          padding: EdgeInsets.only(top: context.theme.spacing.s),
          child: Center(child: ThemeLoader(context.theme.loaders.bar)),
        ),
    ],
  );
}
