import 'package:spring_boot_starter_flutter_material/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

/// An application with the Flutter starter's and this starter's
/// auto-configuration, as the generator writes it: the module's factories
/// (the Material design) with it.
SpringApplication application({
  Map<String, String> properties = const {},
  Map<String, String> files = const {},
  List<BeanDefinition<Object>> beans = const [],
}) => SpringApplication(
  [
    BeanModule(
      'test',
      beans,
      resources: {
        if (properties.isNotEmpty)
          'application.properties': EmbeddedResource.text(
            [
              for (final MapEntry(:key, :value) in properties.entries)
                '$key=$value',
            ].join('\n'),
          ),
        for (final MapEntry(:key, :value) in files.entries)
          key: EmbeddedResource.text(value),
      },
    ),
  ],
  autoConfigurations: [
    springBootStarterFlutterAutoConfiguration,
    springBootStarterFlutterMaterialAutoConfiguration,
  ],
  autoConfigurationMetadata: {
    springBootStarterFlutterMaterialAutoConfiguration:
        const AutoConfigurationModule(factories: [MaterialThemeDesign()]),
  },
  bannerMode: BannerMode.off,
);
