import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Makes a `ChangeNotifier` bean call `notifyListeners()` by itself after
/// its methods run, so the methods only change the state.
///
/// A state class that extends `ChangeNotifier` normally ends every method
/// with `notifyListeners()`, and a forgotten call leaves the screen stale.
/// With this annotation the bean's generated proxy makes the call instead.
/// On a method or setter it notifies after that one; on the class, after
/// every public method and setter (not the getters, nor the members of
/// `ChangeNotifier` and `Object`), except those named in [exclude].
///
/// Use it for a class that already extends `ChangeNotifier`; for a plain
/// class, [ChangeNotifierComponent] does the same and makes it a bean.
///
/// ```dart
/// // The basket's widgets update after add, clear and load.
/// @Component()
/// @BuildContextAccess()
/// @NotifyListeners()
/// class Basket extends ChangeNotifier {
///   final _items = <String>[];
///   int get count => _items.length;
///
///   void add(String isbn) => _items.add(isbn);   // listeners notified
///   void clear() => _items.clear();              // listeners notified
///
///   Future<void> load() async {                  // notified once the
///     _items.addAll(await api.basket());         // Future completes
///   }
/// }
/// ```
///
/// The listeners are notified also when the method throws (the state may
/// have changed before the error); for a method returning a `Future`, when
/// the future completes. Calls from inside the bean itself (`this.add(...)`)
/// go through the proxy too when it is a subclass proxy (a class with
/// private members); otherwise only calls from outside notify. Like every
/// proxy feature it works only on the bean the container hands out, not
/// on an instance created by hand.
///
/// Spring has no counterpart; like `@Transactional`, it is advice around
/// the bean's methods.
class NotifyListeners {
  /// Marks a method or setter, or, on a class, every public method and
  /// setter but the ones named in [exclude].
  const NotifyListeners({this.exclude = const []});

  /// On the class: the names of the methods and setters that do not
  /// notify, such as a method that only reads, or a batch that notifies
  /// once itself. Empty by default; ignored on a method.
  final List<String> exclude;
}

/// Declares a state bean that widgets can listen to, from a plain class:
/// no `extends ChangeNotifier`, no `notifyListeners()` calls.
///
/// It is the usual way to keep app state (a basket, a counter, a selected
/// language) outside the widgets. It is a `@Component`, so the class
/// becomes a bean, and its generated proxy mixes `ChangeNotifier` in and
/// notifies after every public method and setter, except those named in
/// [exclude]. A `SpringStatelessWidget` or `SpringState` that reads the
/// bean's state in `build` rebuilds after each such call; a widget that
/// only calls its methods does not.
///
/// ```dart
/// // The counter is shared by the button that changes it and the text.
/// @ChangeNotifierComponent(exclude: ['reset'])
/// class Counter {
///   int value = 0;
///   void increment() => value++;   // listeners notified
///   void reset() => value = 0;     // excluded: not notified
/// }
///
/// class CounterValue extends SpringStatelessWidget<(Counter,)> {
///   @override
///   Widget build(BuildContext context) {
///     final (counter,) = beans;
///     return Text('${counter.value}');   // rebuilt on every notification
///   }
/// }
/// ```
///
/// The class itself is no `Listenable` (generated code cannot give it a
/// superclass); the bean the container hands out is. `SpringStatelessWidget`
/// and `SpringState` subscribe to the beans of their record by themselves;
/// elsewhere [listenableOf] gives the `Listenable`
/// (`ListenableBuilder(listenable: listenableOf(counter), ...)`). The class
/// must not declare `ChangeNotifier`'s members (`addListener`, `dispose`,
/// ...); the build checks that, and that every name in [exclude] is one of
/// its methods, setters or fields.
///
/// Spring has no counterpart; like `@Transactional`, it is advice around
/// the bean's methods.
class ChangeNotifierComponent extends Component {
  /// A bean named `name` (by default the class name in lowerCamelCase)
  /// whose methods and setters notify, but the ones in [exclude].
  const ChangeNotifierComponent({String? name, this.exclude = const []})
    : super(name);

  /// The names of the methods and setters that do not notify, such as a
  /// method that only reads; empty by default.
  final List<String> exclude;
}

