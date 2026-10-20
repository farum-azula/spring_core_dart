// A runnable tour of spring_core_dart without code generation.
//
// Real applications annotate classes (`@Service()`, `@Autowired()`,
// `@Value(...)`) and let `spring_core_dart_generator` write the bean
// definitions; here they are written by hand so the example runs with a
// plain `dart run example/main.dart`.

import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class Greeter {
  String greet(String name);
}

class EnglishGreeter implements Greeter {
  EnglishGreeter(this.punctuation);

  final String punctuation;

  @override
  String greet(String name) => 'Hello, $name$punctuation';
}

class UserRegistered {
  const UserRegistered(this.name);

  final String name;
}

class Registration {
  Registration(this.greeter, this.events);

  final Greeter greeter;
  final ApplicationEventPublisher events;

  String register(String name) {
    events.publishEvent(UserRegistered(name));
    return greeter.greet(name);
  }
}

/// What the generator would produce for the classes above.
final exampleBeans = BeanModule('example', [
  BeanDefinition<EnglishGreeter>(
    name: 'englishGreeter',
    types: const [EnglishGreeter, Greeter],
    dependencies: const [Dependency.value(r'${greeting.punctuation:!}')],
    create: (r) =>
        EnglishGreeter(r.value<String>(r'${greeting.punctuation:!}')),
  ),
  BeanDefinition<Registration>(
    name: 'registration',
    dependencies: const [Dependency(Greeter)],
    create: (r) => Registration(
      r.dependency<Greeter>(),
      r.dependency<ApplicationEventPublisher>(),
    ),
  ),
]);

Future<void> main() async {
  // Configuration comes from properties (here: an in-memory application
  // file; normally ./application.properties or ./config/).
  final environment = StandardEnvironment();
  await ConfigDataEnvironment(
    environment,
    resourceLoader: DefaultResourceLoader(
      protocolResolvers: [
        InMemoryProtocolResolver('memory:', {
          'application.properties': 'greeting.punctuation=?\napp.users=3',
        }),
      ],
    ),
    defaultLocations: const ['memory:/'],
  ).processAndApply();

  final context = ApplicationContext.run(
    [exampleBeans],
    environment: environment,
  )..addListener<UserRegistered>((e) => print('event: ${e.name} registered'));

  print(context.getBean<Registration>().register('Ada'));
  print('users: ${environment.getPropertyAs<int>('app.users')}');

  // SpEL over a map root.
  final total = SpelExpressionParser()
      .parseExpression('price * quantity')
      .getValue(StandardEvaluationContext({'price': 2, 'quantity': 21}));
  print('total: $total');

  context.close();
}
