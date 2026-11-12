import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoThemeData;
import 'package:material_ui/material_ui.dart' show ThemeData;
import 'package:spring_boot_starter_flutter_cupertino/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';
import 'package:spring_boot_starter_flutter_material/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

export 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';
export 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

/// Both design libraries, for the tests of what the starter does with one
/// in the application: a palette from a seed color, a theme with the
/// properties of Material's or Cupertino's own widgets.
const testDesigns = ThemeDesigns(
  all: [MaterialThemeDesign(), CupertinoThemeDesign()],
  appType: 'material',
);

/// The auto-configurations of an application with the Flutter starter and
/// both design starters, for a test's `SpringApplication`; pass
/// [designAutoConfigurationMetadata] with them.
final designedAutoConfigurations = [
  springBootStarterFlutterAutoConfiguration,
  springBootStarterFlutterMaterialAutoConfiguration,
  springBootStarterFlutterCupertinoAutoConfiguration,
];

/// The app type of an application with both design starters, which has to
/// name one: `material`, under what an example sets itself.
const designDefaultProperties = {'spring.flutter.app.type': 'material'};

/// What the generator writes for the design starters' modules: their
/// designs, which the themes are read with before any bean exists.
final designAutoConfigurationMetadata = <BeanModule, AutoConfigurationModule>{
  springBootStarterFlutterMaterialAutoConfiguration:
      const AutoConfigurationModule(factories: [MaterialThemeDesign()]),
  springBootStarterFlutterCupertinoAutoConfiguration:
      const AutoConfigurationModule(factories: [CupertinoThemeDesign()]),
};

/// The themes of a test as Material's and Cupertino's, with no customizer.
extension DesignedThemes on SpringThemes {
  /// Theme [name] as Material's `ThemeData`.
  ThemeData material(String name) => data(name).toMaterial();

  /// Theme [name] as a `CupertinoThemeData`.
  CupertinoThemeData cupertino(String name) => data(name).toCupertino();
}
