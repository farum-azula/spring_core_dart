import 'package:spring_boot_dart/spring_boot_dart.dart';

/// What a bean of the [DebugBeanGraph] is for, from its stereotype.
///
/// [DebugBeanRoles] decides it, from the definition's annotations (a
/// `@Service` is a [service]) or its `@Bean` method.
enum DebugBeanRole {
  /// A `@Service`.
  service,

  /// A `@Repository`, a data repository.
  repository,

  /// A `@Component` without a narrower stereotype (a
  /// `@ChangeNotifierComponent`, a `@ConfigurationProperties` class), or
  /// an application bean without any.
  component,

  /// A `@Configuration` class.
  configuration,

  /// A bean of a `@Bean` method.
  factoryMethod,

  /// A `@Controller` or `@RestController`.
  controller,

  /// A `SpringStatelessWidget` or `SpringState` that injects beans: not a
  /// bean, a node of the graph all the same.
  widget,

  /// A bean of the framework without a stereotype (a post-processor, an
  /// auto-configured bean), Spring's `ROLE_INFRASTRUCTURE`.
  infrastructure,
}

/// One rule of [DebugBeanRoles]: the role of a definition, or `null` when
/// the rule does not decide it.
abstract interface class DebugBeanRoleRule {
  /// The role of [definition], or `null` to ask the next rule.
  DebugBeanRole? roleOf(BeanDefinition<Object> definition);
}

/// A bean of a `@Bean` method is a [DebugBeanRole.factoryMethod].
final class DebugBeanFactoryMethodRole implements DebugBeanRoleRule {
  /// The rule.
  const DebugBeanFactoryMethodRole();

  @override
  DebugBeanRole? roleOf(BeanDefinition<Object> definition) =>
      definition.factoryMethodName == null ? null : DebugBeanRole.factoryMethod;
}

/// A definition with an annotation of type [A] (or a subtype) has [role].
final class DebugBeanAnnotationRole<A extends Object>
    implements DebugBeanRoleRule {
  /// The rule giving [role] to the definitions annotated with [A].
  const DebugBeanAnnotationRole(this.role);

  /// The role it gives.
  final DebugBeanRole role;

  @override
  DebugBeanRole? roleOf(BeanDefinition<Object> definition) =>
      definition.annotations.any((annotation) => annotation is A) ? role : null;
}

/// The rules that give a bean its [DebugBeanRole], asked in order: the
/// first that decides wins (a chain of responsibility, so a library adds
/// its stereotype by putting a rule before [defaults]).
///
/// ```dart
/// final roles = DebugBeanRoles([
///   const DebugBeanAnnotationRole<UseCase>(DebugBeanRole.service),
///   ...DebugBeanRoles.defaults,
/// ]);
/// ```
final class DebugBeanRoles {
  /// The roles by [rules].
  const DebugBeanRoles([this.rules = defaults]);

  /// The built-in rules: `@Bean` methods, then the stereotypes from the
  /// narrowest to `@Component`.
  static const List<DebugBeanRoleRule> defaults = [
    DebugBeanFactoryMethodRole(),
    DebugBeanAnnotationRole<Configuration>(DebugBeanRole.configuration),
    DebugBeanAnnotationRole<Controller>(DebugBeanRole.controller),
    DebugBeanAnnotationRole<Repository>(DebugBeanRole.repository),
    DebugBeanAnnotationRole<Service>(DebugBeanRole.service),
    DebugBeanAnnotationRole<Component>(DebugBeanRole.component),
  ];

  /// The rules, asked in order.
  final List<DebugBeanRoleRule> rules;

  /// The role of [definition]: the first rule's that decides; without
  /// one, [DebugBeanRole.component] for a bean of the [application],
  /// [DebugBeanRole.infrastructure] for one of the framework.
  DebugBeanRole of(
    BeanDefinition<Object> definition, {
    required bool application,
  }) {
    for (final rule in rules) {
      if (rule.roleOf(definition) case final role?) {
        return role;
      }
    }
    return application ? DebugBeanRole.component : DebugBeanRole.infrastructure;
  }
}
