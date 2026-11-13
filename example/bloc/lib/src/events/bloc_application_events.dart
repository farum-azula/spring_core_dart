import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// Something a bloc did, as an application event: heard with
/// `@EventListener` by any bean, like the app's other events.
sealed class BlocApplicationEvent extends ApplicationEvent {
  /// What [bloc] did.
  BlocApplicationEvent(BlocBase<Object?> super.bloc);

  /// The bloc (or cubit).
  BlocBase<Object?> get bloc => source as BlocBase<Object?>;
}

/// An event was added to a Bloc (a Cubit has none).
final class BlocEventAdded extends BlocApplicationEvent {
  /// [event] added to [bloc].
  BlocEventAdded(super.bloc, this.event);

  /// The bloc's own event.
  final Object? event;

  @override
  String get eventName => 'BlocEventAdded';
}

/// A bloc or a cubit went from one state to another.
final class BlocStateChanged extends BlocApplicationEvent {
  /// [bloc] went from [current] to [next].
  BlocStateChanged(super.bloc, {required this.current, required this.next});

  /// The state before.
  final Object? current;

  /// The state after.
  final Object? next;

  @override
  String get eventName => 'BlocStateChanged';
}

/// A bloc reported an error (`addError`, or one thrown in a handler).
final class BlocFailed extends BlocApplicationEvent {
  /// [bloc] failed with [error].
  BlocFailed(super.bloc, this.error, this.stackTrace);

  /// What was thrown.
  final Object error;

  /// Where.
  final StackTrace stackTrace;

  @override
  String get eventName => 'BlocFailed';
}
