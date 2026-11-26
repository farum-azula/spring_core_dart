// The application's own segments, panes and commands of the debug console
// (`@ConsoleSegment`, `@ConsolePane`, `@ConsoleCommand` of
// spring_boot_starter_flutter): beans only in the application's debug
// part, under the build switches of the console, so a build without them
// refers to them nowhere: a segment only when `segments` names it, a pane
// only when `panes` names it, a command only with the `commands` pane.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';

const _annotations =
    'package:spring_boot_starter_flutter/src/debug/console/console_annotations.dart';

const _consoleKey = 'spring.flutter.debug.console.enabled';
const _segmentsKey = 'spring.flutter.debug.console.segments';
const _panesKey = 'spring.flutter.debug.console.panes';

const _console = BuildSwitch(_consoleKey, whenMissing: BuildInclusion.never);

// A segment of the application: with the console, when `segments` names
// it or holds `*` (its default names only the framework's).
BuildSwitch _segmentSwitch(String name) => BuildSwitch.named(
  _segmentsKey,
  name,
  whenMissing: BuildInclusion.never,
  parents: const [_console],
);

// A pane of the application: with the console, when `panes` names it or
// holds `*` (its default names none).
BuildSwitch _paneSwitch(String name) => BuildSwitch.named(
  _panesKey,
  name,
  whenMissing: BuildInclusion.never,
  parents: const [_console],
);

// A command of the application: with the console's `commands` pane, as
// the framework's commands.
BuildSwitch _commandSwitch(String name) => _paneSwitch('commands');

/// One kind of the console's extensions: its annotation and the field of
/// it that holds the name, the interface its class implements, the getter
/// of the debug part its beans are in, and the build switch of one of a
/// name.
final class _ConsoleExtension {
  const _ConsoleExtension({
    required this.annotationName,
    required this.annotation,
    required this.nameField,
    required this.interfaceName,
    required this.interface,
    required this.getter,
    required this.what,
    required this.buildSwitch,
    required this.lacking,
  });

  // `@ConsoleSegment`, for the messages.
  final String annotationName;
  final TypeChecker annotation;
  final String nameField;
  final String interfaceName;
  final TypeChecker interface;
  final String getter;
  final String what;
  final BuildSwitch Function(String name) buildSwitch;

  // What the build needs to have one of [name], for the messages.
  final String Function(String name) lacking;
}

const _segments = _ConsoleExtension(
  annotationName: '@ConsoleSegment',
  interfaceName: 'DebugConsoleSegment',
  annotation: TypeChecker.fromUrl('$_annotations#ConsoleSegment'),
  nameField: 'segment',
  interface: TypeChecker.fromUrl(
    'package:spring_boot_starter_flutter/src/debug/console/'
    'debug_console_segment.dart#DebugConsoleSegment',
  ),
  getter: r'_$debugConsoleSegments',
  what: 'segment of the debug console',
  buildSwitch: _segmentSwitch,
  lacking: _segmentLacking,
);

String _segmentLacking(String name) =>
    "$_consoleKey: true and $_segmentsKey naming '$name' or holding '*'";

const _panes = _ConsoleExtension(
  annotationName: '@ConsolePane',
  interfaceName: 'DebugConsolePane',
  annotation: TypeChecker.fromUrl('$_annotations#ConsolePane'),
  nameField: 'pane',
  interface: TypeChecker.fromUrl(
    'package:spring_boot_starter_flutter/src/debug/console/'
    'debug_console_pane.dart#DebugConsolePane',
  ),
  getter: r'_$debugConsolePanes',
  what: 'pane of the debug console',
  buildSwitch: _paneSwitch,
  lacking: _paneLacking,
);

String _paneLacking(String name) =>
    "$_consoleKey: true and $_panesKey naming '$name' or holding '*'";

const _commands = _ConsoleExtension(
  annotationName: '@ConsoleCommand',
  interfaceName: 'DebugConsoleCommand',
  annotation: TypeChecker.fromUrl('$_annotations#ConsoleCommand'),
  nameField: 'command',
  interface: TypeChecker.fromUrl(
    'package:spring_boot_starter_flutter/src/debug/console/'
    'debug_console_command.dart#DebugConsoleCommand',
  ),
  getter: r'_$debugConsoleCommands',
  what: 'command of the debug console',
  buildSwitch: _commandSwitch,
  lacking: _commandLacking,
);

String _commandLacking(String name) => _paneLacking('commands');

const List<_ConsoleExtension> _extensions = [_segments, _panes, _commands];

// A class with `@ConsoleSegment`, `@ConsolePane` or `@ConsoleCommand`: its
// kind and the name its annotation gives.
typedef _Extension = ({_ConsoleExtension kind, String name});

// What the part knows of a module: the build keys its extensions are
// decided by, and the classes that are one.
final class _ConsoleModel {
  // The application's build keys; `null` until the main builder has read
  // them (the metadata's scan leaves the beans as they are).
  BuildKeys? keys;

  final Map<(String, String), BuildInclusion> _decided = {};

  // The classes of the module with `@ConsoleSegment`, `@ConsolePane` or
  // `@ConsoleCommand`, whether the build has them or not.
  final Map<ClassElement, _Extension> classes = {};

