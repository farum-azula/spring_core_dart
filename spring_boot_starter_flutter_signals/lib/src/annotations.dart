import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A field of a component whose changes are followed: what read it (a
/// widget's `build`, a [Computed] value, an [Effect] method) is told when
/// it is assigned.
///
/// ```dart
/// @Component()
/// class Basket {
///   @Signal()
///   String? coupon;
///
///   @Signal()
///   List<Book> items = [];
///
///   void apply(String code) => coupon = code;   // an assignment is a change
/// }
/// ```
///
/// The field stays a plain field: no wrapper type and no `.value`. It must
/// be public and not `final` (the bean's generated proxy overrides it, and
/// a private member cannot be overridden from another library). A change
/// is an assignment; for a `List`, `Set`, `Map` or `Queue` a change in
/// place (`items.add(book)`) is one too.
///
/// On a field of a component only: a class the container makes
/// (`@Component`, `@Service`, ...), not a `@Configuration` class.
@ProxyTargetClass()
class Signal {
  /// Marks the field; with [hidden], its value is left out of the debug
  /// tab and the log.
  const Signal({this.hidden = false});

  /// Whether the value is kept out of the debug panel's State tab and of
  /// the log (a token, a password): only how often it changed is shown.
  final bool hidden;
}

/// A value made from other state, kept until what it read changes.
///
/// ```dart
/// @Computed()
/// double get total => items.fold(0.0, (sum, book) => sum + book.price);
/// ```
///
/// On a getter, or a method without parameters. It is computed when first
/// read and again only after a [Signal] field or another computed value it
/// read has changed.
///
/// A getter that returns a `Future` or a `Stream` is asynchronous state:
///
/// ```dart
/// @Computed()
/// Future<List<Book>> get books => client.byGenre(genre);
/// ```
///
/// The request is made when the value is first read and again when `genre`
/// changes; until then every reader gets the same future. Its state
/// (loading, the data, the error) is `books.state`, shown by `AsyncView`;
/// `books.refresh()` asks again and keeps the data on screen meanwhile.
/// What it depends on must be read **before the first `await`**: after it
/// nothing is followed any more.
@ProxyTargetClass()
class Computed {
  /// Marks the getter or method.
  const Computed();
}

/// A method run when the bean is made, and again every time state it read
/// changes.
///
/// ```dart
/// @Effect()
/// void save() => storage.write(items);
/// ```
///
/// A public method without parameters. It follows everything it reads, of
/// its own bean and of others; a read inside `untracked(() => ...)` is not
/// followed. It stops when the bean is destroyed.
@BeanMethodAnnotation()
@ProxyTargetClass()
class Effect {
  /// Marks the method.
  const Effect();
}
