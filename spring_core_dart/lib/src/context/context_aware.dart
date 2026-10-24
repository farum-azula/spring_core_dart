import 'package:spring_core_dart/src/beans/aware.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/post_processors.dart';
import 'package:spring_core_dart/src/context/application_context.dart';
import 'package:spring_core_dart/src/context/event/application_listener.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// Receives the application context, like Spring's
/// `ApplicationContextAware`.
///
/// Prefer constructor injection of [ApplicationContext]; this callback is
/// for beans that cannot take it as a parameter.
///
/// ```dart
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
  /// Called after injection, before init callbacks.
  void setApplicationContext(ApplicationContext applicationContext);
}

/// Receives the environment, like Spring's `EnvironmentAware`.
///
/// ```dart
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
  /// Called after injection, before init callbacks.
  void setEnvironment(Environment environment);
}

/// Receives the resource loader, like Spring's `ResourceLoaderAware`.
///
/// ```dart
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
  /// Called after injection with the context (which is a loader).
  void setResourceLoader(ResourceLoader resourceLoader);
}

/// Receives the event publisher, like Spring's
/// `ApplicationEventPublisherAware`.
///
/// ```dart
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
  /// Called after injection with the context (which is a publisher).
  void setApplicationEventPublisher(ApplicationEventPublisher publisher);
}

/// Receives the message source, like Spring's `MessageSourceAware`.
///
/// ```dart
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
  /// Called after injection with the context (which is a message source).
  void setMessageSource(MessageSource messageSource);
}

/// Receives a resolver of `${...}` placeholders and `#{...}` SpEL
/// expressions, like Spring's `EmbeddedValueResolverAware` (its
/// `EmbeddedValueResolver`): placeholders are resolved first, then the
/// result is evaluated by the factory's `BeanExpressionResolver`; a
/// non-string result is converted with `toString()` (`#{null}` gives an
/// empty string).
///
/// ```dart
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
  /// Called after injection with the placeholder and SpEL resolver.
  void setEmbeddedValueResolver(StringValueResolver resolver);
}

/// Calls the context aware interfaces, like Spring's
/// `ApplicationContextAwareProcessor` (same order).
///
/// The context registers it automatically during refresh; you only need it
/// when building a context-like container yourself.
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
  /// Creates a processor that hands out [context].
  ApplicationContextAwareProcessor(this.context);

  /// The context passed to the `*Aware` callbacks.
  final ConfigurableApplicationContext context;

  /// Invokes every `*Aware` callback [bean] implements, then returns it.
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
