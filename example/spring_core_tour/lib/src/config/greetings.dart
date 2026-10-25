// Collection injection through a primary constructor (Dart 3.13).
//
// Spring (Java): a constructor parameter of type List<T> receives every bean
// of type T. Here the field is declared in the class body and the primary
// constructor only names it (`this._greetings`).

import 'package:spring_core_dart/spring_core_dart.dart';

@Configuration()
class GreetingConfig {
  @Bean(name: 'helloGreeting')
  String helloGreeting() => 'hello';

  @Bean(name: 'hiGreeting')
  String hiGreeting() => 'hi';
}

/// Receives every `String` bean: `r.optionalDependencyList<String>()`.
@Service()
class Greeter(this._greetings) {
  final List<String> _greetings;

  List<String> get greetings => List.unmodifiable(_greetings);
}
