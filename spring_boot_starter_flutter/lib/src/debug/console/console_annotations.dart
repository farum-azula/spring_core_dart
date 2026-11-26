import 'package:spring_boot_dart/spring_boot_dart.dart'
    show Component, DependencyResolver, Order;
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_command.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_segment.dart';

/// Makes a class a segment of the debug console's header
/// (`DebugConsoleSegment`), a bean with constructor injection like any
/// `@Component`.
///
/// The generator registers it only in the application's debug part
/// (`<library>.spring.debug.dart`), and only when the build has the console
/// (`spring.flutter.debug.console.enabled: true`) and
/// `spring.flutter.debug.console.segments` names [segment] or holds `*`:
/// otherwise nothing refers to the class and the compiler leaves it out. A
/// bean of the app that injects it fails the build, as it would have
/// nothing to inject there. Only the application's own scan may have one.
///
/// [segment] is the segment's name, which `segments` and `header` pick it
/// by; the
/// class need not repeat it (`DebugConsoleSegment.name` is for a segment
/// without the annotation), and a `name` that disagrees fails the build.
/// [order] places it among the segments `*` stands for.
///
/// ```dart
/// @ConsoleSegment('ping', order: 50)
/// class PingSegment extends DebugConsoleSegment { ... }
/// ```
///
/// Spring has no counterpart.
class ConsoleSegment extends Component implements Order {
  /// The segment [segment], placed by [order].
  const ConsoleSegment(this.segment, {int order = 0}) : value = order;

  /// The segment's name in the header.
  final String segment;

  /// Its order among the segments.
  @override
  final int value;
}

/// Makes a class a command of the debug console's `commands` pane
/// (`DebugConsoleCommand`), a bean with constructor injection like any
/// `@Component`.
///
/// The generator registers it only in the application's debug part
/// (`<library>.spring.debug.dart`), when the build has the console and its
/// `commands` pane (`spring.flutter.debug.console.enabled: true` and
/// `spring.flutter.debug.console.panes` naming `commands` or holding `*`):
/// without them, nothing refers to the class and the compiler leaves it
/// out. A bean of the app that injects it fails the build. Only the
/// application's own scan may have one.
///
/// [command] is the word that runs it; the class need not repeat it
/// (`DebugConsoleCommand.name` is for a command without the annotation),
/// and a `name` that disagrees fails the build. [order] places it in
/// `help` (and before a command of the same name with a higher one).
///
/// ```dart
/// @ConsoleCommand('reload')
/// class ReloadCommand extends DebugConsoleCommand { ... }
/// ```
///
/// Spring has no counterpart.
class ConsoleCommand extends Component implements Order {
  /// The command [command], placed by [order].
  const ConsoleCommand(this.command, {int order = 0}) : value = order;

  /// The word that runs it.
  final String command;

  /// Its order among the commands.
  @override
  final int value;
}

/// Makes a class a pane of the debug console (`DebugConsolePane`), a bean
/// with constructor injection like any `@Component`: shown under the log
/// pane, among the other shown panes by [order].
///
/// The generator registers it only in the application's debug part
/// (`<library>.spring.debug.dart`), and only when the build has the console
/// (`spring.flutter.debug.console.enabled: true`) and
/// `spring.flutter.debug.console.panes` names [pane] or holds `*`:
/// otherwise nothing refers to the class and the compiler leaves it out. A
/// bean of the app that injects it fails the build. Only the application's
/// own scan may have one.
///
/// [pane] is the pane's name, which `panes` and `shown-panes` pick it by;
/// the class need not repeat it (`DebugConsolePane.name` is for a pane
/// without the annotation), and a `name` that disagrees fails the build.
/// [order] places it among the shown panes, top to bottom (the built-in
/// `commands` is 10).
///
/// ```dart
/// @ConsolePane('cart', order: 20)
/// class CartPane extends DebugConsolePane { ... }
/// ```
///
/// Spring has no counterpart.
class ConsolePane extends Component implements Order {
  /// The pane [pane], placed by [order].
  const ConsolePane(this.pane, {int order = 0}) : value = order;

  /// The pane's name.
  final String pane;

  /// Its place among the panes, top to bottom.
  @override
  final int value;
}

/// The [DebugConsoleSegment] beans of [beans] by name, in the beans'
/// order: their `@ConsoleSegment`'s when they have one (the framework's
/// own carry it in their bean definitions, as the generator writes it for
/// an application's), else their `name`; one with neither is left out, and
/// of two with one name the first is kept. A `name` that disagrees with the
/// annotation fails the start (the build fails earlier for one it can
/// read).
Map<String, DebugConsoleSegment> consoleSegmentsByName(
  DependencyResolver beans,
) => _byName<DebugConsoleSegment, ConsoleSegment>(
  beans,
  (annotation) => annotation.segment,
  (segment) => segment.name,
);

/// The [DebugConsoleCommand] beans of [beans] by word, in the beans' order
/// (the application's first), as [consoleSegmentsByName] names segments:
/// their `@ConsoleCommand`'s word, else their `name`.
Map<String, DebugConsoleCommand> consoleCommandsByName(
  DependencyResolver beans,
) => _byName<DebugConsoleCommand, ConsoleCommand>(
  beans,
  (annotation) => annotation.command,
  (command) => command.name,
);

/// The [DebugConsolePane] beans of [beans] by name, as
/// [consoleSegmentsByName] names segments (their `@ConsolePane`'s name,
/// else their `name`), ordered by their annotation's `order`, top to
/// bottom; of one order, in the beans' order.
Map<String, DebugConsolePane> consolePanesByName(DependencyResolver beans) {
  final named = _byName<DebugConsolePane, ConsolePane>(
    beans,
    (annotation) => annotation.pane,
    (pane) => pane.name,
  );
  final orders = <String, int>{};
  final all = beans.optionalDependencyMap<DebugConsolePane>() ?? const {};
  for (final bean in all.keys) {
    if (beans.findAnnotationOnBean<ConsolePane>(bean) case final pane?) {
      orders.putIfAbsent(pane.pane, () => pane.value);
    }
  }
  final names = named.keys.toList();
  final sorted = [
    for (final (i, name) in names.indexed) (i, orders[name] ?? 0, name),
  ]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
  return {for (final (_, _, name) in sorted) name: named[name]!};
}

Map<String, T> _byName<T extends Object, A extends Object>(
  DependencyResolver beans,
  String Function(A annotation) annotated,
  String? Function(T extension) own,
) {
  final named = <String, T>{};
  final all = beans.optionalDependencyMap<T>() ?? const {};
  for (final MapEntry(key: bean, value: extension) in all.entries) {
    final fromAnnotation = switch (beans.findAnnotationOnBean<A>(bean)) {
      final annotation? => annotated(annotation),
      null => null,
    };
    final fromGetter = own(extension);
    if (fromAnnotation != null &&
        fromGetter != null &&
        fromAnnotation != fromGetter) {
      throw StateError(
        "The bean $bean is named '$fromAnnotation' by its annotation and "
        "'$fromGetter' by its name getter: drop the getter, or make the two "
        'agree.',
      );
    }
    if (fromAnnotation ?? fromGetter case final name?) {
      named.putIfAbsent(name, () => extension);
    }
  }
  return named;
}
