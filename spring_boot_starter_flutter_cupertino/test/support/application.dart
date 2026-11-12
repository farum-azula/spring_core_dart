import 'package:spring_boot_starter_flutter_cupertino/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

/// An application with the Flutter and Cupertino starters, as the
/// generator writes one: [properties] are its `application.properties`,
/// [beans] its own beans. Without [autoConfiguration] it has neither
/// starter's beans nor the Cupertino design.
SpringApplication application({
  Map<String, String> properties = const {},
  List<BeanDefinition<Object>> beans = const [],
  bool autoConfiguration = true,
}) => SpringApplication(
  [
    BeanModule(
      'test',
      beans,
      resources: {
        'application.properties': EmbeddedResource.text(
          [
            // A widget test has no directories to keep the theme chosen
            // in, and its output is the tests' own.
            'spring.flutter.theme.remember=false',
            'logging.level.root=WARN',
            for (final MapEntry(:key, :value) in properties.entries)
              '$key=$value',
          ].join('\n'),
        ),
      },
    ),
  ],
  autoConfigurations: [
    if (autoConfiguration) ...[
      springBootStarterFlutterAutoConfiguration,
      springBootStarterFlutterCupertinoAutoConfiguration,
    ],
  ],
  autoConfigurationMetadata: {
    if (autoConfiguration)
      springBootStarterFlutterCupertinoAutoConfiguration:
          const AutoConfigurationModule(factories: [CupertinoThemeDesign()]),
  },
  bannerMode: BannerMode.off,
);
