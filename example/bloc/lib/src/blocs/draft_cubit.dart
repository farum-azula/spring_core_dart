import 'package:bloc_showcase/src/blocs/closed_with_bean.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// A Cubit of one screen: the title being typed on the "new book" screen.
/// With the `route` scope it is made when the screen opens and closed when
/// the screen does, so the next visit starts empty. No `BlocProvider`
/// around the screen, and no `close()` in a `dispose`.
@Component()
@Scope(NavigationScopes.route)
class DraftCubit extends Cubit<String> with ClosedWithBean<String> {
  /// An empty draft.
  DraftCubit() : super('');

  /// The title as typed so far.
  void type(String title) => emit(title);

  // A release build shortens class names: the journal shows this one.
  @override
  String toString() => 'DraftCubit';
}
