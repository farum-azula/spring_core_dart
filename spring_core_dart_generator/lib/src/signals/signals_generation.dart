// spring_boot_starter_flutter_signals' part of the module build: the
// checks of its annotations and the subclass each bean on signals is made
// as (`<library>.spring.signals.dart`).
import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart' show TypeChecker;
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart';
import 'package:spring_core_dart_generator/src/core/builder/generated_path.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart'
    show moduleBuildSwitches;
import 'package:spring_core_dart_generator/src/signals/signals_emitter.dart';
import 'package:spring_core_dart_generator/src/signals/signals_scanning.dart';

/// What the part reads of the module before it is scanned.
final class SignalsModuleModel {
  /// `spring.flutter.signals.allow-advice`: off unless it says `true`.
  bool allowAdvice = false;

  /// `spring.flutter.signals.buffer.async-methods`: off unless `true`.
  bool bufferAsyncMethods = false;

  /// Whether the beans tell the debug tools of their reads and writes: in
  /// the builds that have a debug tool of the signals, the widest of what
  /// the starter's debug modules' own switches decide (each module with a
  /// `build:` is a debug tool, and each has the recorder the probes tell:
  /// the Signals tab within the panel, the console's segment and panes, the
  /// graph layer), parents included.
  BuildInclusion probes = BuildInclusion.never;
}

/// The part of `spring_boot_starter_flutter_signals` in the module build:
/// it fails the build for an annotation of the starter on a member that
/// cannot be followed ([checkSignals]), and writes the generated subclass
/// of each bean with followed state ([SignalsEmitter]).
final class SignalsGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const SignalsGeneration();

  @override
  String get package => 'spring_boot_starter_flutter_signals';

  @override
  List<TypeChecker> get accessHooks => const [
    signalChecker,
    computedChecker,
    effectChecker,
    onWatchedChecker,
    onUnwatchedChecker,
  ];

  @override
  Future<void> prepareModule(ModuleBuild build) async {
    final keys = BuildKeys(() => build.resources);
    final debugModules = await moduleBuildSwitches(build.buildStep, package);
    build.module.packageModel(SignalsModuleModel.new)
      ..allowAdvice =
          keys.property('spring.flutter.signals.allow-advice') == 'true'
      ..bufferAsyncMethods =
          keys.property('spring.flutter.signals.buffer.async-methods') == 'true'
      ..probes = widestInclusion([
        for (final MapEntry(key: module, value: buildSwitch)
            in debugModules.entries)
          keys.decideSwitch(
            buildSwitch,
            subject: '$package.$module, for the probes of the signals',
            noun: 'debug probe of the signals',
          ),
      ]);
  }

  @override
  void scanClass(ClassElement element, ModuleScan scan) =>
      scan.collectErrors(() => checkSignals(element));

  @override
  void scanMixin(MixinElement element, ModuleScan scan) =>
      scan.collectErrors(() => checkSignals(element));

  @override
  Map<String, Iterable<Spec>> partFiles(ModuleEmission emission) {
    final model = emission.module.packageModel(SignalsModuleModel.new);
    final classes = SignalsEmitter(
      emission,
      allowAdvice: model.allowAdvice,
      bufferAsyncMethods: model.bufferAsyncMethods,
      probes: model.probes,
    ).classes();
    return classes.isEmpty ? const {} : {signalsExtension: classes};
  }
}
