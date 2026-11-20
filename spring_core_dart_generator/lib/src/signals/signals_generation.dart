// spring_boot_starter_flutter_signals' part of the module build: the
// checks of `@Signal`, `@Computed` and `@Effect`.
import 'package:analyzer/dart/element/element.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/signals/signals_scanning.dart';

/// The part of `spring_boot_starter_flutter_signals` in the module build:
/// it fails the build for `@Signal`, `@Computed` or `@Effect` on a member
/// of a class or mixin that the bean's proxy cannot follow
/// ([checkSignals]). It writes nothing: the proxy the core generates
/// follows the members at run time.
final class SignalsGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const SignalsGeneration();

  @override
  String get package => 'spring_boot_starter_flutter_signals';

  @override
  void scanClass(ClassElement element, ModuleScan scan) =>
      scan.collectErrors(() => checkSignals(element));

  @override
  void scanMixin(MixinElement element, ModuleScan scan) =>
      scan.collectErrors(() => checkSignals(element));
}
