import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// Closes a bloc when its bean is destroyed: with the application for a
/// bloc of the app, with the screen for one of the `route` scope. So no
/// widget calls `close()`, and no `BlocProvider` is there to do it.
mixin ClosedWithBean<S> on BlocBase<S> {
  /// Closes the bloc; called by the container.
  @PreDestroy()
  Future<void> closeWithBean() => close();
}
