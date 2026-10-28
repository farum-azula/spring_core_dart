import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/notify_listeners.dart';

/// The rule that picks the bean members whose calls Spring widgets watch:
/// the public getters, methods and setters of a `@ChangeNotifierComponent`
/// class or of a class carrying `@NotifyListeners` (not the members of
/// `ChangeNotifier` and `Object`).
///
/// It exists so that a widget listens to a state bean only when it shows
/// the bean's state. With it, a `SpringStatelessWidget` or `SpringState`
/// subscribes to such a bean only when its `build` reads a getter or a
/// field; calling a method (`onPressed: counter.increment`) costs no
/// rebuilds. The starter pairs it with [BeanReadsInterceptor];
/// applications do not use it.
final class BeanReadsPointcut implements AnnotationPointcut {
  /// The pointcut; it has no settings.
  const BeanReadsPointcut();

  static const _objectMembers = {
    'addListener',
    'removeListener',
    'dispose',
    'notifyListeners',
    'hasListeners',
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
    '==',
  };

  @override
  bool matches(MethodSignature signature, String beanName) =>
      !_objectMembers.contains(signature.name) &&
      signature.targetAnnotations.any(
        (a) => a is ChangeNotifierComponent || a is NotifyListeners,
      );

  @override
  String toString() => 'BeanReadsPointcut';
}

/// The advice that reports each read of a state bean's getter or field to
/// the Spring widget being built, so the widget knows it shows that bean.
///
/// Reads made by the bean itself, inside its own methods and setters, are
/// not reported. The starter registers it; applications do not use it.
final class BeanReadsInterceptor implements MethodInterceptor {
  /// The interceptor; it has no settings.
  const BeanReadsInterceptor();

  @override
  Object? invoke(MethodInvocation invocation) {
    final bean = invocation.proxy;
    if (invocation.signature.kind == MemberKind.getter) {
      BeanReads.read(bean);
      return invocation.proceed();
    }
    // Inside a method the bean reads itself: no widget's read.
    BeanReads._inside[bean] = (BeanReads._inside[bean] ?? 0) + 1;
    try {
      return invocation.proceed();
    } finally {
      final depth = BeanReads._inside[bean]! - 1;
      BeanReads._inside[bean] = depth == 0 ? null : depth;
    }
  }

  @override
  String toString() => 'BeanReadsInterceptor';
}

/// The listening of one Spring widget: which of its `Listenable` beans it
/// subscribes to, and so which bean changes rebuild it.
///
/// A bean whose reads are tracked (its proxy has [BeanReadsInterceptor])
/// is subscribed to when the widget read it in its latest build, or for
/// good once it was read outside any build of a widget holding it (in a
/// `ListView` item builder, a callback): the widget cannot tell then
/// whether its UI shows it, so it keeps listening rather than show stale
/// data. Every other `Listenable` bean (a plain `ChangeNotifier` bean) is
/// subscribed to always.
///
/// The Spring widgets use it internally; it is not exported.
final class BeanReads {
  /// The listening of a widget that rebuilds by calling [onChange].
  BeanReads(this.onChange);

  /// Called when a subscribed bean notifies; it marks the widget for a
  /// rebuild.
  final VoidCallback onChange;

  static BeanReads? _building;
  static final _holders = Expando<Set<BeanReads>>('BeanReads holders');
  static final _inside = Expando<int>('BeanReads methods running');

  List<Listenable> _beans = const [];
  final _tracked = <Listenable>{};
  final _read = <Listenable>{};
  final _always = <Listenable>{};
  final _subscribed = <Listenable>{};

  /// Records a read of [bean]'s state. During the build of a widget that
  /// holds [bean], the read counts for that widget. Elsewhere, unless it
  /// happens inside [bean]'s own methods, it comes from an unknown part of
  /// the UI, so every widget holding [bean] listens to it from then on.
  static void read(Object bean) {
    if (bean is! Listenable) {
      return;
    }
    final building = _building;
    if (building != null && building._tracked.contains(bean)) {
      building._read.add(bean);
      return;
    }
    if (_inside[bean] != null) {
      return;
    }
    for (final holder in [...?_holders[bean]]) {
      if (holder._always.add(bean)) {
        holder._subscribe(bean);
      }
    }
  }

  /// Whether reads of [bean] are tracked, that is whether its proxy runs
  /// [BeanReadsInterceptor].
  static bool _isTracked(Object bean) => switch (bean) {
    final Advised advised => advised.aopAdvisors.any(
      (a) => a.advice is BeanReadsInterceptor,
    ),
    _ => false,
  };

  /// Sets the beans of the widget's record; only the `Listenable` ones
  /// matter. Untracked ones are subscribed to at once. The same beans as
  /// before change nothing; other beans drop every earlier subscription.
  void setBeans(List<Object?> beans) {
    final listenables = [
      for (final bean in beans)
        if (bean is Listenable) bean,
    ];
    if (_same(listenables)) {
      return;
    }
    dispose();
    _beans = listenables;
    for (final bean in listenables) {
      if (_isTracked(bean)) {
        _tracked.add(bean);
        (_holders[bean] ??= {}).add(this);
      } else {
        _always.add(bean);
        _subscribe(bean);
      }
    }
  }

  /// Runs [build] and returns its result, noting the reads of the tracked
  /// beans. Afterwards the widget listens to the beans read (and to those
  /// read outside a build earlier) and stops listening to the others.
  T track<T>(T Function() build) {
    final previous = _building;
    _building = this;
    _read.clear();
    try {
      return build();
    } finally {
      _building = previous;
      for (final bean in _tracked) {
        if (_read.contains(bean) || _always.contains(bean)) {
          _subscribe(bean);
        } else if (_subscribed.remove(bean)) {
          bean.removeListener(onChange);
        }
      }
    }
  }

  void _subscribe(Listenable bean) {
    if (_subscribed.add(bean)) {
      bean.addListener(onChange);
    }
  }

  bool _same(List<Listenable> other) =>
      other.length == _beans.length &&
      [for (var i = 0; i < other.length; i++) i]
          .every((i) => identical(other[i], _beans[i]));

  /// Stops listening to every bean and forgets them; called when the
  /// widget goes away or gets other beans.
  void dispose() {
    for (final bean in _subscribed) {
      bean.removeListener(onChange);
    }
    for (final bean in _tracked) {
      _holders[bean]?.remove(this);
    }
    _subscribed.clear();
    _tracked.clear();
    _read.clear();
    _always.clear();
    _beans = const [];
  }
}
