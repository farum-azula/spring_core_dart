// Scanning for spring_boot_starter_flutter: `@BuildContextAccess` beans
// (generated `BuildContext` getters) and `SpringStatelessWidget<(...)>`
// classes (generated bindings that fill their bean records). Matched by URL,
// so the generator does not depend on spring_boot_starter_flutter.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';

/// `@BuildContextAccess` of spring_boot_starter_flutter.
const contextAccessChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/annotations.dart#BuildContextAccess',
);

/// `SpringStatelessWidget` of spring_boot_starter_flutter.
const springWidgetChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/spring_widgets.dart#SpringStatelessWidget',
);

/// `SpringState` of spring_boot_starter_flutter (the `State` of a stateful
/// widget that gets beans: `SpringState<W, R>`).
const springStateChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/spring_widgets.dart#SpringState',
);

/// A generated `BuildContext` getter for a `@BuildContextAccess` bean.
///
/// ```dart
/// // Input:
/// @Component()
/// @BuildContextAccess()
/// class Basket { ... }
///
/// // Output (in the extension SpringBeans on BuildContext):
/// Basket get basket => SpringScope.beanOf<Basket>(this, qualifier: r'basket');
/// ```
class BuildContextAccessModel {
  /// The getter [getter] for [bean], typed [type].
  BuildContextAccessModel(this.getter, this.bean, this.type);

  /// The getter's name.
  final String getter;

  /// The bean it returns.
  final BeanModel bean;

  /// The getter's type: the bean's type (a `FactoryBean`'s product type).
  final DartType type;
}

/// A record field of a `SpringStatelessWidget`'s beans.
class SpringWidgetField {
  /// A field of bean type [type]; [name] for a named field.
  SpringWidgetField(this.type, {required this.optional, this.name});

  /// The bean type (without `?`).
  final InterfaceType type;

  /// The field's name (named fields only).
  final String? name;

  /// Whether the field is nullable (`findBean`, not required).
  final bool optional;
}

/// A `SpringStatelessWidget<R>` class: how its record [beans] is filled.
///
/// ```dart
/// // Input:
/// class BasketBadge
///     extends SpringStatelessWidget<(Basket, AppNavigator)> { ... }
///
/// // Output (in the module, one definition for all widgets):
/// SpringWidgetBinding(
///   widget: r'package:app/basket_badge.dart#BasketBadge',
///   beans: _$typeOf<(Basket, AppNavigator)>(),
///   types: const [Basket, AppNavigator],
///   resolve: (f) => (SpringWidgetBinding.bean<Basket>(f),
///       SpringWidgetBinding.bean<AppNavigator>(f)),
/// )
/// ```
class SpringWidgetModel {
  /// The binding of [widget] (named [source]) for [beans].
  SpringWidgetModel(
    this.widget,
    this.source,
    this.beans,
    this.positional,
    this.named,
  );

  /// The widget class (for error messages and imports).
  final ClassElement widget;

  /// `package:app/x.dart#Widget`.
  final String source;

  /// The record type.
  final RecordType beans;

  /// The positional fields, in order.
  final List<SpringWidgetField> positional;

  /// The named fields, in the record type's order.
  final List<SpringWidgetField> named;

  /// The bean types checked at startup (the required fields').
  Iterable<InterfaceType> get requiredTypes => [
    for (final field in [...positional, ...named])
      if (!field.optional) field.type,
  ];
}

/// Records [element] in `module.springWidgets` when it is a concrete
/// `SpringStatelessWidget<R>` or `SpringState<W, R>`; throws
/// `InvalidGenerationSource` when R is not a record of bean types.
/// Abstract classes whose R is still a type parameter (base classes for
/// widgets) are skipped.
void scanSpringWidget(ClassElement element, ModuleModel module) {
  final supertype = element.allSupertypes
      .where(
        (type) =>
            springWidgetChecker.isExactly(type.element) ||
            springStateChecker.isExactly(type.element),
      )
      .firstOrNull;
  if (supertype == null || supertype.typeArguments.isEmpty) {
    return;
  }
  final kind = supertype.element.name;
  final beans = supertype.typeArguments.last;
  final name = element.name ?? '?';
  if (beans is TypeParameterType && element.isAbstract) {
    return;
  }
  if (beans is! RecordType ||
      beans.nullabilitySuffix == NullabilitySuffix.question) {
    final example = kind == 'SpringState'
        ? 'SpringState<MyWidget, (Basket, AppNavigator)>'
        : 'SpringStatelessWidget<(Basket, AppNavigator)>';
    throw InvalidGenerationSource(
      '$kind $name: its beans must be a record of bean types, like '
      '$example, not ${beans.getDisplayString()}.',
      element: element,
    );
  }
  SpringWidgetField field(DartType type, String? fieldName) {
    final label = fieldName ?? 'positional field';
    if (type is! InterfaceType ||
        type.isDartCoreObject ||
        type.isDartCoreRecord ||
        type.isDartCoreFunction ||
        type.isDartCoreNull) {
      throw InvalidGenerationSource(
        '$kind $name: ${type.getDisplayString()} ($label of '
        '${beans.getDisplayString()}) is not a bean type; every field of the '
        'record must be a class or interface type (nullable for an optional '
        'bean).',
        element: element,
      );
    }
    final optional = type.nullabilitySuffix == NullabilitySuffix.question;
    return SpringWidgetField(
      optional
          ? type.element.instantiate(
              typeArguments: type.typeArguments,
              nullabilitySuffix: NullabilitySuffix.none,
            )
          : type,
      name: fieldName,
      optional: optional,
    );
  }

  module.springWidgets.add(
    SpringWidgetModel(
      element,
      '${element.library.uri}#$name',
      beans,
      [for (final f in beans.positionalFields) field(f.type, null)],
      [for (final f in beans.namedFields) field(f.type, f.name)],
    ),
  );
}

