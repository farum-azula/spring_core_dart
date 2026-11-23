import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/dart_types.dart';
import 'package:dart_spring_language_server/src/strings/roles/security_expressions.dart';
import 'package:dart_spring_language_server/src/strings/spel_paths.dart';

/// The method an expression is written on, as the types of its values.
final class SpelMethod {
  /// [method] (`null` on a class) of [file], read through [types];
  /// [annotation] holds the expression.
  SpelMethod(this.types, this.file, this.node, this.method, this.annotation);

  /// The type resolution.
  final DartTypes types;

  /// The file.
  final DartFile file;

  /// The string the expression is in.
  final AstNode node;

  /// The method, when the expression is on one.
  final MethodDeclaration? method;

  /// The annotation holding the expression.
  final Annotation? annotation;

  late final Map<String, TypeRef?> _typeParameters = {
    for (final parameter
        in method?.typeParameters?.typeParameters ?? const <TypeParameter>[])
      parameter.name.lexeme: null,
    ..._classTypeParameters(),
  };

  Map<String, TypeRef?> _classTypeParameters() {
    final list = switch (node.thisOrAncestorOfType<CompilationUnitMember>()) {
      final ClassDeclaration c => c.namePart.typeParameters,
      final MixinDeclaration m => m.typeParameters,
      _ => null,
    };
    return {
      for (final parameter in list?.typeParameters ?? const <TypeParameter>[])
        parameter.name.lexeme: null,
    };
  }

  /// The parameters of the method.
  List<FormalParameter> get parameters =>
      method?.parameters?.parameters.toList() ?? const [];

  /// The type of [parameter], awaited.
  TypeRef? typeOf(FormalParameter parameter) =>
      types.refOf(parameter.type, file, _typeParameters);

  /// The class the method is in.
  TypeRef? get enclosing => types.enclosing(node, file);

  /// What the method gives, awaited.
  TypeRef? get returned => types.awaited(
    types.refOf(method?.returnType, file, _typeParameters),
  );

  /// The element a filter expression runs on: of the return value for
  /// `@PostFilter`; of the `filterTarget` parameter, or the only collection
  /// parameter, for `@PreFilter`.
  TypeRef? get filtered {
    final annotation = this.annotation;
    if (annotation == null || annotationName(annotation) != 'PreFilter') {
      return types.elementOf(returned);
    }
    final target = stringValue(namedArgument(annotation, 'filterTarget'));
    final candidates = [
      for (final parameter in parameters)
        if (target != null && target.isNotEmpty
            ? parameter.name?.lexeme == target
            : types.isCollection(typeOf(parameter)))
          parameter,
    ];
    return candidates.length == 1
        ? types.elementOf(typeOf(candidates.single))
        : null;
  }

  /// The variables of the method's arguments: by name, `#p0` and `#a0`.
  Map<String, TypeRef?> get argumentVariables => {
    for (final (index, parameter) in parameters.indexed) ...{
      'p$index': typeOf(parameter),
      'a$index': typeOf(parameter),
      ?parameter.name?.lexeme: typeOf(parameter),
    },
  };
}

/// What one value of an expression's scope is, for a method.
typedef SpelValue = TypeRef? Function(SpelMethod method);

TypeRef? _enclosing(SpelMethod method) => method.enclosing;
TypeRef? _returned(SpelMethod method) => method.returned;
TypeRef? _filtered(SpelMethod method) => method.filtered;

/// The values of the root of a method security expression.
const Map<String, SpelValue> securityRootValues = {
  'this': _enclosing,
  'returnObject': _returned,
  'filterObject': _filtered,
};

/// The values of the root map of a cache expression.
const Map<String, SpelValue> cacheRootValues = {'target': _enclosing};

/// The variables a cache expression has besides the arguments.
const Map<String, SpelValue> cacheVariables = {'result': _returned};

/// The environment of an expression on [method].
SpelEnv spelEnvOf(
  SpelMethod method, {
  Map<String, SpelValue> rootValues = const {},
  Map<String, SpelValue> variables = const {},
  bool arguments = true,
}) => SpelEnv(
  variables: {
    if (arguments) ...method.argumentVariables,
    for (final MapEntry(:key, :value) in variables.entries) key: value(method),
  },
  rootValues: {
    for (final MapEntry(:key, :value) in rootValues.entries) key: value(method),
  },
);

/// How an argument holds SpEL.
enum SpelForm {
  /// The whole string is one expression.
  expression,

  /// Text with `#{...}` expressions in it.
  template,

  /// One expression, or a `#{...}` template when it starts with `#{`; it
  /// may hold `${...}` placeholders, replaced first
  /// (`@ConditionalOnExpression`).
  expressionOrTemplate,
}

/// What an expression of a [SpelSite] can read at run time.
final class SpelSiteScope {
  /// A scope with the root [names], whose [memberTypes] say what their
  /// members are.
  const SpelSiteScope({
    this.names = const {},
    this.memberTypes = const {},
    this.parameters = false,
    this.closedVariables = false,
  });

