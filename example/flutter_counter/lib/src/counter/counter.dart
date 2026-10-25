import 'package:flutter_counter/src/counter/counter_properties.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The count: state in a bean instead of a `State`, so any widget (and
/// any service) can read and change it.
///
/// `@ChangeNotifierComponent` makes it a bean whose proxy is a
/// `ChangeNotifier` and notifies the listeners after every method: no
/// `extends ChangeNotifier`, no `notifyListeners()`. `@BuildContextAccess`
/// generates the `context.counter` getter.
@ChangeNotifierComponent()
@BuildContextAccess()
class Counter {
  Counter(this._properties);

  final CounterProperties _properties;

  int _value = 0;

  /// The current count.
  int get value => _value;

  /// Adds `counter.step`.
  void increment() => _value += _properties.step;
}
