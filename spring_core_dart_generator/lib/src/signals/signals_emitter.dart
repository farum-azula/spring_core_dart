// The generated subclass of a bean on signals, in
// `<library>.spring.signals.dart`: its `@Signal` fields and `@Computed`
// members go straight to what follows them, with no advice around them.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart' show log;
import 'package:code_builder/code_builder.dart' hide FunctionType;
import 'package:code_builder/code_builder.dart' as cb show FunctionType;
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart';
import 'package:spring_core_dart_generator/src/signals/signals_scanning.dart';

const _starter =
    'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

Reference _runtime(String name) => refer(name, _starter);

/// Writes the subclass of each bean of the module that has one, and fails
/// the build for advice on such a bean unless the application allows it.
final class SignalsEmitter {
  /// The emitter of the module of [emission]; [allowAdvice] is
  /// `spring.flutter.signals.allow-advice`.
  SignalsEmitter(
    this.emission, {
    required this.allowAdvice,
    this.bufferAsyncMethods = false,
    this.probes = BuildInclusion.never,
  });

  /// The module being written.
  final ModuleEmission emission;

  /// Whether a bean with followed state may carry advice.
  final bool allowAdvice;

  /// `spring.flutter.signals.buffer.async-methods`: every async method of
  /// such a bean runs in a buffer.
  final bool bufferAsyncMethods;

  /// Where the beans tell the debug tools of their reads and writes
  /// (`ProbedSignalBean`): in no build, every build, or debug builds
  /// only, under the constant a profile or a release build folds. Without
  /// them a read or a write has no probe check to pay.
  final BuildInclusion probes;

  /// The generated classes, in the order of the module's beans.
  List<Spec> classes() => [
    for (final bean in emission.module.beans)
      if (bean.proxy?.accessHooks case final subclass?) ...[
        if (!allowAdvice) ..._refuseAdvice(bean, subclass),
        _beanClass(bean, subclass),
      ],
  ];

  // Nothing to write: throws when the bean carries advice.
  List<Spec> _refuseAdvice(BeanModel bean, AccessHooks subclass) {
    final proxy = bean.proxy!;
    final matched = subclass.pointcutMatch;
    final where =
        subclass.advice ??
        (matched == null
            ? null
            : 'a pointcut that matches '
                  '${proxy.targetType.element.name}.$matched');
    if (where != null) {
      throw InvalidGenerationSource(
        'Advice on a bean with @Signal, @Computed or @Effect members: '
        '$where. Such a bean is not advised by default, since advice around '
        'followed state is easy to get wrong. Move the advised method into '
        'a bean of its own that calls this one, or allow it with '
        'spring.flutter.signals.allow-advice: true in application.yml.',
        element: bean.element,
      );
    }
    return const [];
  }

  Class _beanClass(BeanModel bean, AccessHooks model) {
    final element = bean.element;
    final name = bean.proxy!.targetType.element.name!;
    final lookup = switch (bean.creation) {
      ConstructorCreation(:final lookup) => lookup,
      _ => null,
    };
    final fields = <Field>[];
    final methods = <Method>[];
    for (final member in model.members) {
      final signal = _annotation(member, signalChecker);
      if (signal != null) {
        _writeField(member, signal, element, fields, methods);
      } else if (_annotation(member, computedChecker) != null) {
        _writeComputed(member, element, fields, methods);
      } else if (_annotation(member, effectChecker) != null) {
        methods.add(_effectMethod(member, element));
      } else if (_isBuffered(member)) {
        methods.add(_bufferedMethod(member, element));
      }
    }
    return Class(
      (c) => c
        ..docs.add(
          '/// `$name` on signals: its followed members go straight to their '
          'signals.',
        )
        ..modifier = model.subclass.isFinal ? ClassModifier.final$ : null
        ..name = model.className
        ..extend = lookup == null
            ? emission.type(bean.proxy!.targetType, element)
            : refer(lookup.className)
        ..implements.add(_runtime('SignalBeanHolder'))
        ..constructors.add(
          lookup == null
              ? emission.forwardingConstructor(
                  model.subclass.constructorName,
                  model.subclass.constructorParameters,
                )
              : emission.forwardingConstructor(null, [
                  ProxyParameter(
                    name: r'_$beanFactory',
                    type: lookup.type,
                    isNamed: false,
                    isRequired: true,
                  ),
                  ...lookup.constructorParameters,
                ]),
        )
        ..fields.add(
          Field(
            (f) => f
              ..annotations.add(refer('override'))
              ..modifier = FieldModifier.final$
              ..type = _runtime('SignalBean')
              ..name = 'signalBean'
              ..assignment = _signalBean(name).code,
          ),
        )
        ..fields.addAll(fields)
        ..methods.add(
          Method(
            (m) => m
              ..annotations.add(refer('override'))
              ..type = MethodType.getter
              ..name = 'signalMembers'
              ..returns = TypeReference(
                (t) => t
                  ..symbol = 'Map'
                  ..types.addAll([
                    refer('String'),
                    cb.FunctionType(
                      (f) => f..returnType = _runtime('SignalMember'),
                    ),
                  ]),
              )
              ..lambda = true
              ..body = literalMap({
                for (final field in fields)
                  literalString(_memberName(field.name)): Method(
                    (c) => c
                      ..lambda = true
                      ..body = refer(field.name).code,
                  ).closure,
              }).code,
          ),
        )
        ..methods.add(
          Method(
            (m) => m
              ..annotations.add(refer('override'))
              ..type = MethodType.getter
              ..name = 'eagerSignals'
              ..returns = TypeReference(
                (t) => t
                  ..symbol = 'List'
                  ..types.add(refer('String')),
              )
              ..lambda = true
              ..body = literalConstList([
                for (final member in model.members)
                  if (member.kind == ProxyMemberKind.getter &&
                      _annotation(
                            member,
                            signalChecker,
                          )?.getField('eager')?.toBoolValue() ==
                          true)
                    member.name,
              ]).code,
          ),
        )
        ..methods.add(
          Method(
            (m) => m
              ..annotations.add(refer('override'))
              ..type = MethodType.getter
              ..name = 'signalQueues'
              ..returns = TypeReference(
                (t) => t
                  ..symbol = 'List'
                  ..types.add(refer('String')),
              )
              ..lambda = true
              ..body = literalConstList(
                {
                  for (final member in model.members)
                    if (member.kind == ProxyMemberKind.getter)
                      ?_annotation(
                        member,
                        signalChecker,
                      )?.getField('queue')?.toStringValue(),
                }.toList(),
              ).code,
          ),
        )
        ..methods.addAll(methods),
    );
  }

