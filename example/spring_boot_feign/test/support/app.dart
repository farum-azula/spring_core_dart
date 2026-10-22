// The example application as a context without its runners, for unit
// tests: the generated modules and auto-configurations, and
// lib/resources/application.properties read like at startup (Spring's
// ConfigDataApplicationContextInitializer).
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import '../../bin/main.beans.dart';

/// The application's beans (runners are beans, but nothing calls them).
ApplicationContextRunner appContext() {
  final application = springApplication;
  var runner = const ApplicationContextRunner().withInitializer(
    (context) =>
        ConfigDataEnvironment(context.environment).processAndApplySync(),
  );
  for (final module in application.modules) {
    runner = runner.withUserConfiguration(module);
  }
  for (final module in application.autoConfigurations) {
    runner = runner.withAutoConfiguration(module);
  }
  return runner;
}
