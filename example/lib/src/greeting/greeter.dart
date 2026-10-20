import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/creation_log.dart';

abstract interface class Greeter {
  String greet(String name);
}

/// Picked when a [Greeter] is requested without a qualifier.
@Service()
@Primary()
@Order(2)
class EnglishGreeter implements Greeter {
  EnglishGreeter() {
    creationLog.add('englishGreeter');
  }

  @override
  String greet(String name) => 'Hello, $name';
}

/// Named `french`, also selectable with `@Qualifier('fr')`.
@Service('french')
@Qualifier('fr')
@Order(1)
class FrenchGreeter implements Greeter {
  @override
  String greet(String name) => 'Bonjour, $name';
}

/// JSR-330 style: `@Named` component with an `@Inject` constructor.
@Named('pirate')
@Description('Arr')
class PirateGreeter implements Greeter {
  @Inject()
  PirateGreeter.create();

  @override
  String greet(String name) => 'Ahoy, $name';
}
