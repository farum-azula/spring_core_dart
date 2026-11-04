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

/// Marks a loader kind of the app's own, used by `loaders.<name>.kind` in a
/// theme: a class that extends `ThemeLoaderPainter<P>` (it paints a
/// canvas) or `ThemeLoaderWidget<P>` (it builds widgets).
///
/// The generator registers the class under [name] in `ThemeLoaderKinds`
/// and writes `P`, a props class (for `doors`, `DoorsLoaderProps`) from
/// the keys the theme gives the loaders of that kind, so the painter
/// reads typed values. A theme that names a kind nobody registered, or a
/// key the kind does not take, stops the build and the start.
///
/// ```dart
/// @ThemeLoaderKind('doors')
/// class DoorsLoader extends ThemeLoaderPainter<DoorsLoaderProps> {
///   @override
///   void paint(Canvas canvas, Size size, LoaderFrame<DoorsLoaderProps> frame) {
///     final close = frame.phase('close'); // 0..1
///     // ...
///   }
/// }
/// ```
///
/// Spring has no counterpart: a UI-only idea.
class ThemeLoaderKind {
  /// Registers the annotated class as the loader kind [name].
  const ThemeLoaderKind(this.name);

  /// The value of `kind` in the theme, such as `'doors'`.
  final String name;
}
