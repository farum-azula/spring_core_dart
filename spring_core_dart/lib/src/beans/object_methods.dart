// `@EqualsAndHashCode`, `@ToString` and `@CopyWith`: the object methods
// of a data class, written by the generator into the class's description,
// like Lombok's annotations; `IntrospectedObject`, the mixin whose `==`,
// `hashCode` and `toString()` call them.
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/core/deep_equality.dart';
import 'package:spring_core_dart/src/core/secret_names.dart';

/// An annotation that gives a class `==` and `hashCode` from its fields,
/// so two objects with the same values are equal and find each other in a
/// `Set` or as a `Map` key.
///
/// The generator writes the comparison into the class's description (its
/// [Introspection], in `lib/spring_gen/<library>.spring.introspection.dart`), and
/// the class mixes in [IntrospectedObject], whose `==` and `hashCode` call
/// it. Nothing else is added to the class's file; the build says what to
/// add when the `with` is missing.
///
/// ```dart
/// @EqualsAndHashCode()
/// class Book with IntrospectedObject {
///   const Book(this.title, this.tags);
///
///   final String title;
///   final List<String> tags;
/// }
///
/// Book('Dune', ['sf']) == Book('Dune', ['sf']); // true
/// {Book('Dune', ['sf'])}.contains(Book('Dune', ['sf'])); // true
/// ```
///
/// The fields are the public instance fields the class declares, in their
/// order: [include] names exactly those to use, [exclude] those to leave
/// out (both at once, or a name that is no field of the class, fails the
/// build). Inherited fields count only through [callSuper]. A private
/// field cannot be read from the generated library: it is left out, with a
/// warning of the build unless it is excluded. Fields typed `List`, `Set`,
/// `Map` or `Iterable` (or `Object`, `dynamic` or a type parameter, which
/// may hold one) compare and hash by content, nested ones too ([deepEquals]
/// and [deepHash]); the others with their own `==`. Objects of different
/// classes are never equal (a subclass of `Book` is no `Book` for `==`).
///
/// The build fails when the class does not mix in [IntrospectedObject], or
/// when its `==` or `hashCode` is not IntrospectedObject's (the class, a
/// mixin after it or a superclass declares its own); on an abstract, sealed
/// or `interface` class, a private class, a `@Configuration` class or an
/// aspect (they declare beans and advice, no data); and on an enum, a
/// mixin, an extension, an extension type, a typedef or a member. The
/// build warns about a field in `hashCode` that is not final: an object
/// whose hash changes is lost in the `Set` or `Map` that holds it; exclude
/// the field to say it is meant.
///
/// A `const` constructor stays `const`, but an object with its own `==`
/// can no longer be a key of a constant map or an element of a constant
/// set (Dart asks for primitive equality there). A bean the container
/// hands out through a proxy is compared as the proxy: by identity.
/// Reading a `late` field that is not set yet throws, as in any Dart code.
/// No build key: the methods are the application's behaviour at run time
/// in every build.
///
/// Spring (Java), with Lombok:
/// ```java
/// @EqualsAndHashCode(exclude = "cover")
/// class Book { String title; List<String> tags; byte[] cover; }
/// ```
final class EqualsAndHashCode {
  /// Asks for `==` and `hashCode` over the fields of [include], or all
  /// but those of [exclude], and those of the superclass with [callSuper].
  const EqualsAndHashCode({this.include, this.exclude, this.callSuper = false});

  /// The fields to compare and hash, exactly these; all the class declares
  /// when `null`. Not together with [exclude].
  final List<String>? include;

  /// The fields left out; none when `null`. Not together with [include].
  final List<String>? exclude;

  /// Whether the superclass's part comes first: its description's `==`
  /// and `hashCode` when it has `@EqualsAndHashCode` too, else its own
  /// (`super == other`, `super.hashCode`, which [IntrospectedObject] calls;
  /// the class then mixes it in itself). The build fails when the class
  /// extends no class but `Object`, or when the superclass's `==` is
  /// identity: no two objects would be equal.
  final bool callSuper;
}

