import 'package:spring_core_dart/src/beans/aware.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/context/application_context.dart';
import 'package:spring_core_dart/src/context/event/application_listener.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// Implemented by a bean that wants the application context handed to it
/// through a method call.
///
/// The usual way is to inject [ApplicationContext] through the
/// constructor. This callback is for beans that cannot take it as a
/// parameter, for example a base class shared by many beans whose
/// constructors you do not want to change. The context calls
/// [setApplicationContext] once, after the bean's dependencies are
/// injected and before its init callbacks (`@PostConstruct`).
///
/// ```dart
/// // Looks beans up by name at runtime, e.g. a handler chosen by a
/// // message type.
/// @Component()
/// class BeanLocator implements ApplicationContextAware {
///   late ApplicationContext context;
///
///   @override
///   void setApplicationContext(ApplicationContext applicationContext) =>
///       context = applicationContext;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class BeanLocator implements ApplicationContextAware {
///   public void setApplicationContext(ApplicationContext ctx) { ... }
/// }
/// ```
abstract interface class ApplicationContextAware implements Aware {
  /// Receives the context that created the bean; called once, after
  /// injection and before the init callbacks.
  void setApplicationContext(ApplicationContext applicationContext);
}

/// Implemented by an object that wants the configuration (properties and
/// profiles) handed to it through a method call.
///
/// A bean can simply inject `Environment`. This callback matters for
/// objects the container creates but does not inject: an `ImportSelector`
/// or a registrar, which decide from the configuration which beans to add.
/// The context calls [setEnvironment] after injection and before the init
/// callbacks; for a selector or registrar, before it runs.
///
/// ```dart
/// // Reads feature switches from the configuration.
/// @Component()
/// class FeatureFlags implements EnvironmentAware {
///   late Environment env;
///
///   @override
///   void setEnvironment(Environment environment) => env = environment;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class FeatureFlags implements EnvironmentAware {
///   public void setEnvironment(Environment environment) { ... }
/// }
/// ```
abstract interface class EnvironmentAware implements Aware {
  /// Receives the context's environment; called once, after injection and
  /// before the init callbacks.
  void setEnvironment(Environment environment);
}

/// Implemented by an object that wants the context's resource loader (to
/// read files such as `classpath:templates/mail.txt`) handed to it through
/// a method call.
///
/// A bean can simply inject `ResourceLoader`, or a single file with
/// `@Value('classpath:...') Resource`. This callback matters for an
/// `ImportSelector` or a registrar, which are not injected. The loader is
/// the context itself, so custom protocols added to it work.
///
/// ```dart
/// // Loads mail templates by name when they are needed.
/// @Component()
/// class Templates implements ResourceLoaderAware {
///   late ResourceLoader loader;
///
///   @override
///   void setResourceLoader(ResourceLoader resourceLoader) =>
///       loader = resourceLoader;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Templates implements ResourceLoaderAware {
///   public void setResourceLoader(ResourceLoader resourceLoader) { ... }
/// }
/// ```
abstract interface class ResourceLoaderAware implements Aware {
  /// Receives the context, which is the resource loader; called once,
  /// after injection and before the init callbacks.
  void setResourceLoader(ResourceLoader resourceLoader);
}

/// Implemented by a bean that wants the event publisher handed to it
/// through a method call.
///
/// The usual way is to inject `ApplicationEventPublisher` through the
/// constructor; this callback exists for beans that cannot.
///
/// ```dart
/// // Publishes an event for every order it handles.
/// @Service()
/// class Orders implements ApplicationEventPublisherAware {
///   late ApplicationEventPublisher events;
///
///   @override
///   void setApplicationEventPublisher(ApplicationEventPublisher p) =>
///       events = p;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Orders implements ApplicationEventPublisherAware {
///   public void setApplicationEventPublisher(
///       ApplicationEventPublisher publisher) { ... }
/// }
/// ```
abstract interface class ApplicationEventPublisherAware implements Aware {
  /// Receives the context, which is the event publisher; called once,
  /// after injection and before the init callbacks.
  void setApplicationEventPublisher(ApplicationEventPublisher publisher);
}

