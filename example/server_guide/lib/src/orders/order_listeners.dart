// Who reacts to orders (chapter 6): @EventListener methods with a
// condition, an order and @Async, and an ApplicationListener bean. The
// stock goes first (StockService, @Order(1)).
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/orders/mail.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:neon_books_server/src/shop/receipt.dart';
import 'package:neon_books_server/src/shop/shop_properties.dart';
import 'package:neon_books_server/src/support/chat_message.dart';
import 'package:neon_books_server/src/support/support_sessions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// The condition of [VipDesk.onVipOrder]: a top-level function (Dart has
/// no reflection to evaluate a SpEL `condition` string on the event).
bool isVipOrder(OrderPlaced placed) => placed.order.total >= 100;

@Component()
@Log(topic: 'neon.vip')
class VipDesk {
  /// Only orders of 100 EUR and more, after the stock (`@Order(2)`).
  @EventListener(condition: isVipOrder)
  @Order(2)
  void onVipOrder(OrderPlaced placed) => log.info(
    'VIP order ${placed.order.id} of ${placed.order.customer}: '
    '${placed.order.total} EUR',
  );
}

/// Sends the order confirmation. `@Async()`: on the `TaskExecutor` of the
/// scheduling starter, so placing the order does not wait for the mail.
///
/// Abstract, with a `@Lookup` method: the container creates a generated
/// subclass whose [newReceipt] returns a new prototype on every call.
@Component()
abstract class OrderMailer {
  OrderMailer(
    @Value('classpath:templates/order-confirmation.txt') this.template,
    this.messages,
    this.mail,
    this.shop,
  );

  final Resource template;
  final MessageSource messages;
  final MailSender mail;
  final ShopProperties shop;

  /// A new [ReceiptBuilder] (a prototype bean) per call.
  @Lookup()
  ReceiptBuilder newReceipt();

  @EventListener()
  @Async()
  Future<void> onOrderPlaced(OrderPlaced placed) async {
    final order = placed.order;
    final count = order.lines.fold(0, (sum, line) => sum + line.quantity);
    final receipt = newReceipt();
    for (final line in order.lines) {
      receipt.add('${line.quantity} x ${line.title}: ${line.total}');
    }
    final body = MessageFormat.format((await template.readAsString()).trim(), [
      order.customer,
      order.id,
      messages.getMessage('order.items', args: [count]),
      order.total.toStringAsFixed(2),
      shop.deliveryTime.inDays,
    ]);
    mail.send(
      order.customer,
      messages.getMessage(
        'order.confirmation.subject',
        args: [order.id, shop.name],
      ),
      '$body\n\n${receipt.build()}',
    );
  }
}

/// A classic `ApplicationListener`: tells the customer in the support
/// chat (if connected) that the order left.
@Component()
class ShippingNotifier implements ApplicationListener<OrderShipped> {
  ShippingNotifier(this.support);

  final SupportSessions support;

  @override
  void onApplicationEvent(OrderShipped event) => support.sendTo(
    event.order.customer,
    ChatMessage(
      from: 'NEON Books',
      text: 'Your order ${event.order.id} has shipped.',
      at: DateTime.now().toUtc(),
    ),
  );
}
