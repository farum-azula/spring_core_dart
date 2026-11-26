import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugGraphPane;
import 'package:spring_boot_starter_flutter_signals/src/debug/graph/signals_graph_layer.dart';

/// The debug console's `signals` pane (`signalsPane`, order 20): the
/// console's application graph preset to the signals layer alone
/// ([SignalsGraphLayer]), compact, nearly opaque. A field that changes
/// flashes and a pulse runs to its readers; the scope, "live only" and
/// the bean lanes as in the `graph` pane.
///
/// It is kept beside the `graph` pane so that
/// `spring.flutter.debug.console.panes: [signals]` and `shown-panes:
/// [signals]` go on working, and the signals stay apart from the layers
/// the `graph` pane gathers. It collects only while it shows ([start]);
/// hidden it is not built and nothing listens. In the build only when
/// `spring.flutter.debug.console.panes` names `signals` or holds `*`.
final class SignalsPane extends DebugGraphPane {
  /// The pane over [layer].
  SignalsPane(this.layer) : super([layer], title: 'Signals');

  /// The signals layer.
  final SignalsGraphLayer layer;
}
