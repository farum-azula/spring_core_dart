import 'package:spring_boot_starter_flutter_signals/src/async_value.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';

AsyncMember _memberOf(Object source, String what) =>
    AsyncMember.of(source) ??
    (throw StateError(
      'This $what is not the value of a @Computed getter of a bean, so it '
      'has no state to follow. Read it from the bean as the container '
      'hands it out (context.catalog.books), not from an instance made by '
      'hand, and call .state on what the getter returned.',
    ));

/// The state of a `@Computed` future, and loading it again.
///
/// ```dart
/// @Computed()
/// Future<List<Book>> get books => client.byGenre(genre);
/// ```
///
/// ```dart
/// final state = context.catalog.books.state;      // loading, data, error
/// await context.catalog.books.refresh();          // ask again
/// ```
extension ComputedFuture<T> on Future<T> {
  /// Where the value is. Read in a widget's `build` (a Spring widget, a
  /// `Watch`, an `AsyncView`), it rebuilds the widget when the state
  /// moves.
  AsyncValue<T> get state => _memberOf(this, 'future').state.cast<T>();

  /// Asks again, with the last value kept on screen meanwhile
  /// (`isRefreshing`). Completes when the new answer is there.
  Future<void> refresh() => _memberOf(this, 'future').refresh();

  /// Asks again from nothing: the state is `loading` meanwhile.
  Future<void> reload() => _memberOf(this, 'future').reload();
}

/// The state of a `@Computed` stream.
///
/// ```dart
/// @Computed()
/// Stream<Price> get price => client.prices(genre);
/// ```
///
/// The starter listens to the stream itself: read the events from
/// [state], and do not listen to a single-subscription stream a second
/// time.
extension ComputedStream<T> on Stream<T> {
  /// The last event (`data`), `loading` before the first, or the error.
  AsyncValue<T> get state => _memberOf(this, 'stream').state.cast<T>();

  /// Listens again to a new stream, with the last event kept meanwhile.
  Future<void> refresh() => _memberOf(this, 'stream').refresh();

  /// Listens again to a new stream from nothing.
  Future<void> reload() => _memberOf(this, 'stream').reload();
}
