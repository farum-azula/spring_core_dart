import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_auto_configuration.dart'
    show springBootStarterFlutterCupertinoAutoConfiguration;
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart'
    show CupertinoThemeDesign;
import 'package:spring_boot_starter_flutter_material/spring_auto_configuration.dart'
    show springBootStarterFlutterMaterialAutoConfiguration;
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart'
    show MaterialThemeDesign;

/// The design starters of an application a test makes by hand: their
/// modules, and the factories of each, as the generator lists them for an
/// app with the starters in its dependencies.
///
/// ```dart
/// SpringApplication(
///   [appBeans],
///   autoConfigurations: [
///     springBootStarterFlutterAutoConfiguration,
///     springSecurityCoreAutoConfiguration,
///     ...DesignStarters.onlyMaterial.autoConfigurations,
///   ],
///   autoConfigurationMetadata: DesignStarters.onlyMaterial.metadata,
/// );
/// ```
final class DesignStarters {
  /// The Material starter when [material], the Cupertino one when
  /// [cupertino].
  const DesignStarters({this.material = false, this.cupertino = false});

  /// The starter an app of [appType] must have: Material's for
  /// `material`, Cupertino's for `cupertino`, none for the others.
  factory DesignStarters.of(String appType) => switch (appType) {
    'material' => onlyMaterial,
    'cupertino' => onlyCupertino,
    _ => none,
  };

  /// An app without a design library.
  static const none = DesignStarters();

  /// `spring_boot_starter_flutter_material` alone.
  static const onlyMaterial = DesignStarters(material: true);

  /// `spring_boot_starter_flutter_cupertino` alone.
  static const onlyCupertino = DesignStarters(cupertino: true);

  /// Both starters.
  static const both = DesignStarters(material: true, cupertino: true);

  /// Whether the app has the Material starter.
  final bool material;

  /// Whether the app has the Cupertino starter.
  final bool cupertino;

  /// The starters' modules.
  List<BeanModule> get autoConfigurations => [
    if (material) springBootStarterFlutterMaterialAutoConfiguration,
    if (cupertino) springBootStarterFlutterCupertinoAutoConfiguration,
  ];

  /// The `@AutoConfigurationModule` of each module: its design among the
  /// factories, which the themes read before any bean exists.
  Map<BeanModule, AutoConfigurationModule> get metadata => {
    if (material)
      springBootStarterFlutterMaterialAutoConfiguration:
          const AutoConfigurationModule(factories: [MaterialThemeDesign()]),
    if (cupertino)
      springBootStarterFlutterCupertinoAutoConfiguration:
          const AutoConfigurationModule(factories: [CupertinoThemeDesign()]),
  };
}
