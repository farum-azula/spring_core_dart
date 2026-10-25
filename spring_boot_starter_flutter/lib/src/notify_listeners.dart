import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Calls `notifyListeners()` of a `ChangeNotifier` bean after the method
/// runs, through the bean's AOP proxy, so the method only changes the
/// state.
///
/// On a method: after that method. On the class: after every public method
/// and setter of the bean (not the getters, nor `ChangeNotifier`'s and
/// `Object`'s own members).
///
/// ```dart
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
/// private members); otherwise only calls from outside notify.
///
/// Spring has no counterpart; like `@Transactional`, it is advice around
/// the bean's methods.
class NotifyListeners {
  /// Marks a method, or every public method and setter of a class but the
  /// ones named in [exclude].
  const NotifyListeners({this.exclude = const []});

  /// On the class: the methods and setters that do not notify (a method
  /// that only reads, a batch that notifies once itself).
  final List<String> exclude;
}

/// A `ChangeNotifier` bean without `extends ChangeNotifier`: a stereotype
/// (a `@Component`) whose AOP proxy mixes `ChangeNotifier` in and calls
/// `notifyListeners()` after every public method and setter, except the
/// ones named in [exclude] — `@Component` and `@NotifyListeners` in one.
///
/// ```dart
/// @ChangeNotifierComponent(exclude: ['reset'])
/// class Counter {
///   int value = 0;
///   void increment() => value++;   // listeners notified
///   void reset() => value = 0;     // excluded: not notified
/// }
///
/// class CounterValue extends SpringStatelessWidget<(Counter,)> {
///   @override
///   Widget build(BuildContext context, (Counter,) beans) =>
///       Text('${beans.$1.value}');   // rebuilt on every notification
/// }
/// ```
///
/// The class itself is no `Listenable` (Dart cannot add a superclass to it);
/// the bean the container hands out is. `SpringStatelessWidget` and
/// `SpringState` subscribe to the `Listenable` beans of their record by
/// themselves; elsewhere `listenableOf(bean)` gives the `Listenable`
/// (`ListenableBuilder(listenable: listenableOf(counter), ...)`). The class
/// must not declare `ChangeNotifier`'s members (`addListener`, `dispose`,
/// ...); the build checks it, and that every name in [exclude] is one of
/// its methods or setters.
class ChangeNotifierComponent extends Component {
  /// A bean named `name` (default: the class name, lowerCamelCase) whose
  /// methods and setters notify, but the ones in [exclude].
  const ChangeNotifierComponent({String? name, this.exclude = const []})
    : super(name);

  /// The methods and setters that do not notify.
  final List<String> exclude;
}

/// [bean] as a `Listenable`: a `@ChangeNotifierComponent` bean (the
/// container hands out its proxy, which is a `ChangeNotifier`) or any bean
/// extending `ChangeNotifier`. Throws an `ArgumentError` for any other
/// object.
///
/// ```dart
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

/// Matches the members [NotifyListeners] applies to: methods and setters
/// carrying it, or, when the class carries it (or
/// [ChangeNotifierComponent]), every public method and setter except the
/// getters, the excluded names and the members of `ChangeNotifier`,
/// `Listenable` and `Object`.
final class NotifyListenersPointcut implements AnnotationPointcut {
  /// Creates the pointcut.
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

/// Runs the call, then `notifyListeners()` of the bean (when a returned
/// `Future` completes; also after an error).
final class NotifyListenersInterceptor implements MethodInterceptor {
  /// Creates the interceptor.
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
