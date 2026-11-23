// The `@ChangeNotifierComponent` beans of spring_boot_starter_flutter: a
// part of its own, as the beans' proxies are the core's.
import 'package:analyzer/dart/element/element.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
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
final class ChangeNotifierGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const ChangeNotifierGeneration();

  @override
  String get package => 'spring_boot_starter_flutter';

  @override
  List<AnnotationPlacement> get placements => const [
    _NotifyListenersPlacement(),
  ];

  @override
  void scanClass(ClassElement element, ModuleScan scan) =>
      scan.collectErrors(() => checkChangeNotifierComponent(element));

  @override
  Iterable<ProxyMixin> proxyMixins(ProxyModel proxy) =>
      mixesChangeNotifierIn(proxy.classAnnotations, proxy.targetType)
      ? const [ProxyMixin('ChangeNotifier', 'package:flutter/foundation.dart')]
      : const [];
}

// `@NotifyListeners` is advice: on a method or setter (or the class) of a
// bean that is a ChangeNotifier, or a `@ChangeNotifierComponent`, whose
// proxy notifies; elsewhere the interceptor would throw at the first call
// or nothing would run.
final class _NotifyListenersPlacement extends AdvicePlacement {
  const _NotifyListenersPlacement()
    : super(const [
        notifyListenersChecker,
      ], effect: 'no listener would hear of it');

  @override
  String? problem(AnnotationSite site) {
    if (super.problem(site) case final problem?) {
      return problem;
    }
    if (site.kind == PlaceKind.getter) {
      return '@NotifyListeners on ${site.subject}: a getter only reads, and '
          'notifying on a read rebuilds the widgets that read it, again and '
          'again. Put it on the setter or the method that changes the value.';
    }
    final element = site.kind == PlaceKind.classDeclaration
        ? site.element
        : site.owner;
    if (element is! ClassElement ||
        element.isAbstract ||
        changeNotifierComponentChecker.hasAnnotationOf(element) ||
        changeNotifierChecker.isAssignableFrom(element)) {
      return null;
    }
    return '@NotifyListeners on ${site.subject}: ${element.displayName} is no '
        'ChangeNotifier, so there is no listener to notify (the call would '
        'fail). Extend ChangeNotifier, or annotate ${element.displayName} '
        'with @ChangeNotifierComponent() instead of @Component().';
  }
}
