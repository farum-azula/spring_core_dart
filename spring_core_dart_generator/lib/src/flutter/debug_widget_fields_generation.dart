// The readers of the public fields of the application's own widgets and of
// their `State` classes, which the card of a widget in the debug graph
// shows (`DebugWidgetFields` of spring_boot_starter_flutter): a lazy bean
// in the application's debug part, only in a build that has the widgets
// layer of the graph, so any other build has none of it.
import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart';
import 'package:spring_core_dart_generator/src/core/builder/generated_path.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart'
    show moduleBuildSwitches;

const _flutterSpringUrl =
    'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

const _widgetChecker = TypeChecker.fromUrl(
  'package:flutter/src/widgets/framework.dart#Widget',
);

const _stateChecker = TypeChecker.fromUrl(
  'package:flutter/src/widgets/framework.dart#State',
);

// The modules that bring the widgets layer: the Graph tab's and the
// console's `graph` pane's. Their switches are read from their
// `AutoConfigurationBuild`s.
const _layerModules = {
  'springBootStarterFlutterDebugWidgetsGraphAutoConfiguration',
  'springBootStarterFlutterDebugConsoleWidgetsGraphPaneAutoConfiguration',
};

// The getter of the debug part with the bean.
const _getter = r'_$debugWidgetFields';

// What the part knows of a module: the build keys and the switches of the
// modules with the widgets layer, and the widget and `State` classes of
// its libraries, in the order they were scanned.
final class _FieldsModel {
  BuildKeys? keys;
  List<BuildSwitch> layerSwitches = const [];
  final List<ClassElement> widgets = [];
  final List<ClassElement> states = [];

  // Whether the build has the widgets layer; `false` before the keys are
  // read (the metadata's scan).
  late final bool built = () {
    final keys = this.keys;
    if (keys == null) {
      return false;
    }
    return layerSwitches.any(
      (layerSwitch) =>
          keys.decideSwitch(
            layerSwitch,
            subject:
                "spring_boot_starter_flutter's readers of the widgets' "
                'fields',
            noun: 'part',
          ) !=
          BuildInclusion.never,
    );
  }();
}

