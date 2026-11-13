import 'package:bloc_showcase/src/blocs/closed_with_bean.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// A Cubit for the whole app: `@Component()` makes it a bean, one for the
/// application (a singleton), so every screen that asks for it gets the
/// same count. No `BlocProvider` puts it into the tree.
///
/// It is closed with the application by `ClosedWithBean`: the container
/// does not call a component's `close` by itself.
@Component()
class CounterCubit extends Cubit<int> with ClosedWithBean<int> {
  /// The counter, at zero.
  CounterCubit() : super(0);

  /// One more.
  void increment() => emit(state + 1);

  /// One less.
  void decrement() => emit(state - 1);

  // A release build shortens class names: the journal shows this one.
  @override
  String toString() => 'CounterCubit';
}
