import 'package:spring_core_dart/src/beans/factory_bean.dart';

/// The common supertype of the errors the container throws: a missing or
/// ambiguous bean, a failed creation, a clashing name, a bad property path.
///
/// Catch it to handle any container error in one place, for example to
/// print a readable message when startup fails. Each subclass carries the
/// details of its case; [message] always describes the problem, and
/// [cause] (with [rootCause]) leads to the error behind it.
///
/// ```dart
/// // main: report what went wrong with the beans, then stop.
/// try {
///   context.getBean<Mailer>();
/// } on BeansException catch (e) {
///   print(e.message);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   context.getBean(Mailer.class);
/// } catch (BeansException e) {
///   System.out.println(e.getMessage());
/// }
/// ```
abstract class BeansException implements Exception {
  /// Creates an exception with [message] and an optional [cause].
  const BeansException(this.message, {this.cause});

  /// A human-readable description of the problem.
  final String message;

  /// The error that caused this one, if any: what a constructor threw, or
  /// the container error of a nested bean.
  final Object? cause;

  /// The innermost cause: [cause] followed through nested container
  /// errors, or `null` without a cause. Usually the error that really went
  /// wrong. Spring: `getRootCause()`.
  ///
  /// ```dart
  /// } on BeanCreationException catch (e) {
  ///   print(e.rootCause); // e.g. the StateError a constructor threw
  /// }
  /// ```
  Object? get rootCause {
    Object? root;
    for (var current = cause; current != null;) {
      root = current;
      current = current is BeansException ? current.cause : null;
    }
    return root;
  }

  /// [rootCause], or this exception when it has no cause. Spring:
  /// `getMostSpecificCause()`.
  Object get mostSpecificCause => rootCause ?? this;

  @override
  String toString() =>
      '$runtimeType: $message'
      '${cause == null ? '' : '; nested exception is $cause'}';
}

