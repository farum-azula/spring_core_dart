import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/notify_listeners.dart';

/// Matches the members of the beans whose reads Spring widgets track: the
/// public getters, methods and setters of a `@ChangeNotifierComponent`
/// class or of a class carrying `@NotifyListeners` (not the members of
/// `ChangeNotifier` and `Object`).
///
/// With it a `SpringStatelessWidget` or `SpringState` subscribes to such a
/// bean only when it reads the bean's state (a getter, a field) in
/// `build`; calling its methods (`onPressed: counter.increment`) is free.
final class BeanReadsPointcut implements AnnotationPointcut {
  /// Creates the pointcut.
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

/// Tells the Spring widgets that a getter of a bean ran (a read of its
/// state); keeps a bean's own reads in its methods and setters out.
final class BeanReadsInterceptor implements MethodInterceptor {
  /// Creates the interceptor.
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

/// The `Listenable` beans of one Spring widget and which of them it is
/// subscribed to.
///
/// A bean whose reads are tracked (its proxy has [BeanReadsInterceptor])
/// is subscribed to when the widget read it in its latest build, or once
/// it was read outside any build of a widget holding it (a `ListView`
/// item builder, a callback): the widget cannot tell then whether its UI
/// shows it, so it keeps listening. Every other `Listenable` bean is
/// subscribed to always.
final class BeanReads {
  /// The reads of a widget that calls [onChange] to rebuild.
  BeanReads(this.onChange);

  /// Rebuilds the widget.
  final VoidCallback onChange;

  static BeanReads? _building;
  static final _holders = Expando<Set<BeanReads>>('BeanReads holders');
  static final _inside = Expando<int>('BeanReads methods running');

  List<Listenable> _beans = const [];
  final _tracked = <Listenable>{};
  final _read = <Listenable>{};
  final _always = <Listenable>{};
  final _subscribed = <Listenable>{};

  /// A read of [bean]'s state: by the widget building now when it holds
  /// [bean]; otherwise, but in [bean]'s own methods, by an unknown part
  /// of the UI, so every widget holding it keeps listening.
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

  /// Whether reads of [bean] are tracked: its proxy runs
  /// [BeanReadsInterceptor].
  static bool _isTracked(Object bean) => switch (bean) {
    final Advised advised => advised.aopAdvisors.any(
      (a) => a.advice is BeanReadsInterceptor,
    ),
    _ => false,
  };

  /// Sets the beans of the widget's record (the `Listenable` ones count).
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

  /// Runs [build], noting the reads of the tracked beans, then listens to
  /// the beans read (and to the untracked ones).
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

  /// Stops listening.
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
