// Checks for spring_boot_starter_flutter_signals: `@Signal`, `@Computed`
// and `@Effect` on members the bean's proxy can follow. The annotations
// are recognised by their library's address, so the generator does not
// depend on the starter.
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

const _annotations =
    'package:spring_boot_starter_flutter_signals/src/annotations.dart';

/// Recognises `@Signal` of `spring_boot_starter_flutter_signals`.
const signalChecker = TypeChecker.fromUrl('$_annotations#Signal');

/// Recognises `@Computed` of `spring_boot_starter_flutter_signals`.
const computedChecker = TypeChecker.fromUrl('$_annotations#Computed');

/// Recognises `@Effect` of `spring_boot_starter_flutter_signals`.
const effectChecker = TypeChecker.fromUrl('$_annotations#Effect');

const _configuration = TypeChecker.typeNamedLiterally(
  'Configuration',
  inPackage: 'spring_core_dart',
);

const _configurationProperties = TypeChecker.typeNamedLiterally(
  'ConfigurationProperties',
  inPackage: 'spring_core_dart',
);

Never _fail(String message, Element element) =>
    throw InvalidGenerationSource(message, element: element);

/// Fails the build for `@Signal`, `@Computed` or `@Effect` on a member the
/// bean's proxy cannot follow, naming the member and what to change.
///
/// The proxy is a generated subclass in another library: it overrides
/// public instance members that have a body, and only those. [element] is
/// a class or a mixin.
void checkSignals(InterfaceElement element) {
  final owner = element.name ?? '?';
  var any = false;

  for (final field in element.fields) {
    final name = '$owner.${field.name}';
    if (computedChecker.hasAnnotationOfExact(field)) {
      _fail(
        '@Computed on the field $name: a computed value is a getter (or a '
        'method without parameters) that makes it from other state; a '
        'field that is assigned is a @Signal.',
        field,
      );
    }
    if (effectChecker.hasAnnotationOfExact(field)) {
      _fail('@Effect on the field $name: an effect is a method.', field);
    }
    if (!signalChecker.hasAnnotationOfExact(field)) {
      continue;
    }
    any = true;
    if (field.isAbstract) {
      _fail(
        '@Signal on the abstract field $name: there is no state here to '
        'follow. Annotate the field of the class that has it.',
        field,
      );
    }
    if (field.isStatic) {
      _fail(
        '@Signal on the static field $name: the state followed is the '
        "bean's; make it an instance field.",
        field,
      );
    }
    if (field.isPrivate) {
      _fail(
        '@Signal on the private field $name: the proxy that follows it is '
        'generated in another library and cannot override a private '
        'member. Make the field public.',
        field,
      );
    }
    if (field.isFinal || field.isConst) {
      _fail(
        '@Signal on the final field $name: a field that is never assigned '
        'has nothing to tell. Remove `final`, or the annotation (a final '
        'collection changed in place is read through a field that is not '
        'final).',
        field,
      );
    }
  }

  for (final getter in element.getters) {
    if (getter.isOriginVariable) {
      continue;
    }
    final name = '$owner.${getter.name}';
    if (signalChecker.hasAnnotationOfExact(getter)) {
      _fail(
        '@Signal on the getter $name: a signal is a field that is '
        'assigned; a value made from other state is a @Computed.',
        getter,
      );
    }
    if (effectChecker.hasAnnotationOfExact(getter)) {
      _fail('@Effect on the getter $name: an effect is a method.', getter);
    }
    if (!computedChecker.hasAnnotationOfExact(getter)) {
      continue;
    }
    any = true;
    _checkMember('@Computed', 'getter', name, getter);
  }

  for (final setter in element.setters) {
    if (setter.isOriginVariable) {
      continue;
    }
    for (final (checker, label) in [
      (signalChecker, '@Signal'),
      (computedChecker, '@Computed'),
      (effectChecker, '@Effect'),
    ]) {
      if (checker.hasAnnotationOfExact(setter)) {
        _fail(
          '$label on the setter $owner.${setter.name}: it goes on a field '
          '(@Signal), a getter (@Computed) or a method (@Effect).',
          setter,
        );
      }
    }
  }

  for (final method in element.methods) {
    final name = '$owner.${method.name}';
    if (signalChecker.hasAnnotationOfExact(method)) {
      _fail(
        '@Signal on the method $name: a signal is a field that is '
        'assigned.',
        method,
      );
    }
    final computed = computedChecker.hasAnnotationOfExact(method);
    final effect = effectChecker.hasAnnotationOfExact(method);
    if (!computed && !effect) {
      continue;
    }
    any = true;
    final label = computed ? '@Computed' : '@Effect';
    _checkMember(label, 'method', name, method);
    if (method.formalParameters.isNotEmpty) {
      _fail(
        computed
            ? '@Computed on $name, which takes parameters: a computed value '
                  'is one value, kept until what it read changes. A value '
                  'per argument is not followed; make it a plain method, '
                  'or a getter of state that holds the argument.'
            : '@Effect on $name, which takes parameters: nothing calls an '
                  'effect with any; it runs when what it read changes.',
        method,
      );
    }
    if (method.typeParameters.isNotEmpty) {
      _fail('$label on $name: the method must not be generic.', method);
    }
    final returns = method.returnType;
    if (effect &&
        returns is! VoidType &&
        !(returns is InterfaceType &&
            returns.isDartAsyncFuture &&
            returns.typeArguments.single is VoidType)) {
      _fail(
        '@Effect on $name, which returns a value: nothing reads what an '
        'effect returns. Return void, or make it a @Computed.',
        method,
      );
    }
    if (computed && returns is VoidType) {
      _fail(
        '@Computed on $name, which returns nothing: a computed value is a '
        'value. A method run for what it does is an @Effect.',
        method,
      );
    }
  }

  if (any && _configuration.hasAnnotationOfExact(element)) {
    _fail(
      '@Signal, @Computed and @Effect on a member of the @Configuration '
      'class $owner: they are for the members of a component '
      '(@Component, @Service). Move the state into a component.',
      element,
    );
  }
  if (any && _configurationProperties.hasAnnotationOfExact(element)) {
    _fail(
      '@Signal, @Computed and @Effect on a member of the '
      '@ConfigurationProperties class $owner: its fields are bound from '
      'the configuration once, they are not state that changes. Keep the '
      'state in a component that reads $owner.',
      element,
    );
  }
  _checkOverrides(element, owner);
}

