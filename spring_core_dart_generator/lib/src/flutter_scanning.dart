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

/// Recognises `@BuildContextAccess` of `spring_boot_starter_flutter`, which
/// asks for a `BuildContext` getter for a bean. Matched by URL, so the
/// generator does not depend on that package.
const contextAccessChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/annotations.dart#BuildContextAccess',
);

/// Recognises `SpringStatelessWidget` of `spring_boot_starter_flutter`, a
/// widget that gets the beans named in its record type argument.
const springWidgetChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/spring_widgets.dart#SpringStatelessWidget',
);

/// Recognises `SpringState` of `spring_boot_starter_flutter`: the `State`
/// of a stateful widget that gets the beans named in its record type
/// argument (`SpringState<W, R>`).
const springStateChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/spring_widgets.dart#SpringState',
);

/// A getter to generate in `extension SpringBeans on BuildContext` for a
/// bean marked `@BuildContextAccess`.
///
/// It lets widget code write `context.basket` instead of looking the bean
/// up by type and qualifier. The getter is written into the `.spring.dart`
/// of the `@SpringBootApplication` or `@ComponentScan`.
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

  /// The getter's name: `@BuildContextAccess(name: ...)`, else the bean
  /// name.
  final String getter;

  /// The bean it returns, looked up by its name as qualifier.
  final BeanModel bean;

  /// The getter's type: the bean class, a `@Bean` method's declared return
  /// type, or a `FactoryBean`'s product type.
  final DartType type;
}

/// One field of the bean record of a Spring widget or state: a bean the
/// widget gets.
class SpringWidgetField {
  /// A field of bean type [type]; [name] for a named field.
  SpringWidgetField(this.type, {required this.optional, this.name});

  /// The bean type, without `?`.
  final InterfaceType type;

  /// The field's name for a named field, `null` for a positional one. When
  /// several beans have [type], the name picks one.
  final String? name;

  /// Whether the field is nullable: the bean is looked up with `findBean`
  /// and may be missing; it is not checked at startup.
  final bool optional;
}

/// A scanned `SpringStatelessWidget<R>` or `SpringState<W, R>` class, and
/// how its bean record `R` ([beans]) is filled.
///
/// A widget gets its beans as one record, so code is needed that knows
/// the record's fields and looks each bean up. Every widget of the module
/// becomes one binding in the module's `SpringWidgetBindings` bean.
/// `SpringApplicationWidget` uses the bindings to check at startup that
/// the required beans exist, and the widget uses its binding to build the
/// record.
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

  /// The widget or state class, for error messages and imports.
  final ClassElement widget;

  /// The key of the binding, `package:app/x.dart#Widget`.
  final String source;

  /// The record type `R`.
  final RecordType beans;

  /// The positional fields, in order.
  final List<SpringWidgetField> positional;

  /// The named fields, in the record type's order.
  final List<SpringWidgetField> named;

  /// The bean types checked at startup: those of the non-nullable fields.
  Iterable<InterfaceType> get requiredTypes => [
    for (final field in [...positional, ...named])
      if (!field.optional) field.type,
  ];
}

/// Adds a [SpringWidgetModel] for [element] to `module.springWidgets` when
/// it extends `SpringStatelessWidget<R>` or `SpringState<W, R>`.
///
/// An abstract class whose `R` is still a type parameter (a base class for
/// widgets) is skipped. Throws `InvalidGenerationSource` when `R` is not a
/// non-nullable record, or when a field of it is not a class or interface
/// type (`dynamic`, `Object`, `Function`, a record, `Null`).
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

/// Adds a [BuildContextAccessModel] to `module.buildContextAccess` for each
/// bean of `module.beans` marked `@BuildContextAccess`, on its class or on
/// its `@Bean` method.
///
/// Each invalid getter is reported through [collectErrors], so the build
/// lists them together: a name that is not a public identifier, a reserved
/// word, a member of `BuildContext`, `Object` or the starter's own
/// `SpringBuildContext` extension (which would hide the getter), two beans
/// with the same getter, or `@BuildContextAccess` on a class that is not a
/// bean of this module.
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

/// Recognises `@ChangeNotifierComponent` of `spring_boot_starter_flutter`:
/// a bean whose generated proxy mixes `ChangeNotifier` in, so widgets
/// rebuild when its state changes.
const changeNotifierComponentChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/notify_listeners.dart'
  '#ChangeNotifierComponent',
);

/// Recognises `@NotifyListeners` of `spring_boot_starter_flutter`, which
/// marks the methods and setters after which listeners are notified (on a
/// class: every public one but those in `exclude`).
const notifyListenersChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter/src/notify_listeners.dart'
  '#NotifyListeners',
);

/// Recognises Flutter's `ChangeNotifier`, to tell whether a class already
/// is one.
const changeNotifierChecker = TypeChecker.fromUrl(
  'package:flutter/src/foundation/change_notifier.dart#ChangeNotifier',
);

/// The public members a proxy that mixes `ChangeNotifier` in gets from it.
/// A `@ChangeNotifierComponent` class must not declare them.
const changeNotifierMembers = {
  'addListener',
  'removeListener',
  'dispose',
  'notifyListeners',
  'hasListeners',
};

/// Whether the proxy of a class with [classAnnotations] and [targetType]
/// mixes `ChangeNotifier` in: true for a `@ChangeNotifierComponent` class
/// that is not a `ChangeNotifier` itself (one that is already notifies on
/// its own).
bool mixesChangeNotifierIn(
  List<DartObject> classAnnotations,
  InterfaceType targetType,
) =>
    classAnnotations.any((annotation) {
      final type = annotation.type;
      return type != null && changeNotifierComponentChecker.isExactlyType(type);
    }) &&
    !changeNotifierChecker.isAssignableFromType(targetType);

/// Fails the build when `@ChangeNotifierComponent` or a class-level
/// `@NotifyListeners` on [element] cannot work as written.
///
/// Every name in `exclude` must be a public method, setter or field of the
/// class, its own or inherited; otherwise a typo would silently exclude
/// nothing. A `@ChangeNotifierComponent` class that is not a
/// `ChangeNotifier` must not declare any of [changeNotifierMembers],
/// because its proxy gets them from the mixin.
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