/// Collects the `@BuildContextAccess` getters of `module.beans` into
/// `module.buildContextAccess`, reporting each invalid one through
/// [collectErrors]: a name that is no public identifier, a reserved word,
/// a member of `BuildContext`, `Object` or spring_boot_starter_flutter's own
/// extension, two beans with the same getter, or `@BuildContextAccess` on a
/// class that is no bean of this module.
void scanBuildContextAccess(
  ModuleModel module,
  void Function(void Function() action) collectErrors,
) {
  final byGetter = <String, BeanModel>{};
  final annotated = <Element>{};
  for (final bean in module.beans) {
    final element = bean.element;
    final annotation = contextAccessChecker.firstAnnotationOf(element);
    if (annotation == null) {
      continue;
    }
    annotated.add(element);
    collectErrors(() {
      final explicit = annotation.getField('name')?.toStringValue();
      final getter = explicit ?? bean.name;
      final what = explicit != null
          ? "@BuildContextAccess(name: '$getter') on ${bean.source}"
          : "@BuildContextAccess on bean '${bean.name}' (${bean.source})";
      final fix = explicit != null
          ? 'Choose another name.'
          : "Give the getter a name: @BuildContextAccess(name: 'myGetter').";
      if (!_identifier.hasMatch(getter)) {
        throw InvalidGenerationSource(
          "$what: '$getter' is not a valid Dart identifier for a getter. $fix",
          element: element,
        );
      }
      if (getter.startsWith('_')) {
        throw InvalidGenerationSource(
          "$what: '$getter' is private, so widgets could not use the "
          'getter. $fix',
          element: element,
        );
      }
      if (_reservedWords.contains(getter)) {
        throw InvalidGenerationSource(
          "$what: '$getter' is a reserved word. $fix",
          element: element,
        );
      }
      if (_takenMembers[getter] case final owner?) {
        throw InvalidGenerationSource(
          "$what: '$getter' clashes with $owner.$getter, which a generated "
          'getter cannot replace. $fix',
          element: element,
        );
      }
      if (byGetter[getter] case final other?) {
        throw InvalidGenerationSource(
          "$what: the getter '$getter' is already generated for bean "
          "'${other.name}' (${other.source}). Give one of them another name "
          "with @BuildContextAccess(name: '...').",
          element: element,
        );
      }
      byGetter[getter] = bean;
      module.buildContextAccess.add(
        BuildContextAccessModel(getter, bean, _getterType(bean)),
      );
    });
  }
  for (final element in module.classes) {
    if (!annotated.contains(element) &&
        contextAccessChecker.hasAnnotationOf(element)) {
      collectErrors(
        () => throw InvalidGenerationSource(
          '@BuildContextAccess on ${element.name}, which is no bean of this '
          'application: add @Component() (or another stereotype), or put '
          '@BuildContextAccess on the @Bean method that creates it.',
          element: element,
        ),
      );
    }
  }
}

// The getter's type: a `@Bean` method's declared return type (the bean
// type inferred from its body may be a private or more specific class), a
// `FactoryBean`'s product, else the bean's class.
DartType _getterType(BeanModel bean) {
  if (bean.valueType case final valueType?) {
    return valueType;
  }
  if (bean.factoryObjectTypes case [final product, ...]) {
    return product;
  }
  if (bean.creation case BeanMethodCreation(:final declaredType?)) {
    return declaredType;
  }
  return bean.type;
}

final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

// Dart's reserved words: no getter can have these names.
const _reservedWords = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};