// A member that overrides a followed one without the annotation: the
// proxy reads the annotations of the declaration that runs, so the state
// would stop being followed without a word.
void _checkOverrides(InterfaceElement element, String owner) {
  String? inherited(String name, {required bool getter}) {
    for (final supertype in element.allSupertypes) {
      if (getter) {
        final declared = supertype.element.getGetter(name);
        if (declared == null) {
          continue;
        }
        if (declared.isOriginVariable
            ? signalChecker.hasAnnotationOfExact(declared.variable)
            : computedChecker.hasAnnotationOfExact(declared)) {
          final kind = declared.isOriginVariable
              ? '@Signal field'
              : '@Computed getter';
          return '$kind ${supertype.element.name}.$name';
        }
      } else {
        final declared = supertype.element.getMethod(name);
        if (declared == null) {
          continue;
        }
        for (final (checker, label) in [
          (computedChecker, '@Computed'),
          (effectChecker, '@Effect'),
        ]) {
          if (checker.hasAnnotationOfExact(declared)) {
            return '$label method ${supertype.element.name}.$name';
          }
        }
      }
    }
    return null;
  }

  String message(String name, String overridden) =>
      '$owner.$name overrides the $overridden without its annotation: the '
      'proxy follows the member that runs, so $owner.$name would not be '
      'followed. Repeat the annotation on $owner.$name, or do not override '
      'it.';

  for (final getter in element.getters) {
    final name = getter.name;
    if (name == null || getter.isStatic) {
      continue;
    }
    final annotated = getter.isOriginVariable
        ? signalChecker.hasAnnotationOfExact(getter.variable)
        : computedChecker.hasAnnotationOfExact(getter);
    if (annotated) {
      continue;
    }
    if (inherited(name, getter: true) case final overridden?) {
      _fail(
        message(name, overridden),
        getter.isOriginVariable ? getter.variable : getter,
      );
    }
  }
  for (final method in element.methods) {
    final name = method.name;
    if (name == null ||
        method.isStatic ||
        computedChecker.hasAnnotationOfExact(method) ||
        effectChecker.hasAnnotationOfExact(method)) {
      continue;
    }
    if (inherited(name, getter: false) case final overridden?) {
      _fail(message(name, overridden), method);
    }
  }
}

void _checkMember(
  String label,
  String what,
  String name,
  ExecutableElement member,
) {
  if (member.isAbstract) {
    _fail(
      '$label on the abstract $what $name: there is no body here to run '
      'and follow (the method of a repository or of an HTTP client is '
      'written by the generator, and is not followed). Annotate a $what of '
      'a component that has a body, and call $name from it.',
      member,
    );
  }
  if (member.isStatic) {
    _fail(
      "$label on the static $what $name: the state followed is the bean's; "
      'make it an instance $what.',
      member,
    );
  }
  if (member.isPrivate) {
    _fail(
      '$label on the private $what $name: the proxy that follows it is '
      'generated in another library and cannot override a private member. '
      'Make it public.',
      member,
    );
  }
}
