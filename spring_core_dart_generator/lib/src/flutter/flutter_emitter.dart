// What spring_boot_starter_flutter's part writes into a module: the
// `SpringWidgetBindings` bean of its Spring widgets, the registrations of
// its `@ThemeLoaderKind` classes and the `BuildContext` getters of its
// `@BuildContextAccess` beans.
import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/flutter/flutter_scanning.dart';
import 'package:spring_core_dart_generator/src/flutter/typed_theme_keys.dart'
    show LoaderKinds;

// The runtime library the generated code of spring_boot_starter_flutter
// refers to.
const _flutterSpringUrl =
    'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
const _flutterWidgetsUrl = 'package:flutter/widgets.dart';

/// Writes the Flutter code of one module ([flutter]) through the emitter's
/// [emission].
final class FlutterEmitter {
  /// The Flutter code of [flutter], written through [emission].
  FlutterEmitter(this.emission, this.flutter);

  /// The emitter's ways of naming types and values.
  final ModuleEmission emission;

  /// What the Flutter part found in the module.
  final FlutterModuleModel flutter;

  /// `extension SpringBeans on BuildContext { Basket get basket => ...; }`
  /// for the `@BuildContextAccess` beans.
  Extension contextAccessExtension() => Extension(
    (e) => e
      ..docs.add(
        '/// Getters for the `@BuildContextAccess` beans, for widgets below '
        '`SpringApplicationWidget`.',
      )
      ..name = 'SpringBeans'
      ..on = refer('BuildContext', _flutterWidgetsUrl)
      ..methods.addAll([
        for (final access in flutter.buildContextAccess)
          Method(
            (m) => m
              ..docs.add(
                "/// The bean '${emission.docText(access.bean.name)}'.",
              )
              ..type = MethodType.getter
              ..returns = emission.anyType(access.type, access.bean.element)
              ..name = access.getter
              ..lambda = true
              ..body = refer('SpringScope', _flutterSpringUrl)
                  .property('beanOf')
                  .call(
                    [refer('this')],
                    {'qualifier': emission.string(access.bean.name)},
                    [emission.anyType(access.type, access.bean.element)],
                  )
                  .code,
          ),
      ]),
  );

  /// `ThemeLoaderKinds.register<P>('doors', painter: DoorsLoader(), ...)`
  /// for each `@ThemeLoaderKind` class of the module.
  List<Expression> loaderKindRegistrations() {
    final kinds = refer('ThemeLoaderKinds', _flutterSpringUrl);
    return [
      for (final kind in flutter.loaderKinds)
        () {
          final props = LoaderKinds.propsClass(kind.name);
          final instance = emission
              .type(kind.element.thisType, kind.element)
              .newInstance([]);
          return kinds.property('register').call(
            [emission.string(kind.name)],
            {
              if (kind.painter) 'painter': instance else 'widget': instance,
              if (kind.typedProps) ...{
                'props': refer('$props._'),
                'keys': refer('$props.keys'),
              },
            },
            [
              if (kind.typedProps)
                refer(props)
              else
                refer('LoaderValues', _flutterSpringUrl),
            ],
          );
        }(),
    ];
  }

  /// The `SpringWidgetBindings` bean of the module: how the bean record of
  /// each `SpringStatelessWidget<R>` is filled (one binding per distinct
  /// R, the first widget in scan order names it). Not an autowire
  /// candidate: `SpringStatelessWidget` finds it with `getBeansOfType`.
  Expression springWidgetBindings() {
    final bindings = refer('SpringWidgetBindings', _flutterSpringUrl);
    final binding = refer('SpringWidgetBinding', _flutterSpringUrl);
    final distinct = <SpringWidgetModel>[];
    for (final widget in flutter.springWidgets) {
      if (!distinct.any((other) => other.beans == widget.beans)) {
        distinct.add(widget);
      }
    }
    Expression field(SpringWidgetField field, Element element) => field.optional
        ? refer('f')
              .property('findBean')
              .call([], {}, [emission.type(field.type, element)])
        : binding
              .property('bean')
              .call(
                [
                  refer('f'),
                  if (field.name case final name?) emission.string(name),
                ],
                {},
                [emission.type(field.type, element)],
              );
    // `BeanDefinition<SpringWidgetBindings>`: its type is the only one.
    return emission
        .spring('BeanDefinition')
        .newInstance(
          [],
          {
            'name': emission.string(
              'flutterSpringWidgetBindings#${emission.moduleName}',
            ),
            'source': emission.string(
              '$_flutterSpringUrl#SpringWidgetBindings',
            ),
            'autowireCandidate': literalFalse,
            'create': emission.closure(
              ['r'],
              bindings.call([
                literalList([
                  for (final widget in distinct)
                    binding.call([], {
                      'widget': emission.string(widget.source),
                      'beans': emission.typeValue(widget.beans, widget.widget),
                      'types': literalConstList([
                        for (final type in widget.requiredTypes)
                          emission.type(type, widget.widget),
                      ]),
                      'resolve': emission.closure(
                        ['f'],
                        literalRecord(
                          [
                            for (final f in widget.positional)
                              field(f, widget.widget),
                          ],
                          {
                            for (final f in widget.named)
                              f.name!: field(f, widget.widget),
                          },
                        ).code,
                        lambda: true,
                      ),
                      // The beans of a filled record, for the widgets to
                      // subscribe to the Listenable ones.
                      'values': Method(
                        (m) => m
                          ..requiredParameters.add(
                            Parameter((p) => p..name = 'r'),
                          )
                          ..body = Block.of([
                            declareFinal('v')
                                .assign(
                                  refer('r').asA(
                                    emission.anyType(
                                      widget.beans,
                                      widget.widget,
                                    ),
                                  ),
                                )
                                .statement,
                            literalList([
                              for (var i = 0; i < widget.positional.length; i++)
                                refer('v').property('\$${i + 1}'),
                              for (final f in widget.named)
                                refer('v').property(f.name!),
                            ]).returned.statement,
                          ]),
                      ).closure,
                    }),
                ]),
              ]).code,
              lambda: true,
            ),
          },
          [bindings],
        );
  }
}
