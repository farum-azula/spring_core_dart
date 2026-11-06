import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Marks a bean method as the handler of a keyboard shortcut's [action]
/// (`search.open`). The keys come from `spring.flutter.shortcuts.<action>`,
/// or from [keys] when the configuration does not name the action.
///
/// The method takes nothing, a `BuildContext` (the focused widget's) or a
/// `ShortcutInvocation`. It returns nothing (the key is handled) or a
/// `bool`: `false` passes the key on to the next handler of the action.
///
/// ```dart
/// @Component()
/// class SearchActions {
///   @Shortcut('search.open', keys: ['primary+k'])
///   void open(BuildContext context) => SearchDialog.show(context);
/// }
/// ```
///
/// ```yaml
/// spring:
///   flutter:
///     shortcuts:
///       search.open: [primary+k, slash]
/// ```
///
/// Several handlers of one action are asked by [order] (lower first), and
/// a `ShortcutHandlers` widget of the screen before them all.
///
/// Spring has no counterpart; like `@Scheduled`, the starter finds the
/// methods it marks.
@BeanMethodAnnotation()
class Shortcut {
  /// Marks the handler of [action].
  const Shortcut(this.action, {this.keys = const [], this.order = 0});

  /// The action's name, the key of `spring.flutter.shortcuts`.
  final String action;

  /// The keys when the configuration does not name the action, in any
  /// notation (`primary+k`, `char:?`).
  final List<String> keys;

  /// The place among the action's handlers; lower first.
  final int order;
}
