// The Flutter counter on spring_boot_starter_flutter, in one file.
//
// In an application the generator writes the beans: annotate the classes
// (`@SpringBootApplication()` on main, `@ChangeNotifierComponent()` on
// Counter) and run `dart run build_runner build` — see README.md. Here the
// bean module is written by hand, so the example runs without code
// generation.
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The count: state in a bean instead of a `State`, so any widget (and any
/// service) can read and change it.
class Counter extends ChangeNotifier {
  int _value = 0;

  /// The current count.
  int get value => _value;

  /// Adds one and tells the listeners.
  void increment() {
    _value++;
    notifyListeners();
  }
}

/// What the generator writes for the annotated classes of an application.
SpringApplication application() => SpringApplication([
  BeanModule('example', [
    BeanDefinition<Counter>(
      name: 'counter',
      types: const [Counter],
      create: (_) => Counter(),
    ),
  ]),
]);

void main() => runApp(
  // Starts the application (a splash screen meanwhile, a report when it
  // fails) and gives its beans to every widget below.
  SpringApplicationWidget(
    application: application,
    child: const MaterialApp(home: CounterPage()),
  ),
);

/// The page of the template; stateless, the count is the `Counter` bean.
class CounterPage extends StatelessWidget {
  /// Creates the page.
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Any bean by type.
    final counter = context.bean<Counter>();
    return Scaffold(
      appBar: AppBar(title: const Text('spring_boot_starter_flutter')),
      body: Center(
        child: ListenableBuilder(
          listenable: counter,
          builder: (context, _) => Text(
            '${counter.value}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: counter.increment,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
