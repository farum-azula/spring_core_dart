// The Flutter counter as a Spring Boot application: the count is a bean,
// widgets get beans by type, and the generator writes the rest
// (example.spring.dart, from `dart run build_runner build`).
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'example.spring.dart';

/// The count: state in a bean instead of a `State`, so any widget (and any
/// service) can read and change it. The generator makes it a
/// `ChangeNotifier` that notifies after every method.
@ChangeNotifierComponent()
class Counter {
  int _value = 0;

  /// The current count.
  int get value => _value;

  /// Adds one.
  void increment() => _value++;
}

@SpringBootApplication()
void main() => runApp(
  // Starts the application (a splash screen meanwhile, a report when it
  // fails) and gives its beans to every widget below.
  SpringApplicationWidget(
    application: () => springApplication,
    child: const MaterialApp(home: CounterPage()),
  ),
);

/// The page of the template, stateless: the count is the `Counter` bean.
class CounterPage extends SpringStatelessWidget<(Counter,)> {
  /// Creates the page.
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (counter,) = beans;
    return Scaffold(
      appBar: AppBar(title: const Text('spring_boot_starter_flutter')),
      body: const Center(child: CounterText()),
      // Only calls a method: a tap does not rebuild the page.
      floatingActionButton: FloatingActionButton(
        onPressed: counter.increment,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Reads `counter.value`, so it rebuilds after every increment.
class CounterText extends SpringStatelessWidget<(Counter,)> {
  /// Creates the text.
  const CounterText({super.key});

  @override
  Widget build(BuildContext context) {
    final (counter,) = beans;
    return Text(
      '${counter.value}',
      style: Theme.of(context).textTheme.headlineMedium,
    );
  }
}