  // The state of the bean [label], probed in the builds [probes] says.
  Expression _signalBean(String label) {
    Expression of(String type) =>
        _runtime(type).newInstance([literalString(label)]);
    return switch (probes) {
      BuildInclusion.never => of('SignalBean'),
      BuildInclusion.always => of('ProbedSignalBean'),
      BuildInclusion.debugOnly => const CodeExpression(
        Code('($debugOnlyCondition)'),
      ).conditional(of('ProbedSignalBean'), of('SignalBean')),
    };
  }

  // `items` of the holder `_itemsSignal` or `_itemsComputed`.
  static String _memberName(String holder) => holder.substring(
    1,
    holder.length -
        (holder.endsWith('Signal') ? 'Signal'.length : 'Computed'.length),
  );

  static DartObject? _annotation(ProxyMember member, TypeChecker checker) {
    for (final annotation in member.mergedAnnotations) {
      final type = annotation.type;
      if (type != null && checker.isExactlyType(type)) {
        return annotation;
      }
    }
    return null;
  }

  void _writeField(
    ProxyMember member,
    DartObject signal,
    Element element,
    List<Field> fields,
    List<Method> methods,
  ) {
    final holder = '_${member.name}Signal';
    final type = emission.anyType(member.returnType, element);
    final direct = signal.getField('queued')?.toBoolValue() == false;
    if (member.kind == ProxyMemberKind.setter) {
      methods.add(
        Method(
          (m) => m
            ..annotations.add(refer('override'))
            ..type = MethodType.setter
            ..name = member.name
            ..requiredParameters.add(
              Parameter(
                (p) => p
                  ..name = 'value'
                  ..type = type,
              ),
            )
            ..body = refer(holder)
                .property(direct ? 'writeDirect' : 'write')
                .call([refer('value')])
                .statement,
        ),
      );
      return;
    }
    final returned = member.returnType;
    final arguments = returned is InterfaceType
        ? returned.typeArguments
        : const <DartType>[];
    fields.add(
      Field(
        (f) => f
          ..late = true
          ..modifier = FieldModifier.final$
          ..type = _runtime('ValueMember')
          ..name = holder
          ..assignment = refer('signalBean')
              .property('field')
              .call(
                [
                  literalString(member.name),
                  Method(
                    (m) => m
                      ..lambda = true
                      ..body = refer('super').property(member.name).code,
                  ).closure,
                ],
                {
                  if (arguments.isNotEmpty &&
                      arguments.every(emission.canCapture))
                    'arguments': literalConstList([
                      for (final argument in arguments)
                        emission.spring('TypeCapture').constInstance([], {}, [
                          emission.anyType(argument, element),
                        ]),
                    ]),
                  if (returned is InterfaceType)
                    'type': literalString(returned.element.name!),
                  'options': emission.constant(signal, element),
                },
              )
              .code,
      ),
    );
    methods.add(
      Method(
        (m) => m
          ..annotations.add(refer('override'))
          ..type = MethodType.getter
          ..name = member.name
          ..returns = type
          ..lambda = true
          ..body = refer(
            holder,
          ).property(direct ? 'readDirect' : 'read').call([]).asA(type).code,
      ),
    );
  }

