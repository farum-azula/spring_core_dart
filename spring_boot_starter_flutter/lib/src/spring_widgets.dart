import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A widget that gets the beans named in its type, handed to [build] as a
/// record. The generator sees every `SpringStatelessWidget` and writes how its
/// record is filled, so the start fails when a bean is missing.
///
/// The constructor stays yours: nothing is injected into it.
///
/// ```dart
/// class BasketBadge extends SpringStatelessWidget<(Basket, AppNavigator)> {
///   const BasketBadge({this.compact = false, super.key});
///   final bool compact;
///
///   @override
///   Widget build(BuildContext context, (Basket, AppNavigator) beans) {
///     final (basket, navigator) = beans;
///     return Badge(label: Text('${basket.count}'));
///   }
/// }
/// ```
///
/// A record with named fields (`({Basket basket, Clock clock})`) works too;
/// when several beans have a field's type, the field's name picks one
/// (like a constructor parameter's name in Spring). Tests call
/// `build(context, (FakeBasket(), FakeNavigator()))` directly, or put the
/// widget under a `SpringScope`.
abstract class SpringStatelessWidget<B extends Record> extends Widget {
  /// Const constructor for subclasses.
  const SpringStatelessWidget({super.key});

  /// Describes the part of the UI this widget is, with [beans] from the
  /// application context; like `StatelessWidget.build`. Tests may call it
  /// with fakes.
  Widget build(BuildContext context, B beans);

  /// The record type this widget gets (`B`).
  Type get beansType => B;

  @override
  SpringStatelessElement createElement() => SpringStatelessElement(this);

  Widget _buildWith(BuildContext context, Record beans) =>
      build(context, beans as B);
}

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

  final _listening = _BeanListeners();

  /// The beans named in this state's type, from the application context.
  /// The state rebuilds when one of them that is a `Listenable` (a
  /// `ChangeNotifier`, a `@ChangeNotifierComponent` bean) notifies.
  B get beans {
    final current = _beans;
    if (current != null) {
      return current;
    }
    final context = _context ?? SpringScope.of(this.context, listen: false);
    final beans = SpringWidgetBindings.resolve(context, B, runtimeType) as B;
    _listening.listenTo(
      SpringWidgetBindings.valuesOf(context, B, beans),
      _onBeanChanged,
    );
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

  final _listening = _BeanListeners();

  @override
  Widget build() {
    final widget = this.widget as SpringStatelessWidget<Record>;
    final context = SpringScope.of(this);
    final beans = SpringWidgetBindings.resolve(
      context,
      widget.beansType,
      widget.runtimeType,
    );
    _listening.listenTo(
      SpringWidgetBindings.valuesOf(context, widget.beansType, beans),
      markNeedsBuild,
    );
    return widget._buildWith(this, beans);
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

/// The `Listenable` beans a Spring widget is subscribed to.
final class _BeanListeners {
  List<Listenable> _listenables = const [];
  VoidCallback? _onChange;

  void listenTo(List<Object?> beans, VoidCallback onChange) {
    final listenables = [
      for (final bean in beans)
        if (bean is Listenable) bean,
    ];
    if (_same(listenables) && onChange == _onChange) {
      return;
    }
    dispose();
    _listenables = listenables;
    _onChange = onChange;
    for (final listenable in listenables) {
      listenable.addListener(onChange);
    }
  }

  bool _same(List<Listenable> other) =>
      other.length == _listenables.length &&
      [for (var i = 0; i < other.length; i++) i]
          .every((i) => identical(other[i], _listenables[i]));

  void dispose() {
    final onChange = _onChange;
    if (onChange != null) {
      for (final listenable in _listenables) {
        listenable.removeListener(onChange);
      }
    }
    _listenables = const [];
    _onChange = null;
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
