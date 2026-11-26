import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_view.dart';

/// A pane of the debug console, under its header: a bean, picked by its
/// name, the one its `@ConsolePane` gives when it has one, else [name] (a
/// pane registered as a plain bean or made by hand). A [name] that
/// disagrees with the annotation fails the build (and, for one the build
/// cannot read, the start).
///
/// `spring.flutter.debug.console.panes` lists the panes the build has (`*`:
/// every one): a pane it does not name has no code in the build, its
/// built-in module or its `@ConsolePane` class's registration with it.
/// `spring.flutter.debug.console.shown-panes` says which of them show at
/// the start; the debug panel's Console tab shows or hides each while the
/// app runs (`DebugConsole.showPane`).
///
/// The shown panes stack under the header by their annotation's `order`,
/// a divider between neighbours that a drag moves; each keeps its height
/// while the app runs, [initialHeight] until dragged, never under
/// [minHeight]. A hidden pane is not built at all, and the next one moves
/// up; [start] runs while it shows, and what it returns stops it when it
/// hides (or the console does), so a hidden pane costs nothing. Draw it
/// again at most once a frame (a `ListenableBuilder` over what notifies
/// once a frame, or a frame callback), and take its colours and fonts from
/// the debug theme (`DebugStyle.of(context)`).
///
/// A pane has nothing to do for the console's interaction
/// (`DebugConsole.interaction`): while the panes pass the pointer through,
/// the console keeps every pointer from it, and while they interact it
/// takes them as it does. What it adds to the header takes taps in both.
///
/// The framework's own, `logs` (the records of the log buffer, order 0)
/// and `commands` (the commands and their input line, order 10), are beans
/// like an application's. With no pane shown the console is its header
/// alone.
///
/// ```dart
/// @ConsolePane('cart', order: 20)
/// class CartPane extends DebugConsolePane {
///   CartPane(this.cart);
///
///   final Cart cart;
///
///   @override
///   String get title => 'Cart';
///
///   @override
///   Widget build(BuildContext context, DebugConsole console) {
///     final style = DebugStyle.of(context);
///     return ListenableBuilder(
///       listenable: cart,
///       builder: (context, _) => ListView(
///         children: [
///           for (final item in cart.items)
///             Text('${item.name} × ${item.count}', style: style.code),
///         ],
///       ),
///     );
///   }
/// }
/// ```
///
/// ```yaml
/// spring.flutter.debug.console:
///   enabled: true
///   panes: [logs, commands, cart]   # in the build
///   shown-panes: [logs, cart]       # shown at the start
/// ```
///
/// Spring has no counterpart.
abstract class DebugConsolePane {
  /// A pane.
  const DebugConsolePane();

  /// Its name in `spring.flutter.debug.console.panes` when no
  /// `@ConsolePane` names it; `null` (the default): the annotation's.
  String? get name => null;

  /// What the debug panel's Console tab calls it.
  String get title;

  /// The least it is high: one line of the console
  /// ([DebugConsoleView.lineHeight]) unless it says more.
  double get minHeight => DebugConsoleView.lineHeight;

  /// How high it starts, until dragged: six lines unless it says
  /// otherwise; never under [minHeight].
  double get initialHeight => DebugConsoleView.lineHeight * 6;

  /// How opaque its background is, from 0 to 1; `null` (the default): the
  /// console's (`spring.flutter.debug.console.opacity`). The console's
  /// background is behind every part of it, the header and each shown
  /// pane; a pane of dense graphics (a graph) says more, 0.9 say, so the
  /// app under it does not show through its lines. Only while the panes
  /// interact: passing the pointer through, every pane's background is of
  /// `spring.flutter.debug.console.pass-through-opacity`, so the app the
  /// taps reach shows.
  double? get backgroundOpacity => null;

  /// Starts what the pane reads, while it shows. Returns what stops it;
  /// nothing by default.
  void Function() start() => _nothing;

  static void _nothing() {}

  /// The pane, in [console], given the pane's height and the console's
  /// width.
  Widget build(BuildContext context, DebugConsole console);

  /// What it adds at the right of the console's header while it shows
  /// (the `logs` pane's `Select`, its `paused`); `null` (the default):
  /// nothing. Built with the header, so draw it again at most once a frame
  /// as [build] is.
  Widget? buildHeader(BuildContext context, DebugConsole console) => null;
}