  // Whether [member] runs in a buffer: `@SignalBuffer()`, or every async
  // method with `buffer.async-methods`, but `@SignalBuffer(false)`.
  bool _isBuffered(ProxyMember member) {
    if (member.kind != ProxyMemberKind.method) {
      return false;
    }
    final returned = member.returnType;
    final async = returned is InterfaceType && returned.isDartAsyncFuture;
    final marked = _annotation(member, signalBufferChecker);
    final enabled = marked?.getField('enabled')?.toBoolValue();
    if (marked != null && enabled == bufferAsyncMethods) {
      log.warning(
        '@SignalBuffer(${enabled! ? '' : 'false'}) on ${member.name} '
        'changes nothing: spring.flutter.signals.buffer.async-methods is '
        '$bufferAsyncMethods.',
      );
    }
    return async &&
        !_starterAnnotated(member) &&
        (enabled ?? bufferAsyncMethods);
  }

  // A member another annotation of the starter already handles.
  static bool _starterAnnotated(ProxyMember member) => [
    onWatchedChecker,
    onUnwatchedChecker,
  ].any((checker) => _annotation(member, checker) != null);

  // The method, run in a buffer of its bean.
  Method _bufferedMethod(ProxyMember member, Element element) => Method(
    (m) => m
      ..annotations.add(refer('override'))
      ..name = member.name
      ..returns = emission.anyType(member.returnType, element)
      ..types.addAll([
        for (final typeParameter in member.typeParameters)
          TypeReference(
            (t) => t
              ..symbol = typeParameter.name
              ..bound = typeParameter.bound == null
                  ? null
                  : emission.anyType(typeParameter.bound!, element),
          ),
      ])
      ..requiredParameters.addAll([
        for (final parameter in member.parameters)
          if (!parameter.isNamed && parameter.isRequired)
            emission.parameter(parameter, element),
      ])
      ..optionalParameters.addAll([
        for (final parameter in member.parameters)
          if (parameter.isNamed || !parameter.isRequired)
            emission.parameter(parameter, element),
      ])
      ..lambda = true
      ..body = refer('signalBean').property('buffered').call([
        Method(
          (c) => c
            ..lambda = true
            ..body = refer('super').property(member.name).call(
              [
                for (final parameter in member.parameters)
                  if (!parameter.isNamed) refer(parameter.name),
              ],
              {
                for (final parameter in member.parameters)
                  if (parameter.isNamed) parameter.name: refer(parameter.name),
              },
              [
                for (final typeParameter in member.typeParameters)
                  refer(typeParameter.name!),
              ],
            ).code,
        ).closure,
      ]).code,
  );

  // Its body, followed in a run the container started.
  Method _effectMethod(ProxyMember member, Element element) => Method(
    (m) => m
      ..annotations.add(refer('override'))
      ..name = member.name
      ..returns = emission.anyType(member.returnType, element)
      ..lambda = true
      ..body = refer('signalBean').property('effectBody').call([
        literalString(member.name),
        Method(
          (c) => c
            ..lambda = true
            ..body = refer('super').property(member.name).call([]).code,
        ).closure,
      ]).code,
  );

  void _writeComputed(
    ProxyMember member,
    Element element,
    List<Field> fields,
    List<Method> methods,
  ) {
    final holder = '_${member.name}Computed';
    final type = emission.anyType(member.returnType, element);
    final returned = member.returnType;
    final asynchronous =
        returned is InterfaceType &&
        (returned.isDartAsyncFuture || returned.isDartAsyncStream);
    final isGetter = member.kind == ProxyMemberKind.getter;
    final original = isGetter
        ? refer('super').property(member.name)
        : refer('super').property(member.name).call([]);
    fields.add(
      Field(
        (f) => f
          ..late = true
          ..modifier = FieldModifier.final$
          ..type = _runtime(asynchronous ? 'AsyncMember' : 'ComputedMember')
          ..name = holder
          ..assignment = refer('signalBean')
              .property(asynchronous ? 'asynchronous' : 'computed')
              .call([
                literalString(member.name),
                Method(
                  (m) => m
                    ..lambda = true
                    ..body = original.code,
                ).closure,
              ])
              .code,
      ),
    );
    methods.add(
      Method(
        (m) => m
          ..annotations.add(refer('override'))
          ..type = isGetter ? MethodType.getter : null
          ..name = member.name
          ..returns = type
          ..lambda = true
          ..body = refer(holder).property('read').call([]).asA(type).code,
      ),
    );
  }
}
