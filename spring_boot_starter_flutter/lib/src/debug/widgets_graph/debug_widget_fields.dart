/// A public field of a widget or a `State`: its name, and what reads it
/// from an instance of the class.
typedef DebugFieldReader = (String name, Object? Function(Object instance));

/// The public fields of the application's own widgets and of their `State`
/// classes, by class, which the card of a widget in the application graph
/// shows (its `properties` and `state properties` blocks).
///
/// The generator writes it into the application's debug part
/// (`<library>.spring.debug.dart`) as the lazy bean `debugWidgetFields`,
/// only when the build has the widgets layer
/// (`spring.flutter.debug.graph.layers` letting `widgets` in, within
/// `spring.flutter.debug.graph.enabled` and `spring.flutter.debug.enabled`,
/// or the console's `graph` pane), and the application refers to it only
/// outside release builds: a release build, or one without the layer, has
/// none of it. For each public, non-generic widget class of the
/// application's scan that does not override `debugFillProperties` (one
/// that does tells its values through Flutter's diagnostics), and for its
/// public `State` class, it lists the public instance fields the class and
/// its superclasses of the application's package declare. Getters are left
/// out, as a getter may compute, allocate or change something; so is a
/// `late` field with an initializer, which reading would run. Private
/// fields cannot be read from another library, so they are not shown.
///
/// ```dart
/// // Output, main.spring.debug.dart:
/// List<BeanDefinition<Object>> get _$debugWidgetFields => [
///   BeanDefinition<DebugWidgetFields>(
///     name: r'debugWidgetFields',
///     lazy: true,
///     create: (r) => DebugWidgetFields({
///       PassportCard: [(r'player', (o) => (o as PassportCard).player)],
///     }),
///   ),
/// ];
/// ```
final class DebugWidgetFields {
  /// The fields of each class in [readers].
  const DebugWidgetFields(this.readers);

  /// The fields of each class, in their order of declaration.
  final Map<Type, List<DebugFieldReader>> readers;

  /// The fields of [instance]'s class; none for a class it does not know.
  List<DebugFieldReader> of(Object instance) =>
      readers[instance.runtimeType] ?? const [];
}
