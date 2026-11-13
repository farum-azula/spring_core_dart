import 'package:bloc_showcase/src/blocs/counter_cubit.dart';
import 'package:bloc_showcase/src/events/bloc_application_events.dart';
import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// Only the changes of the counter.
bool ofCounter(BlocStateChanged change) => change.bloc is CounterCubit;

/// What the blocs of the app did, heard as application events: this bean
/// subscribes to no bloc and knows none but the counter by name.
@Service()
class Journal extends ChangeNotifier {
  final List<String> _lines = [];

  /// How often the counter changed.
  int counterChanges = 0;

  /// The last lines, newest first.
  List<String> get lines => List.unmodifiable(_lines.reversed.take(8));

  /// Every event added to any Bloc.
  @EventListener()
  void onEvent(BlocEventAdded added) =>
      _write('${added.bloc} ← ${added.event}');

  /// Every change of state, of a Bloc or a Cubit.
  @EventListener()
  void onChange(BlocStateChanged change) => _write(
    '${change.bloc}: ${change.current} → ${change.next}',
  );

  /// Only the counter's, by a condition.
  @EventListener(condition: ofCounter)
  void onCounter(BlocStateChanged change) => counterChanges++;

  /// An error of any bloc.
  @EventListener()
  void onFailure(BlocFailed failed) =>
      _write('${failed.bloc} failed: ${failed.error}');

  void _write(String line) {
    _lines.add(line);
    notifyListeners();
  }
}
