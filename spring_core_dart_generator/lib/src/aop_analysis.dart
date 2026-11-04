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
import 'package:spring_core_dart_generator/src/flutter_scanning.dart'
    show mixesChangeNotifierIn;

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
///   not its weight. Nothing is generated for such a bean's members
///   (`AopProxyFactory.pruned`, with the reason): advice registered at run
///   time without the build seeing it is not applied to it; the build
///   option `aop_prune: false` keeps every proxy.
///
/// Pruning needs certainty. It is off, and every bean keeps its proxy,
/// without [foreign], when a module declares an advisor bean whose pointcut
/// the build cannot read from its `@Bean` method (an
/// `ExpressionPointcut('...')` with a constant expression, an
/// `AnnotationMatchingPointcut<A>` or a pointcut declaring its
/// `annotationTypes` can be read), or when a pointcut refers to one the
/// build cannot follow. A bean keeps its proxy
/// when its class or a member carries an annotation an annotation-driven
/// advisor of a starter matches (`@Transactional`, `@Cacheable`,
/// `@Validated`: the pointcut, or the advisor, declares them in a
/// `static const annotationTypes` list; when one declares none, any
/// annotation from outside `package:spring_core_dart` and the SDK keeps
/// it), when it has an introduction, when its proxy class mixes
/// `ChangeNotifier` in (a `@ChangeNotifierComponent` that is not one), and
/// when a pointcut might match it. A subclass proxy (the bean is created
/// as the generated subclass) is pruned like a wrapper: the bean is then
/// created as its own class. Annotations of the SDK (`@override`) and of
/// `package:meta` never keep a proxy.
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
  // Advisor beans whose `@Bean` method the build could read count like
  // aspects: an expression is matched against the beans, annotations keep
  // the beans carrying them. One the build cannot read may match anything.
  final advisors = module.beans.where(_isAdvisor).toList();
  final unknownAdvisor = advisors.any((bean) => bean.advisorPointcut == null);
  for (final (owner, expression) in [
    for (final bean in advisors)
      if (bean.advisorPointcut?.expression case final expression?)
        (bean.name, expression),
    for (final expression in foreign?.expressions ?? const <String>[])
      ('advisor', expression),
  ]) {
    try {
      expressions.add(ExpressionPointcut(expression, owner: owner));
    } on FormatException {
      complete = false;
    }
  }
  for (final bean in advisors) {
    foreign?.advisedAnnotations.addAll(
      bean.advisorPointcut?.annotations ?? const {},
    );
  }
  if (!prune ||
      foreign == null ||
      foreign.unknown ||
      foreign.advisors ||
      !complete ||
      unknownAdvisor) {
    return;
  }
  for (final bean in module.beans) {
    final proxy = bean.proxy;
    if (proxy == null ||
        proxy.unavailableReason != null ||
        mixesChangeNotifierIn(proxy.classAnnotations, proxy.targetType) ||
        proxy.introductions.isNotEmpty ||
        bean.aspect != null ||
        _classMayBeAdvised(proxy, foreign)) {
      continue;
    }
    final names = [...bean.aliases, ...bean.qualifiers];
    // The members a pointcut may match, or an annotation-driven advisor
    // through their own annotations; the others are not proxied.
    final advised = {
      for (final member in proxy.members)
        if (_memberMayBeAdvised(proxy, member, foreign) ||
            expressions.any(
              (pointcut) => pointcut.matchesBean(
                _signature(proxy, member),
                bean.name,
                names,
              ),
            ))
          member,
    };
    if (advised.isNotEmpty && advised.length < proxy.members.length) {
      proxy.advisedMembers = advised;
    }
    if (advised.isEmpty) {
      proxy.pruned = true;
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

// Advisors of starters match by annotation (`@Cacheable`, `@Validated`):
// a bean keeps its proxy when it carries one of the annotations they
// declare, or, when one of them declares none, any annotation from
// outside `spring_core_dart` and the SDK.
//
// A class-level annotation (`@Transactional` on the class) concerns every
// member: the whole proxy is kept.
bool _classMayBeAdvised(ProxyModel proxy, ForeignAdvice foreign) =>
    _anyAdvice(proxy, proxy.classAnnotations, foreign);

// The same for the annotations of one member: on it and on the
// declarations it overrides, on the class (and superclasses) its body is
// in, on its parameters (`@Valid`).
bool _memberMayBeAdvised(
  ProxyModel proxy,
  ProxyMember member,
  ForeignAdvice foreign,
) => _anyAdvice(proxy, [
  ...member.mergedAnnotations,
  ...member.implementingTypeAnnotations,
  for (final level in member.superclassAnnotations) ...level,
  for (final parameter in member.parameters) ...parameter.annotations,
], foreign);

bool _anyAdvice(
  ProxyModel proxy,
  List<DartObject> annotations,
  ForeignAdvice foreign,
) {
  // `@Validated` on a `@ConfigurationProperties` class validates the bound
  // properties once, at startup; method validation leaves such classes out
  // (Spring Boot's `MethodValidationExcludeFilter`), so it advises nothing.
  final configurationProperties = proxy.classAnnotations.any(
    (a) => a.type?.element?.name == 'ConfigurationProperties',
  );
  return annotations.any(
    (annotation) =>
        !(configurationProperties &&
            annotation.type?.element?.name == 'Validated') &&
        _mayBeAdvice(annotation, foreign),
  );
}

bool _mayBeAdvice(DartObject annotation, ForeignAdvice foreign) {
  final element = annotation.type?.element;
  if (element == null) {
    return true;
  }
  if (element.name == 'Validated') {
    return true;
  }
  final library = element.library!;
  final uri = library.uri.toString();
  // `@override`, `@Deprecated`, `@pragma`, `package:meta`'s markers and
  // the core's own annotations advise nothing.
  if (library.isInSdk ||
      uri.startsWith('package:meta/') ||
      uri.startsWith('package:spring_core_dart/')) {
    return false;
  }
  if (foreign.undeclaredAnnotations) {
    return true;
  }
  // The annotation or a supertype of it (`class AdminOnly extends
  // PreAuthorize`): the pointcuts test with `is`.
  final type = annotation.type;
  return [
    if (type is InterfaceType) ...[type, ...type.element.allSupertypes],
  ].any(
    (t) => foreign.advisedAnnotations.contains(
      '${t.element.library.uri}#${t.element.name}',
    ),
  );
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
