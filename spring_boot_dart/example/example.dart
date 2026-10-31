// A Spring Boot application in Dart: annotated classes, one annotation on
// main, and the generator writes the rest (example.spring.dart, from
// `dart run build_runner build`).
//
//   dart run example/example.dart
//   dart run example/example.dart --greeting.name=Ada
//   GREETING_NAME=Grace dart run example/example.dart

import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'example.spring.dart';

/// The `greeting.*` properties: command line, environment variables,
/// `application.properties` / `application.yml`.
@ConfigurationProperties('greeting')
class GreetingProperties {
  /// Who to greet.
  String name = 'World';

  /// How many times.
  int times = 1;
}

/// A service with its dependency in the constructor.
@Service()
class Greeter {
  Greeter(this.properties);

  final GreetingProperties properties;

  String greeting() => 'Hello, ${properties.name}!';
}

/// Runs once the application has started, like Spring's
/// `CommandLineRunner`. `@Log` gives it a `log` (a logger named
/// `greeting`); it shows at info because `main` sets that level.
@Component()
@Log(topic: 'greeting')
class GreetOnStartup implements CommandLineRunner {
  GreetOnStartup(this.greeter, this.properties);

  final Greeter greeter;
  final GreetingProperties properties;

  @override
  void run(List<String> args) {
    for (var i = 0; i < properties.times; i++) {
      log.info(greeter.greeting());
    }
  }
}

/// `--logging.level.greeting=warn` silences the example's own lines.
@SpringBootApplication()
void main(List<String> args) => springApplication.run(args);
