import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/bean_reads.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A stateless widget that receives the beans it needs: the record type
/// `B` lists them, and `build` reads them from [beans].
///
/// Flutter creates widgets with their own constructors, so nothing can be
/// injected into them the way beans get their dependencies. Instead, the
/// widget names its beans in its type, `SpringStatelessWidget<(Basket,)>`,
/// and gets them filled in from the application context at each build.
/// Compared with `context.bean<T>()` this gives three things: the beans
/// are typed and listed in one place; the generator sees every such widget
/// and the application fails at startup, not at some later build, when a
/// bean is missing; and the widget rebuilds when a state bean it shows
/// changes (see [beans]).
///
/// Use it for any widget that shows or uses beans and keeps no `State` of
/// its own; with controllers, animations or work in `initState`, use
/// [SpringStatefulWidget]. The constructor stays yours. With more than one
/// bean, a typedef names the record, which keeps the class line short:
///
/// ```dart
/// typedef ThemeMenuBeans = (
///   ThemeSelection,
///   SpringThemes,
/// );
///
/// // A menu of every theme; picking one changes the whole app at once.
/// class ThemeMenu extends SpringStatelessWidget<ThemeMenuBeans> {
///   const ThemeMenu({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final (
///       selection,
///       themes,
///     ) = beans;
///     return PopupMenuButton<String>(
///       onSelected: selection.select,
///       itemBuilder: (_) => [
///         for (final name in ['system', ...themes.names])
///           PopupMenuItem(value: name, child: Text(name)),
///       ],
///     );
///   }
/// }
/// ```
///
/// A record with named fields (`({Basket basket, Clock clock})`, read as
/// `beans.basket`) works too; when several beans have a field's type, the
/// field's name picks one, like a constructor parameter's name in Spring.
/// A nullable field (`Clock?`) is optional.
///
/// Tests put the widget under a `SpringScope` with the context of a
/// `springBootTest`, or call [buildWith] with fakes, such as
/// `buildWith(context, (FakeBasket(), FakeClock()))` for a widget of
/// `(Basket, Clock)`.
///
/// Spring has no counterpart: a Java bean is injected into a controller or
/// a view, never looked up from a UI tree.
abstract class SpringStatelessWidget<B extends Record> extends Widget {
  /// Lets subclasses have `const` constructors; [key] is the usual widget
  /// key.
  const SpringStatelessWidget({super.key});

  /// Describes the part of the UI this widget is, like
  /// `StatelessWidget.build`; read the beans from [beans] here.
  Widget build(BuildContext context);

  /// The beans named in this widget's type, from the application context
  /// of the place it is built in.
  ///
  /// The widget rebuilds when one of them that is a `Listenable` notifies.
  /// A `@ChangeNotifierComponent` (or `@NotifyListeners`) bean counts only
  /// when [build] read its state (a getter, a field): calling its methods
  /// (`onPressed: counter.increment`) costs no rebuilds. A plain
  /// `ChangeNotifier` bean counts always.
  ///
  /// Read it in [build] and in the callbacks made there (`onPressed`). A
  /// widget is immutable and one `const` instance may be built in several
  /// places, so after [build] it holds the beans of the latest build; a
  /// widget built under two application contexts at once takes them into
  /// locals in [build] (`final (basket, clock) = beans;`). Reading it
  /// before the first build throws a `FlutterError`.
  B get beans {
    final building = _building;
    if (building != null && identical(building.widget, this)) {
      return building.beans as B;
    }
    final latest = _latestBeans[this];
    if (latest != null) {
      return latest as B;
    }
    throw FlutterError.fromParts([
      ErrorSummary('$runtimeType.beans was read before the widget was built.'),
      ErrorHint(
        'Read beans in build (or in callbacks made there); tests can call '
        'buildWith(context, beans) with fakes.',
      ),
    ]);
  }

  /// Builds this widget with [beans] instead of the application context's,
  /// for tests that check the widget with fakes and no application:
  /// `buildWith(context, (FakeBasket(), FakeClock()))`.
  @visibleForTesting
  Widget buildWith(BuildContext context, B beans) => _buildWith(context, beans);

  /// The record type `B` this widget gets, which the framework uses to
  /// find how to fill it.
  Type get beansType => B;

  @override
  SpringStatelessElement createElement() => SpringStatelessElement(this);

  Widget _buildWith(BuildContext context, Record beans) {
    _latestBeans[this] = beans;
    final previous = _building;
    _building = (widget: this, beans: beans);
    try {
      return build(context);
    } finally {
      _building = previous;
    }
  }
}

