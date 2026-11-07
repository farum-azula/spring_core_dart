import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/bound_properties.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_keys.dart';

/// The app's keyboard shortcuts: the keys of every action, from
/// `spring.flutter.shortcuts.<action>` or the `keys` of its `@Shortcut`,
/// and its handlers, the `@Shortcut` methods and `ShortcutHandler` beans.
/// The starter registers it and puts the keys above the app's navigator;
/// a widget reads it for a label (`ShortcutLabel`).
///
/// ```yaml
/// spring:
///   flutter:
///     shortcuts:
///       search.open: primary+k            # ⌘K on macOS, Ctrl+K elsewhere
///       navigation.back: [alt+left, primary+bracket-left]
///       help.show: char:?
/// ```
///
/// The keys are read by a chain of [ShortcutNotation]s: the app's
/// `ShortcutNotation` beans first, then [CharacterNotation] and
/// [KeyCombinationNotation]. A value no notation reads stops the start,
/// naming the property; two actions on the same keys are a warning.
///
/// An action's handlers are asked in their order (`@Shortcut(order:)`,
/// `Ordered`) until one handles the press; a `ShortcutHandlers` widget of
/// the focused screen is asked before them.
final class KeyboardShortcuts extends BeanPostProcessor
    implements BeanFactoryAware, SmartInitializingSingleton {
  /// The shortcuts of [environment]'s configuration.
  KeyboardShortcuts(this.environment);

  /// The prefix of the actions' keys.
  static const prefix = 'spring.flutter.shortcuts';

  static const _log = SpringLog(
    'spring_boot_starter_flutter.KeyboardShortcuts',
  );

  /// The configuration read.
  final ConfigurableEnvironment environment;

  BeanFactory? _factory;
  final _handlers = <String, List<(int, ShortcutHandler)>>{};
  final _defaults = <String, List<String>>{};
  final _bindings = <TargetPlatform, Map<String, List<ShortcutKeys>>>{};
  Map<String, List<String>>? _configured;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _factory = beanFactory;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    if (bean is ShortcutHandler) {
      _add(bean.action, bean is Ordered ? (bean as Ordered).order : 0, bean);
      if (bean is KeyedShortcutHandler && bean.keys.isNotEmpty) {
        _defaults.putIfAbsent(bean.action, () => bean.keys);
      }
    }
    final factory = _factory;
    if (factory is! BeanDefinitionRegistry ||
        !(factory as BeanDefinitionRegistry).containsBeanDefinition(beanName)) {
      return bean;
    }
    final definition = (factory as BeanDefinitionRegistry).getBeanDefinition(
      beanName,
    );
    for (final method in definition.annotatedMethods) {
      for (final shortcut in method.annotations.whereType<Shortcut>()) {
        final handler = _MethodHandler.of(bean, method, shortcut, definition);
        _add(shortcut.action, shortcut.order, handler);
        if (shortcut.keys.isNotEmpty) {
          _defaults.putIfAbsent(shortcut.action, () => shortcut.keys);
        }
      }
    }
    return bean;
  }

  void _add(String action, int order, ShortcutHandler handler) {
    final handlers = _handlers.putIfAbsent(action, () => [])
      ..add((order, handler));
    mergeSort(handlers, compare: (a, b) => a.$1.compareTo(b.$1));
    _bindings.clear();
  }

  /// Reads the keys at the end of the start: a wrong value stops it.
  @override
  void afterSingletonsInstantiated() => bindings(defaultTargetPlatform);

  /// Adds [handler] for its action, as a bean would be; for a library that
  /// makes handlers itself.
  void addHandler(ShortcutHandler handler, {int order = 0}) =>
      _add(handler.action, order, handler);

  /// The actions with keys or handlers.
  Set<String> get actions => {..._configuration().keys, ..._handlers.keys};

  /// Whether a bean handles [action].
  bool handles(String action) => _handlers[action]?.isNotEmpty ?? false;

  /// The keys of every action on [platform].
  Map<String, List<ShortcutKeys>> bindings(TargetPlatform platform) =>
      _bindings[platform] ??= _read(platform);

  /// The keys of [action] on [platform]; empty when it has none.
  List<ShortcutKeys> keysOf(String action, TargetPlatform platform) =>
      bindings(platform)[action] ?? const [];

  /// Asks the handlers of the invocation's action in order; `true` when
  /// one handled it.
  bool dispatch(ShortcutInvocation invocation) {
    for (final (_, handler) in [...?_handlers[invocation.action]]) {
      if (handler.handle(invocation)) {
        return true;
      }
    }
    return false;
  }

  Map<String, List<String>> _configuration() =>
      _configured ??= boundProperties<FlutterProperties>(
        environment,
        'flutterProperties',
      ).shortcuts;

  Map<String, List<ShortcutKeys>> _read(TargetPlatform platform) {
    final notations = ShortcutNotations(
      switch (_factory) {
        final ListableBeanFactory factory =>
          factory.getSortedBeans<ShortcutNotation>(),
        _ => const [],
      },
    );
    final configured = _configuration();
    final texts = {..._defaults, ...configured};
    final result = <String, List<ShortcutKeys>>{};
    final owners = <String, String>{};
    for (final MapEntry(key: action, value: written) in texts.entries) {
      final keys = <ShortcutKeys>[];
      for (final (i, text) in written.indexed) {
        if (text.trim().isEmpty) {
          continue;
        }
        final property = configured.containsKey(action)
            ? '$prefix.$action${written.length > 1 ? '[$i]' : ''}'
            : '@Shortcut($action).keys';
        final parsed = notations.parse(
          text,
          property: property,
          platform: platform,
        );
        final label = parsed.label(platform);
        final other = owners[label];
        if (other != null && other != action) {
          _log.warning(
            () =>
                "The keys $label are given to '$other' and '$action'; "
                'the one nearer the focus wins.',
          );
        }
        owners[label] = action;
        keys.add(parsed);
      }
      result[action] = List.unmodifiable(keys);
    }
    return Map.unmodifiable(result);
  }
}

final class _MethodHandler implements ShortcutHandler {
  _MethodHandler(this.action, this._bean, this._method, this._argument);

  factory _MethodHandler.of(
    Object bean,
    BeanMethod<Object> method,
    Shortcut shortcut,
    BeanDefinition<Object> definition,
  ) {
    final name = '${definition.beanType}.${method.name}';
    final types = method.parameterTypes;
    if (types.length > 1 ||
        method.parameters.length > types.length ||
        (types.length == 1 &&
            types.single != BuildContext &&
            types.single != ShortcutInvocation)) {
      throw StateError(
        'Invalid @Shortcut method $name: it takes nothing, a BuildContext '
        'or a ShortcutInvocation',
      );
    }
    if (shortcut.action.trim().isEmpty) {
      throw StateError('Invalid @Shortcut on $name: the action is empty');
    }
    return _MethodHandler(
      shortcut.action,
      bean,
      method,
      types.isEmpty ? null : types.single,
    );
  }

  @override
  final String action;
  final Object _bean;
  final BeanMethod<Object> _method;
  final Type? _argument;

  @override
  bool handle(ShortcutInvocation invocation) {
    final context = invocation.context;
    if (_argument == BuildContext && context == null) {
      return false;
    }
    final result = _method.invoke(_bean, [
      if (_argument == BuildContext) context,
      if (_argument == ShortcutInvocation) invocation,
    ]);
    return result is! bool || result;
  }
}
