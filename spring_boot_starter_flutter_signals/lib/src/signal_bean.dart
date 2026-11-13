import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';

/// The followed state of one bean: its `@Signal` fields and `@Computed`
/// values as they are first used, and its running `@Effect` methods.
final class SignalBean {
  /// The state of [bean], shown as [label] (its class's name).
  SignalBean(this.bean, this.label);

  /// The bean (its proxy: what the container hands out).
  final Object bean;

  /// The bean's class, for the names of its members (`Basket.items`).
  final String label;

  /// The members used so far, by name.
  final Map<String, SignalMember> members = {};

  /// The `@Effect` methods, by name, with how often each ran.
  final Map<String, int> effectRuns = {};

  final List<void Function()> _stops = [];
  bool _closed = false;

  /// Whether the bean is being destroyed: nothing is followed any more,
  /// and its members read and write the bean's own fields.
  bool get closed => _closed;

  /// Keeps [stop], which ends a running effect.
  void addEffect(void Function() stop) => _stops.add(stop);

  /// Ends the effects and frees every member. The bean's own
  /// `@PreDestroy` methods run after this and still read its fields.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final stop in _stops) {
      stop();
    }
    _stops.clear();
    for (final member in members.values) {
      member.dispose();
    }
  }
}

/// Every bean with followed state that lives now: what the interceptor
/// and the debug tab share. It notifies its listeners when a bean comes
/// or goes, not for a change of state.
final class SignalBeans extends ChangeNotifier {
  final Expando<SignalBean> _states = Expando('signal beans');

  // Held weakly: the container never destroys a prototype, so its state
  // must go when the last reference to the bean does.
  final List<WeakReference<SignalBean>> _live = [];

  /// The names of the bean definitions with a `@Signal`, `@Computed` or
  /// `@Effect` member, found before any bean is made.
  final Set<String> names = {};

  /// The beans with followed state, in the order they were made. A
  /// prototype nobody holds any more is no longer among them.
  Iterable<SignalBean> get live {
    _live.removeWhere((reference) => reference.target == null);
    return [for (final reference in _live) ?reference.target];
  }

  /// The state of [bean], made on first use.
  SignalBean of(Object bean, String label) {
    final existing = _states[bean];
    if (existing != null) {
      return existing;
    }
    final state = _states[bean] = SignalBean(bean, label);
    _live.add(WeakReference(state));
    _changed();
    return state;
  }

  /// The state of [bean], `null` when it has none.
  SignalBean? find(Object bean) => _states[bean];

  /// Ends the state of [bean] when it is destroyed.
  void close(Object bean) {
    final state = _states[bean];
    if (state == null) {
      return;
    }
    state.close();
    _live.removeWhere(
      (reference) => reference.target == null || reference.target == state,
    );
    _changed();
  }

  bool _scheduled = false;

  // Beans come and go while widgets are built: the listeners hear after.
  void _changed() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    Future.microtask(() {
      _scheduled = false;
      notifyListeners();
    });
  }
}