/// The widget being built and its beans: what [SpringStatelessWidget.beans]
/// gives during `build`.
({SpringStatelessWidget<Record> widget, Record beans})? _building;

/// The beans of each [SpringStatelessWidget]'s latest build, for callbacks
/// that read `beans` after `build`.
final _latestBeans = Expando<Record>('SpringStatelessWidget beans');

/// A stateful widget whose [SpringState] receives the beans named in its
/// record type `B`.
///
/// It is to [SpringStatelessWidget] what `StatefulWidget` is to
/// `StatelessWidget`: use it when the widget also needs a `State`, for a
/// text controller, an animation, or work started in `initState` (such as
/// loading data from a bean). The `State` extends [SpringState] and reads
/// the beans from `beans`, available from `initState` on. The same checks
/// at startup and the same rebuilds apply.
///
/// ```dart
/// typedef BasketPageBeans = (
///   Basket,
///   Clock,
/// );
///
/// class BasketPage extends SpringStatefulWidget<BasketPageBeans> {
///   const BasketPage({super.key});
///
///   @override
///   State<BasketPage> createState() => _BasketPageState();
/// }
///
/// class _BasketPageState extends SpringState<BasketPage, BasketPageBeans> {
///   @override
///   void initState() {
///     super.initState();
///     // Fetch the basket from the server once, when the page opens.
///     final ( // already available here
///       basket,
///       _,
///     ) = beans;
///     basket.load();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     final (
///       basket,
///       clock,
///     ) = beans;
///     return Text('${basket.count} at ${clock.now}');
///   }
/// }
/// ```
///
/// The record is written twice, on the widget and on its `State` (Dart
/// cannot take it from the widget); the compiler checks that both are the
/// same, and a typedef keeps it in one place.
abstract class SpringStatefulWidget<B extends Record> extends StatefulWidget {
  /// Lets subclasses have `const` constructors; [key] is the usual widget
  /// key.
  const SpringStatefulWidget({super.key});

  /// The record type `B` this widget's state gets.
  Type get beansType => B;

  @override
  StatefulElement createElement() => _SpringStatefulElement(this);
}

/// Notes the beans a [SpringState] reads in `build`, so the state listens
/// only to the beans it shows.
class _SpringStatefulElement extends StatefulElement {
  _SpringStatefulElement(super.widget);

  @override
  Widget build() => switch (state) {
    final SpringState<SpringStatefulWidget<Record>, Record> state =>
      state._listening.track(super.build),
    _ => super.build(),
  };
}

/// The `State` of a [SpringStatefulWidget]: a `State` that gets the beans
/// named in its record type `B` as [beans].
///
/// Extend it instead of `State<W>` and repeat the widget's record type
/// (best through a shared typedef). The generator sees every `SpringState`,
/// so the application fails at startup when a bean is missing. [beans] is
/// available from `initState` on and is filled again when the widget ends
/// up under another application context (a hot reload that changed beans,
/// a `SpringScope` with a new one). A record with named fields works as
/// for [SpringStatelessWidget]. Subclasses that override `dispose` or
/// `didChangeDependencies` must call `super`.
abstract class SpringState<W extends SpringStatefulWidget<B>, B extends Record>
    extends State<W> {
  ApplicationContext? _context;
  B? _beans;

  late final _listening = BeanReads(_onBeanChanged);

  /// The beans named in this state's type, from the application context.
  ///
  /// The state rebuilds when one of them that is a `Listenable` notifies.
  /// A `@ChangeNotifierComponent` (or `@NotifyListeners`) bean counts only
  /// when `build` read its state (a getter, a field): calling its methods
  /// costs no rebuilds. A plain `ChangeNotifier` bean counts always.
  B get beans {
    final current = _beans;
    if (current != null) {
      return current;
    }
    final context = _context ?? SpringScope.of(this.context, listen: false);
    final beans = SpringWidgetBindings.resolve(context, B, runtimeType) as B;
    _listening.setBeans(SpringWidgetBindings.valuesOf(context, B, beans));
    return _beans = beans;
  }

  void _onBeanChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _listening.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final context = SpringScope.maybeOf(this.context);
    if (!identical(context, _context)) {
      if (_context != null) {
        _beans = null;
      }
      _context = context;
    }
  }
}

/// The element of a [SpringStatelessWidget], like `StatelessElement` for a
/// `StatelessWidget`: it fills the widget's beans at each build and
/// listens to the ones the build reads. Flutter creates it; applications
/// do not use it.
class SpringStatelessElement extends ComponentElement {
  /// The element of [widget].
  SpringStatelessElement(SpringStatelessWidget<Record> super.widget);

  late final _listening = BeanReads(markNeedsBuild);