/// Implemented by a bean that wants the translated messages handed to it
/// through a method call.
///
/// The usual way is to inject `MessageSource` through the constructor;
/// this callback exists for beans that cannot. What it receives is the
/// context, which looks messages up in the `messageSource` bean.
///
/// ```dart
/// // Translates labels for the user's locale.
/// @Component()
/// class Labels implements MessageSourceAware {
///   late MessageSource messages;
///
///   @override
///   void setMessageSource(MessageSource messageSource) =>
///       messages = messageSource;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Labels implements MessageSourceAware {
///   public void setMessageSource(MessageSource messageSource) { ... }
/// }
/// ```
abstract interface class MessageSourceAware implements Aware {
  /// Receives the context, which is a message source; called once, after
  /// injection and before the init callbacks.
  void setMessageSource(MessageSource messageSource);
}

/// Implemented by a bean that resolves `@Value`-style texts itself: it
/// receives a function that resolves `${...}` placeholders and `#{...}`
/// expressions.
///
/// Use it when the keys to resolve are only known at runtime, such as a
/// template that names properties. `@Value` covers the fixed cases. The
/// function resolves placeholders first, then evaluates the result with
/// the factory's `BeanExpressionResolver` (SpEL); a non-string result is
/// converted with `toString()`, and `#{null}` gives an empty string (as
/// Spring's `EmbeddedValueResolver`).
///
/// ```dart
/// // Paths built from properties, with a default.
/// @Component()
/// class Paths implements EmbeddedValueResolverAware {
///   late String home;
///   late String cache;
///
///   @override
///   void setEmbeddedValueResolver(StringValueResolver resolver) {
///     home = resolver(r'${app.home:/tmp}');
///     cache = resolver(r"#{'${app.home:/tmp}' + '/cache'}");
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Paths implements EmbeddedValueResolverAware {
///   public void setEmbeddedValueResolver(StringValueResolver resolver) {
///     home = resolver.resolveStringValue("${app.home:/tmp}");
///     cache = resolver.resolveStringValue("#{'${app.home:/tmp}' + '/cache'}");
///   }
/// }
/// ```
abstract interface class EmbeddedValueResolverAware implements Aware {
  /// Receives the placeholder and SpEL resolver; called once, after
  /// injection and before the init callbacks.
  void setEmbeddedValueResolver(StringValueResolver resolver);
}

/// The bean post-processor that calls the `*Aware` callbacks of this
/// library on each bean, with the context's objects.
///
/// Every context registers it during the refresh, so beans that implement
/// `EnvironmentAware`, `ApplicationContextAware` and the like get their
/// callbacks. You only need it when you build a container of your own.
/// The callbacks run in Spring's order: environment, value resolver,
/// resource loader, event publisher, message source, application context.
///
/// ```dart
/// context.beanFactory.addBeanPostProcessor(
///   ApplicationContextAwareProcessor(context),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// // Registered internally by AbstractApplicationContext.prepareBeanFactory:
/// beanFactory.addBeanPostProcessor(
///     new ApplicationContextAwareProcessor(this));
/// ```
final class ApplicationContextAwareProcessor extends BeanPostProcessor {
  /// Creates a processor that hands [context] (and its environment) to
  /// the beans.
  ApplicationContextAwareProcessor(this.context);

  /// The context passed to the `*Aware` callbacks; it is also the
  /// resource loader, event publisher and message source they receive.
  final ConfigurableApplicationContext context;

  /// Calls every `*Aware` callback [bean] implements, then returns the
  /// bean unchanged. Runs before the bean's init callbacks.
  @override
  Object postProcessBeforeInitialization(Object bean, String beanName) {
    // Same order as Spring: environment, value resolver, resource loader,
    // event publisher, message source, application context.
    if (bean is EnvironmentAware) {
      bean.setEnvironment(context.environment);
    }
    if (bean is EmbeddedValueResolverAware) {
      bean.setEmbeddedValueResolver(_resolveEmbeddedValue);
    }
    if (bean is ResourceLoaderAware) {
      bean.setResourceLoader(context);
    }
    if (bean is ApplicationEventPublisherAware) {
      bean.setApplicationEventPublisher(context);
    }
    if (bean is MessageSourceAware) {
      bean.setMessageSource(context);
    }
    if (bean is ApplicationContextAware) {
      bean.setApplicationContext(context);
    }
    return bean;
  }

  // Spring's EmbeddedValueResolver: `${...}` first, then `#{...}`.
  String _resolveEmbeddedValue(String value) {
    final factory = context.beanFactory;
    final resolved = factory.resolveEmbeddedValue(value);
    final expressions = factory.beanExpressionResolver;
    if (expressions == null) {
      return resolved;
    }
    return expressions.evaluate(resolved, factory)?.toString() ?? '';
  }
}