/// An annotation that gives a class a `toString()` that shows its fields:
/// `Book(title: Dune, pages: 412)`.
///
/// The generator writes the text into the class's description (see
/// [EqualsAndHashCode]), and the class mixes in [IntrospectedObject],
/// whose `toString()` calls it. The class's name in the text is its name
/// in the source, also in a minified web build.
///
/// ```dart
/// @ToString(mask: ['card'])
/// class Login with IntrospectedObject {
///   Login(this.user, this.password, this.card);
///
///   final String user;
///   final String password;
///   final String card;
/// }
///
/// Login('ada', 'hunter2', '4242').toString();
/// // Login(user: ada, password: ******, card: ******)
/// ```
///
/// A field whose name looks secret ([SecretNames.looksSecret]: `password`,
/// `apiKey`, `refreshToken`, ...) is written `******`, and so is a field
/// of [mask]; [reveal] shows a field the rule would hide. That is decided
/// at build time: the value of a masked field is never read. The fields
/// are chosen as for [EqualsAndHashCode] ([include], [exclude], private
/// fields left out with a warning). Without [includeNames] only the
/// values are written (`Book(Dune, 412)`); with [callSuper] the
/// superclass's text comes first (`Book(super: Base(id: 1), title: Dune)`).
///
/// The build fails when the class's `toString` is not
/// [IntrospectedObject]'s, for a name of [mask] or [reveal] that is no
/// field written, a name in both, a name of [reveal] the rule does not
/// hide, and for the targets [EqualsAndHashCode] refuses. A class with an
/// `==` of its own may have `@ToString` alone.
///
/// Spring (Java), with Lombok:
/// ```java
/// @ToString(exclude = "cover", includeFieldNames = true)
/// class Book { String title; int pages; byte[] cover; }
/// ```
final class ToString {
  /// Asks for a `toString()` of the fields of [include], or all but those
  /// of [exclude], with their names unless [includeNames] is `false`, and
  /// the superclass's text first with [callSuper].
  const ToString({
    this.include,
    this.exclude,
    this.includeNames = true,
    this.callSuper = false,
    this.mask = const [],
    this.reveal = const [],
  });

  /// The fields to write, exactly these; all the class declares when
  /// `null`. Not together with [exclude].
  final List<String>? include;

  /// The fields left out; none when `null`. Not together with [include].
  final List<String>? exclude;

  /// Whether each value follows its field's name (`title: Dune`); only the
  /// values (`Dune`) when `false`.
  final bool includeNames;

  /// Whether the superclass's text is written first: its description's
  /// when it has `@ToString` too, else its own `toString()`. The build
  /// fails when the class extends no class but `Object`.
  final bool callSuper;

  /// More fields written `******`, besides those whose names look secret.
  final List<String> mask;

  /// Fields whose names look secret but are written as they are.
  final List<String> reveal;
}

/// An annotation that gives a class a typed `copyWith`: a copy with some
/// values changed.
///
/// The generator writes it into `lib/spring_gen/<library>.spring.introspection.dart`
/// as an extension; the libraries that call `copyWith` import that file
/// (the class's own file needs nothing). An argument left out keeps the
/// value of the original, `null` clears a nullable field, and a value of
/// the wrong type does not compile. `copyWith` is a getter returning a
/// function (`BookCopyWith`), so `copyWith(subtitle: null)` is no
/// redundant argument for the analyzer.
///
/// ```dart
/// @CopyWith()
/// class Book {
///   const Book(this.title, {required this.pages, this.subtitle});
///
///   final String title;
///   final int pages;
///   final String? subtitle;
/// }
///
/// // import 'package:shop/spring_gen/src/app.spring.introspection.dart';
/// final dune = Book('Dune', pages: 412, subtitle: 'Book one');
/// dune.copyWith(pages: 896);       // Dune, 896 pages, Book one
/// dune.copyWith(subtitle: null);   // Dune, 412 pages, no subtitle
/// ```
///
/// The copy is made by the class's unnamed constructor, or the one
/// [constructor] names (a factory too). Each copied field must match a
/// constructor parameter by name, or the build fails naming the field; a
/// field left out by [include] or [exclude] is passed on as it is. A
/// generic class keeps its type arguments: `Page<Book>.copyWith(...)`
/// returns a `Page<Book>`. The build fails on the targets
/// [EqualsAndHashCode] refuses, a missing or private constructor, a
/// required parameter no field can fill, and a class with a member named
/// `copyWith` (it would win over the extension).
///
/// Spring (Java), with Lombok: `@With` (one `withTitle(...)` per field).
final class CopyWith {
  /// Asks for a `copyWith` of the fields of [include], or all but those of
  /// [exclude], made through [constructor].
  const CopyWith({this.include, this.exclude, this.constructor});

  /// The fields `copyWith` can change, exactly these; all the class
  /// declares when `null`. Not together with [exclude].
  final List<String>? include;

  /// The fields `copyWith` cannot change (they keep their value); none
  /// when `null`. Not together with [include].
  final List<String>? exclude;

  /// The name of the constructor that makes the copy (`'of'` for
  /// `Book.of(...)`); the unnamed one when `null`.
  final String? constructor;
}

