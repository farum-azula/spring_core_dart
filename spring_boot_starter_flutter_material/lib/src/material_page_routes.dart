import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_material/src/material_theme_design.dart';
import 'package:spring_boot_starter_flutter_material/src/spring_theme_extension.dart';

/// Material's page route and hero flights for the router of
/// `spring_boot_starter_flutter_navigation`, in an app of type `material`:
/// a page whose transition is `platform` comes in as Material's theme has
/// it per platform (`ThemeData.pageTransitionsTheme`).
///
/// A bean of the starter; the router asks every [DesignPageRoutes] bean
/// and knows no design library itself.
final class MaterialPageRoutes implements DesignPageRoutes {
  /// The routes.
  const MaterialPageRoutes();

  static bool _material(String appType) =>
      appType.trim().toLowerCase() == MaterialThemeDesign.typeName;

  @override
  PageRoute<Object?>? pageRoute(
    PageTransitionType transition,
    String appType,
    SpringPageRequest page,
  ) => transition == PageTransitionType.platform && _material(appType)
      ? _MaterialRoute(page)
      : null;

  @override
  HeroController? heroController(String appType) =>
      _material(appType) ? MaterialApp.createMaterialHeroController() : null;
}

// [animation] along [curve], when the page gives one.
Animation<double> _curved(Animation<double> animation, Curve? curve) =>
    curve == null
    ? animation
    : CurvedAnimation(parent: animation, curve: curve);

final class _MaterialRoute extends PageRoute<Object?>
    with MaterialRouteTransitionMixin<Object?> {
  _MaterialRoute(this._page) : super(settings: _page.settings);

  final SpringPageRequest _page;

  // The page of the route now: a router replaces it in place.
  @override
  Widget buildContent(BuildContext context) => _page.childOf(settings);

  // Flutter's own transitions, one per platform.
  static const _platform = PageTransitionsTheme();

  // The transition of a page that asks for `platform`: Material's, as the
  // app's theme has it when code chose it (a `ThemeCustomizer` setting
  // `pageTransitionsTheme`), else Flutter's own for the platform. The
  // theme's `motion.page-transition` is for Material's routes of the app's
  // own, not for a page that asks for the platform's.
  PageTransitionsBuilder _builder(BuildContext context) {
    final theme = Theme.of(context);
    final own = theme.pageTransitionsTheme.builders[theme.platform];
    final motion = theme.extension<SpringThemeExtension>()?.data.pageTransition;
    return own == null || identical(own, motion)
        ? _platform.builders[theme.platform] ??
              const ZoomPageTransitionsBuilder()
        : own;
  }

  @override
  Duration get transitionDuration =>
      _page.duration ?? _builder(navigator!.context).transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _page.duration ?? _builder(navigator!.context).reverseTransitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _builder(context).buildTransitions<Object?>(
    this,
    context,
    _curved(animation, _page.curve),
    _curved(secondaryAnimation, _page.curve),
    child,
  );

  @override
  bool get maintainState => true;

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}
