import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/bean_reads.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A widget that gets the beans named in its type as [beans], like a
/// `SpringState`. The generator sees every `SpringStatelessWidget` and
/// writes how its record is filled, so the start fails when a bean is
/// missing.
///
/// The constructor stays yours: nothing is injected into it.
///
/// ```dart
/// class BasketBadge extends SpringStatelessWidget<(Basket, AppNavigator)> {
///   const BasketBadge({this.compact = false, super.key});
///   final bool compact;
///
///   @override
///   Widget build(BuildContext context) {
///     final (basket, navigator) = beans;
///     return Badge(label: Text('${basket.count}'));
///   }
/// }
/// ```
///
/// A record with named fields (`({Basket basket, Clock clock})`, read as
/// `beans.basket`) works too; when several beans have a field's type, the
/// field's name picks one (like a constructor parameter's name in Spring).
/// Tests put the widget under a `SpringScope`, or call
/// `buildWith(context, (FakeBasket(), FakeNavigator()))` directly.
abstract class SpringStatelessWidget<B extends Record> extends Widget {
  /// Const constructor for subclasses.
  const SpringStatelessWidget({super.key});

  /// Describes the part of the UI this widget is, like
  /// `StatelessWidget.build`; the beans are in [beans].
  Widget build(BuildContext context);

  /// The beans named in this widget's type, from the application context
  /// of the place it is built in. The widget rebuilds when one of them
  /// that is a `Listenable` notifies — a `@ChangeNotifierComponent` (or
  /// `@NotifyListeners`) bean only when [build] read its state (a getter,
  /// a field); calling its methods (`onPressed: counter.increment`) costs
  /// no rebuilds.
  ///
  /// Read it in [build] and in the callbacks made there (`onPressed`). A
  /// widget is immutable and one `const` instance may be built in several
  /// places, so after [build] it holds the beans of the latest build; a
  /// widget built under two application contexts at once takes them into
  /// locals in [build] (`final (basket, clock) = beans;`).
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

  /// Builds this widget with [beans] instead of the application context's:
  /// tests call it with fakes (`buildWith(context, (FakeBasket(),
  /// FakeClock()))`).
  @visibleForTesting
  Widget buildWith(BuildContext context, B beans) => _buildWith(context, beans);

  /// The record type this widget gets (`B`).
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

/// A stateful widget whose [SpringState] gets the beans named in its type
/// — the stateful counterpart of [SpringStatelessWidget], like
/// `StatefulWidget` next to `StatelessWidget`.
///
/// ```dart
/// class BasketPage extends SpringStatefulWidget<(Basket, Clock)> {
///   const BasketPage({super.key});
///
///   @override
///   State<BasketPage> createState() => _BasketPageState();
/// }
///
/// class _BasketPageState extends SpringState<BasketPage, (Basket, Clock)> {
///   @override
///   void initState() {
///     super.initState();
///     final (basket, _) = beans; // already available here
///     basket.load();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     final (basket, clock) = beans;
///     return Text('${basket.count} at ${clock.now}');
///   }
/// }
/// ```
///
/// The record is named twice (Dart cannot take it from the widget); the
/// compiler checks that both are the same, and a typedef
/// (`typedef BasketBeans = (Basket, Clock);`) keeps it in one place.
abstract class SpringStatefulWidget<B extends Record> extends StatefulWidget {
  /// Const constructor for subclasses.
  const SpringStatefulWidget({super.key});

  /// The record type this widget's state gets (`B`).
  Type get beansType => B;

  @override
  StatefulElement createElement() => _SpringStatefulElement(this);
}

/// Notes the beans a [SpringState] reads in `build`.
class _SpringStatefulElement extends StatefulElement {
  _SpringStatefulElement(super.widget);

  @override
  Widget build() => switch (state) {
    final SpringState<SpringStatefulWidget<Record>, Record> state =>
      state._listening.track(super.build),
    _ => super.build(),
  };
}

/// The `State` of a [SpringStatefulWidget]: [beans] holds the beans named
/// in its type. The generator sees every `SpringState`, so the start fails
/// when a bean is missing.
///
/// [beans] is available from `initState` on and is read again when the
/// widget ends up under another application context (a `SpringScope` with
/// a new one). A record with named fields works like for
/// [SpringStatelessWidget].
abstract class SpringState<W extends SpringStatefulWidget<B>, B extends Record>
    extends State<W> {
  ApplicationContext? _context;
  B? _beans;

  late final _listening = BeanReads(_onBeanChanged);

  /// The beans named in this state's type, from the application context.
  /// The state rebuilds when one of them that is a `Listenable` notifies
  /// — a `@ChangeNotifierComponent` (or `@NotifyListeners`) bean only
  /// when `build` read its state (a getter, a field); calling its methods
  /// costs no rebuilds.
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

/// The element of a [SpringStatelessWidget], like `StatelessElement`.
class SpringStatelessElement extends ComponentElement {
  /// An element for [widget].
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

/// How the record of one [SpringStatelessWidget] type is filled; written by the
/// generator, not by hand.
final class SpringWidgetBinding {
  /// The binding of [widget] whose beans are a [beans] record of [types].
  const SpringWidgetBinding({
    required this.widget,
    required this.beans,
    required this.types,
    required this.resolve,
    this.values,
  });

  /// The widget class, for messages (`package:app/basket_badge.dart#BasketBadge`).
  final String widget;

  /// The record type (`(Basket, AppNavigator)`).
  final Type beans;

  /// The bean types the record holds, checked when the application starts.
  final List<Type> types;

  /// Fills the record from [factory].
  final Record Function(BeanFactory factory) resolve;

  /// The beans of a record [resolve] returned, in field order: the widgets
  /// subscribe to the `Listenable` ones.
  final List<Object?> Function(Record beans)? values;

  /// The bean of [T] for a record field: by type; when several beans have
  /// it and none is primary, the one called [name] (a named field's name).
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

/// The [SpringWidgetBinding]s of a generated module, registered as a bean;
/// the generator writes one per `@SpringBootApplication` / `@ComponentScan`
/// that has [SpringStatelessWidget]s.
final class SpringWidgetBindings {
  /// The bindings of one module.
  const SpringWidgetBindings(this.bindings);

  /// The bindings, one per widget class.
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

  /// The beans in [record] (of type [beans]), from its generated binding.
  static List<Object?> valuesOf(
    ApplicationContext context,
    Type beans,
    Record record,
  ) => _of(context)[beans]?.values?.call(record) ?? const [];

  /// The [beans] record of [owner] (a `SpringStatelessWidget` or `SpringState`
  /// type) filled from [context].
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

  /// Checks that every bean the [SpringStatelessWidget]s of [context] need exists;
  /// `SpringApplicationWidget` calls it after the start, so a missing bean fails the
  /// start instead of a later build.
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
