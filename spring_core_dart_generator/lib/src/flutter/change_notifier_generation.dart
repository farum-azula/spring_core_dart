// The `@ChangeNotifierComponent` beans of spring_boot_starter_flutter: a
// part of its own, as the beans' proxies are the core's.
import 'package:analyzer/dart/element/element.dart';
import 'package:spring_core_dart_generator/src/core/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';
import 'package:spring_core_dart_generator/src/flutter/flutter_scanning.dart';

/// The `@ChangeNotifierComponent` and `@NotifyListeners` part of
/// `spring_boot_starter_flutter` in the module build.
///
/// The proxy of a `@ChangeNotifierComponent` that is no `ChangeNotifier`
/// mixes `ChangeNotifier` in, so the bean the container hands out is the
/// `Listenable` widgets subscribe to; the build fails when the class
/// cannot work as written ([checkChangeNotifierComponent]).
///
/// ```dart
/// // Input:
/// @ChangeNotifierComponent()
/// class Basket { ... }
///
/// // Output:
/// class _$BasketProxy with ChangeNotifier, AdvisedWrapper implements Basket
/// ```
final class ChangeNotifierGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const ChangeNotifierGeneration();

  @override
  String get package => 'spring_boot_starter_flutter';

  @override
  void scanClass(ClassElement element, ModuleScan scan) =>
      scan.collectErrors(() => checkChangeNotifierComponent(element));

  @override
  Iterable<ProxyMixin> proxyMixins(ProxyModel proxy) =>
      mixesChangeNotifierIn(proxy.classAnnotations, proxy.targetType)
      ? const [ProxyMixin('ChangeNotifier', 'package:flutter/foundation.dart')]
      : const [];
}
