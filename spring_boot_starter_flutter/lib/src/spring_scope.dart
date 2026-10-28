import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The inherited widget that holds the application context for the
/// widgets below it: every way a widget gets a bean
/// (`context.bean<T>()`, the generated getters, the `beans` record of a
/// Spring widget) looks it up here.
///
/// An app does not create it: `SpringApplicationWidget` puts one at the
/// root once the application has started. Tests do create it, around the
/// widget under test, with the context of a `springBootTest`, so the
/// widget gets real or replaced beans without starting the whole app.
///
/// Widgets that read beans through it are rebuilt when the context is
/// replaced (a hot reload that changed beans), so they never keep using a
/// closed context.
///
/// ```dart
/// // A widget test with a fake basket instead of the real one.
/// final app = springBootTest(
///   springApplication,
///   overrides: [BeanOverride<Basket>(FakeBasket())],
/// );
///
/// testWidgets('shows the count', (tester) async {
///   await tester.pumpWidget(SpringScope(
///     applicationContext: app.context,
///     child: const MaterialApp(home: BasketBadge()),
///   ));
/// });
/// ```
///
/// Spring has no counterpart: a Java bean is injected, never looked up
/// from a UI tree.
class SpringScope extends InheritedWidget {
  /// Gives [applicationContext] to [child] and every widget below it.
  const SpringScope({
    required this.applicationContext,
    required super.child,
    super.key,
  });

  /// The context the widgets below get their beans and messages from.
  final ApplicationContext applicationContext;

  /// The application context of the nearest [SpringScope] above
  /// [context]. Throws a `FlutterError` explaining the setup when there is
  /// none.
  ///
  /// With [listen] `true` (the default), the widget of [context] is rebuilt
  /// when the application context is replaced. Pass `false` where a
  /// dependency cannot be registered, such as in `State.initState`.
  static ApplicationContext of(BuildContext context, {bool listen = true}) {
    final scope = maybeOf(context, listen: listen);
    if (scope == null) {
      throw FlutterError.fromParts([
        ErrorSummary('No SpringScope above ${context.widget.runtimeType}.'),
        ErrorDescription(
          'Beans are read from the application context that SpringApplicationWidget '
          '(or a SpringScope in tests) gives to the widget tree.',
        ),
        ErrorHint(
          'Wrap the app in SpringApplicationWidget: '
          'runApp(SpringApplicationWidget(application: () => springApplication, '
          'child: const MyApp())).',
        ),
      ]);
    }
    return scope;
  }

  /// Like [of], but `null` when there is no [SpringScope] above [context],
  /// for widgets that also work without Spring. With `listen: false`, the
  /// widget of [context] is not rebuilt when the application context is
  /// replaced (usable in `State.initState`).
  static ApplicationContext? maybeOf(
    BuildContext context, {
    bool listen = true,
  }) =>
      (listen
              ? context.dependOnInheritedWidgetOfExactType<SpringScope>()
              : context.getInheritedWidgetOfExactType<SpringScope>())
          ?.applicationContext;

  /// The bean of type [T] (with [qualifier], the bean of that name, alias
  /// or qualifier) from the context of the nearest [SpringScope]; what
  /// `context.bean<T>()` and the generated getters call. The widget is
  /// rebuilt when the context is replaced, not when the bean changes.
  static T beanOf<T extends Object>(
    BuildContext context, {
    String? qualifier,
  }) => of(context).getBean<T>(qualifier: qualifier);

  @override
  bool updateShouldNotify(SpringScope oldWidget) =>
      !identical(oldWidget.applicationContext, applicationContext);
}
