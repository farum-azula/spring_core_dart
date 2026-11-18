part of 'bean_scanner.dart';

// What the starters' parts get of the scanner: the module, its way of
// reporting a problem, and the readings of classes the core makes for its
// own beans, which a part reuses for the classes it reads (the data
// starter's entities and repositories), so both read a class the same way.

/// What the scan hooks of a `StarterGeneration` get: the module being
/// filled, the scanner's way of reporting a problem without stopping the
/// scan, and what the scanner reads of a class for the core's own beans
/// and introspections, for the classes a part reads.
///
/// ```dart
/// @override
/// bool claimClass(ClassElement element, ModuleScan scan) {
///   if (!clockChecker.hasAnnotationOf(element)) {
///     return false;
///   }
///   scan.addGeneratedBean(element, ClockCreation(element));
///   return true;
/// }
/// ```
base class ModuleScan {
  /// The scan of the module [scanner] fills.
  ModuleScan(BeanScanner scanner) : _scanner = scanner;

  final BeanScanner _scanner;

  /// The module being filled. A part keeps what it finds in a model of its
  /// own, [ModuleModel.starterModel].
  ModuleModel get module => _scanner.module;

  /// Runs [action], adding the `InvalidGenerationSource` it throws to the
  /// build's errors instead of stopping the build (see
  /// [BeanScanner.collectErrors]).
  void collectErrors(void Function() action) => _scanner.collectErrors(action);

  /// The name of [element]; an unnamed one fails the build.
  String requireName(Element element) => _scanner._requireName(element);

  /// The public instance fields with a getter that describe [element], as
  /// its introspection lists them: its own, its mixins' (the last one
  /// first), then each superclass's with its mixins'; the first
  /// declaration of a name wins. Interfaces are left out.
  Iterable<FieldElement> describedFields(ClassElement element) =>
      _scanner._describedFields(_scanner._describedClasses(element));

  /// The annotations of [element] the generated code writes: public, not
  /// of the SDK nor the container's own. One the generated code cannot
  /// re-create (a private constant among its values) is left out; a
  /// constraint or `@Valid` fails the build instead.
  List<DartObject> userAnnotations(Element element) =>
      _scanner._userAnnotations(element);

  /// Whether the generated code can write [value] as a constant
  /// expression (no private constant or function among its values).
  bool isRecreatable(DartObject value) => _scanner._isRecreatable(value);

  /// The first private class [type] mentions (itself, a type argument, a
  /// function or record part), which the generated code cannot name; or
  /// `null`.
  InterfaceType? privateType(DartType type) => BeanScanner._privateType(type);

  /// The constant initial value of [field], or `null` when it has none the
  /// generated code can write. The initializers are those of the classes
  /// the build resolved before the scan: the introspected ones, and those a
  /// part asked for (`StarterGeneration.initialValueClasses`).
  InitialValue? initialValueOf(FieldElement field) =>
      _scanner.initialValueOf(field);

  /// Introspects the classes of [user]'s package that [type] is made of
  /// (its type arguments too: `Future<Page<Book>>`) for [need]: what the
  /// part's runtime does with them (reads them, creates them, evaluates
  /// expressions over them).
  void introspectUsed(
    DartType type,
    ClassElement user, {
    required IntrospectionNeed need,
  }) => _scanner._introspectUsed(type, user, need: need);

  /// Where the expressions of [annotations] (those of one method) look, as
  /// the parts that know them say ([StarterGeneration.expressionUse]): at
  /// the arguments, the result, the bean. For a part whose annotation
  /// reads values by the expressions of others (`@PreAuthorize` and a
  /// method's other annotations, `@Caching` and those it holds).
  SpelUse spelUse(Iterable<DartObject> annotations) =>
      _scanner._spelUse(annotations);

  /// The member a generated class writes for [method] of the type whose
  /// [hierarchy] is given (the type first, then its supertypes),
  /// [declaringType] naming it in messages: the signature with its
  /// parameter names and defaults, and the annotations advice matches. A
  /// proxy's member is read the same way. `null` when its types or default
  /// values cannot be written in the generated library.
  ProxyMember? proxyMember(
    MethodElement method,
    List<InterfaceType> hierarchy,
    String declaringType,
  ) => _scanner._proxyMethod(method, hierarchy, declaringType);

  /// Adds to the module the bean of [element], an interface or abstract
  /// class whose implementation the part generates, made by [creation]: a
  /// bean as any other, named by its `@Component(name:)` or after the
  /// class (`BookRepository` → `bookRepository`), looked up by the class
  /// and its supertypes, with its `@Primary`, `@Qualifier`s, conditions
  /// and annotations; and a proxy (`_$BookRepositoryProxy`) unless the
  /// build's proxies are off, so advice (`@Transactional` on its methods)
  /// wraps it.
  void addGeneratedBean(ClassElement element, StarterCreation creation) =>
      _scanner._addGeneratedBean(element, creation);
}
