// Profiles, @Primary / @Fallback / @Qualifier.
//
// Spring (Java): @Profile("dev"), profile expressions, @Qualifier.
import 'package:spring_core_dart/spring_core_dart.dart';

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

@Service()
class Checkout {
  Checkout(this.gateway, @Qualifier('offline') this.backup);

  final PaymentGateway gateway;
  final PaymentGateway backup;
}
