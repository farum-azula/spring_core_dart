import 'package:spring_core_dart/spring_core_dart.dart';

/// An annotation that is itself a `Condition`, like Spring Boot's
/// `@ConditionalOnProperty`.
class ConditionalOnProperty implements Condition {
  const ConditionalOnProperty(this.name, {this.havingValue = 'true'});

  final String name;
  final String havingValue;

  @override
  bool matches(ConditionContext context) =>
      context.environment.getProperty(name) == havingValue;
}

class NeverMatches implements Condition {
  const NeverMatches();

  @override
  bool matches(ConditionContext context) => false;
}

@Component()
@ConditionalOnProperty('feature.audit')
class AuditFeature {}

@Component()
@Conditional([NeverMatches])
class NeverRegistered {}

abstract interface class Clock {
  String now();
}

/// Used when no other clock is registered.
@Component()
@Fallback()
class SystemClock implements Clock {
  @override
  String now() => 'system';
}

@Component()
@Profile(['test'])
class FixedClock implements Clock {
  @override
  String now() => 'fixed';
}
