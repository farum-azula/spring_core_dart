// The runtime package is not a dependency of the generator (consumers pull
// both from git without overrides), but every consumer has it, and the
// build script resolves packages with the consumer's package config: the
// build parses pointcuts with the very parser the application runs.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart/aop.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';

/// Build-time checks and savings for AOP, run on the scanned [module]
/// before it is emitted.
///
/// - Every advice expression is parsed with the runtime's own parser
///   ([ExpressionPointcut]): a syntax error fails the build, naming the
///   aspect, the advice and the position, instead of failing the context
///   at startup. A reference to a pointcut the build cannot see (another
///   package's holder class) is left to the runtime.
/// - With [prune], `aop_proxies: all` keeps its meaning but not its
///   weight: a proxy class is not generated for a bean no pointcut of the
///   module can match. The bean keeps its signatures
///   (`AopProxyFactory.unavailable`), so an advisor from elsewhere that
///   turns out to match it fails the startup with the reason instead of
///   being skipped silently.
///
/// Pruning needs certainty, so it is off (every bean keeps its proxy)
/// when the module has no advice, declares an advisor bean, or has a
/// pointcut that refers to one the build cannot follow; a bean is kept when
/// its class or a member carries an annotation from outside
/// `package:spring_core_dart` (annotation-driven advisors of starters, like
/// `@Cacheable`) or `@Validated`, when it is a subclass proxy (it is the
/// bean itself), and when a pointcut might match it.
///
/// ```dart
/// analyzeAop(module, prune: true);
/// ```
void analyzeAop(ModuleModel module, {required bool prune}) {
  final aspects = [
    for (final bean in module.beans)
      if (bean.aspect != null) bean,
  ];
  final qualified = <String, String>{
    for (final bean in aspects)
      for (final MapEntry(:key, :value) in bean.aspect!.pointcuts.entries)
        if (!key.contains('.')) '${bean.type.element.name}.$key': value,
  };
  final expressions = <ExpressionPointcut>[];
  var complete = true;
  for (final bean in aspects) {
    final owner = bean.type.element.name!;
    final named = {...qualified, ...bean.aspect!.pointcuts};
    for (final advice in bean.aspect!.advice) {
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
          ),
        );
      } on FormatException catch (e) {
        if (_unresolvable(e)) {
          complete = false;
          continue;
        }
        throw InvalidGenerationSource(
          'The pointcut of ${advice.kind} advice $owner.${advice.methodName} '
          'is invalid: ${_describe(e)}',
          element: bean.element,
        );
      }
    }
    for (final MapEntry(:key, :value) in bean.aspect!.pointcuts.entries) {
      try {
        ExpressionPointcut(value, namedPointcuts: named, owner: owner);
      } on FormatException catch (e) {
        if (!_unresolvable(e) && !e.message.contains('argument binding')) {
          throw InvalidGenerationSource(
            'The @Pointcut $owner.$key is invalid: ${_describe(e)}',
            element: bean.element,
          );
        }
      }
    }
  }
  if (!prune ||
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
          'the build found no pointcut that matches '
          '${proxy.targetType.element.name}, so it generated no proxy class '
          'for it (set the build option aop_prune: false to generate one '
          'for every bean).';
    }
  }
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
  for (final member in proxy.members) ...member.annotations,
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
