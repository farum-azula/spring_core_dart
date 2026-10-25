// Conditions: attribute-style condition annotations and @Conditional.
//
// Spring (Java): @Conditional(MyCondition.class), Boot's
// @ConditionalOnProperty.
import 'package:spring_core_dart/spring_core_dart.dart';

/// A condition annotation like Boot's @ConditionalOnProperty.
class ConditionalOnProperty implements Condition {
  const ConditionalOnProperty(this.name, {this.havingValue = 'true'});

  final String name;
  final String havingValue;

  @override
  bool matches(ConditionContext context) =>
      context.environment.getProperty(name) == havingValue;
}

class OnWeekendsOnly implements Condition {
  const OnWeekendsOnly();

  @override
  bool matches(ConditionContext context) => false; // never, for the demo
}

@Service()
@ConditionalOnProperty('feature.recommendations')
class Recommendations {
  List<String> forReader(String reader) => ['Dune', 'Cosmos'];
}

@Service()
@Conditional([OnWeekendsOnly])
class WeekendSale {}
