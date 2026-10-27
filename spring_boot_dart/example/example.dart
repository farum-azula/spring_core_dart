// A Spring Boot application in Dart: annotated classes, one annotation on
// main, and the generator writes the rest (example.spring.dart, from
// `dart run build_runner build`).
//
//   dart run example/example.dart
//   dart run example/example.dart --greeting.name=Ada
//   GREETING_NAME=Grace dart run example/example.dart

// An example: printing to the console is how it shows its result.
// ignore_for_file: avoid_print
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
/// `CommandLineRunner`.
@Component()
class GreetOnStartup implements CommandLineRunner {
  GreetOnStartup(this.greeter, this.properties);

  final Greeter greeter;
  final GreetingProperties properties;

  @override
  void run(List<String> args) {
    for (var i = 0; i < properties.times; i++) {
      print(greeter.greeting());
    }
  }
}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