// Members a generated extension getter on BuildContext cannot shadow:
// Flutter's BuildContext, Object, and spring_boot_starter_flutter's
// SpringBuildContext.
const _takenMembers = {
  'widget': 'BuildContext',
  'owner': 'BuildContext',
  'mounted': 'BuildContext',
  'debugDoingBuild': 'BuildContext',
  'findRenderObject': 'BuildContext',
  'size': 'BuildContext',
  'dependOnInheritedElement': 'BuildContext',
  'dependOnInheritedWidgetOfExactType': 'BuildContext',
  'getInheritedWidgetOfExactType': 'BuildContext',
  'getElementForInheritedWidgetOfExactType': 'BuildContext',
  'findAncestorWidgetOfExactType': 'BuildContext',
  'findAncestorStateOfType': 'BuildContext',
  'findRootAncestorStateOfType': 'BuildContext',
  'findAncestorRenderObjectOfType': 'BuildContext',
  'visitAncestorElements': 'BuildContext',
  'visitChildElements': 'BuildContext',
  'dispatchNotification': 'BuildContext',
  'describeElement': 'BuildContext',
  'describeWidget': 'BuildContext',
  'describeMissingAncestor': 'BuildContext',
  'describeOwnershipChain': 'BuildContext',
  'hashCode': 'Object',
  'runtimeType': 'Object',
  'toString': 'Object',
  'noSuchMethod': 'Object',
  'springContext': 'SpringBuildContext',
  'bean': 'SpringBuildContext',
  'message': 'SpringBuildContext',
};

/// `@ChangeNotifierComponent` of spring_boot_starter_flutter: a bean whose
/// proxy mixes `ChangeNotifier` in.
const changeNotifierComponentChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/notify_listeners.dart'
  '#ChangeNotifierComponent',
);

/// `@NotifyListeners` of spring_boot_starter_flutter.
const notifyListenersChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/notify_listeners.dart'
  '#NotifyListeners',
);

/// Flutter's `ChangeNotifier`.
const changeNotifierChecker = TypeChecker.fromUrl(
  'package:flutter/src/foundation/change_notifier.dart#ChangeNotifier',
);

/// The members a proxy that mixes `ChangeNotifier` in gets from it.
const changeNotifierMembers = {
  'addListener',
  'removeListener',
  'dispose',
  'notifyListeners',
  'hasListeners',
};

/// Whether the proxy of a class with [classAnnotations] and [targetType]
/// mixes `ChangeNotifier` in: a `@ChangeNotifierComponent` class that is no
/// `ChangeNotifier` itself.
bool mixesChangeNotifierIn(
  List<DartObject> classAnnotations,
  InterfaceType targetType,
) =>
    classAnnotations.any((annotation) {
      final type = annotation.type;
      return type != null && changeNotifierComponentChecker.isExactlyType(type);
    }) &&
    !changeNotifierChecker.isAssignableFromType(targetType);

/// Checks a class carrying `@ChangeNotifierComponent` or a class-level
/// `@NotifyListeners`: every name in `exclude` is one of its public methods,
/// setters or fields; a `@ChangeNotifierComponent` class that is no
/// `ChangeNotifier` declares none of `ChangeNotifier`'s members (its proxy
/// gets them).
void checkChangeNotifierComponent(ClassElement element) {
  final name = element.name ?? '?';
  for (final (checker, label) in [
    (changeNotifierComponentChecker, '@ChangeNotifierComponent'),
    (notifyListenersChecker, '@NotifyListeners'),
  ]) {
    final annotation = checker.firstAnnotationOfExact(element);
    if (annotation == null) {
      continue;
    }
    final members =
        {
              for (final method in element.methods)
                if (method.isPublic && !method.isStatic) method.name,
              for (final field in element.fields)
                if (field.isPublic && !field.isStatic) field.name,
              for (final getter in element.getters)
                if (getter.isPublic && !getter.isStatic) getter.name,
              for (final setter in element.setters)
                if (setter.isPublic && !setter.isStatic) setter.name,
              for (final supertype in element.allSupertypes)
                if (!supertype.isDartCoreObject) ...[
                  for (final method in supertype.methods)
                    if (method.isPublic) method.name,
                  for (final setter in supertype.setters)
                    if (setter.isPublic) setter.name,
                  for (final getter in supertype.getters)
                    if (getter.isPublic) getter.name,
                ],
            }
            .whereType<String>()
            .map((n) => n.endsWith('=') ? n.substring(0, n.length - 1) : n)
            .toSet();
    for (final excluded
        in ConstantReader(annotation).peek('exclude')?.listValue ??
            const <DartObject>[]) {
      final excludedName = excluded.toStringValue();
      if (excludedName != null && !members.contains(excludedName)) {
        throw InvalidGenerationSource(
          '$label on $name: exclude names $excludedName, which is no public '
          'method, setter or field of $name.',
          element: element,
        );
      }
    }
    if (checker == changeNotifierComponentChecker &&
        !changeNotifierChecker.isAssignableFromType(element.thisType)) {
      final clashes = members.intersection(changeNotifierMembers);
      if (clashes.isNotEmpty) {
        throw InvalidGenerationSource(
          '@ChangeNotifierComponent on $name: ${clashes.join(', ')} would '
          'clash with the ChangeNotifier its proxy mixes in; rename '
          '${clashes.length == 1 ? 'it' : 'them'}, or let $name extend '
          'ChangeNotifier.',
          element: element,
        );
      }
    }
  }
}