/// The error thrown when no bean matches a requested type, qualifier or
/// name.
///
/// You usually see it because a bean was never registered: its class is
/// outside the scanned folders, a condition or profile excluded it, or a
/// qualifier is misspelled. Catch it around a lookup that may fail, or use
/// `findBean` (which returns `null`) instead.
///
/// ```dart
/// // The 'smtp' mailer may not be configured.
/// try {
///   factory.getBean<Mailer>(qualifier: 'smtp');
/// } on NoSuchBeanDefinitionException catch (e) {
///   print('${e.type} / ${e.qualifier} missing'); // Mailer / smtp missing
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   BeanFactoryAnnotationUtils.qualifiedBeanOfType(
///       factory, Mailer.class, "smtp");
/// } catch (NoSuchBeanDefinitionException e) {
///   System.out.println(e.getBeanType() + " missing");
/// }
/// ```
class NoSuchBeanDefinitionException extends BeansException {
  /// No bean of [type] (with [qualifier], if given); [requiredBy] names the
  /// bean being created when the lookup failed, if any.
  NoSuchBeanDefinitionException(this.type, {this.qualifier, this.requiredBy})
    : beanName = null,
      super(
        'No bean of type $type'
        '${qualifier == null ? '' : " with qualifier '$qualifier'"}'
        '${requiredBy == null ? '' : ", required by bean '$requiredBy'"}.',
      );

  /// No bean named [beanName]; [requiredBy] names the bean being created
  /// when the lookup failed, if any.
  NoSuchBeanDefinitionException.named(String this.beanName, {this.requiredBy})
    : type = null,
      qualifier = null,
      super(
        "No bean named '$beanName'"
        '${requiredBy == null ? '' : ", required by bean '$requiredBy'"}.',
      );

  /// The requested type, or `null` for a lookup by name.
  final Type? type;

  /// The requested qualifier, if any (lookups by type only).
  final String? qualifier;

  /// The requested bean name, or `null` for a lookup by type.
  final String? beanName;

  /// The bean being created when the lookup failed, if any.
  final String? requiredBy;
}

/// The error thrown when several beans match a requested type and none of
/// them wins.
///
/// A winner is the single `@Primary` bean, the only one not marked
/// `@Fallback`, the one named like the parameter or the qualifier, or the
/// one with the lowest jakarta `@Priority`. Fix it by marking one bean
/// `@Primary()`, by selecting one with `@Qualifier`, or by injecting a
/// `List<T>` when you want them all. It is a
/// [NoSuchBeanDefinitionException], so code that catches "no bean" also
/// catches "no single bean".
///
/// ```dart
/// // Two Greeter beans and no @Primary.
/// try {
///   factory.getBean<Greeter>();
/// } on NoUniqueBeanDefinitionException catch (e) {
///   print(e.candidates); // [english, french]
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   factory.getBean(Greeter.class);
/// } catch (NoUniqueBeanDefinitionException e) {
///   System.out.println(e.getBeanNamesFound());
/// }
/// ```
class NoUniqueBeanDefinitionException extends NoSuchBeanDefinitionException {
  /// The beans named in [candidates] all match [type]; [samePriority] is
  /// set when they tie on `@Priority`.
  NoUniqueBeanDefinitionException(
    Type super.type,
    this.candidates, {
    super.qualifier,
    super.requiredBy,
    this.samePriority,
  });

  /// The names of the matching beans (only the primary ones when several
  /// are primary).
  final List<String> candidates;

  /// The `@Priority` value several candidates share as the highest, when
  /// that is why none could be chosen.
  final int? samePriority;

  @override
  String get message => samePriority != null
      ? 'Multiple beans of type $type found with the same highest priority '
            '($samePriority)'
            '${requiredBy == null ? '' : " (required by bean '$requiredBy')"}'
            ' among candidates: ${candidates.join(', ')}.'
      : '${candidates.length} beans of type $type match'
            '${qualifier == null ? '' : " qualifier '$qualifier'"}'
            '${requiredBy == null ? '' : " (required by bean '$requiredBy')"}: '
            '${candidates.join(', ')}. '
            'Mark one with @Primary or select one with @Qualifier.';
}

/// The error thrown when an injection point of a bean cannot be filled:
/// the bean, its injection point and the reason are in the message.
///
/// This is the usual startup error of a misconfigured application; it is a
/// [BeanCreationException]. It is thrown by `validateBeanGraph` (a declared
/// dependency has no bean or several candidates, a required `@Value`
/// placeholder has no value) and when resolving an injection point fails
/// while the bean is created:
/// [cause] is the lookup error (a missing or ambiguous bean, or the
/// failure of the dependency's own creation), so nested exceptions show
/// the chain of beans and injection points.
///
/// ```dart
/// // The `${smtp}` property is missing from the configuration.
/// try {
///   context.refresh();
/// } on UnsatisfiedDependencyException catch (e) {
///   print('${e.beanName}: ${e.dependency}'); // mailer: @Value("${smtp}")
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   context.refresh();
/// } catch (UnsatisfiedDependencyException e) {
///   System.out.println(e.getBeanName() + ": " + e.getInjectionPoint());
/// }
/// ```
class UnsatisfiedDependencyException extends BeanCreationException {
  /// The injection point [dependency] of [beanName] failed for [reason].
  UnsatisfiedDependencyException(
    String beanName,
    this.dependency,
    String reason, {
    super.cause,
    super.causeStackTrace,
  }) : super.withMessage(
         beanName,
         "Bean '$beanName' has an unsatisfied dependency $dependency: $reason",
       );

  /// A description of the failed injection point (e.g.
  /// `@Value("${port}")` or `Greeter 'delegate'`).
  final String dependency;
}

/// The error thrown when a bean name or alias is registered while the name
/// is already taken.
///
/// Two beans got the same name, usually two classes with the same name in
/// different folders, or a `@Bean` method named like a class. Rename one
/// (`@Component('otherName')`), or set
/// `DefaultListableBeanFactory.allowBeanDefinitionOverriding` when
/// replacing a bean on purpose. It is a [BeanDefinitionStoreException].
///
/// ```dart
/// // Registering the same name twice.
/// BeanDefinition<English> english() =>
///     BeanDefinition<English>(name: 'english', create: (_) => English());
///
/// factory.registerBeanDefinition(english());
/// factory.registerBeanDefinition(english()); // throws
/// ```
///
/// Spring (Java):
/// ```java
/// factory.setAllowBeanDefinitionOverriding(false);
/// factory.registerBeanDefinition("english", def);
/// factory.registerBeanDefinition("english", def); // throws
/// ```
class BeanDefinitionOverrideException extends BeanDefinitionStoreException {
  /// [name] is taken; [source] describes the registration that was
  /// rejected.
  BeanDefinitionOverrideException(this.name, this.source)
    : super(
        "Bean name '$name' is already in use"
        '${source == null ? '' : ' (registering $source)'}.',
      );

  /// The clashing bean name or alias.
  final String name;

  /// The source of the rejected registration, if known.
  final String? source;
}

/// The error thrown when a bean definition cannot be registered: an
/// invalid name, or a name that is taken.
///
/// An empty name or one starting with `&` is invalid, and so is a name
/// already used as an alias of a bean that no longer exists. A taken name
/// is
/// reported by the subclass [BeanDefinitionOverrideException].
///
/// ```dart
/// // `&` is reserved for asking for a factory bean itself.
/// factory.registerBeanDefinition(
///   BeanDefinition<Clock>(name: '&clock', create: (_) => Clock()),
/// ); // throws: invalid bean name
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring throws it for invalid definitions, e.g. unreadable XML:
/// new XmlBeanDefinitionReader(factory).loadBeanDefinitions("bad.xml");
/// ```
class BeanDefinitionStoreException extends BeansException {
  /// The registration failed as [message] describes.
  const BeanDefinitionStoreException(super.message);
}

/// The error thrown when beans depend on each other in a cycle, so none of
/// them can be created first.
///
/// [cycle] lists the beans in order. It is a [BeanCreationException].
///
/// Unlike Spring, cycles are always rejected (there are no early
/// references); `validateBeanGraph` reports them at refresh before any bean
/// is created. A cycle found while beans are being created is wrapped,
/// like any creation error, in the exceptions of the beans being created
/// (see [BeansException.rootCause]). Break a cycle with `@Lazy()` or
/// `ObjectProvider<T>`.
///
/// ```dart
/// // Bean a injects b and b injects a.
/// try {
///   context.refresh();
/// } on BeanCurrentlyInCreationException catch (e) {
///   print(e.cycle); // [a, b, a]
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   context.refresh();
/// } catch (BeanCurrentlyInCreationException e) {
///   System.out.println(e.getBeanName());
/// }
/// ```
class BeanCurrentlyInCreationException extends BeanCreationException {
  /// The beans named in [cycle] depend on each other in a cycle.
  BeanCurrentlyInCreationException(this.cycle)
    : super.withMessage(
        cycle.last,
        'Circular dependency: ${cycle.join(' -> ')}.',
      );

  /// The product of the `FactoryBean` named `cycle.first` was requested
  /// again while its `getObject()` was creating it.
  BeanCurrentlyInCreationException.factoryProduct(this.cycle)
    : super.withMessage(
        cycle.last,
        'Circular dependency: ${cycle.join(' -> ')}: the product of '
        "FactoryBean '${cycle.first}' was requested while its getObject() "
        'was creating it.',
      );

  /// Bean names forming the cycle; the first and last are the same bean
  /// ([beanName], the bean requested again).
  final List<String> cycle;
}

/// The error thrown when creating a bean failed: its constructor or
/// `@Bean` method, its injection or an init callback threw.
///
/// [beanName] is the bean being created and [cause] what went wrong.
/// Errors of nested beans are wrapped once per level, so the chain of
/// causes leads to the bean that actually failed; [rootCause] is the
/// original error.
///
/// ```dart
/// // Print which bean failed and why.
/// try {
///   factory.getBean<Mailer>();
/// } on BeanCreationException catch (e) {
///   print('${e.beanName}: ${e.cause}\n${e.causeStackTrace}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   factory.getBean(Mailer.class);
/// } catch (BeanCreationException e) {
///   System.out.println(e.getBeanName() + ": " + e.getMostSpecificCause());
/// }
/// ```
class BeanCreationException extends BeansException {
  /// Creating [beanName] failed with [cause], thrown at [causeStackTrace].
  BeanCreationException(this.beanName, Object cause, this.causeStackTrace)
    : super("Error creating bean '$beanName'", cause: cause);

  /// Creating [beanName] failed as [message] describes; used by the
  /// subclasses.
  BeanCreationException.withMessage(
    this.beanName,
    super.message, {
    super.cause,
    StackTrace? causeStackTrace,
  }) : causeStackTrace = causeStackTrace ?? StackTrace.empty;

  /// The bean whose creation failed.
  final String beanName;

  /// The stack trace of [cause] (empty without a cause).
  final StackTrace causeStackTrace;
}

/// The error thrown when a singleton that does not exist yet is requested
/// while the factory destroys its singletons.
///
/// The container is shutting down, so it refuses to create new beans. It
/// usually comes from a destroy callback that looks up a bean: look the
/// bean up earlier, or inject it so it is destroyed after the bean that
/// uses it.
///
/// ```dart
/// // A destroy callback that looks up a bean not created yet:
/// preDestroy: (bean) => factory.getBean<Audit>(), // throws
/// ```
///
/// Spring (Java):
/// ```java
/// @PreDestroy void close() { beanFactory.getBean(Audit.class); } // throws
/// ```
class BeanCreationNotAllowedException extends BeanCreationException {
  /// Creating the singleton [beanName] was refused during shutdown.
  BeanCreationNotAllowedException(String beanName)
    : super.withMessage(
        beanName,
        "Singleton bean '$beanName' cannot be created while the singletons "
        'of this factory are being destroyed (do not request a bean from a '
        'BeanFactory in a destroy method).',
      );
}

/// The error thrown when `&name` asks for the factory of a bean that is
/// not a `FactoryBean`.
///
/// `&` before a bean name means "the factory itself, not its product", so
/// it only works for factory beans. It is a
/// [BeanNotOfRequiredTypeException] whose required type is `FactoryBean`.
///
/// ```dart
/// factory.getBeanByName('&english'); // throws: English is no FactoryBean
/// ```
///
/// Spring (Java):
/// ```java
/// factory.getBean("&english"); // BeanIsNotAFactoryException
/// ```
class BeanIsNotAFactoryException extends BeanNotOfRequiredTypeException {
  /// [beanName], dereferenced with `&`, is an [actualType], not a
  /// `FactoryBean`.
  BeanIsNotAFactoryException(String beanName, Type actualType)
    : super(beanName, FactoryBean, actualType);
}

/// The error thrown when a bean exists but is not of the requested type.
///
/// Typically a post-processor replaced the bean with a wrapper that does
/// not implement the requested class, or a lookup by name asked for the
/// wrong type.
///
/// ```dart
/// try {
///   factory.getBean<English>();
/// } on BeanNotOfRequiredTypeException catch (e) {
///   print('${e.requiredType} vs ${e.actualType}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   factory.getBean("english", English.class);
/// } catch (BeanNotOfRequiredTypeException e) {
///   System.out.println(e.getRequiredType() + " vs " + e.getActualType());
/// }
/// ```
class BeanNotOfRequiredTypeException extends BeansException {
  /// [beanName] is an [actualType], not a [requiredType].
  BeanNotOfRequiredTypeException(
    this.beanName,
    this.requiredType,
    this.actualType,
  ) : super(
        "Bean '$beanName' is expected to be of type $requiredType but was "
        'actually of type $actualType.',
      );

  /// The bean (or resolvable dependency) that was looked up.
  final String beanName;

  /// The type that was requested.
  final Type requiredType;

  /// The runtime type of the object found.
  final Type actualType;
}

/// The error thrown when a bean of a custom scope is looked up and no
/// scope of that name is registered.
///
/// Register the scope (`registerScope`) before the first lookup of such a
/// bean. Spring throws an `IllegalStateException` ("No Scope registered
/// for scope name") here.
///
/// ```dart
/// // @Scope('screen') bean, but no registerScope('screen', ...) call:
/// factory.getBean<CartState>(); // throws ScopeNotRegisteredException
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring throws IllegalStateException in the same situation:
/// factory.getBean(CartState.class);
/// ```
class ScopeNotRegisteredException extends BeansException {
  /// [beanName] uses the unknown scope [scopeName].
  ScopeNotRegisteredException(this.scopeName, this.beanName)
    : super(
        "No scope registered for scope name '$scopeName' (bean '$beanName').",
      );

  /// The unknown scope name.
  final String scopeName;

  /// The bean declared in that scope.
  final String beanName;
}

/// The error thrown when a bean is looked up while its scope is not
/// active, for example a screen-scoped bean while no screen is open.
///
/// The `CustomScope` signals this by throwing a `StateError` from `get`.
/// A singleton that needs such a bean should get it through a scoped proxy
/// or an `ObjectProvider`, whose `getIfAvailable`, `getIfUnique` and
/// `ifAvailable` treat an inactive scope like a missing bean. It is a
/// [BeanCreationException].
///
/// ```dart
/// // A scope that is only active while a screen is open.
/// class ScreenScope implements CustomScope {
///   @override
///   Object get(String name, Object Function() objectFactory) =>
///       _current?.get(name, objectFactory) ??
///       (throw StateError('No screen is open'));
///   ...
/// }
/// cartProvider.getIfAvailable(); // null while no screen is open
/// ```
///
/// Spring (Java):
/// ```java
/// cartProvider.getIfAvailable(); // null outside the scope
/// ```
class ScopeNotActiveException extends BeanCreationException {
  /// The bean [beanName] of scope [scopeName] cannot be reached now;
  /// [cause] is the scope's `StateError`.
  ScopeNotActiveException(
    String beanName,
    this.scopeName,
    Object cause, [
    StackTrace? causeStackTrace,
  ]) : super.withMessage(
         beanName,
         "Scope '$scopeName' is not active for the current context; consider "
         'defining a scoped proxy for this bean if you intend to refer to it '
         'from a singleton',
         cause: cause,
         causeStackTrace: causeStackTrace,
       );

  /// The inactive scope.
  final String scopeName;
}