  // Where [extension] goes; `null` before the keys are read.
  BuildInclusion? inclusionOf(_Extension extension) {
    final keys = this.keys;
    if (keys == null) {
      return null;
    }
    return _decided[(extension.kind.getter, extension.name)] ??= keys
        .decideSwitch(
          extension.kind.buildSwitch(extension.name),
          subject:
              "${extension.kind.annotationName}('${extension.name}') of the "
              'application',
          noun: extension.kind.what,
        );
  }
}

/// The part of `spring_boot_starter_flutter` that keeps an application's
/// console extensions out of every build that does not show them.
///
/// A class with `@ConsoleSegment` (`@ConsolePane`, `@ConsoleCommand`) is a
/// bean like any `@Component`, constructor injection included; its
/// definition goes into the getter `_$debugConsoleSegments`
/// (`_$debugConsolePanes`, `_$debugConsoleCommands`) of the application's
/// debug part, `<library>.spring.debug.dart`, which the module spreads
/// into its beans, and its annotation into the definition's
/// `annotations`, where the console reads its name (else the class's
/// `name` getter). A segment is there only when the build has the console
/// (`spring.flutter.debug.console.enabled: true`) and
/// `spring.flutter.debug.console.segments` names it or holds `*`; a pane
/// only when the build has the console and
/// `spring.flutter.debug.console.panes` names it or holds `*`; a command
/// only when the build has the console and its `commands` pane (`panes`
/// naming `commands` or holding `*`), as the framework's own commands.
/// Otherwise the class is no bean at all and nothing refers to it, so the
/// compiler leaves it out.
///
/// ```dart
/// // Input (segments: [fps, ping]):
/// @ConsoleSegment('ping', order: 50)
/// class PingSegment extends DebugConsoleSegment {
///   PingSegment(this.client);
///   ...
/// }
///
/// // Output, main.spring.debug.dart:
/// List<BeanDefinition<Object>> get _$debugConsoleSegments => [
///   BeanDefinition<PingSegment>(
///     name: r'pingSegment',
///     order: 50,
///     annotations: const [ConsoleSegment('ping', order: 50)],
///     ...,
///   ),
/// ];
/// // main.spring.dart, the application's beans:
/// ..._$debugConsoleSegments,
/// ```
///
/// The build fails for such a class that does not implement its interface,
/// one outside the application's own scan (a nested `@ComponentScan` has
/// no debug part), a bean of the app that is no console extension and
/// injects one (in a build without it there would be nothing to inject),
/// an extension that injects one this build leaves out, a `name` getter
/// that says another name than the annotation (the annotation's name is
/// the default, the getter names a segment or command registered without
/// it), and a bean of a segment's or a command's class with neither, which
/// the console could not name.
final class DebugConsoleGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const DebugConsoleGeneration();

  @override
  String get package => 'spring_boot_starter_flutter';

  static _ConsoleModel _model(ModuleModel module) =>
      module.packageModel(_ConsoleModel.new);

  @override
  Future<void> prepareModule(ModuleBuild build) async {
    _model(build.module).keys = BuildKeys(() => build.resources);
  }

  static _Extension? _extensionOf(Element element) {
    for (final kind in _extensions) {
      if (kind.annotation.firstAnnotationOf(element) case final annotation?) {
        final name = ConstantReader(annotation).peek(kind.nameField);
        return (kind: kind, name: name?.stringValue ?? '');
      }
    }
    return null;
  }

  // Left out of the build, the class is no bean: claimed, and nothing
  // made.
  @override
  bool claimClass(ClassElement element, ModuleScan scan) {
    final extension = _extensionOf(element);
    return extension != null &&
        _model(scan.module).inclusionOf(extension) == BuildInclusion.never;
  }

  @override
  void scanClass(ClassElement element, ModuleScan scan) {
    final extension = _extensionOf(element);
    if (extension == null) {
      return;
    }
    final kind = extension.kind;
    _model(scan.module).classes[element] = extension;
    scan.collectErrors(() {
      if (!kind.interface.isAssignableFrom(element)) {
        throw InvalidGenerationSource(
          '${kind.annotationName} on ${element.displayName}: a ${kind.what} '
          'implements ${kind.interfaceName}, which the console reads it by.',
          element: element,
        );
      }
      if (extension.name.trim().isEmpty) {
        throw InvalidGenerationSource(
          '${kind.annotationName} on ${element.displayName}: its name is '
          'empty, and the console knows a ${kind.what} only by it.',
          element: element,
        );
      }
    });
  }

  @override
  Future<void> checkModule(ModuleBuild build) async {
    final model = _model(build.module);
    final classes = model.classes;
    for (final MapEntry(key: element, value: extension) in classes.entries) {
      await _checkAgreement(element, extension, build);
    }
    for (final bean in build.module.beans) {
      final own = classes[bean.element];
      if (own == null) {
        _checkUnnamed(bean, build);
      }
      for (final point in bean.dependencies) {
        final injected = point.type.element;
        if (injected is! ClassElement) {
          continue;
        }
        final extension = classes[injected];
        if (extension == null) {
          continue;
        }
        final kind = extension.kind;
        if (own == null) {
          build.collectErrors(() {
            throw InvalidGenerationSource(
              'The bean ${bean.name} injects ${injected.displayName}, a '
              '${kind.annotationName} class: it is a bean only in a build '
              'with ${kind.lacking(extension.name)}, registered in the debug '
              'part, and no other bean may need it, or a build without it '
              'would have nothing to inject. Inject it only into the '
              "console's segments, panes and commands, or make "
              '${injected.displayName} a plain @Component.',
              element: bean.element,
            );
          });
        } else if (model.inclusionOf(extension) == BuildInclusion.never) {
          build.collectErrors(() {
            throw InvalidGenerationSource(
              '${own.kind.annotationName} ${bean.name} injects '
              '${injected.displayName}, which this build leaves out: it '
              'needs ${kind.lacking(extension.name)}. Let the build have '
              '${injected.displayName} too, or inject what it reads '
              'instead.',
              element: bean.element,
            );
          });
        }
      }
    }
  }

  // The `name` getter [element] has from below the console's base class
  // ([kind]'s own returns `null`); `null` when it has none.
  static PropertyAccessorElement? _nameGetter(
    ClassElement element,
    _ConsoleExtension kind,
  ) {
    final getter = element.thisType.lookUpGetter('name', element.library);
    final owner = getter?.enclosingElement;
    if (getter == null ||
        (owner is InterfaceElement && kind.interface.isExactly(owner))) {
      return null;
    }
    return getter;
  }

  // The string [getter] always returns, when the build can read it: a
  // getter `=> 'ping'` or a field `= 'ping'`; `null` otherwise (a value
  // made at run time, checked when the app starts).
  static Future<String?> _literalName(
    PropertyAccessorElement getter,
    ModuleBuild build,
  ) async {
    final resolver = build.buildStep.resolver;
    final Expression? returned;
    if (getter.isOriginVariable) {
      final variable = getter.variable;
      if (!variable.isFinal && !variable.isConst) {
        return null;
      }
      final node = await resolver.astNodeFor(variable.firstFragment);
      returned = node is VariableDeclaration ? node.initializer : null;
    } else {
      final node = await resolver.astNodeFor(getter.firstFragment);
      returned = node is MethodDeclaration
          ? switch (node.body) {
              ExpressionFunctionBody(:final expression) => expression,
              _ => null,
            }
          : null;
    }
    return returned is SimpleStringLiteral ? returned.value : null;
  }

  // An annotated class whose `name` getter says another name: the build
  // fails, the annotation being the default the getter may only repeat.
  static Future<void> _checkAgreement(
    ClassElement element,
    _Extension extension,
    ModuleBuild build,
  ) async {
    final getter = _nameGetter(element, extension.kind);
    if (getter == null) {
      return;
    }
    final name = await _literalName(getter, build);
    if (name == null || name == extension.name) {
      return;
    }
    build.collectErrors(() {
      throw InvalidGenerationSource(
        "${extension.kind.annotationName}('${extension.name}') on "
        "${element.displayName}, whose name getter says '$name': the "
        "annotation's name is the one the console uses. Drop the getter, "
        'or make the two agree.',
        element: element,
      );
    });
  }

  // A bean of a segment's, a pane's or a command's class with neither the
  // annotation nor a `name` getter: the console would have no name to use
  // it by.
  static void _checkUnnamed(BeanModel bean, ModuleBuild build) {
    final element = bean.type.element;
    if (element is! ClassElement || element.isAbstract) {
      return; // a @Bean method's interface type: its class is not known
    }
    for (final kind in _extensions) {
      if (!kind.interface.isAssignableFromType(bean.type) ||
          _nameGetter(element, kind) != null) {
        continue;
      }
      build.collectErrors(() {
        throw InvalidGenerationSource(
          'The bean ${bean.name} is a ${kind.interfaceName} with neither '
          '${kind.annotationName} nor a name getter: the console knows a '
          '${kind.what} by its name, so it would never use this one. Put '
          '${kind.annotationName}(<name>) on the class, or override '
          '`String? get name`.',
          element: bean.element,
        );
      });
    }
  }

  @override
  BeanPlacement? beanPlacement(BeanModel bean, ModuleEmission emission) {
    final element = bean.element;
    if (element is! ClassElement) {
      return null;
    }
    final extension = _extensionOf(element);
    if (extension == null) {
      return null;
    }
    final kind = extension.kind;
    final inclusion = _model(emission.module).inclusionOf(extension);
    return BeanPlacement(
      getter: kind.getter,
      docs:
          "/// The application's ${kind.annotationName} beans, in the "
          'build that shows them only.',
      condition: inclusion == BuildInclusion.debugOnly
          ? debugOnlyCondition
          : null,
      outsideApplication:
          '${kind.annotationName} on ${element.displayName}: a ${kind.what} '
          "is registered in the debug part of the application's library "
          '(<library>.spring.debug.dart), which only the '
          "@SpringBootApplication's own scan has. Move the class into the "
          "application's scan.",
    );
  }
}
