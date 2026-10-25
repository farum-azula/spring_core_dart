import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Gives the running application context to the widgets below it.
///
/// [SpringApplicationWidget] puts one at the root. Tests put one around the widget under
/// test with the context of a `springBootTest`:
///
/// ```dart
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
/// Widgets that read beans through it are rebuilt when the context is
/// replaced (a hot reload that changed beans), so they never keep using a
/// closed context.
class SpringScope extends InheritedWidget {
  /// Gives [applicationContext] to [child] and its descendants.
  const SpringScope({
    required this.applicationContext,
    required super.child,
    super.key,
  });

  /// The context the widgets below get beans from.
  final ApplicationContext applicationContext;

  /// The context of the nearest [SpringScope]; [context] is rebuilt when it
  /// is replaced. Throws a `FlutterError` when there is none.
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

  /// Like [of], `null` when there is no [SpringScope] above [context].
  /// With `listen: false` [context] is not rebuilt when the context is
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
  /// or qualifier) from the context of the nearest [SpringScope].
  static T beanOf<T extends Object>(
    BuildContext context, {
    String? qualifier,
  }) => of(context).getBean<T>(qualifier: qualifier);

  @override
  bool updateShouldNotify(SpringScope oldWidget) =>
      !identical(oldWidget.applicationContext, applicationContext);
}
