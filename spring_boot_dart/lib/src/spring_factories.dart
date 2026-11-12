import 'package:spring_core_dart/spring_core_dart.dart';

/// What the starters of an application add to it before its beans exist:
/// the constants of every `AutoConfigurationModule.factories`, found by
/// their type.
///
/// Some things must work while the environment is prepared or a splash
/// shows, when no bean exists yet (the design a Flutter theme is read
/// with). A starter lists them on its module, and the code that needs them
/// asks for a type. The application has it as
/// `SpringApplication.factories`, and the context as the
/// `springFactories` bean.
///
/// ```dart
/// // In a listener of ApplicationEnvironmentPreparedEvent.
/// final designs = event.springApplication.factories.load<ThemeDesign>();
/// ```
///
/// Spring (Java):
/// ```java
/// List<ThemeDesign> designs =
///     SpringFactoriesLoader.loadFactories(ThemeDesign.class, classLoader);
/// ```
///
/// Spring finds them in `META-INF/spring.factories` on the class path;
/// here the generator copies them from the modules into the generated
/// application.
final class SpringFactories {
  /// The given factories, in the order of their modules.
  const SpringFactories([this._all = const []]);

  final List<Object> _all;

  /// Every factory of type [T]: by `Ordered`, else in the order of the
  /// modules. Empty when no starter has one.
  List<T> load<T extends Object>() => OrderComparator.sort<T>([
    for (final factory in _all)
      if (factory is T) factory,
  ]);
}
