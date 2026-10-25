import 'package:flutter/material.dart';
import 'package:flutter_counter/src/counter/counter.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The number: a `SpringStatelessWidget` gets the beans named in its type
/// as `beans`; it reads `counter.value` in build, so it rebuilds after
/// each tap (and only it, not the page).
class CounterValue extends SpringStatelessWidget<(Counter,)> {
  const CounterValue({super.key});

  @override
  Widget build(BuildContext context) {
    final (counter,) = beans;
    return Text(
      '${counter.value}',
      style: Theme.of(context).textTheme.headlineMedium,
    );
  }
}
