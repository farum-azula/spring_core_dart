// A tour of spring_core_dart in a Spring Boot application: beans are
// annotated classes, dependencies come through constructors, settings
// through @Value, and events through @EventListener. The generator writes
// the bean definitions (main.spring.dart, from `dart run build_runner
// build`).
//
//   dart run example/main.dart
//   dart run example/main.dart '--greeting.punctuation=?'

// An example: printing to the console is how it shows its result.
// ignore_for_file: avoid_print
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.spring.dart';

/// Several implementations can stand behind one interface.
abstract interface class Greeter {
  String greet(String name);
}

@Component()
class EnglishGreeter implements Greeter {
  /// A setting, with its default after the colon.
  EnglishGreeter(@Value(r'${greeting.punctuation:!}') this.punctuation);

  final String punctuation;

  @override
  String greet(String name) => 'Hello, $name$punctuation';
}

/// An application event: any object.
class UserRegistered {
  const UserRegistered(this.name);

  final String name;
}

@Service()
class Registration {
  Registration(this.greeter, this.events);

  final Greeter greeter;
  final ApplicationEventPublisher events;

  String register(String name) {
    events.publishEvent(UserRegistered(name));
    return greeter.greet(name);
  }
}

@Component()
class WelcomeMail {
  @EventListener()
  void onRegistered(UserRegistered event) =>
      print('event: ${event.name} registered');
}

@Component()
class Tour implements CommandLineRunner {
  Tour(this.registration, @Value('#{2 * 21}') this.answer);

  final Registration registration;

  /// A SpEL expression, evaluated once.
  final int answer;

  @override
  void run(List<String> args) {
    print(registration.register('Ada'));
    print('answer: $answer');
  }
}

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
