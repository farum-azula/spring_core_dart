import 'package:spring_core_dart/spring_core_dart.dart';

/// A condition of our own (`@Conditional([SupplierConfigured])`): the
/// supplier has an address and an API key. In prod without
/// `SUPPLIER_API_KEY` the restock job is simply not there.
class SupplierConfigured implements Condition {
  const SupplierConfigured();

  @override
  bool matches(ConditionContext context) {
    final environment = context.environment;
    bool has(String key) => (environment.getProperty(key) ?? '').isNotEmpty;
    return has('neon.supplier.url') && has('neon.supplier.api-key');
  }
}