/// Returns [bean] typed as a `Listenable`, for Flutter widgets that take
/// one, such as `ListenableBuilder` or `AnimatedBuilder`.
///
/// A `@ChangeNotifierComponent` class is not a `Listenable` to the
/// compiler, although the bean the container hands out (its proxy) is.
/// This function bridges the two. It also accepts any bean that extends
/// `ChangeNotifier`. Throws an `ArgumentError` for any other object, such
/// as an instance created by hand instead of taken from the container.
/// Spring widgets do not need it: they listen to their beans by
/// themselves.
///
/// ```dart
/// // A plain widget that shows the counter and follows its changes.
/// ListenableBuilder(
///   listenable: listenableOf(context.counter),
///   builder: (context, _) => Text('${context.counter.value}'),
/// );
/// ```
Listenable listenableOf(Object bean) => bean is Listenable
    ? bean
    : throw ArgumentError.value(
        bean,
        'bean',
        'is no Listenable: a @ChangeNotifierComponent bean is one only as '
            'the container hands it out (its proxy), and a bean without '
            '@ChangeNotifierComponent must extend ChangeNotifier',
      );

/// The rule that picks the bean members after which listeners are
/// notified: methods and setters marked [NotifyListeners], or, when the
/// class carries [NotifyListeners] or [ChangeNotifierComponent], every
/// public method and setter except getters, the excluded names and the
/// members of `ChangeNotifier`, `Listenable` and `Object`.
///
/// The starter pairs it with [NotifyListenersInterceptor]; applications
/// do not use it.
final class NotifyListenersPointcut implements AnnotationPointcut {
  /// The pointcut; it has no settings.
  const NotifyListenersPointcut();

  static const _notifierMembers = {
    'addListener',
    'removeListener',
    'dispose',
    'notifyListeners',
    'hasListeners',
    'toString',
    'noSuchMethod',
    '==',
  };

  @override
  bool matches(MethodSignature signature, String beanName) {
    if (signature.kind == MemberKind.getter) {
      return false;
    }
    if (signature.mergedAnnotations.any((a) => a is NotifyListeners)) {
      return true;
    }
    if (_notifierMembers.contains(signature.name)) {
      return false;
    }
    for (final annotation in signature.targetAnnotations) {
      final exclude = switch (annotation) {
        NotifyListeners(:final exclude) => exclude,
        ChangeNotifierComponent(:final exclude) => exclude,
        _ => null,
      };
      if (exclude != null) {
        return !exclude.contains(signature.name);
      }
    }
    return false;
  }

  @override
  String toString() => 'NotifyListenersPointcut';
}

/// The advice behind [NotifyListeners] and [ChangeNotifierComponent]: it
/// runs the call, then `notifyListeners()` of the bean.
///
/// For a returned `Future` it notifies when the future completes, and it
/// also notifies after an error. It throws a `StateError` when the bean is
/// no `ChangeNotifier`. The starter registers it; applications do not use
/// it.
final class NotifyListenersInterceptor implements MethodInterceptor {
  /// The interceptor; it has no settings.
  const NotifyListenersInterceptor();

  @override
  Object? invoke(MethodInvocation invocation) {
    // A @ChangeNotifierComponent's proxy is the ChangeNotifier the
    // listeners subscribed to; a bean extending ChangeNotifier is one itself.
    final proxy = invocation.proxy;
    final notifier = proxy is ChangeNotifier ? proxy : invocation.target;
    if (notifier is! ChangeNotifier) {
      throw StateError(
        '@NotifyListeners on ${invocation.signature.targetType}.'
        '${invocation.signature.name}: the bean is no ChangeNotifier.',
      );
    }
    final Object? result;
    try {
      result = invocation.proceed();
    } catch (_) {
      _notify(notifier);
      rethrow;
    }
    if (result is Future<Object?>) {
      return result.whenComplete(() => _notify(notifier));
    }
    _notify(notifier);
    return result;
  }

  static void _notify(ChangeNotifier notifier) =>
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      notifier.notifyListeners();

  @override
  String toString() => 'NotifyListenersInterceptor';
}
