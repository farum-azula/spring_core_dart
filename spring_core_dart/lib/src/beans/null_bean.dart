/// The instance of a bean whose `@Bean` method (or `create`) returned
/// `null`, like Spring's `NullBean`.
///
/// The bean exists (its name is registered, `containsBean` is true and
/// `getBeanByName` returns this object), but type lookups and injection
/// treat it as absent: `getBean<T>()` and a required injection point fail
/// with `NoSuchBeanDefinitionException`, `findBean<T>()` and an optional
/// point get `null`, and collections, `getBeansOfType` and providers leave
/// it out. It is not post-processed, initialized or destroyed.
///
/// ```dart
/// @Configuration()
/// class AppConfig {
///   @Bean()
///   Cache? cache(Environment env) =>
///       env.getProperty('cache.enabled') == 'true' ? Cache() : null;
/// }
///
/// context.findBean<Cache>(); // null when disabled
/// context.getBeanByName('cache') is NullBean; // true when disabled
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// Cache cache(Environment env) {
///   return env.getProperty("cache.enabled", Boolean.class, false)
///       ? new Cache() : null;
/// }
/// ```
final class NullBean {
  /// Creates the placeholder of one null bean (each null bean has its own,
  /// as in Spring).
  NullBean();

  /// [bean] as [T], or `null` for a [NullBean]: what an inter-bean call of
  /// a full-mode `@Bean` method that returned `null` gets (used by
  /// generated code).
  ///
  /// ```dart
  /// final Cache? cache = NullBean.orNull<Cache>(
  ///   beanFactory.getBeanByName('cache'),
  /// );
  /// ```
  static T? orNull<T extends Object>(Object bean) =>
      bean is NullBean ? null : bean as T;

  @override
  String toString() => 'null';
}
