import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/spring_widgets.dart';

/// A Spring widget in the tree: its element, and the record type of its
/// beans (its `beansType`).
typedef DebugGraphSpringWidget = ({Element element, Type beansType});

/// Widget types of a library that only call a builder of the
/// application's (`Builder`, `LayoutBuilder`, a starter's `Watch`): what
/// they make is created in the application's files, yet they are not the
/// application's widgets. The widgets layer folds them away, and a debug
/// tool that names a widget after the one it is in skips them
/// ([DebugGraphWidgets.isBuilderType]).
///
/// Flutter's are built in ([flutter]). A starter adds its own with a bean
/// of this type that registers itself while it lives:
///
/// ```dart
/// BeanDefinition<DebugGraphBuilders>(
///   name: 'signalsGraphBuilders',
///   types: const [DebugGraphBuilders],
///   create: (_) => const DebugGraphBuilders({'Watch', 'AsyncView'}),
///   postConstruct: DebugGraphWidgets.addBuilders,
///   preDestroy: DebugGraphWidgets.removeBuilders,
/// )
/// ```
///
/// Put the bean in the starter's debug modules only, so a build without
/// the debug tools has neither it nor the names.
///
/// Spring has no counterpart.
final class DebugGraphBuilders {
  /// The builder widgets named [types], by their type without type
  /// arguments (`ValueListenableBuilder`).
  const DebugGraphBuilders(this.types);

  /// Flutter's own builders.
  static const flutter = DebugGraphBuilders({
    'Builder',
    'StatefulBuilder',
    'LayoutBuilder',
    'ListenableBuilder',
    'AnimatedBuilder',
    'ValueListenableBuilder',
    'StreamBuilder',
    'FutureBuilder',
    'TweenAnimationBuilder',
    'OrientationBuilder',
    'KeyedSubtree',
    'Visibility',
  });

  /// The type names, without type arguments.
  final Set<String> types;
}

/// What the layers of the application graph share about widgets: the id of
/// the node that stands for a widget, the Spring widgets in the tree, and
/// the builder widgets that are not the application's ([builders]).
///
/// The node of a widget belongs to one layer (the widgets layer); another
/// layer that knows a widget ties its nodes to it by [idOf], and the edge
/// is drawn when both layers show.
abstract final class DebugGraphWidgets {
  static final List<DebugGraphBuilders> _registered = [];
  static Set<String>? _builders;

  /// The builder widgets' type names: Flutter's
  /// ([DebugGraphBuilders.flutter]) and those of every registered
  /// [DebugGraphBuilders].
  static Set<String> get builders => _builders ??= Set.unmodifiable({
    ...DebugGraphBuilders.flutter.types,
    for (final registered in _registered) ...registered.types,
  });

  /// Adds [builders] to [builders] until [removeBuilders] takes them out:
  /// a bean's `postConstruct`. Added twice, it must be removed twice.
  static void addBuilders(DebugGraphBuilders builders) {
    _registered.add(builders);
    _builders = null;
  }

  /// Takes out [builders], added by [addBuilders]: a bean's `preDestroy`.
  static void removeBuilders(DebugGraphBuilders builders) {
    if (_registered.remove(builders)) {
      _builders = null;
    }
  }

  /// Whether [type], a widget's `runtimeType` as text, is a builder's:
  /// its name without type arguments is one of [builders]
  /// (`ValueListenableBuilder<int>`).
  static bool isBuilderType(String type) {
    final open = type.indexOf('<');
    return builders.contains(open < 0 ? type : type.substring(0, open));
  }

  /// Whether [widget] is a builder's ([isBuilderType]).
  static bool isBuilder(Widget widget) =>
      isBuilderType('${widget.runtimeType}');

  /// The id of the node that stands for the widget of [element], in any
  /// layer: `widget:<identity of the element>`. Stable while the element
  /// is mounted.
  static String idOf(BuildContext element) =>
      'widget:${identityHashCode(element)}';

  /// The Spring widgets (`SpringStatelessWidget`, `SpringStatefulWidget`)
  /// mounted under [root] (the app's root element by default), in the
  /// tree's order. It walks the whole tree: for a view that shows, a few
  /// times a second at most; nothing keeps a list of them meanwhile.
  static List<DebugGraphSpringWidget> springWidgets([Element? root]) {
    final found = <DebugGraphSpringWidget>[];
    void visit(Element element) {
      switch (element.widget) {
        case final SpringStatelessWidget<Record> widget:
          found.add((element: element, beansType: widget.beansType));
        case final SpringStatefulWidget<Record> widget:
          found.add((element: element, beansType: widget.beansType));
      }
      element.visitChildren(visit);
    }

    final start = root ?? WidgetsBinding.instance.rootElement;
    if (start != null) {
      visit(start);
    }
    return found;
  }
}