  @override
  Widget build() {
    final widget = this.widget as SpringStatelessWidget<Record>;
    final context = SpringScope.of(this);
    final beans = SpringWidgetBindings.resolve(
      context,
      widget.beansType,
      widget.runtimeType,
    );
    _listening.setBeans(
      SpringWidgetBindings.valuesOf(context, widget.beansType, beans),
    );
    return _listening.track(() => widget._buildWith(this, beans));
  }

  @override
  void update(SpringStatelessWidget<Record> newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }

  @override
  void unmount() {
    _listening.dispose();
    super.unmount();
  }
}

/// How one record of beans is filled from the container, for the Spring
/// widgets that declare it.
///
/// The generator writes one per [SpringStatelessWidget] or [SpringState]
/// class, because filling a record type needs code that names each field.
/// Widgets find it by record type, so widgets that share a record share
/// how it is filled. Applications never write or use it.
final class SpringWidgetBinding {
  /// The binding of [widget], whose beans are a [beans] record of [types].
  const SpringWidgetBinding({
    required this.widget,
    required this.beans,
    required this.types,
    required this.resolve,
    this.values,
  });

  /// The widget class, for error messages
  /// (`package:app/basket_badge.dart#BasketBadge`).
  final String widget;

  /// The record type, such as `(Basket, Clock)`.
  final Type beans;

  /// The bean types the record holds; [SpringWidgetBindings.check] makes
  /// sure each exists when the application starts.
  final List<Type> types;

  /// Fills the record from a bean factory.
  final Record Function(BeanFactory factory) resolve;

  /// The beans of a record [resolve] returned, in field order, so the
  /// widgets can subscribe to the `Listenable` ones. When `null`, the
  /// widgets listen to none of them.
  final List<Object?> Function(Record beans)? values;

  /// The bean of [T] for one record field, as generated code asks for it:
  /// by type; when several beans have the type and none is primary, the
  /// one called [name] (the name of a named field).
  static T bean<T extends Object>(BeanFactory factory, [String? name]) {
    if (name == null) {
      return factory.getBean<T>();
    }
    try {
      return factory.getBean<T>();
    } on NoUniqueBeanDefinitionException {
      return factory.getBean<T>(qualifier: name);
    }
  }
}

/// The [SpringWidgetBinding]s of a generated module, registered as a bean,
/// through which Spring widgets find how to fill their records.
///
/// The generator writes one per `@SpringBootApplication` or
/// `@ComponentScan` that has Spring widgets. Applications never write or
/// use it.
final class SpringWidgetBindings {
  /// The [bindings] of one module.
  const SpringWidgetBindings(this.bindings);

  /// The bindings, one per Spring widget or `SpringState` class.
  final List<SpringWidgetBinding> bindings;

  static final _byContext = Expando<Map<Type, SpringWidgetBinding>>(
    'SpringStatelessWidget bindings',
  );

  static Map<Type, SpringWidgetBinding> _of(ApplicationContext context) =>
      _byContext[context] ??= {
        for (final bindings
            in context.getBeansOfType<SpringWidgetBindings>().values)
          for (final binding in bindings.bindings) binding.beans: binding,
      };

  /// The beans in [record] (of type [beans]) as a list, from its generated
  /// binding; empty when there is none.
  static List<Object?> valuesOf(
    ApplicationContext context,
    Type beans,
    Record record,
  ) => _of(context)[beans]?.values?.call(record) ?? const [];

  /// The [beans] record of [owner] (a `SpringStatelessWidget` or
  /// `SpringState` type) filled from [context]. Throws a `FlutterError`
  /// that says to run the generator when no binding has the record type.
  static Record resolve(ApplicationContext context, Type beans, Type owner) {
    final binding = _of(context)[beans];
    if (binding == null) {
      throw FlutterError.fromParts([
        ErrorSummary('No generated beans for $owner ($beans).'),
        ErrorHint(
          'Run `dart run build_runner build` (or keep `build_runner watch` '
          'running); after a change to SpringStatelessWidget or SpringState types a '
          'hot restart may be needed.',
        ),
      ]);
    }
    return binding.resolve(context);
  }

  /// Checks that every bean the Spring widgets of [context] need exists,
  /// and throws a `NoSuchBeanDefinitionException` naming the widget
  /// otherwise. `SpringApplicationWidget` calls it after the start, so a
  /// missing bean fails the start instead of a later build.
  static void check(ApplicationContext context) {
    for (final binding in _of(context).values) {
      for (final type in binding.types) {
        if (context.getBeanNamesForType(type).isEmpty) {
          throw NoSuchBeanDefinitionException(type, requiredBy: binding.widget);
        }
      }
    }
  }
}
