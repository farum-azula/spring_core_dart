/// Base class of container errors, like Spring's `BeansException`.
///
/// ```dart
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

  /// Human-readable description of the problem.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message'
      '${cause == null ? '' : '; nested exception is $cause'}';
}

/// No bean matches a requested type, qualifier or name, like Spring's
/// `NoSuchBeanDefinitionException`.
///
/// ```dart
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
  /// bean whose dependency failed.
  NoSuchBeanDefinitionException(this.type, {this.qualifier, this.requiredBy})
    : beanName = null,
      super(
        'No bean of type $type'
        '${qualifier == null ? '' : " with qualifier '$qualifier'"}'
        '${requiredBy == null ? '' : ", required by bean '$requiredBy'"}.',
      );

  /// No bean named [beanName]; [requiredBy] names the bean that asked.
  NoSuchBeanDefinitionException.named(String this.beanName, {this.requiredBy})
    : type = null,
      qualifier = null,
      super(
        "No bean named '$beanName'"
        '${requiredBy == null ? '' : ", required by bean '$requiredBy'"}.',
      );

  /// The requested type, or `null` for a lookup by name.
  final Type? type;

  /// The requested qualifier, if any.
  final String? qualifier;

  /// The requested bean name, or `null` for a lookup by type.
  final String? beanName;

  /// The bean being created when the lookup failed, if any.
  final String? requiredBy;
}

/// Several beans match a requested type and none wins (no single
/// `@Primary`, not resolvable by fallback or parameter name), like Spring's
/// `NoUniqueBeanDefinitionException`.
///
/// ```dart
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
  /// Several [candidates] match [type].
  NoUniqueBeanDefinitionException(
    Type super.type,
    this.candidates, {
    super.qualifier,
    super.requiredBy,
  });

  /// Names of the matching beans (only the primary ones when several are
  /// primary).
  final List<String> candidates;

  @override
  String get message =>
      '${candidates.length} beans of type $type match'
      '${qualifier == null ? '' : " qualifier '$qualifier'"}'
      '${requiredBy == null ? '' : " (required by bean '$requiredBy')"}: '
      '${candidates.join(', ')}. '
      'Mark one with @Primary or select one with @Qualifier.';
}

/// A dependency of a bean cannot be satisfied, like Spring's
/// `UnsatisfiedDependencyException`.
///
/// Thrown by `validateBeanGraph`, e.g. when a required `@Value`
/// placeholder has no value.
///
/// ```dart
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
class UnsatisfiedDependencyException extends BeansException {
  /// [beanName]'s [dependency] failed for [reason].
  UnsatisfiedDependencyException(
    this.beanName,
    this.dependency,
    String reason, {
    super.cause,
  }) : super(
         "Bean '$beanName' has an unsatisfied dependency $dependency: $reason",
       );

  /// The bean whose dependency failed.
  final String beanName;

  /// Description of the failed dependency (e.g. `@Value("${port}")`).
  final String dependency;
}

/// Two definitions use the same name (or an alias clashes), like Spring's
/// `BeanDefinitionOverrideException`.
///
/// Set `DefaultListableBeanFactory.allowBeanDefinitionOverriding` to
/// replace definitions instead.
///
/// ```dart
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
class BeanDefinitionOverrideException extends BeansException {
  /// [name] is taken; [source] describes what tried to register it.
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

/// Definitions cannot be changed (configuration frozen) or are invalid,
/// like Spring's `BeanDefinitionStoreException`.
///
/// ```dart
/// factory.freezeConfiguration();
/// factory.registerBeanDefinition(def); // throws
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring throws it for invalid definitions, e.g. unreadable XML:
/// new XmlBeanDefinitionReader(factory).loadBeanDefinitions("bad.xml");
/// ```
class BeanDefinitionStoreException extends BeansException {
  /// Creates the exception with [message].
  const BeanDefinitionStoreException(super.message);
}

/// Beans depend on each other in a cycle, like Spring's
/// `BeanCurrentlyInCreationException`.
///
/// Unlike Spring, cycles are always rejected (there are no early
/// references); `validateBeanGraph` reports them at refresh before any bean
/// is created. Break a cycle with `ObjectProvider<T>`.
///
/// ```dart
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
class BeanCurrentlyInCreationException extends BeansException {
  /// Reports the bean names forming [cycle].
  BeanCurrentlyInCreationException(this.cycle)
    : super('Circular dependency: ${cycle.join(' -> ')}.');

  /// Bean names forming the cycle; the first and last are the same bean.
  final List<String> cycle;
}

/// A constructor, factory method, injection or init callback threw, like
/// Spring's `BeanCreationException`.
///
/// Errors from nested beans are wrapped once per level, so [cause] chains
/// lead to the bean that actually failed.
///
/// ```dart
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
  /// Creating [beanName] failed with [cause].
  BeanCreationException(this.beanName, Object cause, this.causeStackTrace)
    : super("Error creating bean '$beanName'", cause: cause);

  /// The bean whose creation failed.
  final String beanName;

  /// Stack trace of [cause].
  final StackTrace causeStackTrace;
}

/// `&name` was used for a bean that is not a `FactoryBean`, like Spring's
/// `BeanIsNotAFactoryException`.
///
/// ```dart
/// factory.getBeanByName('&english'); // throws: English is no FactoryBean
/// ```
///
/// Spring (Java):
/// ```java
/// factory.getBean("&english"); // BeanIsNotAFactoryException
/// ```
class BeanIsNotAFactoryException extends BeansException {
  /// [beanName] is not a `FactoryBean`.
  BeanIsNotAFactoryException(this.beanName)
    : super("Bean '$beanName' is not a FactoryBean.");

  /// The bean that was dereferenced with `&`.
  final String beanName;
}

/// The bean exists but is not of the requested type, like Spring's
/// `BeanNotOfRequiredTypeException`.
///
/// Typically a post-processor replaced the bean with a wrapper that does
/// not implement the requested class.
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

  /// The runtime type of the bean.
  final Type actualType;
}

/// A bean uses a scope that is not registered, like Spring's
/// "No Scope registered for scope name" `IllegalStateException`.
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
