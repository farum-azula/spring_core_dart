/// The object that stands for a bean whose `@Bean` method (or `create`
/// callback) returned `null`.
///
/// A `@Bean` method declared `T?` may decide at startup that there is no
/// object, for example when a feature is switched off. You rarely meet a
/// `NullBean` yourself: injection and lookups by type just see no bean.
/// The bean exists (its name is registered, `containsBean` is true and
/// `getBeanByName` returns this object), but type lookups and injection
/// treat it as absent: `getBean<T>()` and a required injection point fail
/// with `NoSuchBeanDefinitionException`, `findBean<T>()` and an optional
/// point get `null`, and collections, `getBeansOfType` and providers leave
/// it out. It is not post-processed, initialized or destroyed.
///
/// ```dart
/// // No cache when it is switched off in the configuration.
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
/// Spring (Java), whose `NullBean` follows the same rules:
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

  /// [bean] as [T], or `null` for a [NullBean]. Generated code uses it so
  /// that calling, from another `@Bean` method of a full-mode
  /// `@Configuration`, a `@Bean` method that returned `null` gives `null`.
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
