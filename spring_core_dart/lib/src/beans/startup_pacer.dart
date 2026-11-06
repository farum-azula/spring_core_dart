/// Asked between two beans while the context creates its singletons: may
/// the start go on, or should it let something else run first? A paused
/// start lets a UI draw its frames (a splash that moves while the beans
/// are made), at the price of a longer start.
///
/// The bean factory asks its `DefaultListableBeanFactory.startupPacer`
/// only on the asynchronous path (`refreshAsync`); without one there is
/// no pause and no cost.
///
/// ```dart
/// // A pause every 8 ms of work, for the UI's frame.
/// final class EveryEightMs implements StartupPacer {
///   final _watch = Stopwatch()..start();
///
///   @override
///   Future<void>? pace() {
///     if (_watch.elapsedMilliseconds < 8) return null;
///     _watch.reset();
///     return Future<void>.delayed(Duration.zero);
///   }
/// }
/// ```
///
/// Spring (Java): no counterpart; the JVM has threads, Dart's start shares
/// one with the UI.
abstract interface class StartupPacer {
  /// `null` to go on at once, or a future to wait for before the next bean.
  Future<void>? pace();
}
