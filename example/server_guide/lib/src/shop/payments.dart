// Choosing between beans of one type (chapter 1): a gateway per profile,
// a @Fallback for when neither profile is active, a @Qualifier to get
// the fallback on purpose.
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class PaymentGateway {
  /// Charges [order]; the payment reference.
  String charge(CustomerOrder order);
}

/// dev: no money moves.
@Component('sandbox')
@Profile(['dev'])
class SandboxGateway implements PaymentGateway {
  @override
  String charge(CustomerOrder order) => 'sandbox-${order.id}';
}

/// prod: a real payment provider would be called here.
@Component('live')
@Profile(['prod'])
class LiveGateway implements PaymentGateway {
  @override
  String charge(CustomerOrder order) => 'live-${order.id}';
}

/// Queues the payment for later. Injected where no other gateway is
/// active (`@Fallback`), and by name as the backup.
@Component('offline')
@Fallback()
class OfflineGateway implements PaymentGateway {
  @override
  String charge(CustomerOrder order) => 'queued-${order.id}';
}

/// Thrown by a gateway that cannot charge now.
class PaymentException implements Exception {
  PaymentException(this.message);

  final String message;

  @override
  String toString() => 'PaymentException: $message';
}

@Service()
@Log()
class Checkout {
  /// [gateway]: the active profile's (the non-`@Fallback` candidate);
  /// [backup]: the `offline` bean, by `@Qualifier`.
  Checkout(this.gateway, @Qualifier('offline') this.backup);

  final PaymentGateway gateway;
  final PaymentGateway backup;

  String pay(CustomerOrder order) {
    try {
      return gateway.charge(order);
    } on PaymentException catch (error) {
      log.warning('payment of order ${order.id} queued: ${error.message}');
      return backup.charge(order);
    }
  }
}
