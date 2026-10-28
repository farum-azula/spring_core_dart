// The only import of the runtime package in the generator: the build
// parses pointcuts with the very parser the application runs, so a
// pointcut accepted here is accepted at startup. The build script resolves
// packages with the consumer's package config, so this is the consumer's
// version of spring_core_dart.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart/aop.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';

/// Checks the AOP declarations of the scanned [module] and adjusts its
/// proxies before the module is emitted.
///
/// The module emitter calls it once per module. It does three things:
///
/// - It parses every advice, `@Pointcut` and `@Aspect('perthis(...)')`
///   expression of the module's aspects with the runtime's own parser
///   ([ExpressionPointcut]). A syntax error throws an
///   `InvalidGenerationSource` that names the aspect, the advice and the
///   character position, instead of failing the context at startup. A
///   reference to a pointcut the build cannot see (another package's
///   holder class) is left to the runtime.
/// - It adds the `@DeclareParents` introductions of the module's aspects
///   to the proxies of the module's beans whose class matches the type
///   pattern, so the proxy class implements the introduced interface.
/// - With [prune] and [foreign] (the advice of the application's other
///   modules), it skips the proxy class of every bean that no pointcut of
///   the application can match. `aop_proxies: all` keeps its meaning but
///   not its weight. The bean keeps its signatures
///   (`AopProxyFactory.unavailable`), so an advisor from elsewhere that
///   matches it after all fails the startup with the reason instead of
///   being skipped silently.
///
/// Pruning needs certainty. It is off, and every bean keeps its proxy,
/// without [foreign], when no module has advice, when a module declares an
/// advisor bean, or when a pointcut refers to one the build cannot follow.
/// A bean always keeps its proxy when its class or a member carries an
/// annotation from outside `package:spring_core_dart` (annotation-driven
/// advisors of starters, like `@Cacheable`) or `@Validated`, when it is a
/// subclass proxy (the proxy is the bean itself), when it has an
/// introduction, and when a pointcut might match it.
///
/// ```dart
/// // In the @SpringBootApplication output: prune, knowing the advice of
/// // the nested modules and the auto-configurations.
/// analyzeAop(module, prune: true, foreign: foreignAdvice);
/// ```
void analyzeAop(
  ModuleModel module, {
  required bool prune,
  ForeignAdvice? foreign,
}) {
  final aspects = [
    for (final bean in module.beans)
      if (bean.aspect case final aspect?) (bean.type.element.name!, aspect),
  ];
  final all = [...aspects, ...?foreign?.aspects];
  final qualified = <String, String>{
    for (final (owner, aspect) in all)
      for (final MapEntry(:key, :value) in aspect.pointcuts.entries)
        if (!key.contains('.')) '$owner.$key': value,
  };
  final typeTests = <String, bool Function(Object?)>{
    for (final (_, aspect) in all)
      for (final name in aspect.typeTests.keys) name: (_) => true,
  };
  final argumentAnnotations = <String, Object? Function(Object?)>{
    for (final (_, aspect) in all)
      for (final name in aspect.argumentAnnotations) name: (_) => name,
  };
  final expressions = <ExpressionPointcut>[];
  var complete = true;
  for (final (owner, aspect) in all) {
    final own = aspects.any((entry) => identical(entry.$2, aspect));
    final element = own
        ? module.beans
              .firstWhere((bean) => identical(bean.aspect, aspect))
              .element
        : null;
    final named = {...qualified, ...aspect.pointcuts};
    for (final advice in aspect.advice) {
      try {
        expressions.add(
          ExpressionPointcut(
            advice.pointcut,
            namedPointcuts: named,
            bindings: {
              for (final binding in advice.bindings)
                binding.name: AdviceBinding(
                  binding.type.element?.name ?? 'Object',
                  (_) => true,
                ),
            },
            owner: owner,
            typeTests: typeTests,
            argumentAnnotations: argumentAnnotations,
          ),
        );
      } on FormatException catch (e) {
        if (!own || _unresolvable(e)) {
          complete = false;
          continue;
        }
        throw InvalidGenerationSource(
          'The pointcut of ${advice.kind} advice $owner.${advice.methodName} '
          'is invalid: ${_describe(e)}',
          element: element,
        );
      }
    }
    if (!own) {
      continue;
    }
    for (final MapEntry(:key, :value) in aspect.pointcuts.entries) {
      try {
        ExpressionPointcut(value, namedPointcuts: named, owner: owner);
      } on FormatException catch (e) {
        if (!_unresolvable(e) && !e.message.contains('argument binding')) {
          throw InvalidGenerationSource(
            'The @Pointcut $owner.$key is invalid: ${_describe(e)}',
            element: element,
          );
        }
      }
    }
    if (aspect.perClause case final perClause?) {
      final inner = perClause.substring(
        perClause.indexOf('(') + 1,
        perClause.lastIndexOf(')'),
      );
      try {
        ExpressionPointcut(inner, namedPointcuts: named, owner: owner);
      } on FormatException catch (e) {
        if (!_unresolvable(e)) {
          throw InvalidGenerationSource(
            "The instantiation model @Aspect('$perClause') of $owner is "
            'invalid: ${_describe(e)}',
            element: element,
          );
        }
      }
    }
  }
  _applyIntroductions(module, [for (final (_, aspect) in aspects) aspect]);
  if (!prune ||
      foreign == null ||
      foreign.unknown ||
      foreign.advisors ||
      expressions.isEmpty ||
      !complete ||
      module.beans.any((bean) => _isAdvisor(bean))) {
    return;
  }
  for (final bean in module.beans) {
    final proxy = bean.proxy;
    if (proxy == null ||
        proxy.unavailableReason != null ||
        proxy.subclass != null ||
        proxy.introductions.isNotEmpty ||
        bean.aspect != null ||
        _mayBeAdvisedElsewhere(proxy)) {
      continue;
    }
    final names = [...bean.aliases, ...bean.qualifiers];
    final matched = proxy.members.any((member) {
      final signature = _signature(proxy, member);
      return expressions.any(
        (pointcut) => pointcut.matchesBean(signature, bean.name, names),
      );
    });
    if (!matched) {
      proxy.unavailableReason =
          'the build found no pointcut of the application that matches '
          '${proxy.targetType.element.name}, so it generated no proxy class '
          'for it (set the build option aop_prune: false to generate one '
          'for every bean).';
    }
  }
}

