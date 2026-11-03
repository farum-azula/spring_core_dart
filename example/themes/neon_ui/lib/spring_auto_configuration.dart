/// The auto-configuration of neon_ui: it embeds `lib/resources/` (the theme
/// `themes/neon.yml`) so an app imports it with
/// `spring.config.import: resources:themes/neon.yml`, and it generates the
/// typed theme keys of the library (`lib/spring_gen/theme.spring.dart`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'spring_gen/spring_auto_configuration.spring.dart';

export 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';

@ComponentScan()
@AutoConfigurationModule()
final BeanModule neonUiAutoConfiguration = $neonUiAutoConfiguration;