/// Where the superclass's part of an object method comes from
/// ([ObjectMethods.superEquals], [ObjectMethods.superToString]): with
/// `callSuper: true`, or for a method the class's annotations do not
/// generate.
enum SuperMethod {
  /// No part of the superclass: the generated method alone; for a method
  /// that is not generated, the superclass's own (`super == other`).
  none,

  /// The described superclass's ([ObjectMethods.superclass], the closest
  /// class above with `@EqualsAndHashCode` or `@ToString`): its method
  /// first, then the generated one; for a method that is not generated,
  /// its method alone (a subclass with `@ToString` keeps the `==` of its
  /// superclass's `@EqualsAndHashCode`).
  described,

  /// The superclass's own `==`, `hashCode` or `toString()`, written by
  /// hand, which [IntrospectedObject] calls as `super` (the class mixes it
  /// in itself), then the generated one.
  inherited,
}

/// The `==`, `hashCode` and `toString()` of a class, generated for
/// `@EqualsAndHashCode` and `@ToString` into the class's [Introspection]
/// ([Introspection.objectMethods]); [IntrospectedObject] calls them.
///
/// The functions are typed (`bool Function(Book a, Book b)`) and compare,
/// hash and write the fields the annotations chose. With `callSuper: true`
/// the superclass's part comes first ([superEquals], [superToString]): its
/// description's methods when it has the annotation too
/// ([SuperMethod.described], [superclass]), else its own
/// ([SuperMethod.inherited]). A method the annotations do not generate is
/// the described superclass's when there is one, else the superclass's own
/// (`@ToString` alone on a class that extends `Object`: `==` is identity).
///
/// ```dart
/// // Generated for @EqualsAndHashCode() @ToString() on Book:
/// bool _$equals0(Book a, Book b) =>
///     a.title == b.title && deepEquals(a.tags, b.tags);
/// int _$hashCode1(Book object) =>
///     Object.hash(object.title, deepHash(object.tags));
/// String _$toString2(Book object) =>
///     'Book(title: ${object.title}, tags: ${object.tags})';
///
/// const Introspection<Book>(
///   className: r'Book',
///   objectMethods: ObjectMethods<Book>(
///     equals: _$equals0,
///     hashCode: _$hashCode1,
///     toString: _$toString2,
///   ),
/// )
/// ```
///
/// Spring (Java): no counterpart; Lombok writes the methods into the class
/// at compile time.
final class ObjectMethods<T extends Object> {
  /// The methods of [T]: `equals` compares two of its objects field by
  /// field, `hashCode` hashes one, `toString` writes one; with
  /// `callSuper`, `toStringWithSuper` writes one after the superclass's
  /// text (its second argument), and [superclass], [superEquals] and
  /// [superToString] say where the superclass's part comes from.
  const ObjectMethods({
    this._equals,
    this._hashCode,
    this._toString,
    this._toStringWithSuper,
    this.superclass,
    this.superEquals = SuperMethod.none,
    this.superToString = SuperMethod.none,
  });

  final bool Function(T a, T b)? _equals;
  final int Function(T object)? _hashCode;
  final String Function(T object)? _toString;
  final String Function(T object, String superText)? _toStringWithSuper;

  /// The described superclass ([SuperMethod.described]): the closest class
  /// above [T] with `@EqualsAndHashCode` or `@ToString`.
  final Type? superclass;

  /// Where the superclass's part of `==` and `hashCode` comes from.
  final SuperMethod superEquals;

  /// Where the superclass's part of `toString()` comes from.
  final SuperMethod superToString;

  /// Whether [IntrospectedObject]'s `==` and `hashCode` are these
  /// ([equalsOf], [hashCodeOf]): generated, or the described superclass's.
  /// Otherwise they are the superclass's own.
  bool get definesEquals =>
      _equals != null || superEquals == SuperMethod.described;

  /// Whether [IntrospectedObject]'s `toString()` is this one ([toStringOf]):
  /// generated, or the described superclass's. Otherwise it is the
  /// superclass's own.
  bool get definesToString =>
      _toString != null ||
      _toStringWithSuper != null ||
      superToString == SuperMethod.described;

  /// Whether [object] is a [T].
  bool isInstance(Object object) => object is T;

  /// Whether [T] is a subtype of the class [other] describes.
  bool isSubtypeOf(ObjectMethods<Object> other) => other._isSupertypeOf<T>();

  bool _isSupertypeOf<S>() => <S>[] is List<T>;

  ObjectMethods<Object> _parent() {
    final type = superclass!;
    return Introspector.objectMethodsForType(type) ??
        (throw StateError(
          'No description of $type is registered, though the object '
          "methods of $T use its own. Register the descriptions of $type's "
          'module too.',
        ));
  }

