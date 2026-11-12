import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

/// The designs of an app of type `cupertino` with this starter.
const cupertinoDesigns = ThemeDesigns(
  all: [CupertinoThemeDesign()],
  appType: 'cupertino',
);

/// Those of an app that has a Material starter too: `components.*` is
/// read by it.
const bothDesigns = ThemeDesigns(
  all: [ComponentsDesign(), CupertinoThemeDesign()],
  appType: 'cupertino',
);

/// The themes of [properties] in a Cupertino app.
SpringThemes themes(
  Map<String, String> properties, {
  ThemeDesigns designs = cupertinoDesigns,
}) => SpringThemes(properties, designs: designs);

/// Theme [name] of [properties] in a Cupertino app.
SpringThemeData theme(
  Map<String, String> properties, {
  String name = 'light',
  ThemeDesigns designs = cupertinoDesigns,
}) => themes(properties, designs: designs).data(name);

/// A property the theme refuses, whose full name contains [key].
Matcher invalid(String key) => throwsA(
  isA<ThemePropertyException>().having((e) => e.key, 'key', contains(key)),
);

/// A design that reads `components.*` and nothing of it, as the Material
/// starter's does for this starter's tests.
final class ComponentsDesign implements ThemeDesign {
  /// The design.
  const ComponentsDesign();

  @override
  String get appType => 'material';

  @override
  List<String> get themeProperties => const ['components'];

  @override
  List<String> get schemeVariants => const [];

  @override
  SpringColorScheme colorScheme(ColorSchemeSpec spec) =>
      SpringColorScheme.baseline(spec.brightness);

  @override
  PageTransitionsBuilder? pageTransition(PageTransitionType type) => null;

  @override
  void check(SpringThemeData theme) {}
}
