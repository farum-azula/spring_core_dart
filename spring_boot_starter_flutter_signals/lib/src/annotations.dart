import 'package:spring_boot_dart/spring_boot_dart.dart';

/// What happens to the writes of a bean's field that were not told yet
/// when the bean's scope ends.
enum OnScopeEnd {
  /// They are dropped, and a warning names the bean and the fields.
  discard,

  /// They are told at once, before the bean ends.
  flush,

  /// The bean's state stays until they are told by its queue, or until
  /// `spring.flutter.signals.defer-timeout` passes (then a warning).
  defer,
}

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
///   @Signal(hidden: true, queue: 'ui')
///   List<Book> items = [];
///
///   void apply(String code) => coupon = code;   // an assignment is a change
/// }
/// ```
///
/// The field stays a plain field: no wrapper type and no `.value`. It must
/// be public and not `final` (the bean's generated subclass overrides it,
/// and a private member cannot be overridden from another library). A
/// change is an assignment; for a `List`, `Set`, `Map` or `Queue` a change
/// in place (`items.add(book)`) is one too.
///
/// On a field of a component only: a class the container makes
/// (`@Component`, `@Service`, ...), not a `@Configuration` class.
@AccessHook()
class Signal {
  /// Marks the field.
  const Signal({
    this.hidden = false,
    this.equals,
    this.queued = true,
    this.queue,
    this.eager,
    this.followCollection = true,
    this.onScopeEnd,
  });

  /// Whether the value is kept out of the debug panel's Signals tab and of
  /// the log (a token, a password): only how often it changed is shown.
  final bool hidden;

  /// Decides whether a new value is a change that tells the readers; `==`
  /// when not given. A value it calls equal is still kept. A top-level or
  /// static function.
  final bool Function(Object? previous, Object? next)? equals;

  /// Whether the writes go through a queue and a buffer. `false`: an
  /// assignment is told at once and takes part in no buffer or
  /// transaction, and the generated accessors skip those checks.
  final bool queued;

  /// The name of the queue (`spring.flutter.signals.queues.<name>`, or a
  /// `SignalFlushSchedule` bean with that `@Qualifier`) that tells the
  /// writes of this field; the default one when not given.
  final String? queue;

  /// Whether the signal is made with the bean rather than on first use;
  /// `spring.flutter.signals.eager` when not given.
  final bool? eager;

  /// Whether a `List`, `Set`, `Map` or `Queue` in the field also tells of
  /// a change in place. `false`: only an assignment is a change.
  final bool followCollection;

  /// What happens to writes not told yet when the scope of the bean ends;
  /// `spring.flutter.signals.on-scope-end` when not given.
  final OnScopeEnd? onScopeEnd;
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
@AccessHook()
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
///
/// Every run after the first runs as the user the bean was made for, never
/// as the user whose change ran it: a singleton made at the start runs as
/// the program-wide user of the moment (nobody before a login), a bean
/// made inside a `runWithContext` scope as that scope's user. A value it
/// may not read stays refused for it, whoever computed it before.
@BeanMethodAnnotation()
@AccessHook()
class Effect {
  /// Marks the method.
  const Effect();
}

/// A method called when something starts watching the listed members of
/// the bean (a widget on screen, an effect): the moment to open a stream
/// or start polling.
///
/// ```dart
/// @Signal()
/// int price = 0;
///
/// @OnWatched(['price'])
/// void connect() => feed.start();
///
/// @OnUnwatched(['price'], delay: Duration(seconds: 5))
/// void disconnect() => feed.stop();
/// ```
///
/// The members are `@Signal` fields or `@Computed` values of the same bean,
/// by name. They are one group: the method is called when the first of
/// them gets a watcher, and [OnUnwatched] when the last one loses its
/// watchers. With [each], it is called for each of them.
///
/// A public method without parameters. Its error goes to the
/// `TypedErrorHandler<SignalExecutionException>` bean.
@BeanMethodAnnotation()
@AccessHook()
class OnWatched {
  /// Called for the members [signals].
  const OnWatched(
    this.signals, {
    this.each = false,
    this.delay = Duration.zero,
  });

  /// The names of the members.
  final List<String> signals;

  /// Whether each member counts on its own instead of the group.
  final bool each;

  /// How long the watch must last before the method is called.
  final Duration delay;
}

/// A method called when the listed members of the bean lost their last
/// watcher: see [OnWatched].
///
/// A rebuild that drops a watcher and takes it again in the same frame is
/// no change: the call waits for the end of the frame, and then for
/// [delay].
@BeanMethodAnnotation()
@AccessHook()
class OnUnwatched {
  /// Called for the members [signals].
  const OnUnwatched(
    this.signals, {
    this.each = false,
    this.delay = Duration.zero,
  });

  /// The names of the members.
  final List<String> signals;

  /// Whether each member counts on its own instead of the group.
  final bool each;

  /// How long the members must stay unwatched before the method is called.
  final Duration delay;
}
