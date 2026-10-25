/// Marks a bean for a generated `BuildContext` getter, so widgets anywhere
/// in the tree reach it as `context.basket` instead of passing it through
/// constructors.
///
/// Only marked beans get a getter, so the list stays short even with
/// hundreds of beans. The getter is named after the bean ([name] when
/// given) and is generated next to `springApplication` (in the
/// `.spring.dart` file of the `@SpringBootApplication` library): import
/// that file where the getters are used.
///
/// ```dart
/// @Component()
/// @BuildContextAccess()
/// class Basket { ... }
///
/// // in any widget below SpringApplicationWidget
/// Text('${context.basket.count}');
/// ```
///
/// Spring has no counterpart: a Java bean is injected into a controller or
/// a view, never looked up from a UI tree.
class BuildContextAccess {
  /// Generates a getter named after the bean, or [name].
  const BuildContextAccess({this.name});

  /// The getter's name; the bean's name by default.
  final String? name;
}
