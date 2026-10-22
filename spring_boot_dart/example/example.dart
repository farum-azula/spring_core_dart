// With spring_core_dart_generator the whole entry point is:
//
//   @SpringBootApplication()
//   void main(List<String> args) => runApplication(args);
//
// and beans are plain annotated classes. This example writes the bean
// definitions by hand, so it runs without code generation:
//
//   dart run example/example.dart --greeting.name=Ada
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Bound from `greeting.*` properties (command line, environment, config
/// files).
class GreetingProperties {
  String name = 'World';
}

class Greeter implements CommandLineRunner {
  Greeter(this.properties);

  final GreetingProperties properties;

  @override
  void run(List<String> args) => print('Hello, ${properties.name}!');
}

final appModule = BeanModule('app', [
  BeanDefinition<GreetingProperties>(
    name: 'greetingProperties',
    create: (_) => GreetingProperties(),
    inject: (bean, r) => bean.name = r.value<String>(r'${greeting.name:World}'),
  ),
  BeanDefinition<Greeter>(
    name: 'greeter',
    types: const [Greeter, CommandLineRunner],
    create: (r) => Greeter(r.dependency<GreetingProperties>()),
  ),
]);

void main(List<String> args) {
  final context = SpringApplication([appModule]).run(args);
  context.close();
}
