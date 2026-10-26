// Profiles, @Primary / @Fallback / @Qualifier.
//
// Spring (Java): @Profile("dev"), profile expressions, @Qualifier.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/app.spring.dart';

abstract interface class PaymentGateway {
  String charge(double amount);
}

@Component('sandbox')
@Profile(['dev'])
class SandboxGateway implements PaymentGateway {
  @override
  String charge(double amount) => 'sandbox charged $amount';
}

@Component('live')
@Profile(['prod'])
class LiveGateway implements PaymentGateway {
  @override
  String charge(double amount) => 'live charged $amount';
}

/// Used only when no other gateway is active.
@Component('offline')
@Fallback()
class OfflineGateway implements PaymentGateway {
  @override
  String charge(double amount) => 'offline: queued $amount';
}

/// A profile expression: active for dev-tools (a member of the dev group)
/// unless prod is active too.
@Component()
@Profile(['dev-tools & !prod'])
class DebugToolbar {}

/// `@Log` generates the `log` getter (in app.spring.dart), like Lombok's
/// `@Slf4j`: a named logger, levels from `logging.level.*`.
@Service()
@Log(topic: 'neon.checkout')
class Checkout {
  Checkout(this.gateway, @Qualifier('offline') this.backup);

  final PaymentGateway gateway;
  final PaymentGateway backup;

  /// Charges [amount], logging the result with structured fields.
  String pay(double amount) {
    final result = gateway.charge(amount);
    log.info('paid $amount', fields: {'gateway': gateway.runtimeType});
    log.debug(() => 'gateway answered: $result'); // built only if enabled
    return result;
  }
}