  /// The names of the root; empty when the root is open (beans).
  final Map<String, SecurityName> names;

  /// The members of the [SecurityName.memberType]s, for completion.
  final Map<String, Map<String, String?>> memberTypes;

  /// Whether the method's parameters are variables.
  final bool parameters;

  /// Whether a variable outside the known ones is reported: nothing can
  /// add one to this scope's context.
  final bool closedVariables;
}

/// One annotation (or call) whose arguments the framework evaluates.
final class SpelSite {
  /// The [arguments] of [callee] (`'0'` for the first positional one, else
  /// the name), read in [form] over [scope].
  const SpelSite(this.callee, this.arguments, this.form, this.scope);

  /// The annotation or constructor, or `Type.method`.
  final String callee;

  /// The arguments that hold SpEL.
  final Set<String> arguments;

  /// How they hold it.
  final SpelForm form;

  /// What they can read.
  final SpelSiteScope scope;
}

/// The root of a `CallTemplates` expression: a method security root with
/// no target, return value or filtered element.
final Map<String, SecurityName> _callTemplateNames = {
  for (final MapEntry(:key, :value) in securityNames.entries)
    if (!const {'this', 'returnObject', 'filterObject'}.contains(key))
      key: value,
};

/// `#{...}` of the Supabase storage and Realtime annotations: the
/// `MethodSecurityExpressionHandler` context of `CallTemplates`.
final callTemplateScope = SpelSiteScope(
  names: _callTemplateNames,
  memberTypes: securityMembers,
  parameters: true,
);

/// An expression evaluated for the current user with no method arguments
/// (`PrincipalView`, `RouteSecurity.preAuthorize`). A customizer of the
/// handler may add variables.
final principalScope = SpelSiteScope(
  names: _callTemplateNames,
  memberTypes: securityMembers,
);

/// The root of `ExpressionRateLimitKeyResolver`.
const rateLimitNames = <String, SecurityName>{
  'request': SecurityName(
    'request',
    'request',
    'The HTTP request: `path`, `method`, `remoteAddress`, `principal`, '
        '`headers`.',
    isProperty: true,
    memberType: 'RateLimitHttpRequest',
  ),
  'headers': SecurityName(
    'headers',
    "headers['X-Api-Key']",
    'The headers of the request, in any case.',
    isProperty: true,
  ),
  'principal': SecurityName(
    'principal',
    'principal',
    'The authenticated user; `null` for an anonymous request.',
    isProperty: true,
    memberType: 'RateLimitPrincipal',
  ),
  'authentication': SecurityName(
    'authentication',
    'authentication',
    'The authenticated user, as `principal`.',
    isProperty: true,
    memberType: 'RateLimitPrincipal',
  ),
  'address': SecurityName(
    'address',
    'address',
    "The client's address.",
    isProperty: true,
  ),
  'method': SecurityName(
    'method',
    'method',
    'The HTTP method.',
    isProperty: true,
  ),
  'path': SecurityName(
    'path',
    'path',
    'The path of the request.',
    isProperty: true,
  ),
};

/// `#{...}` of a rate limit key.
const rateLimitScope = SpelSiteScope(
  names: rateLimitNames,
  memberTypes: {
    'RateLimitHttpRequest': {
      'path': null,
      'method': null,
      'remoteAddress': null,
      'principal': 'RateLimitPrincipal',
      'headers': null,
    },
    'RateLimitPrincipal': {'name': null},
  },
  closedVariables: true,
);

/// `@ConditionalOnExpression`: beans and the environment on the root.
const beanExpressionScope = SpelSiteScope();

/// Every argument the framework evaluates as SpEL that no other role
/// reads: a new one is one entry here.
final List<SpelSite> spelSites = [
  for (final annotation in const [
    'Upload',
    'Download',
    'SignedUrl',
    'PublicUrl',
    'StorageObject',
    'DeleteObject',
  ])
    SpelSite(annotation, const {'0'}, SpelForm.template, callTemplateScope),
  SpelSite(
    'RealtimeChannel',
    const {
      '0',
      'presenceKey',
    },
    SpelForm.template,
    callTemplateScope,
  ),
  SpelSite(
    'PostgresChanges',
    const {
      'filter',
    },
    SpelForm.template,
    callTemplateScope,
  ),
  const SpelSite('RateLimiter', {'key'}, SpelForm.template, rateLimitScope),
  SpelSite(
    'PrincipalView',
    const {
      'expression',
    },
    SpelForm.expression,
    principalScope,
  ),
  SpelSite(
    'RouteSecurity.preAuthorize',
    const {
      '0',
    },
    SpelForm.expression,
    principalScope,
  ),
  const SpelSite(
    'ConditionalOnExpression',
    {'0'},
    SpelForm.expressionOrTemplate,
    beanExpressionScope,
  ),
];