// Adds every `@DeclareParents` of [aspects] to the generated proxy classes
// of the beans whose class matches its type pattern and does not already
// implement the interface (Spring's DeclareParentsAdvisor).
void _applyIntroductions(ModuleModel module, List<AspectModel> aspects) {
  final introductions = [for (final aspect in aspects) ...aspect.introductions];
  if (introductions.isEmpty) {
    return;
  }
  for (final bean in module.beans) {
    final proxy = bean.proxy;
    if (proxy == null ||
        proxy.unavailableReason != null ||
        bean.aspect != null) {
      continue;
    }
    for (final introduction in introductions) {
      final interfaceName = introduction.interfaceType.element.name!;
      if (proxy.targetTypeNames.contains(interfaceName) ||
          !_typePatternMatches(
            introduction.typePattern,
            proxy.targetTypeNames,
          )) {
        continue;
      }
      proxy.introductions.add(introduction);
    }
  }
}

// AspectJ type pattern of `@DeclareParents`: `Type` (simple name, `*`
// wildcards; a package prefix is ignored) or `Type+` (or a subtype);
// [types] are the bean class first, then its supertypes.
bool _typePatternMatches(String raw, List<String> types) {
  var pattern = raw.trim();
  final subtypes = pattern.endsWith('+');
  if (subtypes) {
    pattern = pattern.substring(0, pattern.length - 1);
  }
  pattern = pattern.split('.').where((part) => part.isNotEmpty).last;
  return subtypes
      ? types.any((type) => wildcardMatch(pattern, type))
      : wildcardMatch(pattern, types.first);
}

// A syntax error with the position of the problem.
String _describe(FormatException e) {
  final offset = e.offset;
  final source = e.source;
  return '${e.message}${offset == null ? '' : ' at character $offset'}'
      '${source is String ? " of '$source'" : ''}';
}

// A named pointcut of a class the build cannot see.
bool _unresolvable(FormatException e) => e.message.contains('unknown pointcut');

bool _isAdvisor(BeanModel bean) => bean.exposedTypes.any(
  (type) =>
      const {
        'Advisor',
        'PointcutAdvisor',
        'DefaultPointcutAdvisor',
      }.contains(type.element.name) &&
      type.element.library.uri.path.startsWith('spring_core_dart/'),
);

// Advisors of starters match by annotation (`@Cacheable`, `@Validated`).
bool _mayBeAdvisedElsewhere(ProxyModel proxy) => [
  ...proxy.classAnnotations,
  for (final member in proxy.members) ...[
    ...member.mergedAnnotations,
    ...member.implementingTypeAnnotations,
    for (final level in member.superclassAnnotations) ...level,
  ],
  for (final member in proxy.members)
    for (final parameter in member.parameters) ...parameter.annotations,
].any(_isForeignAnnotation);

bool _isForeignAnnotation(DartObject annotation) {
  final element = annotation.type?.element;
  if (element == null) {
    return true;
  }
  return element.name == 'Validated' ||
      !element.library!.uri.toString().startsWith('package:spring_core_dart/');
}

// What the runtime's `MethodSignature` of [member] is, for matching only.
MethodSignature _signature(ProxyModel proxy, ProxyMember member) =>
    MethodSignature(
      name: member.name,
      declaringType: member.declaringType,
      declaringTypes: member.declaringTypes,
      targetType: proxy.targetType.element.name!,
      kind: switch (member.kind) {
        ProxyMemberKind.method => MemberKind.method,
        ProxyMemberKind.getter => MemberKind.getter,
        ProxyMemberKind.setter => MemberKind.setter,
      },
      returnType: _simpleName(member.returnType),
      parameterTypes: member.kind == ProxyMemberKind.method
          ? [for (final p in member.parameters) _simpleName(p.type)]
          : const [],
      parameterNames: [for (final p in member.parameters) p.name],
      annotationTypes: [
        for (final a in member.annotations) a.type!.element!.name!,
      ],
      targetTypes: proxy.targetTypeNames,
      targetAnnotationTypes: [
        for (final a in proxy.classAnnotations) a.type!.element!.name!,
      ],
      implementingTypes: member.implementingTypes,
      implementingTypeAnnotationTypes: member.implementingTypes.isEmpty
          ? null
          : [
              for (final a in member.implementingTypeAnnotations)
                a.type!.element!.name!,
            ],
      isProtected: member.isProtected,
    );

// Type name used in signatures (as the emitter writes it).
String _simpleName(DartType type) => switch (type) {
  InterfaceType() => type.element.name!,
  TypeParameterType() => type.element.name!,
  VoidType() => 'void',
  FunctionType() => 'Function',
  RecordType() => 'Record',
  _ => 'dynamic',
};
