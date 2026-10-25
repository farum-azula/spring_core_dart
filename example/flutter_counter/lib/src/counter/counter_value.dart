import 'package:flutter/material.dart';
import 'package:flutter_counter/src/counter/counter.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The number: a `SpringStatelessWidget` gets the beans named in its type
/// as `beans` and rebuilds when one of them notifies (the `Counter` after
/// each tap).
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