/// The part of `spring_boot_starter_flutter` that writes the readers of
/// the application's widgets' fields, for the cards of the debug graph.
///
/// For each public, non-generic, non-abstract widget class of the
/// application's scan that does not override `debugFillProperties` (one
/// that does tells its values through Flutter's diagnostics, which the
/// card shows), and for each such `State` class of a widget, it lists the
/// public instance fields the class and its superclasses of the same
/// package declare, each with a closure that reads it. Getters are left
/// out: a getter may compute, allocate or change something, and the card
/// reads its values whenever the graph walks the tree. So is a `late` field
/// with an initializer, which reading would run, and a static one. A
/// private field cannot be read from the generated library, so it is not
/// shown.
///
/// The list is a lazy bean, `debugWidgetFields`, in the getter
/// `_$debugWidgetFields` of the application's debug part
/// (`<library>.spring.debug.dart`), which the module spreads into its beans
/// only in debug builds. It is written only when the build has the
/// widgets layer (`spring.flutter.debug.graph.layers` letting `widgets`
/// in, within `spring.flutter.debug.graph.enabled` and
/// `spring.flutter.debug.enabled`; or the console's `graph` pane): any other
/// build, and a nested `@ComponentScan`, which has no debug part, gets
/// nothing.
///
/// ```dart
/// // Output, main.spring.debug.dart:
/// List<BeanDefinition<Object>> get _$debugWidgetFields => [
///   BeanDefinition<DebugWidgetFields>(
///     name: r'debugWidgetFields',
///     lazy: true,
///     create: (r) => DebugWidgetFields({
///       PassportCard: [(r'player', (o) => (o as PassportCard).player)],
///     }),
///   ),
/// ];
/// // main.spring.dart, the application's beans:
/// if (!const bool.fromEnvironment('dart.vm.product') &&
///     !const bool.fromEnvironment('dart.vm.profile'))
///   ..._$debugWidgetFields,
/// ```
final class DebugWidgetFieldsGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const DebugWidgetFieldsGeneration();

  @override
  String get package => 'spring_boot_starter_flutter';

  static _FieldsModel _model(ModuleModel module) =>
      module.packageModel(_FieldsModel.new);

  @override
  Future<void> prepareModule(ModuleBuild build) async {
    final switches = await moduleBuildSwitches(build.buildStep, package);
    _model(build.module)
      ..keys = BuildKeys(() => build.resources)
      ..layerSwitches = [
        for (final MapEntry(key: module, value: layerSwitch)
            in switches.entries)
          if (_layerModules.contains(module)) layerSwitch,
      ];
  }

  @override
  void scanClass(ClassElement element, ModuleScan scan) {
    if (!element.isPublic ||
        element.isAbstract ||
        element.typeParameters.isNotEmpty) {
      return;
    }
    final model = _model(scan.module);
    if (_widgetChecker.isAssignableFrom(element)) {
      model.widgets.add(element);
    } else if (_stateChecker.isAssignableFrom(element)) {
      model.states.add(element);
    }
  }

  // Whether [emission] writes the readers: an application's module whose
  // build has the widgets layer.
  static bool _writes(ModuleEmission emission) =>
      emission.hasApplicationPart(debugExtension) &&
      _model(emission.module).built;

  @override
  Iterable<Expression> beanDefinitions(ModuleEmission emission) => [
    if (_writes(emission) && _readers(emission).isNotEmpty)
      const CodeExpression(Code('if ($debugOnlyCondition) ...$_getter')),
  ];

  @override
  Map<String, Iterable<Spec>> partFiles(ModuleEmission emission) {
    if (!_writes(emission)) {
      return const {};
    }
    final readers = _readers(emission);
    if (readers.isEmpty) {
      return const {};
    }
    return {
      debugExtension: [
        Method(
          (m) => m
            ..docs.add(
              "/// The public fields of the application's widgets and their "
              'states, which the\n/// cards of the debug graph show '
              '(`DebugWidgetFields`).',
            )
            ..type = MethodType.getter
            ..returns = TypeReference(
              (t) => t
                ..symbol = 'List'
                ..types.add(
                  TypeReference(
                    (t) => t
                      ..symbol = 'BeanDefinition'
                      ..url = 'package:spring_core_dart/spring_core_dart.dart'
                      ..types.add(refer('Object')),
                  ),
                ),
            )
            ..name = _getter
            ..lambda = true
            ..body = literalList([
              emission
                  .spring('BeanDefinition')
                  .newInstance(
                    [],
                    {
                      'name': emission.string('debugWidgetFields'),
                      'source': emission.string(
                        '$_flutterSpringUrl#DebugWidgetFields',
                      ),
                      'lazy': literalTrue,
                      'create': emission.closure(
                        ['r'],
                        refer(
                          'DebugWidgetFields',
                          _flutterSpringUrl,
                        ).call([literalMap(readers)]).code,
                        lambda: true,
                      ),
                    },
                    [refer('DebugWidgetFields', _flutterSpringUrl)],
                  ),
            ]).code,
        ),
      ],
    };
  }

  // The readers of each class, by its `Type`: the widgets', then their
  // states'.
  static Map<Expression, Expression> _readers(ModuleEmission emission) {
    final model = _model(emission.module);
    final widgets = model.widgets.toSet();
    final readers = <Expression, Expression>{};
    void add(ClassElement element) {
      if (_overridesDiagnostics(element)) {
        return;
      }
      final fields = _fieldsOf(element);
      if (fields.isEmpty) {
        return;
      }
      try {
        final type = emission.type(element.thisType, element);
        readers[emission.typeValue(element.thisType, element)] = literalList([
          for (final name in fields)
            literalRecord([
              emission.string(name),
              emission.closure(
                ['o'],
                refer('o').asA(type).property(name).code,
                lambda: true,
              ),
            ], {}),
        ]);
      } on InvalidGenerationSource {
        // A class the generated library cannot import: not shown.
      }
    }

    widgets.forEach(add);
    for (final state in model.states) {
      final widget = state.allSupertypes
          .where((type) => _stateChecker.isExactly(type.element))
          .firstOrNull
          ?.typeArguments
          .firstOrNull
          ?.element;
      if (widgets.contains(widget)) {
        add(state);
      }
    }
    return readers;
  }

  // Whether [element] or a superclass of its own overrides
  // `debugFillProperties`: Flutter's diagnostics then tell its values.
  static bool _overridesDiagnostics(ClassElement element) {
    final method = element.thisType.lookUpMethod(
      'debugFillProperties',
      element.library,
    );
    final owner = method?.enclosingElement;
    return owner is InterfaceElement && _samePackage(owner, element);
  }

  // The public instance fields [element] and its superclasses of its
  // package declare, the class's own first; no `late` field with an
  // initializer (reading it would run it).
  static List<String> _fieldsOf(ClassElement element) {
    final names = <String>[];
    for (
      InterfaceElement? type = element;
      type != null && _samePackage(type, element);
      type = type.supertype?.element
    ) {
      for (final field in type.fields) {
        final name = field.name;
        if (name == null ||
            field.isStatic ||
            !field.isPublic ||
            !(field.isOriginDeclaration ||
                field.isOriginDeclaringFormalParameter) ||
            (field.isLate && field.hasInitializer) ||
            names.contains(name)) {
          continue;
        }
        names.add(name);
      }
    }
    return names;
  }

  static bool _samePackage(Element element, Element other) =>
      _packageOf(element) == _packageOf(other);

  // The package of [element]'s library (`asset:` for one outside `lib/`),
  // else its scheme (`dart`).
  static String? _packageOf(Element element) {
    final uri = element.library?.uri;
    if (uri == null) {
      return null;
    }
    return (uri.scheme == 'package' || uri.scheme == 'asset') &&
            uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first
        : uri.scheme;
  }
}
