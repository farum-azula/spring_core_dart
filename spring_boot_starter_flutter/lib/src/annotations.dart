/// Marks a bean that widgets reach through a generated getter on
/// `BuildContext`, such as `context.basket`.
///
/// Use it for the few beans that many widgets need, often in plain
/// `StatelessWidget`s or deep in the tree: a basket, a session, the
/// current user. `context.basket` is shorter than `context.bean<Basket>()`
/// and typed, and nothing has to be passed through constructors. For the
/// beans of one widget, the `beans` record of a `SpringStatelessWidget` is
/// usually the better fit: it is checked at startup and rebuilds the
/// widget when a state bean changes, which a getter does not.
///
/// Only marked beans get a getter, so the list stays short even with
/// hundreds of beans. The getter is named after the bean ([name] when
/// given) and is generated next to `springApplication`, in the
/// `.spring.dart` file of the `@SpringBootApplication` library: import that
/// file where the getters are used.
///
/// ```dart
/// @ChangeNotifierComponent()
/// @BuildContextAccess()
/// class Basket { ... }
///
/// // In a book's tile: put the book into the basket on a tap.
/// IconButton(
///   onPressed: () => context.basket.add(book),
///   icon: const Icon(Icons.add_shopping_cart),
/// );
/// ```
///
/// Spring has no counterpart: a Java bean is injected into a controller or
/// a view, never looked up from a UI tree.
class BuildContextAccess {
  /// Asks for a getter named after the bean, or [name] when given.
  const BuildContextAccess({this.name});

  /// The getter's name, for example `'cart'` for `context.cart`; `null`
  /// (the default) uses the bean's name.
  final String? name;
}
