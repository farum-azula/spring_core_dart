// The application context runner of the tests: the web and actuator
// starters with the test application, in the mock web environment.
import 'dart:convert';

import 'package:spring_boot_starter_actuator/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/app.dart';

/// The runner of the test application with [properties].
ApplicationContextRunner actuatorRunner([
  List<String> properties = const [],
]) => const ApplicationContextRunner()
    .withUserConfiguration(actuatorTestBeans)
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
    .withAutoConfiguration(springBootStarterWebAutoConfiguration)
    .withAutoConfiguration(springBootStarterActuatorAutoConfiguration)
    .withPropertyValues([
      'spring.test.web-environment=mock',
      'logging.level.root=warn',
      ...properties,
    ]);

/// Runs the test application with [properties] and gives [body] its
/// MockMvc.
Future<void> withActuator(
  Future<void> Function(MockMvc mvc, AssertableApplicationContext context)
  body, {
  List<String> properties = const [],
  ApplicationContextRunner Function(ApplicationContextRunner runner)? setUp,
}) {
  var runner = actuatorRunner(properties);
  if (setUp != null) {
    runner = setUp(runner);
  }
  return runner.runAsync((context) async {
    expect(context.startupFailure, isNull);
    await body(MockMvc.of(context.context), context);
  });
}

/// The JSON body of [result].
Object? jsonOf(MvcResult result) => jsonDecode(result.response.bodyText);
