import 'package:flutter/material.dart';
import 'package:neon_books_app/src/account/login_page.dart';
import 'package:neon_books_app/src/account/session.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:neon_books_app/src/orders/order_service.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The beans of [OrdersPage].
typedef OrdersPageBeans = (
  OrderService,
  Session,
);

/// The Orders screen: the user's orders (an admin's: everyone's, the
/// server filters them with `@PostFilter`).
class OrdersPage extends SpringStatefulWidget<OrdersPageBeans> {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends SpringState<OrdersPage, OrdersPageBeans> {
  Future<List<ShopOrder>>? _orders;
  String? _user;

  @override
  Widget build(BuildContext context) {
    final (
      service,
      session,
    ) = beans;
    final user = session.user;
    if (user == null) {
      _orders = null;
      return Center(
        child: OutlinedButton.icon(
          onPressed: () => LoginPage.open(context),
          icon: const Icon(Icons.login),
          label: Text(context.message('orders.login')),
        ),
      );
    }
    if (user != _user) {
      _user = user;
      _orders = service.orders();
    }
    return RefreshIndicator(
      onRefresh: () async {
        final orders = service.orders();
        setState(() => _orders = orders);
        await orders;
      },
      child: FutureBuilder(
        future: _orders,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              children: [
                ListTile(title: Text(errorMessage(context, snapshot.error!))),
              ],
            );
          }
          final orders = snapshot.data;
          if (orders == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (orders.isEmpty) {
            return ListView(
              children: [ListTile(title: Text(context.message('orders.none')))],
            );
          }
          return ListView(
            children: [
              for (final order in orders)
                ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text(
                    context.message('orders.order', args: [order.id]),
                  ),
                  subtitle: Text(
                    [
                      for (final line in order.lines)
                        '${line.quantity} × ${line.title.isEmpty ? line.isbn : line.title}',
                    ].join(', '),
                  ),
                  trailing: Text(price(order.total)),
                ),
            ],
          );
        },
      ),
    );
  }
}