  /// Whether [IntrospectedObject]'s `==` and `hashCode` call the
  /// superclass's own first (`super == other`), for this class or for the
  /// described superclass.
  bool get equalsCallsSuper => switch (superEquals) {
    SuperMethod.none => false,
    SuperMethod.inherited => true,
    SuperMethod.described => _parent().equalsCallsSuper,
  };

  /// Whether [IntrospectedObject]'s `toString()` calls the superclass's own
  /// first, for this class or for the described superclass.
  bool get toStringCallsSuper => switch (superToString) {
    SuperMethod.none => false,
    SuperMethod.inherited => true,
    SuperMethod.described => _parent().toStringCallsSuper,
  };

  /// Whether [a] and [b], two objects of one class, are equal: the
  /// described superclass's comparison first, then the generated one.
  /// [IntrospectedObject] has checked their runtime types, and the
  /// superclass's own `==` when [equalsCallsSuper].
  bool equalsOf(Object a, Object b) {
    if (superEquals == SuperMethod.described && !_parent().equalsOf(a, b)) {
      return false;
    }
    final equals = _equals;
    return equals == null || equals(a as T, b as T);
  }

  /// The hash code of [object]: the generated one, combined with the
  /// superclass's ([superHash], its own `hashCode` when [equalsCallsSuper],
  /// or its description's).
  int hashCodeOf(Object object, int superHash) {
    final parent = switch (superEquals) {
      SuperMethod.none => null,
      SuperMethod.inherited => superHash,
      SuperMethod.described => _parent().hashCodeOf(object, superHash),
    };
    final hash = _hashCode;
    if (hash == null) {
      return parent ?? superHash;
    }
    final own = hash(object as T);
    return parent == null ? own : Object.hash(parent, own);
  }

  /// The text of [object]: the generated one, after the superclass's
  /// ([superText], its own `toString()` when [toStringCallsSuper], or its
  /// description's).
  String toStringOf(Object object, String? superText) {
    if (_toString case final text?) {
      return text(object as T);
    }
    final parent = switch (superToString) {
      SuperMethod.none || SuperMethod.inherited => superText ?? '',
      SuperMethod.described => _parent().toStringOf(object, superText),
    };
    final withSuper = _toStringWithSuper;
    return withSuper == null ? parent : withSuper(object as T, parent);
  }

  @override
  String toString() => 'ObjectMethods<$T>';
}

/// The mixin whose `==`, `hashCode` and `toString()` are those the
/// generator wrote for the class's `@EqualsAndHashCode` and `@ToString`.
///
/// It finds them in the class's description, through the [Introspector]
/// ([Introspector.objectMethodsOf], by the object's runtime type), so the
/// class's own file needs nothing generated: one `with`.
///
/// ```dart
/// @EqualsAndHashCode()
/// @ToString()
/// class Book with IntrospectedObject {
///   const Book(this.title);
///
///   final String title;
/// }
/// ```
///
/// `==` is `identical(this, other)`, or the same runtime type and equal
/// fields. A method the annotations do not generate is the superclass's
/// (`@ToString` alone: `==` stays identity, or the `==` of a superclass
/// with `@EqualsAndHashCode`). A class without a description of its own (a
/// subclass the build did not annotate) uses that of its closest described
/// superclass. When no description is registered at all (a unit test that
/// started no context), each of the three throws a `StateError` that says
/// how to register them: never a silent comparison by identity.
///
/// The descriptions are registered by the application's context as it
/// starts, or in a test without one by
/// `Introspector.shared.registerAll($appIntrospections)` (the getter of
/// the module's generated `<library>.spring.introspection.dart`).
///
/// Spring (Java): no counterpart; Lombok writes `equals`, `hashCode` and
/// `toString` into the class.
mixin IntrospectedObject {
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    final methods = Introspector.objectMethodsOf(this);
    if (!methods.definesEquals) {
      return super == other;
    }
    if (other.runtimeType != runtimeType ||
        (methods.equalsCallsSuper && !(super == other))) {
      return false;
    }
    return methods.equalsOf(this, other);
  }

  @override
  int get hashCode {
    final methods = Introspector.objectMethodsOf(this);
    if (!methods.definesEquals) {
      return super.hashCode;
    }
    return methods.hashCodeOf(
      this,
      methods.equalsCallsSuper ? super.hashCode : 0,
    );
  }

  @override
  String toString() {
    final methods = Introspector.objectMethodsOf(this);
    if (!methods.definesToString) {
      return super.toString();
    }
    return methods.toStringOf(
      this,
      methods.toStringCallsSuper ? super.toString() : null,
    );
  }
}
