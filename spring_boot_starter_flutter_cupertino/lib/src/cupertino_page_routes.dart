import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_theme_design.dart';

/// Cupertino's page route and hero flights for the router of
/// `spring_boot_starter_flutter_navigation`: the iOS slide with its swipe
/// back.
///
/// The starter declares it as a bean (`cupertinoPageRoutes`). The router
/// asks it for the route of a page whose transition is `cupertino`, in an
/// app of any type, or `platform` in an app of type `cupertino`:
///
/// ```yaml
/// spring.flutter.theme.motion.page-transition:
///   type: cupertino
///   duration: 350ms
/// ```
final class CupertinoPageRoutes implements DesignPageRoutes {
  /// The routes.
  const CupertinoPageRoutes();

  @override
  PageRoute<Object?>? pageRoute(
    PageTransitionType transition,
    String appType,
    SpringPageRequest page,
  ) => switch (transition) {
    PageTransitionType.cupertino => _CupertinoRoute(page),
    PageTransitionType.platform when _own(appType) => _CupertinoRoute(page),
    _ => null,
  };

  /// Cupertino's hero controller (flights in a straight line) in an app of
  /// type `cupertino`; `null` in the others.
  @override
  HeroController? heroController(String appType) =>
      _own(appType) ? CupertinoApp.createCupertinoHeroController() : null;

  static bool _own(String appType) =>
      appType.trim().toLowerCase() == CupertinoThemeDesign.typeName;
}

// [animation] along [curve], when the page gives one.
Animation<double> _curved(Animation<double> animation, Curve? curve) =>
    curve == null
    ? animation
    : CurvedAnimation(parent: animation, curve: curve);

final class _CupertinoRoute extends PageRoute<Object?>
    with CupertinoRouteTransitionMixin<Object?> {
  _CupertinoRoute(this.page) : super(settings: page.settings);

  final SpringPageRequest page;

  @override
  Widget buildContent(BuildContext context) => page.childOf(settings);

  @override
  Duration get transitionDuration => page.duration ?? super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      page.duration ?? super.reverseTransitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => super.buildTransitions(
    context,
    _curved(animation, page.curve),
    _curved(secondaryAnimation, page.curve),
    child,
  );

  // iOS dims the page below with a light black while the new one slides
  // in, and keeps it under the page. A theme's background shows through
  // every screen: there the dimming would stay on it, darker than the
  // theme says, so a theme with a background has none.
  @override
  Color? get barrierColor {
    final context = navigator?.context;
    final background = context == null
        ? null
        : SpringTheme.maybeOf(context)?.background;
    return background == null ? super.barrierColor : null;
  }

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}
