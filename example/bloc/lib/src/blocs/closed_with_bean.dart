import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// Closes a bloc when its bean is destroyed: with the application for a
/// bloc of the app, with the screen for one of the `route` scope. So no
/// widget calls `close()`, and no `BlocProvider` is there to do it.
mixin ClosedWithBean<S> on BlocBase<S> {
  /// Closes the bloc; called by the container. Not awaited: a screen's
  /// beans are destroyed at once when the screen closes, and a bloc
  /// refuses new events and states from the moment `close` is called.
  @PreDestroy()
  void closeWithBean() => unawaited(close());
}
