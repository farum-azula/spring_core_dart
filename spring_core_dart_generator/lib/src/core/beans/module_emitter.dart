import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart' as cb show FunctionType;
import 'package:code_builder/code_builder.dart' hide FunctionType, RecordType;
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/aop/aop_analysis.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/log_scanning.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart';
import 'package:spring_core_dart_generator/src/core/builder/code_writer.dart';
import 'package:spring_core_dart_generator/src/core/builder/dart_format.dart';
import 'package:spring_core_dart_generator/src/core/builder/generated_path.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/core/introspection/introspection_emitter.dart';
import 'package:spring_core_dart_generator/src/core/introspection/introspection_model.dart';
import 'package:spring_core_dart_generator/src/core/introspection/object_methods/object_methods_model.dart';

part 'configuration_emitter.dart';
part 'lookup_emitter.dart';

// Runtime types are always imported from the public library, never from
// `src/`.
const _springUrl = 'package:spring_core_dart/spring_core_dart.dart';

const _payloadApplicationEvent = TypeChecker.typeNamedLiterally(
  'PayloadApplicationEvent',
  inPackage: 'spring_core_dart',
);

// A reference to a public runtime type, e.g. `BeanDefinition`.
Reference _spring(String name) => refer(name, _springUrl);

/// A raw string literal of [value], so `$` and backslashes in names and
/// expressions are written as they are.
Expression _str(String value) => literalString(value, raw: true);

/// [value] (a user string: a bean name, a logger topic) for a generated
/// `///` comment: on one line, as a line break would end the comment and
/// turn the rest into code; control characters are written as escapes.
String _docText(String value) => value.replaceAllMapped(
  RegExp(r'[\x00-\x1f\x7f\u0085\u2028\u2029]'),
  (match) => switch (match[0]!) {
    '\n' => r'\n',
    '\r' => r'\r',
    '\t' => r'\t',
    final char => '\\u{${char.codeUnitAt(0).toRadixString(16)}}',
  },
);

/// Writes the sources of a module (a `*.spring.dart` library and the files
/// beside it, [ModuleSources]) from a scanned [ModuleModel].
///
/// The scanner decides what the beans are; this class decides how that is
/// written as Dart that the runtime can execute without reflection. One
/// emitter writes one module. Its files by kind, each only when the module
/// has some:
///
/// - `<library>.spring.proxies.dart`, a part of the library: an AOP proxy per
///   proxied bean (and per bean of a library package an aspect may match)
///   and the lazy-resolution proxies;
/// - `<library>.spring.introspection.dart`, a library: the descriptions of the
///   classes the module uses (`IntrospectionEmitter`), in a getter
///   `$<name>Introspections`;
/// - `<library>.spring.properties.dart`, a library: the binding of its
///   `@ConfigurationProperties` classes, the descriptions only their binder
///   uses (`onlyForBinding`), in a getter `$<name>PropertiesIntrospections`;
/// - the parts of an application's library the builder fills
///   (`partDeclarations`): `<library>.spring.debug.dart`, what only debug and
///   profile builds use, which the library refers to only under
///   `!dart.vm.product`, and `<library>.spring.env.dart`, the values of the
///   `--dart-define`s the application may read.
///
/// The library itself contains, in this order:
///
/// - the generated classes: implementations of `@InterfaceProxy`
///   interfaces and the classes of the packages' parts (data
///   repositories), subclasses of full-mode `@Configuration` classes and of
///   classes with `@Lookup` methods;
/// - a getter `BeanModule get $<name>` with a `BeanDefinition` per bean
///   and the module's property sources, embedded resources, imports,
///   registrars, introspections (spread from the descriptions' getters)
///   and configurers. It is a getter, not a
///   variable, so a hot reload that replaces its body yields the beans of
///   the new code;
/// - any extra declarations of the caller (the `springApplication` and
///   `runApplication` functions of a `@SpringBootApplication`), those of
///   the packages' parts (the `BuildContext` extension, the screens'
///   constants) and the `@Log` extensions.
///
/// The packages' parts ([generations]) add their classes, their bean
/// definitions after the beans' (and the creation of the beans they make),
/// their statements to the module getter and their declarations after it,
/// through a [ModuleEmission]; the code of a part in debug and profile
/// builds only sits under the condition [generationConditions] gives it.
///
/// Code is built with `code_builder`, so imports get prefixes such as
/// `_i1.` (omitted in the examples below), and formatted with
/// `dart_style`. Before writing, [emit] runs the AOP checks of
/// [analyzeAop].
///
/// ```dart
/// // Input:
/// @Service()
/// class Greeter {
///   Greeter(this.clock);
///   final Clock clock;
/// }
/// // Output (beans.spring.dart, ProxyMode.none):
/// // GENERATED CODE - DO NOT MODIFY BY HAND
/// // Generated by spring_core_dart_generator from @ComponentScan.
///
/// /// Beans found by `@ComponentScan` in `lib/src/`.
/// BeanModule get $appBeans => BeanModule(r'appBeans', [
///   BeanDefinition<Greeter>(
///     name: r'greeter',
///     source: r'package:app/src/greeter.dart#Greeter',
///     types: const [Greeter],
///     dependencies: const [Dependency(Clock, name: r'clock')],
///     create: (r) => Greeter(r.dependency<Clock>(name: r'clock')),
///   ),
/// ]);
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Classic Spring keeps definitions in memory and uses reflection to
/// // create beans. Spring 6 AOT is the closest match: during the build a
/// // BeanFactoryInitializationAotProcessor (BeanRegistrationsAotContribution)
/// // writes Java source that registers the beans without reflection:
/// public static BeanDefinition getGreeterBeanDefinition() {
///   RootBeanDefinition definition = new RootBeanDefinition(Greeter.class);
///   definition.setInstanceSupplier(BeanInstanceSupplier
///       .<Greeter>forConstructor(Clock.class)
///       .withGenerator((registeredBean, args) ->
///           new Greeter(args.get(0))));
///   return definition;
/// }
/// ```
class ModuleEmitter {
  /// Creates an emitter for the library [output], from which imports are
  /// computed.
  ///
  /// [dependencies] are the packages the output may import from (see the
  /// field). [pruneProxies] and [foreignAdvice] turn on proxy pruning; the
  /// `@ComponentScan` output of a library package passes
  /// `pruneProxies: false` (any module may import it).
  ///
  /// ```dart
  /// final emitter = ModuleEmitter(generatedId(input));
  /// ```
  ModuleEmitter(
    this.output, {
    this.dependencies,
    this.pruneProxies = true,
    this.foreignAdvice,
    this.deferProxies = false,
    this.generations = const [],
    this.generationConditions = const {},
  });

  /// The packages' parts of the build, asked in turn for their classes,
  /// bean definitions, the creation of their beans, module statements and
  /// declarations.
  final List<PackageGeneration> generations;

  /// The condition the code of a part of [generations] is under, by part
  /// ([notInReleaseCondition] for one its build key leaves to debug and
  /// profile builds, `PackageGeneration.build`); a part without one is in
  /// every build. Its bean definitions (those it writes, and those of the
  /// beans it makes), its module statements, its lists of introspections
  /// and its resources are written under it; its classes, declarations and
  /// part files cannot be (a declaration is no statement), and a release
  /// build drops them as nothing else uses them.
  final Map<PackageGeneration, String> generationConditions;

  /// Whether the module (a `lib/` module of a library package) leaves to
  /// the application the proxy classes only its aspects can match
  /// (`AopProxyFactory.deferred`, see [analyzeAop]): only when
  /// [foreignAdvice], the advice of the package's other modules and of the
  /// auto-configurations, cannot match them either.
  final bool deferProxies;

  /// The aspects and advisors of the application's other modules (of the
  /// package's, for [deferProxies]). Only the `@SpringBootApplication`
  /// output knows them all and passes them; when `null`, no proxy is
  /// pruned (see [analyzeAop]).
  final ForeignAdvice? foreignAdvice;

  /// Whether to skip the proxy classes of beans that no pointcut of the
  /// application can match (build option `aop_prune`). It has an effect
  /// only together with [foreignAdvice].
  final bool pruneProxies;

  // The module being emitted.
  late ModuleModel _module;

  // What the packages' parts get of this emitter, for the module being
  // emitted.
  late ModuleEmission _emission;

  /// The library being generated. Imports of files of the same package
  /// outside `lib/` (an `asset:` URI) are written relative to it.
  final AssetId output;

  /// The packages the generated library's package depends on directly,
  /// itself included; `null` when unknown.
  ///
  /// A declaration of any other package (a transitive dependency) is
  /// imported through a library of these that exports it, the way the
  /// user's code reaches it. So the output does not trigger
  /// `depend_on_referenced_packages`.
  final Set<String>? dependencies;

  // How the module's library names types, constants and functions; the
  // libraries of its descriptions have writers of their own, which share
  // its annotation types (the module's `typeTests`).
  late final CodeWriter _writer = CodeWriter(
    output,
    dependencies: dependencies,
  );

  // The `TypeInfo`s and direct calls of the beans' methods, written in the
  // module's library.
  late final IntrospectionEmitter _introspected = IntrospectionEmitter(_writer);

  TypeReference _type(DartType type, Element element) =>
      _writer.classType(type, element);

  Reference _anyType(DartType type, Element element) =>
      _writer.anyType(type, element);

  Expression _constant(DartObject value, Element element) =>
      _writer.constant(value, element);

  Expression _initialValue(Object? value, Element element, [DartType? type]) =>
      _writer.initialValue(value, element, type);

  Expression _closure(
    List<String> parameters,
    Code body, {
    bool lambda = false,
  }) => _writer.closure(parameters, body, lambda: lambda);

  Expression _function(
    String kind,
    Reference returns,
    List<(String, Reference)> parameters,
    Code body, {
    bool lambda = true,
  }) =>
      _writer.topLevelFunction(kind, returns, parameters, body, lambda: lambda);

  Expression _constantDeclaration(String kind, Expression value) =>
      _writer.topLevelConstant(kind, value);

  Expression _functionReference(ExecutableElement function, Element element) =>
      _writer.functionReference(function, element);

  String? _importUrl(
    Uri uri,
    Element element, {
    String? name,
    Element? declaration,
  }) => _writer.importUrl(uri, element, name: name, declaration: declaration);

  (Expression, bool) _typeInfo(DartType type, Element element) =>
      _introspected.typeInfo(type, element);

  (List<Expression>, Map<String, Expression>)? _directArguments(
    List<ConstructorParameterModel> parameters,
    Element element, {
    required Expression positional,
    required Expression? named,
  }) => _introspected.directArguments(
    parameters,
    element,
    positional: positional,
    named: named,
  );

  static TypeReference get _objectOrNull => CodeWriter.objectOrNull;

  static TypeReference get _argumentList => CodeWriter.argumentList;

  static TypeReference get _namedArgumentMap => CodeWriter.namedArgumentMap;

  /// A reference to the class [type], imported like the emitter's own
  /// references, for code the builder writes outside the emitter (the
  /// `exclude` classes of `@SpringBootApplication`).
  Reference classReference(InterfaceType type, Element element) =>
      _type(type, element);

  /// Writes [module] and returns the sources of the generated library and
  /// of its files, unformatted: the builder formats each as its package's
  /// files are ([DartFormat]), once.
  ///
  /// [moduleName] is the `BeanModule` name (the `@ComponentScan` variable,
  /// or `application`), [variableName] the generated getter (`$` +
  /// [moduleName]), and [scannedDirectory] only appears in the getter's doc
  /// comment. [extra] declarations are appended after the getter (and
  /// the parts' leading declarations); [partDeclarations] go into parts
  /// of the library, by the part's ending ([applicationPartExtensions]: the
  /// debug part, which the library refers to only under
  /// `!dart.vm.product`, and the part of the `--dart-define` values).
  /// [resources] are embedded as
  /// `resources:` files. [packageParts] are the generated files of each
  /// part that are `part of` the library ([PackageGeneration.moduleParts]),
  /// with their imports, their lists of introspections and their
  /// resources, in the parts' order; [coreParts] are the core's own (the
  /// classes of `spring.json.schemas`), written after them.
  ///
  /// Throws `InvalidGenerationSource` when a type, constant or function
  /// cannot be referenced from [output] (a private constant, or a file of
  /// another package outside `lib/`), or when [analyzeAop] finds an invalid
  /// pointcut.
  ///
  /// ```dart
  /// final sources = ModuleEmitter(output).emit(
  ///   moduleName: 'appBeans',
  ///   variableName: r'$appBeans',
  ///   scannedDirectory: 'lib/src',
  ///   module: module,
  /// );
  /// // sources.module: "// GENERATED CODE ...
  /// //   BeanModule get $appBeans => BeanModule(r'appBeans', [...],
  /// //       introspections: [..._i2.$appBeansIntrospections]);"
  /// // sources.introspection: "// GENERATED CODE ...
  /// //   List<Introspection<Object>> get $appBeansIntrospections => [...];"
  /// ```
  ///
  /// Spring (Java):
  ///
  /// ```java
  /// // Spring 6 AOT writes the equivalent Java source (with JavaPoet) at
  /// // build time, e.g. AppConfig__BeanDefinitions.java and
  /// // AppConfig__BeanFactoryRegistrations.java.
  /// ```
  ModuleSources emit({
    required String moduleName,
    required String variableName,
    required String scannedDirectory,
    required ModuleModel module,
    List<Spec> extra = const [],
    Map<String, List<Spec>> partDeclarations = const {},
    Map<String, ({String? text, String? base64})> resources = const {},
    Map<PackageGeneration, ModuleParts> packageParts = const {},
    List<ModuleParts> coreParts = const [],
  }) {
    _module = module;
    _packageCreators.clear();
    _usesTypeOf = false;
    _knownAdvisors = null;
    _writer.annotationTypes.clear();
    _writer.topLevelDeclarations.clear();
    analyzeAop(
      module,
      prune: pruneProxies,
      foreign: foreignAdvice,
      defer: deferProxies,
    );
    final emission = _emission = ModuleEmission._(this, moduleName);
    // Classes and definitions first: the types in their annotations go
    // into the module's typeTests. The proxies go into a part of their own
    // (`<library>.spring.proxies.dart`).
    final proxies = <Spec>[
      for (final bean in module.beans)
        if (bean.proxy case final proxy?
            when proxy.unavailableReason == null && !proxy.deferred)
          _proxyClass(proxy, bean.element, lookup: _lookupOf(bean)),
      // Those of beans of library packages an aspect may match.
      for (final foreign in module.foreignProxies)
        if (foreign.proxy.unavailableReason == null)
          _proxyClass(foreign.proxy, foreign.element),
      for (final proxy in module.lazyProxies.values) _lazyClass(proxy),
    ];
    final classes = <Spec>[
      for (final bean in module.beans)
        if (bean.creation case InterfaceProxyCreation(:final model))
          _interfaceImplClass(model),
      for (final generation in generations) ...generation.classes(emission),
      for (final bean in module.beans)
        if (bean.creation case ConstructorCreation(
          configuration: final model?,
        ))
          configurationClass(model),
      for (final bean in module.beans)
        if (_lookupOf(bean) case final model?) lookupClass(model),
      if (module.beans.any(
        (bean) => switch (bean.creation) {
          ConstructorCreation(:final configuration?) =>
            configuration.beanMethods.any((m) => m.defaults.isNotEmpty),
          _ => false,
        },
      ))
        absentMarkerClass(),
    ];
    final definitions = literalList([
      for (final bean in module.beans) _guardedBean(bean, _definition(bean)),
      for (final generation in generations)
        for (final definition in generation.beanDefinitions(emission))
          _guarded(generation, definition),
    ]);
    final parts = [
      for (final part in [...packageParts.values, ...coreParts]) ...part.parts,
    ];
    final proxiesFile = moduleFileId(output, proxiesExtension);
    final partImports = [
      for (final part in [...packageParts.values, ...coreParts])
        ...part.imports,
    ];
    final resourceEntries = _resourceEntries(
      resources,
      packageParts,
      coreParts,
    );
    // The lists of a part (the classes of spring.json.schemas).
    final packageIntrospections = [
      for (final MapEntry(key: generation, value: part) in packageParts.entries)
        for (final list in part.introspections)
          _guarded(generation, refer('...$list')),
      for (final part in coreParts)
        for (final list in part.introspections) refer('...$list'),
    ];
    final descriptions = _ModuleDescriptions(this, variableName);
    final arguments = <String, Expression>{
      if (module.imports.isNotEmpty)
        'imports': literalList([
          for (final variable in module.imports)
            refer(
              variable.name!,
              _importUrl(variable.library.uri, variable, name: variable.name),
            ),
        ]),
      if (resourceEntries.isNotEmpty)
        'resources': literalConstMap(resourceEntries),
      if (module.propertySources.isNotEmpty)
        'propertySources': literalList([
          for (final source in module.propertySources) _propertySource(source),
        ]),
      if (module.registrars.isNotEmpty)
        'registrars': literalList([
          for (final registrar in module.registrars)
            _spring('ImportDeclaration').newInstance(
              [_type(registrar.type, registrar.element).property('new')],
              {
                if (registrar.conditions.isNotEmpty)
                  'conditions': literalList([
                    for (final condition in registrar.conditions)
                      _condition(condition, registrar.element),
                  ]),
                'importer': _str(registrar.importer),
              },
            ),
        ]),
      if (module.foreignProxies.any((f) => f.proxy.unavailableReason == null))
        'aopProxies': _foreignProxies(module.foreignProxies),
      // The descriptions, written into files of their own, at the place of
      // the list: the types in their annotations join the typeTests in the
      // same order.
      if (descriptions.describe(module.introspections) case final lists
          when lists.isNotEmpty || packageIntrospections.isNotEmpty)
        'introspections': literalList([...lists, ...packageIntrospections]),
      if (module.configurables.isNotEmpty)
        'configurers': literalMap({
          for (final configurable in module.configurables)
            _type(configurable.type, configurable.element): _configurer(
              configurable,
            ),
        }),
      if (module.configurables.any((c) => c.postConstruct.isNotEmpty))
        'configurablePostConstruct': literalMap({
          for (final configurable in module.configurables)
            if (configurable.postConstruct.isNotEmpty)
              _type(configurable.type, configurable.element):
                  _configurableCalls(configurable, configurable.postConstruct),
        }),
      if (module.configurables.any((c) => c.preDestroy.isNotEmpty))
        'configurablePreDestroy': literalMap({
          for (final configurable in module.configurables)
            if (configurable.preDestroy.isNotEmpty)
              _type(configurable.type, configurable.element):
                  _configurableCalls(configurable, configurable.preDestroy),
        }),
    };
    if (_writer.annotationTypes.isNotEmpty) {
      arguments['typeTests'] = literalMap({
        for (final (type, element) in _writer.annotationTypes.values)
          _type(type, element): Method(
            (m) => m
              ..requiredParameters.add(Parameter((p) => p..name = 'value'))
              ..lambda = true
              ..body = refer('value').isA(_type(type, element)).code,
          ).closure,
      });
    }
    if (_writer.annotationTypes.isNotEmpty) {
      arguments['typeDepths'] = literalMap({
        for (final (type, element) in _writer.annotationTypes.values)
          _type(type, element): literalNum(_supertypeDepth(type.element)),
      });
    }
    final moduleExpression = _spring('BeanModule').newInstance([
      _str(moduleName),
      definitions,
    ], arguments);
    final statements = [
      for (final generation in generations)
        ..._guardedStatements(
          generation,
          generation.moduleStatements(emission).toList(),
        ),
    ];
    final leading = [
      for (final generation in generations)
        ...generation.leadingDeclarations(emission),
    ];
    final declarations = [
      for (final generation in generations)
        ...generation.declarations(emission),
    ];
    final library = Library(
      (b) => b
        // The generated files that are `part of` this one (the typed keys),
        // and the imports they need, as a part has none of its own.
        ..directives.addAll([
          for (final url in partImports)
            switch (url.split(' as ')) {
              [final library, final prefix] => Directive.import(
                library,
                as: prefix,
              ),
              _ => Directive.import(url),
            },
          for (final url in parts) Directive.part(url),
          if (proxies.isNotEmpty)
            Directive.part(p.url.basename(proxiesFile.path)),
          for (final MapEntry(key: extension, value: declarations)
              in partDeclarations.entries)
            if (declarations.isNotEmpty)
              Directive.part(
                p.url.basename(moduleFileId(output, extension).path),
              ),
        ])
        ..body.addAll(classes)
        ..body.addAll(_writer.topLevelDeclarations)
        ..body.addAll([
          if (_usesTypeOf)
            Method(
              (m) => m
                ..docs.add(
                  '/// [T] as a `Type` value (function and record types).',
                )
                ..returns = refer('Type')
                ..name = typeOfFunction
                ..types.add(refer('T'))
                ..lambda = true
                ..body = refer('T').code,
            ),
        ])
        // A getter, not a final variable: a hot reload replaces its body,
        // so the next call returns the beans of the new code.
        ..body.add(
          Method(
            (m) => m
              ..docs.add(
                '/// Beans found by `@ComponentScan` in '
                '`${_docText(scannedDirectory)}`.',
              )
              ..type = MethodType.getter
              ..returns = _spring('BeanModule')
              ..name = variableName
              ..lambda = statements.isEmpty
              ..body = statements.isEmpty
                  ? moduleExpression.code
                  : Block.of([
                      ...statements,
                      moduleExpression.returned.statement,
                    ]),
          ),
        )
        ..body.addAll(leading)
        ..body.addAll(extra)
        ..body.addAll(declarations)
        ..body.addAll([
          for (final (log, name) in _logExtensionNames(module.loggers))
            _logExtension(log, name),
        ]),
    );
    // One emitter for the library and its parts, whose imports the
    // library declares: the parts first, so their imports are known.
    final emitter = _writer.emitter();
    final proxiesSource = _partSource(proxies, emitter);
    final partSources = {
      for (final MapEntry(key: extension, value: declarations)
          in partDeclarations.entries)
        extension: ?_partSource(declarations, emitter),
    };
    final source =
        '$generatedHeader'
        '${parts.isEmpty ? '' : '// ignore_for_file: unused_import\n'}\n'
        '${library.accept(emitter)}';
    return ModuleSources(
      source,
      introspection: descriptions.introspectionSource(),
      properties: descriptions.propertiesSource(),
      proxies: proxiesSource,
      parts: partSources,
    );
  }

  // The source of a part of the module's library with [declarations],
  // written by the library's [emitter]; `null` without any.
  String? _partSource(List<Spec> declarations, DartEmitter emitter) {
    if (declarations.isEmpty) {
      return null;
    }
    // A top-level function with an arrow body ends with `;` in a library,
    // which writes it; alone, the emitter leaves it out.
    final code = [
      for (final spec in declarations)
        switch (spec) {
          Method(lambda: true) => '${spec.accept(emitter)};',
          _ => '${spec.accept(emitter)}',
        },
    ];
    return '$generatedHeader\n'
        "part of '${p.url.basename(output.path)}';\n\n"
        '${code.join('\n\n')}';
  }

  // The part that wrote the creation of each bean a part makes
  // (`PackageCreation`), so its definition goes under the part's condition.
  final Map<BeanModel, PackageGeneration> _packageCreators = {};

  // [element], an element of a list the part [generation] adds to, under
  // the part's condition: `if (!const bool.fromEnvironment(...)) element`.
  Expression _guarded(PackageGeneration generation, Expression element) =>
      switch (generationConditions[generation]) {
        final condition? => CodeExpression(
          Block.of([Code('if ($condition) '), element.code]),
        ),
        null => element,
      };

  // The definition of [bean], under the condition of the part that makes
  // it, if one does.
  Expression _guardedBean(BeanModel bean, Expression definition) =>
      switch (_packageCreators[bean]) {
        final generation? => _guarded(generation, definition),
        null => definition,
      };

  // The module statements of the part [generation], in one `if` block
  // under its condition.
  List<Code> _guardedStatements(
    PackageGeneration generation,
    List<Code> statements,
  ) => switch (generationConditions[generation]) {
    final condition? when statements.isNotEmpty => [
      Block.of([Code('if ($condition) {'), ...statements, const Code('}')]),
    ],
    _ => statements,
  };

  // The entries of `resources:`: the module's [resources], then those of
  // the [packageParts] and of the [coreParts] (one of a part's replaces a
  // module's file of the same path); those of a part under a condition
  // come last, each under it.
  Map<Expression, Expression> _resourceEntries(
    Map<String, ({String? text, String? base64})> resources,
    Map<PackageGeneration, ModuleParts> packageParts,
    List<ModuleParts> coreParts,
  ) {
    Expression resource(({String? text, String? base64}) value) =>
        value.text != null
        ? _spring('EmbeddedResource')
              .constInstanceNamed('text', [_str(value.text!)])
        : _spring('EmbeddedResource')
              .constInstanceNamed('base64', [_str(value.base64!)]);
    final always = {
      ...resources,
      for (final MapEntry(key: generation, value: part) in packageParts.entries)
        if (!generationConditions.containsKey(generation)) ...part.resources,
      for (final part in coreParts) ...part.resources,
    };
    return {
      for (final MapEntry(key: path, :value) in always.entries)
        _str(path): resource(value),
      for (final MapEntry(key: generation, value: part) in packageParts.entries)
        if (generationConditions.containsKey(generation))
          for (final MapEntry(key: path, :value) in part.resources.entries)
            _guarded(generation, _str(path)): resource(value),
    };
  }

  // One `BeanDefinition<T>(...)`. Optional arguments are only written when
  // they differ from the runtime defaults, keeping the output small.
  Expression _definition(BeanModel bean) {
    final element = bean.element;
    final dependencies = bean.dependencies;
    final injection = _injection(bean.properties, bean.methods, element);
    return _spring('BeanDefinition').newInstance(
      [],
      {
        'name': _str(bean.name),
        'source': _str(bean.source),
        // `[T]` is the runtime default.
        if (bean.valueType != null)
          'types': _typeValues([bean.valueType!, ...bean.exposedTypes], element)
        else if (!_onlyOwnType(bean))
          'types': literalConstList([
            for (final type in bean.exposedTypes) _type(type, element),
          ]),
        if (bean.factoryObjectTypes case final products?)
          'factoryObjectTypes': literalConstList([
            for (final type in products) _type(type, element),
          ]),
        if (bean.aliases.isNotEmpty)
          'aliases': literalConstList([for (final a in bean.aliases) _str(a)]),
        if (bean.scope != 'singleton') 'scope': _str(bean.scope),
        if (bean.scopedProxy case final proxy?)
          'scopedProxy': refer(proxy.className).property('new'),
        if (bean.lazy) 'lazy': literalTrue,
        if (bean.primary) 'primary': literalTrue,
        if (bean.fallback) 'fallback': literalTrue,
        if (!bean.autowireCandidate) 'autowireCandidate': literalFalse,
        if (!bean.defaultCandidate) 'defaultCandidate': literalFalse,
        if (bean.creation case BeanMethodCreation(
          :final ownerName,
          :final methodName,
          :final isStatic,
        )) ...{
          if (!isStatic) 'factoryBeanName': _str(ownerName),
          'factoryMethodName': _str(methodName),
        },
        if (bean.order case final order?) 'order': literalNum(order),
        if (bean.description case final description?)
          'description': _str(description),
        if (bean.dependsOn.isNotEmpty)
          'dependsOn': literalConstList([
            for (final d in bean.dependsOn) _str(d),
          ]),
        if (bean.qualifiers.isNotEmpty)
          'qualifiers': literalConstSet({
            for (final q in bean.qualifiers) _str(q),
          }),
        if (bean.conditions.isNotEmpty)
          'conditions': literalList([
            for (final condition in bean.conditions)
              _condition(condition, element),
          ]),
        if (dependencies.isNotEmpty)
          'dependencies':
              dependencies.every(
                (p) => p.exactType == null || _isConstTypeValue(p.exactType!),
              )
              ? literalConstList([
                  for (final point in dependencies) _dependency(point, element),
                ])
              : literalList([
                  for (final point in dependencies) _dependency(point, element),
                ]),
        'create': _closure(['r'], _creation(bean).code, lambda: true),
        'inject': ?injection,
        if (bean.postConstruct.isNotEmpty)
          'postConstruct': _calls(bean.postConstruct, bean),
        if (bean.initMethod case final method?) ...{
          'initMethod': _calls([method], bean),
          'initMethodName': _str(method),
        },
        if (bean.preDestroy.isNotEmpty)
          'preDestroy': _calls(bean.preDestroy, bean),
        if (bean.destroyMethod case final method?) ...{
          'destroyMethod': _calls([method], bean),
          'destroyMethodName': _str(
            bean.destroyMethodInferred ? '(inferred)' : method,
          ),
        },
        if (bean.listeners.isNotEmpty)
          'eventListeners': literalList([
            for (final listener in bean.listeners)
              _listener(bean.type, listener, element),
          ]),
        if (bean.annotatedMethods.isNotEmpty)
          'annotatedMethods': literalList([
            for (final method in bean.annotatedMethods)
              _annotatedMethod(bean.type, method, element),
          ]),
        if (bean.annotations.isNotEmpty)
          'annotations': literalConstList([
            for (final annotation in bean.annotations)
              _constant(annotation, element),
          ]),
        if (bean.proxy case final proxy?)
          'aopProxy': _proxyFactory(proxy, element),
        if (bean.aspect case final aspect?)
          'aspect': _aspect(bean.type, aspect, element),
      },
      [
        if (bean.valueType case final valueType?)
          _anyType(valueType, element)
        else
          _type(bean.type, element),
      ],
    );
  }

  // Whether the bean is looked up by its own type only, the `types` the
  // runtime defaults to (`[T]` of `BeanDefinition<T>`).
  static bool _onlyOwnType(BeanModel bean) =>
      bean.exposedTypes.length == 1 && bean.exposedTypes.single == bean.type;

  // A function or record type as a `Type` value: its public alias (a
  // constant), else `_$typeOf<T>()` (no literal exists for such types).
  Expression _typeValue(DartType type, Element element) {
    if (type is InterfaceType) {
      return _type(type, element);
    }
    final alias = type.alias;
    if (alias != null &&
        alias.element.isPublic &&
        alias.typeArguments.isEmpty &&
        type.nullabilitySuffix == NullabilitySuffix.none) {
      final name = alias.element.name!;
      return refer(
        name,
        _importUrl(alias.element.library.uri, element, name: name),
      );
    }
    _usesTypeOf = true;
    return refer(typeOfFunction).call([], {}, [_anyType(type, element)]);
  }

  bool _isConstTypeValue(DartType type) =>
      type is InterfaceType ||
      (type.alias?.element.isPublic ?? false) &&
          type.alias!.typeArguments.isEmpty &&
          type.nullabilitySuffix == NullabilitySuffix.none;

  // A `types:` list starting with a function or record type.
  Expression _typeValues(List<DartType> types, Element element) {
    final values = [for (final type in types) _typeValue(type, element)];
    return types.every(_isConstTypeValue)
        ? literalConstList(values)
        : literalList(values);
  }

  // Whether `_$typeOf` is used by the module being emitted.
  bool _usesTypeOf = false;

  // The body of a function returning `Object?` that calls [call]: its
  // value, or `null` after a `void` call (as `Function.apply` returns).
  static (Code, bool) _returning(Expression call, {required bool isVoid}) =>
      isVoid
      ? (Block.of([call.statement, literalNull.returned.statement]), false)
      : (call.code, true);

  // The longest chain of supertypes from [element] up to `Object` (which
  // is 0): a superclass, an interface, a mixin or a constraint each is one
  // step. Of two types a thrown exception is an instance of, the one that
  // is the subtype of the other has the greater depth
  // (`BeanModule.typeDepths`).
  int _supertypeDepth(InterfaceElement element, [Set<Element>? visiting]) {
    if (element.thisType.isDartCoreObject) {
      return 0;
    }
    final path = visiting ?? <Element>{};
    if (!path.add(element)) {
      return 0;
    }
    final supertypes = [
      ?element.supertype,
      ...element.interfaces,
      ...element.mixins,
      if (element is MixinElement) ...element.superclassConstraints,
    ];
    var depth = 0;
    for (final supertype in supertypes) {
      final candidate = 1 + _supertypeDepth(supertype.element, path);
      if (candidate > depth) {
        depth = candidate;
      }
    }
    path.remove(element);
    return depth == 0 ? 1 : depth;
  }

  /// The name of the generated `Type _$typeOf<T>() => T;` helper.
  ///
  /// A function or record type cannot be written as a type literal in
  /// `const [...]`, so such a bean type is written as `_$typeOf<...>()`.
  /// The helper is emitted only when the module uses it.
  static const typeOfFunction = r'_$typeOf';

  // `inject: (bean, r) { bean.x = ...; bean.m(...); }`, or `null` when the
  // bean has no field, setter or method injection.
  Expression? _injection(
    List<PropertyInjection> properties,
    List<MethodInjection> methods,
    Element element,
  ) {
    if (properties.isEmpty && methods.isEmpty) {
      return null;
    }
    return _closure([
      'bean',
      'r',
    ], _injectionBody(refer('bean'), properties, methods, element));
  }

  // Members in Spring's order (superclass first; per class fields, then
  // setters and methods), see `injectionRank`.
  Code _injectionBody(
    Expression bean,
    List<PropertyInjection> properties,
    List<MethodInjection> methods,
    Element element,
  ) => Block.of([
    for (final (_, statement) in sortedByRank([
      for (final property in properties)
        (property.rank, _propertyStatement(bean, property, element)),
      for (final method in methods)
        (method.rank, _methodStatement(bean, method, element)),
    ], (entry) => entry.$1))
      statement,
  ]);

  Code _propertyStatement(
    Expression bean,
    PropertyInjection property,
    Element element,
  ) =>
      // An optional field or setter is left alone when nothing is found
      // (keeps its initializer; Spring does not call the setter either).
      property.point.optional && property.point.defaultValue == null
      ? Block.of([
          const Code('if ('),
          _lookup(property.point, element).code,
          const Code(' case final value?) {'),
          bean.property(property.name).assign(refer('value')).statement,
          const Code('}'),
        ])
      : bean
            .property(property.name)
            .assign(_lookup(property.point, element))
            .statement;

  Code _methodStatement(
    Expression bean,
    MethodInjection method,
    Element element,
  ) {
    final (positional, named) = _arguments(method.arguments, element);
    return bean.property(method.name).call(positional, named).statement;
  }

  // `(bean) { final target = bean as T; target.a(); }` for lifecycle
  // methods of a `@Configurable` class.
  Expression _configurableCalls(
    ConfigurableModel configurable,
    List<String> methods,
  ) => _closure(
    ['bean'],
    Block.of([
      declareFinal('target')
          .assign(
            refer('bean').asA(_type(configurable.type, configurable.element)),
          )
          .statement,
      for (final method in methods)
        refer('target').property(method).call([]).statement,
    ]),
  );

  // Configurers receive `Object`, hence the cast to the configurable type.
  Expression _configurer(ConfigurableModel configurable) {
    final element = configurable.element;
    return _closure(
      ['bean', 'r'],
      Block.of([
        declareFinal('target')
            .assign(refer('bean').asA(_type(configurable.type, element)))
            .statement,
        _injectionBody(
          refer('target'),
          configurable.properties,
          configurable.methods,
          element,
        ),
      ]),
    );
  }

  // `IntrospectedMethod<T>('name', invoke: ..., annotations: [...])` for a
  // method with a `@BeanMethodAnnotation()` annotation.
  //
  // The method is called directly, the arguments read from the lists the
  // way `Function.apply` passes them (see [_directArguments]); its closures
  // are top-level functions, so the `IntrospectedMethod` is a constant when its
  // type descriptions are.
  Expression _annotatedMethod(
    InterfaceType beanType,
    AnnotatedMethodModel method,
    Element element,
  ) {
    final bean = _type(beanType, element);
    final hasNamed = method.parameters.any((p) => p.isNamed);
    // `invoke` passes no named arguments: optional ones keep their default.
    final positionalCall = _directArguments(
      method.parameters,
      element,
      positional: refer('arguments'),
      named: null,
    );
    final namedCall = hasNamed
        ? _directArguments(
            method.parameters,
            element,
            positional: refer('positional'),
            named: refer('named'),
          )
        : null;
    // The call, or `Function.apply` when an argument cannot be written
    // (or, for `invoke`, a required named one is not passed).
    (Code, bool) body(
      (List<Expression>, Map<String, Expression>)? arguments,
      List<Expression> apply,
    ) => arguments != null
        ? _returning(
            refer('bean')
                .property(method.name)
                .call(arguments.$1, arguments.$2),
            isVoid: method.isVoid && !method.isFuture,
          )
        : (
            refer('Function').property('apply').call([
              refer('bean').property(method.name),
              ...apply,
            ]).code,
            true,
          );
    final (invokeBody, invokeLambda) = body(positionalCall, [
      refer('arguments'),
    ]);
    final invoke = _function(
      'invoke',
      _objectOrNull,
      [('bean', bean), ('arguments', _argumentList)],
      invokeBody,
      lambda: invokeLambda,
    );
    Expression? invokeNamed;
    if (hasNamed) {
      final (namedBody, namedLambda) = body(namedCall, [
        refer('positional'),
        refer('named'),
      ]);
      invokeNamed = _function(
        'invokeNamed',
        _objectOrNull,
        [
          ('bean', bean),
          ('positional', _argumentList),
          ('named', _namedArgumentMap),
        ],
        namedBody,
        lambda: namedLambda,
      );
    }
    var isConst = true;
    final parameters = <Expression>[];
    for (final parameter in method.parameters) {
      final (type, typeIsConst) = _typeInfo(parameter.type, element);
      isConst = isConst && typeIsConst;
      parameters.add(
        _spring('IntrospectedParameter').newInstance(
          [_str(parameter.name)],
          {
            'type': type,
            if (parameter.isNamed)
              'symbol': CodeExpression(Code('#${parameter.name}')),
            if (parameter.isRequired) 'isRequired': literalTrue,
            if (parameter.annotations.isNotEmpty)
              'annotations': literalConstList([
                for (final annotation in parameter.annotations)
                  _constant(annotation, element),
              ]),
          },
        ),
      );
    }
    final returnTypeInfo = method.isVoid
        ? null
        : _typeInfo(method.valueType, element);
    isConst = isConst && (returnTypeInfo?.$2 ?? true);
    final arguments = {
      if (method.parameterTypes.isNotEmpty)
        'parameterTypes': literalConstList([
          for (final type in method.parameterTypes)
            if (type == null) refer('Object') else _type(type, element),
        ]),
      if (parameters.isNotEmpty) 'parameters': literalList(parameters),
      'returnTypeInfo': ?returnTypeInfo?.$1,
      if (method.isFuture) 'isFuture': literalTrue,
      if (method.isVoid) 'isVoid': literalTrue,
      'invoke': invoke,
      'invokeNamed': ?invokeNamed,
      if (method.annotations.isNotEmpty)
        'annotations': literalConstList([
          for (final annotation in method.annotations)
            _constant(annotation, element),
        ]),
    };
    return isConst
        ? _spring('IntrospectedMethod')
              .constInstance([_str(method.name)], arguments, [bean])
        : _spring('IntrospectedMethod')
              .newInstance([_str(method.name)], arguments, [bean]);
  }

  // -----------------------------------------------------------------------
  // AOP
  // -----------------------------------------------------------------------

  // Advice is invoked through a closure taking the aspect, the join point,
  // the return value/error and the values the pointcut bound (by advice
  // parameter name); the parameters are mapped as recorded in
  // `AdviceModel.parameters`. `accepts` filters by the value's type so a
  // typed after-returning/after-throwing advice only sees matching values;
  // `bindings` tells the pointcut which names are parameters and their
  // types.
  Expression _aspect(InterfaceType type, AspectModel aspect, Element element) {
    final aspectType = _type(type, element);
    return TypeReference(
      (t) => t
        ..symbol = 'AspectMetadata'
        ..url = _springUrl
        ..types.add(aspectType),
    ).newInstance([], {
      if (aspect.advice.isNotEmpty)
        'advice': literalList([
          for (final advice in aspect.advice)
            TypeReference(
              (t) => t
                ..symbol = 'AspectAdvice'
                ..url = _springUrl
                ..types.add(aspectType),
            ).newInstance([], {
              'kind': _spring('AdviceKind').property(advice.kind),
              'pointcut': _str(advice.pointcut),
              'methodName': _str(advice.methodName),
              'invoke': _closure(
                ['aspect', 'joinPoint', 'value', 'bindings'],
                refer('aspect').property(advice.methodName).call([
                  for (final parameter in advice.parameters)
                    switch (parameter) {
                      JoinPointParameter(proceeding: false) => refer(
                        'joinPoint',
                      ),
                      JoinPointParameter() => refer(
                        'joinPoint',
                      ).asA(_spring('ProceedingJoinPoint')),
                      ValueParameter(:final type) => refer(
                        'value',
                      ).asA(_anyType(type, element)),
                      BoundParameter(:final name, :final type) => refer(
                        'bindings',
                      ).index(_str(name)).asA(_anyType(type, element)),
                    },
                ]).code,
                lambda: true,
              ),
              if (advice.bindings.isNotEmpty)
                'bindings': literalMap({
                  for (final binding in advice.bindings)
                    _str(binding.name): _spring('AdviceBinding').newInstance([
                      _str(_simpleName(binding.type)),
                      _closure(
                        ['value'],
                        refer('value')
                            .isA(_anyType(binding.type, element))
                            .code,
                        lambda: true,
                      ),
                    ]),
                }),
              // Only `dynamic` and `Object?` take every value; a
              // non-nullable `Object` skips the `null` of a void method
              // (Spring passes it; Dart cannot).
              if (advice.valueType case final valueType?
                  when valueType is! DynamicType &&
                      !(valueType.isDartCoreObject &&
                          valueType.nullabilitySuffix ==
                              NullabilitySuffix.question))
                'accepts': _closure(
                  ['value'],
                  refer('value').isA(_anyType(valueType, element)).code,
                  lambda: true,
                ),
            }),
        ]),
      if (aspect.pointcuts.isNotEmpty)
        'pointcuts': literalMap({
          for (final MapEntry(:key, :value) in aspect.pointcuts.entries)
            _str(key): _str(value),
        }),
      if (aspect.perClause case final perClause?) 'perClause': _str(perClause),
      // `args(Type)` tests the runtime argument (AspectJ's instanceof).
      if (aspect.typeTests.isNotEmpty)
        'typeTests': literalMap({
          for (final MapEntry(:key, :value) in aspect.typeTests.entries)
            _str(key): _closure(
              ['value'],
              refer('value').isA(_type(value, element)).code,
              lambda: true,
            ),
        }),
      // `@args(Annotation)`: the annotation of the argument's class, among
      // the scanned classes carrying it (most derived first).
      if (aspect.argumentAnnotations.isNotEmpty)
        'argumentAnnotations': literalMap({
          for (final name in aspect.argumentAnnotations)
            _str(name): _closure(
              ['value'],
              _annotatedClasses(name, element).reversed
                  .fold<Expression>(
                    literalNull,
                    (otherwise, entry) =>
                        refer('value')
                            .isA(_type(entry.$1, element))
                            .conditional(entry.$2, otherwise),
                  )
                  .code,
              lambda: true,
            ),
        }),
    });
  }

  // The scanned classes carrying an annotation named [name] (subtypes
  // first), each with the annotation as a constant expression.
  List<(InterfaceType, Expression)> _annotatedClasses(
    String name,
    Element element,
  ) {
    final found = <(InterfaceType, Expression, int)>[];
    for (final type in _module.classes) {
      for (final annotation in type.metadata.annotations) {
        final value = annotation.computeConstantValue();
        if (value?.type?.element?.name != name) {
          continue;
        }
        try {
          found.add((
            type.library.typeSystem.instantiateInterfaceToBounds(
              element: type,
              nullabilitySuffix: NullabilitySuffix.none,
            ),
            _constant(value!, element),
            type.allSupertypes.length,
          ));
        } on InvalidGenerationSource {
          // A private annotation value cannot be written; not matched.
        }
        break;
      }
    }
    found.sort((a, b) => b.$3.compareTo(a.$3));
    return [for (final (type, value, _) in found) (type, value)];
  }

  // `_$knownAdvisors<n>`, the advisors the build pruned the module's
  // proxies for, declared once per module on first use.
  Expression? _knownAdvisors;

  // The `knownAdvisors:` argument of a pruned or partial factory.
  Map<String, Expression> _knownAdvisorsArgument(ProxyModel proxy) {
    final known = _module.knownAdvisors;
    if (known == null || !(proxy.pruned || proxy.advisedMembers != null)) {
      return const {};
    }
    return {
      'knownAdvisors': _knownAdvisors ??= _constantDeclaration(
        'knownAdvisors',
        literalConstSet({
          for (final source in known.toList()..sort()) _str(source),
        }),
      ),
    };
  }

  // The runtime decides whether to proxy (any advisor matching one of the
  // signatures) and then calls `create` with the target and an invoker.

  // The factories of the foreign proxies by source; those of beans only in
  // modules under a condition (not in a release, one platform) under it.
  Expression _foreignProxies(List<ForeignProxyModel> proxies) {
    final available = [
      for (final foreign in proxies)
        if (foreign.proxy.unavailableReason == null) foreign,
    ];
    if (!available.any((foreign) => foreign.condition != null)) {
      return literalMap({
        for (final foreign in available)
          _str(foreign.source): _proxyFactory(foreign.proxy, foreign.element),
      });
    }
    return CodeExpression(
      Block.of([
        const Code('{'),
        for (final foreign in available) ...[
          if (foreign.condition case final condition?) Code('if ($condition) '),
          _str(foreign.source).code,
          const Code(': '),
          _proxyFactory(foreign.proxy, foreign.element).code,
          const Code(', '),
        ],
        const Code('}'),
      ]),
    );
  }

  Expression _proxyFactory(ProxyModel proxy, Element element) {
    // The runtime's `AopProxyFactory.prunedReason` says why.
    if (proxy.pruned) {
      return _spring(
        'AopProxyFactory',
      ).constInstanceNamed('pruned', [], _knownAdvisorsArgument(proxy));
    }
    // The bean class, once for the signatures of all its members.
    final advisable = proxy.advisableMembers;
    final target = advisable.isEmpty
        ? null
        : _constantDeclaration(
            'target',
            _spring('AopTarget').newInstance(
              [_str(proxy.targetType.element.name!)],
              {
                'types': literalConstList([
                  for (final name in proxy.targetTypeNames) _str(name),
                ]),
                if (proxy.classAnnotations.isNotEmpty) ...{
                  'annotations': literalConstList([
                    for (final annotation in proxy.classAnnotations)
                      _constant(annotation, element),
                  ]),
                  'annotationTypes': literalConstList([
                    for (final annotation in proxy.classAnnotations)
                      _str(annotation.type!.element!.name!),
                  ]),
                },
              },
            ),
          );
    final signatures = literalConstList([
      for (final member in advisable)
        _signature(proxy, member, target!, element),
    ]);
    // The application's module brings the class (BeanModule.aopProxies).
    if (proxy.deferred) {
      return _spring(
        'AopProxyFactory',
      ).constInstanceNamed('deferred', [], {'signatures': signatures});
    }
    if (proxy.unavailableReason case final reason?) {
      return _spring('AopProxyFactory').newInstanceNamed('unavailable', [], {
        'signatures': signatures,
        'reason': _str(reason),
      });
    }
    final introductions = literalList([
      for (final introduction in proxy.introductions)
        _spring('Introduction').newInstance([], {
          'interfaceName': _str(introduction.interfaceType.element.name!),
          'aspectType': _str(introduction.aspectType),
          'create': _closure(
            [],
            _type(introduction.defaultImpl, element).newInstance([]).code,
            lambda: true,
          ),
        }),
    ]);
    // A subclass proxy is the bean itself; advice is attached to it.
    if (proxy.subclass != null) {
      final bean = refer('bean');
      return _spring('AopProxyFactory').newInstanceNamed('subclass', [], {
        'signatures': signatures,
        if (proxy.introductions.isNotEmpty) 'introductions': introductions,
        ..._knownAdvisorsArgument(proxy),
        // The bean's own calls are advised too (`@ProxyTargetClass()`).
        if (proxy.targetClass) 'adviseSelfCalls': literalTrue,
        'advise': _closure(
          ['bean', 'invoker'],
          bean
              .isA(refer(proxy.className))
              .conditional(
                bean
                    .cascade('aopInvoker')
                    .assign(refer('invoker'))
                    .parenthesized,
                literalNull,
              )
              .code,
          lambda: true,
        ),
      });
    }
    return _spring('AopProxyFactory').newInstance([], {
      'signatures': signatures,
      if (proxy.introductions.isNotEmpty) 'introductions': introductions,
      ..._knownAdvisorsArgument(proxy),
      'create': _closure(
        ['target', 'invoker'],
        refer(proxy.className).newInstance([
          refer('target').asA(_type(proxy.targetType, element)),
          refer('invoker'),
        ]).code,
        lambda: true,
      ),
    });
  }

  // Const metadata that pointcuts are matched against (names, types and
  // annotations as plain values, since there is no reflection).
  //
  // `MethodSignature.of(name, target, ...)`: the class part is [target];
  // the declaring type(s) only when not the bean class.
  Expression _signature(
    ProxyModel proxy,
    ProxyMember member,
    Expression target,
    Element element,
  ) => _spring('MethodSignature').newInstanceNamed(
    'of',
    [
      _str(member.name),
      target,
    ],
    {
      if (member.declaringType != proxy.targetType.element.name)
        'declaringType': _str(member.declaringType),
      // `[declaringType]` is the default.
      if (member.declaringTypes.length != 1 ||
          member.declaringTypes.single != member.declaringType)
        'declaringTypes': literalConstList([
          for (final name in member.declaringTypes) _str(name),
        ]),
      if (member.kind != ProxyMemberKind.method)
        'kind': _spring('MemberKind').property(member.kind.name),
      if (_simpleName(member.returnType) != 'dynamic')
        'returnType': _str(_simpleName(member.returnType)),
      // The type arguments of a getter's type, for advice that follows
      // the bean's state and must make typed objects of it.
      if (proxy.targetClass &&
          member.kind == ProxyMemberKind.getter &&
          member.returnType is InterfaceType &&
          (member.returnType as InterfaceType).typeArguments.isNotEmpty &&
          (member.returnType as InterfaceType).typeArguments.every(
            _canCapture,
          ))
        'returnTypeArguments': literalConstList([
          for (final argument
              in (member.returnType as InterfaceType).typeArguments)
            _spring(
              'TypeCapture',
            ).constInstance([], {}, [_anyType(argument, element)]),
        ]),
      if (member.kind == ProxyMemberKind.method && member.parameters.isNotEmpty)
        'parameterTypes': literalConstList([
          for (final parameter in member.parameters)
            _str(_simpleName(parameter.type)),
        ]),
      if (member.kind == ProxyMemberKind.method && member.parameters.isNotEmpty)
        'parameterNames': literalConstList([
          for (final parameter in member.parameters) _str(parameter.name),
        ]),
      if (member.kind == ProxyMemberKind.method &&
          member.parameters.any((p) => p.annotations.isNotEmpty))
        'parameterAnnotations': literalConstList([
          for (final parameter in member.parameters)
            literalConstList([
              for (final annotation in parameter.annotations)
                _constant(annotation, element),
            ]),
        ]),
      if (member.annotations.isNotEmpty)
        'annotations': literalConstList([
          for (final annotation in member.annotations)
            _constant(annotation, element),
        ]),
      // Only when the overridden declarations add some (else the runtime
      // falls back to `annotations`).
      if (!_sameAnnotations(member.mergedAnnotations, member.annotations))
        'mergedAnnotations': literalConstList([
          for (final annotation in member.mergedAnnotations)
            _constant(annotation, element),
        ]),
      if (member.annotations.isNotEmpty)
        'annotationTypes': literalConstList([
          for (final annotation in member.annotations)
            _str(annotation.type!.element!.name!),
        ]),
      // An inherited member: `within` / `@within` see the class of its body.
      if (member.implementingTypes.isNotEmpty) ...{
        'implementingTypes': literalConstList([
          for (final name in member.implementingTypes) _str(name),
        ]),
        'implementingTypeAnnotations': literalConstList([
          for (final annotation in member.implementingTypeAnnotations)
            _constant(annotation, element),
        ]),
        'implementingTypeAnnotationTypes': literalConstList([
          for (final annotation in member.implementingTypeAnnotations)
            _str(annotation.type!.element!.name!),
        ]),
      },
      if (member.superclassAnnotations.isNotEmpty)
        'superclassAnnotations': literalConstList([
          for (final level in member.superclassAnnotations)
            literalConstList([
              for (final annotation in level) _constant(annotation, element),
            ]),
        ]),
      if (member.isProtected) 'isProtected': literalTrue,
    },
  );

  // Type name used in signatures (`execution(int add(int, int))`).
  static bool _sameAnnotations(List<DartObject> a, List<DartObject> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) i].every((i) => a[i] == b[i]);

  static String _simpleName(DartType type) => switch (type) {
    InterfaceType() => type.element.name!,
    TypeParameterType() => type.element.name!,
    VoidType() => 'void',
    FunctionType() => 'Function',
    RecordType() => 'Record',
    _ => 'dynamic',
  };

  // The generated subclass overriding the `@Lookup` methods of [bean].
  static LookupClassModel? _lookupOf(BeanModel bean) => switch (bean.creation) {
    ConstructorCreation(:final lookup) => lookup,
    _ => null,
  };

  // The classes the packages' parts mix into the proxy (`ChangeNotifier`
  // for a `@ChangeNotifierComponent`): the bean the container hands out
  // carries them.
  static List<Reference> _proxyMixins(ProxyModel proxy) => [
    for (final mixin in proxy.mixins) refer(mixin.name, mixin.url),
  ];

  // The proxy class: holds the target and the invoker, implements
  // `Advised`, forwards `toString` without advice and overrides every
  // member from `proxy.members`.
  Class _proxyClass(
    ProxyModel proxy,
    Element element, {
    LookupClassModel? lookup,
  }) {
    if (proxy.subclass case final subclass?) {
      return _subclassProxyClass(proxy, subclass, element, lookup: lookup);
    }
    final targetType = _type(proxy.targetType, element);
    // `AdvisedWrapper` implements `Advised` through `aopInvoker`.
    return Class(
      (c) => c
        ..docs.addAll(
          _proxyClassDocs(
            proxy,
            'Wraps `${proxy.targetType.element.name}`: each call runs the '
            'advice that matches it at run time',
          ),
        )
        ..name = proxy.className
        ..mixins.addAll([..._proxyMixins(proxy), _spring('AdvisedWrapper')])
        ..implements.addAll([
          for (final interface in proxy.interfaces) _type(interface, element),
          for (final introduction in proxy.introductions)
            _type(introduction.interfaceType, element),
        ])
        ..fields.addAll([
          Field(
            (f) => f
              ..name = '_target'
              ..modifier = FieldModifier.final$
              ..type = targetType,
          ),
          Field(
            (f) => f
              ..annotations.add(refer('override'))
              ..name = 'aopInvoker'
              ..modifier = FieldModifier.final$
              ..type = _spring('ProxyInvoker'),
          ),
        ])
        ..constructors.add(
          Constructor(
            (k) => k.requiredParameters.addAll([
              Parameter(
                (p) => p
                  ..name = '_target'
                  ..toThis = true,
              ),
              Parameter(
                (p) => p
                  ..name = 'aopInvoker'
                  ..toThis = true,
              ),
            ]),
          ),
        )
        ..methods.addAll([
          Method(
            (m) => m
              ..annotations.add(refer('override'))
              ..type = MethodType.getter
              ..name = 'aopTarget'
              ..returns = refer('Object')
              ..lambda = true
              ..body = refer('_target').code,
          ),
          if (!proxy.customToString)
            Method(
              (m) => m
                ..annotations.add(refer('override'))
                ..name = 'toString'
                ..returns = refer('String')
                ..lambda = true
                ..body = refer('_target').property('toString').call([]).code,
            ),
          for (final (index, member) in proxy.advisableMembers.indexed)
            _proxyMember(proxy, member, index, element),
          // Members no pointcut can match: forwarded without advice.
          for (final member in proxy.members)
            if (!(proxy.advisedMembers?.contains(member) ?? true))
              _forwardingMember(
                member,
                refer('this').property('_target'),
                element,
              ),
          ..._introducedMembers(
            proxy,
            element,
            (_) => refer('this').property('aopInvoker'),
          ),
        ]),
    );
  }

  // The members of the `@DeclareParents` interfaces, forwarded to the
  // invoker's delegate (the first introduction declaring a name wins; the
  // bean's own members are never replaced).
  // [invoker] gives the invoker expression for an introduction.
  List<Method> _introducedMembers(
    ProxyModel proxy,
    Element element,
    Expression Function(IntroductionModel introduction) invoker,
  ) {
    final seen = {
      for (final member in proxy.members) '${member.kind.name}:${member.name}',
    };
    return [
      for (final (index, introduction) in proxy.introductions.indexed)
        for (final member in introduction.members)
          if (seen.add('${member.kind.name}:${member.name}'))
            _forwardingMember(
              member,
              invoker(introduction)
                  .property('introduction')
                  .call([literalNum(index)])
                  .asA(_type(introduction.interfaceType, element)),
              element,
            ),
    ];
  }

  // A subclass proxy: forwards the bean constructor, holds the invoker the
  // auto proxy creator attaches (`AdvisedSubclass.aopInvoker`) and
  // overrides every forwardable member to run `super` through the advice
  // (see `SubclassProxy`).
  //
  // A bean with `@Lookup` methods: the proxy extends the generated lookup
  // subclass (its `super` calls reach the lookup overrides) and takes the
  // bean factory first.
  Class _subclassProxyClass(
    ProxyModel proxy,
    SubclassProxy subclass,
    Element element, {
    LookupClassModel? lookup,
  }) {
    // `AdvisedSubclass` holds the invoker and implements `Advised`.
    return Class(
      (c) => c
        ..docs.addAll(
          _proxyClassDocs(
            proxy,
            '`${proxy.targetType.element.name}` as its own proxy: once '
            'advice matches it at run time, each call runs that advice',
          ),
        )
        ..modifier = subclass.isFinal ? ClassModifier.final$ : null
        ..name = proxy.className
        ..extend = lookup == null
            ? _type(proxy.targetType, element)
            : refer(lookup.className)
        ..mixins.addAll([..._proxyMixins(proxy), _spring('AdvisedSubclass')])
        ..implements.addAll([
          for (final introduction in proxy.introductions)
            _type(introduction.interfaceType, element),
        ])
        ..constructors.add(
          lookup == null
              ? _forwardingConstructor(
                  subclass.constructorName,
                  subclass.constructorParameters,
                )
              // The lookup subclass has the bean constructor's parameters
              // after the bean factory, and calls that constructor itself.
              : _forwardingConstructor(null, [
                  ProxyParameter(
                    name: r'_$beanFactory',
                    type: lookup.type,
                    isNamed: false,
                    isRequired: true,
                  ),
                  ...lookup.constructorParameters,
                ]),
        )
        ..methods.addAll([
          // The members no pointcut can match are inherited.
          for (final (index, member) in proxy.advisableMembers.indexed)
            _proxyMember(proxy, member, index, element, subclass: true),
          // No invoker: the aspect of the introduction is not registered.
          ..._introducedMembers(
            proxy,
            element,
            (introduction) => refer('this')
                .property('aopInvoker')
                .ifNullThen(
                  _spring('ProxyInvoker').property('notIntroduced').call([
                    refer('this'),
                    _str(introduction.interfaceType.element.name!),
                  ]),
                )
                .parenthesized,
          ),
        ]),
    );
  }

  // The implementation of an interface proxy: every method hands its call
  // to the `InvocationHandler` with the method's `ProxyMethod`; `$create`
  // builds the metadata and asks the factory beans for the handler.
  Class _interfaceImplClass(InterfaceProxyModel model) {
    final element = model.type.element;
    final interfaceType = _type(model.type, element);
    final self = refer(model.className);
    Expression method(InterfaceMethodModel method) {
      final arguments = [
        for (final (index, parameter) in method.parameters.indexed)
          refer('arguments')
              .index(literalNum(index))
              .asA(_anyType(parameter.type, element)),
      ];
      final call = refer('target')
          .asA(interfaceType)
          .property(method.name)
          .call(
            [
              for (final (index, parameter) in method.parameters.indexed)
                if (!parameter.isNamed) arguments[index],
            ],
            {
              for (final (index, parameter) in method.parameters.indexed)
                if (parameter.isNamed) parameter.name: arguments[index],
            },
          );
      return _interfaceProxyMethod(
        method,
        element,
        call: method.isVoid && !method.isFuture
            ? _closure([
                'target',
                'arguments',
              ], Block.of([call.statement, literalNull.returned.statement]))
            : _closure(['target', 'arguments'], call.code, lambda: true),
      );
    }

    final metadata = _spring('InterfaceMetadata').newInstance(
      [],
      {
        'typeName': _str(element.name!),
        if (model.annotations.isNotEmpty)
          'annotations': literalConstList([
            for (final annotation in model.annotations)
              _constant(annotation, element),
          ]),
        'methods': literalList([for (final m in model.methods) method(m)]),
      },
      [interfaceType],
    );
    return Class(
      (c) => c
        ..docs.add(
          '/// Implements `${element.name}` through an `InvocationHandler`.',
        )
        ..name = model.className
        ..implements.add(interfaceType)
        ..fields.addAll([
          Field(
            (f) => f
              ..name = '_handler'
              ..modifier = FieldModifier.final$
              ..type = _spring('InvocationHandler'),
          ),
          Field(
            (f) => f
              ..name = '_metadata'
              ..modifier = FieldModifier.final$
              ..type = TypeReference(
                (t) => t
                  ..symbol = 'InterfaceMetadata'
                  ..url = _spring('InterfaceMetadata').url
                  ..types.add(interfaceType),
              ),
          ),
        ])
        ..constructors.add(
          Constructor(
            (k) => k.requiredParameters.addAll([
              Parameter(
                (p) => p
                  ..name = '_handler'
                  ..toThis = true,
              ),
              Parameter(
                (p) => p
                  ..name = '_metadata'
                  ..toThis = true,
              ),
            ]),
          ),
        )
        ..methods.addAll([
          Method(
            (m) => m
              ..static = true
              ..name = r'$create'
              ..returns = self
              ..requiredParameters.add(
                Parameter(
                  (p) => p
                    ..name = 'r'
                    ..type = _spring('DependencyResolver'),
                ),
              )
              ..body = Block.of([
                declareFinal('metadata').assign(metadata).statement,
                self
                    .newInstance([
                      _spring('InterfaceProxies')
                          .property('handlerFor')
                          .call([refer('r'), refer('metadata')]),
                      refer('metadata'),
                    ])
                    .returned
                    .statement,
              ]),
          ),
          for (final (index, member) in model.signatures.members.indexed)
            () {
              final info = model.methods[index];
              final invoke = refer('this')
                  .property('_handler')
                  .property('invoke')
                  .call([
                    refer('this')
                        .property('_metadata')
                        .property('methods')
                        .index(literalNum(index)),
                    if (member.parameters.isEmpty)
                      literalConstList([])
                    else
                      literalList([
                        for (final parameter in member.parameters)
                          refer(parameter.name),
                      ]),
                  ]);
              final Code body;
              var lambda = true;
              if (info.isFuture) {
                body = _spring('retypeFuture')
                    .call([invoke], {}, [_anyType(info.valueType, element)])
                    .code;
              } else if (info.isVoid) {
                lambda = false;
                body = invoke.statement;
              } else {
                body = invoke.asA(_anyType(member.returnType, element)).code;
              }
              return Method(
                (m) => m
                  ..annotations.add(refer('override'))
                  ..name = member.name
                  ..returns = _anyType(member.returnType, element)
                  ..requiredParameters.addAll([
                    for (final parameter in member.parameters)
                      if (!parameter.isNamed && parameter.isRequired)
                        _proxyParameter(parameter, element),
                  ])
                  ..optionalParameters.addAll([
                    for (final parameter in member.parameters)
                      if (parameter.isNamed || !parameter.isRequired)
                        _proxyParameter(parameter, element),
                  ])
                  ..lambda = lambda
                  ..body = body,
              );
            }(),
        ]),
    );
  }

  // The `ProxyMethod` that tells the starter of an interface method: its
  // parameters, result and annotations; [call] invokes the method on an
  // implementation (a Feign fallback), left out where none can exist.
  Expression _interfaceProxyMethod(
    InterfaceMethodModel method,
    Element element, {
    Expression? call,
  }) => _spring('ProxyMethod').newInstance(
    [_str(method.name)],
    {
      if (method.parameters.isNotEmpty)
        'parameters': literalList([
          for (final parameter in method.parameters)
            _spring('IntrospectedParameter').newInstance(
              [_str(parameter.name)],
              {
                'type': _typeInfo(parameter.type, element).$1,
                if (parameter.isNamed)
                  'symbol': CodeExpression(Code('#${parameter.name}')),
                if (parameter.isRequired) 'isRequired': literalTrue,
                if (parameter.annotations.isNotEmpty)
                  'annotations': literalConstList([
                    for (final annotation in parameter.annotations)
                      _constant(annotation, element),
                  ]),
              },
            ),
        ]),
      'returnType': method.isVoid
          ? _spring('DynamicType').constInstance([])
          : _typeInfo(method.valueType, element).$1,
      if (method.isFuture) 'isFuture': literalTrue,
      if (method.isVoid) 'isVoid': literalTrue,
      if (method.annotations.isNotEmpty)
        'annotations': literalConstList([
          for (final annotation in method.annotations)
            _constant(annotation, element),
        ]),
      'call': ?call,
    },
  );

  // A `@Lazy` injection point gets an instance of this class instead of the
  // bean: every member resolves the bean again (cheap once the factory is
  // frozen) and forwards to it, like Spring's lazy-resolution proxy:
  //
  //   class _$BookServiceLazy implements BookService {
  //     _$BookServiceLazy(this._resolve);
  //     final BookService Function() _resolve;
  //     @override
  //     Book find(String isbn) => _resolve().find(isbn);
  //   }
  Class _lazyClass(ProxyModel proxy) {
    final element = proxy.targetType.element;
    final resolve = refer('this').property('_resolve').call([]);
    return Class(
      (c) => c
        ..docs.add(
          '/// Resolves `${proxy.targetType.element.name}` on every call '
          '(`@Lazy` injection).',
        )
        ..name = proxy.className
        ..implements.addAll([
          for (final interface in proxy.interfaces) _type(interface, element),
        ])
        ..fields.add(
          Field(
            (f) => f
              ..name = '_resolve'
              ..modifier = FieldModifier.final$
              ..type = cb.FunctionType(
                (t) => t..returnType = _type(proxy.targetType, element),
              ),
          ),
        )
        ..constructors.add(
          Constructor(
            (k) => k.requiredParameters.add(
              Parameter(
                (p) => p
                  ..name = '_resolve'
                  ..toThis = true,
              ),
            ),
          ),
        )
        ..methods.addAll([
          if (!proxy.customToString)
            Method(
              (m) => m
                ..annotations.add(refer('override'))
                ..name = 'toString'
                ..returns = refer('String')
                ..lambda = true
                ..body = resolve.property('toString').call([]).code,
            ),
          for (final member in proxy.members)
            _forwardingMember(member, resolve, element),
        ]),
    );
  }

  // [member] forwarded to [receiver] as it is (no advice).
  Method _forwardingMember(
    ProxyMember member,
    Expression receiver,
    Element element,
  ) => switch (member.kind) {
    ProxyMemberKind.getter => Method(
      (m) => m
        ..annotations.add(refer('override'))
        ..type = MethodType.getter
        ..name = member.name
        ..returns = _anyType(member.returnType, element)
        ..lambda = true
        ..body = receiver.property(member.name).code,
    ),
    ProxyMemberKind.setter => Method(
      (m) => m
        ..annotations.add(refer('override'))
        ..type = MethodType.setter
        ..name = member.name
        ..requiredParameters.add(
          Parameter(
            (p) => p
              ..name = 'value'
              ..type = _anyType(member.returnType, element),
          ),
        )
        ..body = receiver
            .property(member.name)
            .assign(refer('value'))
            .statement,
    ),
    ProxyMemberKind.method => Method(
      (m) => m
        ..annotations.add(refer('override'))
        ..name = member.name
        ..returns = _anyType(member.returnType, element)
        ..types.addAll([
          for (final typeParameter in member.typeParameters)
            TypeReference(
              (t) => t
                ..symbol = typeParameter.name
                ..bound = typeParameter.bound == null
                    ? null
                    : _anyType(typeParameter.bound!, element),
            ),
        ])
        ..requiredParameters.addAll([
          for (final parameter in member.parameters)
            if (!parameter.isNamed && parameter.isRequired)
              _proxyParameter(parameter, element),
        ])
        ..optionalParameters.addAll([
          for (final parameter in member.parameters)
            if (parameter.isNamed || !parameter.isRequired)
              _proxyParameter(parameter, element),
        ])
        ..lambda = true
        ..body = receiver.property(member.name).call(
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
    ),
  };

  // The doc comment of a proxy class: [summary], then the advice the build
  // found around every member, if any.
  List<String> _proxyClassDocs(ProxyModel proxy, String summary) =>
      _docComment([
        ...'$summary (each member says what the build found for it).'.split(
          ' ',
        ),
        if (proxy.classAdvice.isNotEmpty) ...[
          'Around',
          'every',
          'member:',
          ..._listed(proxy.classAdvice, end: '.'),
        ],
      ], indent: 0);

  // The doc comment of [member] in its proxy class: the advice the build
  // found around it.
  List<String> _proxyMemberDocs(ProxyModel proxy, ProxyMember member) {
    final advice = proxy.memberAdvice[member] ?? const [];
    return _docComment([
      '${member.name}:',
      if (advice.isEmpty)
        ...'no advice of its own found by the build'.split(' ')
      else
        ..._listed(advice),
    ], indent: 2);
  }

  // [items] separated by commas, the last one followed by [end].
  static List<String> _listed(List<String> items, {String end = ''}) => [
    for (final (index, item) in items.indexed)
      if (index == items.length - 1) '$item$end' else '$item,',
  ];

  // `///` lines of [words] (each kept whole: an annotation as written has
  // spaces) that fit in 80 columns at [indent], but for a word longer than
  // a line.
  static List<String> _docComment(List<String> words, {required int indent}) {
    final width = 80 - indent - '/// '.length;
    final lines = <String>[];
    var line = '';
    for (final word in words) {
      if (line.isNotEmpty && line.length + 1 + word.length > width) {
        lines.add(line);
        line = '';
      }
      line = line.isEmpty ? word : '$line $word';
    }
    return [
      for (final text in [...lines, if (line.isNotEmpty) line]) '/// $text',
    ];
  }

  // One forwarded member of [proxy]. Its override calls the invoker
  // (`aopInvoker.invoke(proxy: this, target: _target, methodIndex: index,
  // arguments: [...], original: (args) => ...)`): the index identifies the
  // member's `MethodSignature`, `arguments` are the caller's (advice may
  // replace them) and `original` makes the real call on the target with
  // the arguments the advice passes on. Methods returning `Future` use
  // `invokeAsync` so advice can await the result; void members return
  // `null` from the original call. A wrapper proxy forwards to `_target`;
  // a subclass proxy forwards to `super`, directly while no advice is
  // attached (`_$invoker` is null).
  Method _proxyMember(
    ProxyModel proxy,
    ProxyMember member,
    int index,
    Element element, {
    bool subclass = false,
  }) {
    // Fields are read through `this.` and the local has a `_$` name, so a
    // parameter named `_target`, `_invoker` or `invoker` does not shadow
    // them.
    final self = refer('this');
    final receiver = subclass ? refer('super') : self.property('_target');
    final target = subclass ? self : self.property('_target');
    // The local holding a subclass proxy's invoker: `_$invoker`, or a name
    // no parameter has.
    var dollars = 0;
    String localName() => '_\$invoker${r'$' * dollars}';
    while (member.parameters.any((p) => p.name == localName())) {
      dollars++;
    }
    final local = localName();
    final invokerRef = subclass ? refer(local) : self.property('aopInvoker');
    // What the invoker is given: the proxy, the target, the member's index,
    // the caller's arguments and the original call.
    Map<String, Expression> invokerArguments(
      List<Expression> arguments,
      Expression original,
    ) => {
      'proxy': refer('this'),
      'target': target,
      'methodIndex': literalNum(index),
      'arguments': arguments.isEmpty
          ? literalConstList([])
          : literalList(arguments),
      'original': original,
    };
    Expression invoke(List<Expression> arguments, Expression original) =>
        invokerRef
            .property('invoke')
            .call([], invokerArguments(arguments, original));
    // A `Future<T>` result goes through `invokeAsync<T>` and a
    // `FutureOr<T>` one through `invokeFutureOr<T>`, so after-style advice
    // runs when the future completes; `null` for other types (`Future<T>?`
    // is an ordinary value: advice sees the future or null).
    Expression? invokeAwaiting(
      DartType returnType,
      List<Expression> arguments,
      Expression call,
    ) {
      if (returnType is! InterfaceType ||
          returnType.nullabilitySuffix != NullabilitySuffix.none ||
          !(returnType.isDartAsyncFuture || returnType.isDartAsyncFutureOr)) {
        return null;
      }
      return invokerRef
          .property(
            returnType.isDartAsyncFuture ? 'invokeAsync' : 'invokeFutureOr',
          )
          .call(
            [],
            invokerArguments(arguments, call),
            [_anyType(returnType.typeArguments.single, element)],
          );
    }

    // The method body: [advised] runs through the invoker, [direct] is the
    // plain super call of a subclass proxy without advice.
    (Code, bool) body(
      Expression advised,
      Expression direct, {
      bool isVoid = false,
    }) {
      if (!subclass) {
        return (isVoid ? advised.statement : advised.code, !isVoid);
      }
      final invoker = declareFinal(local)
          .assign(refer('this').property('aopInvoker'));
      final isNull = refer(local).equalTo(literalNull);
      if (isVoid) {
        return (
          Block.of([
            invoker.statement,
            const Code('if ('),
            isNull.code,
            const Code(') {'),
            direct.statement,
            const Code('} else {'),
            advised.statement,
            const Code('}'),
          ]),
          false,
        );
      }
      return (
        Block.of([
          invoker.statement,
          isNull.conditional(direct, advised).returned.statement,
        ]),
        false,
      );
    }

    switch (member.kind) {
      case ProxyMemberKind.getter:
        final type = _anyType(member.returnType, element);
        final call = _closure(
          ['_'],
          receiver.property(member.name).code,
          lambda: true,
        );
        final (code, lambda) = body(
          invokeAwaiting(member.returnType, [], call) ??
              invoke([], call).asA(type),
          receiver.property(member.name),
        );
        return Method(
          (m) => m
            ..docs.addAll(_proxyMemberDocs(proxy, member))
            ..annotations.add(refer('override'))
            ..type = MethodType.getter
            ..name = member.name
            ..returns = type
            ..lambda = lambda
            ..body = code,
        );
      case ProxyMemberKind.setter:
        final type = _anyType(member.returnType, element);
        final (code, _) = body(
          invoke(
            [refer('value')],
            _closure(
              ['args'],
              Block.of([
                receiver
                    .property(member.name)
                    .assign(refer('args').index(literalNum(0)).asA(type))
                    .statement,
                literalNull.returned.statement,
              ]),
            ),
          ),
          receiver.property(member.name).assign(refer('value')),
          isVoid: true,
        );
        return Method(
          (m) => m
            ..docs.addAll(_proxyMemberDocs(proxy, member))
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
            ..body = code,
        );
      case ProxyMemberKind.method:
        final parameters = member.parameters;
        final typeArguments = [
          for (final typeParameter in member.typeParameters)
            refer(typeParameter.name!),
        ];
        final positional = <Expression>[];
        final named = <String, Expression>{};
        for (final (index, parameter) in parameters.indexed) {
          final argument = refer('args')
              .index(literalNum(index))
              .asA(_anyType(parameter.type, element));
          if (parameter.isNamed) {
            named[parameter.name] = argument;
          } else {
            positional.add(argument);
          }
        }
        final targetCall = receiver
            .property(member.name)
            .call(positional, named, typeArguments);
        final direct = receiver
            .property(member.name)
            .call(
              [
                for (final p in parameters)
                  if (!p.isNamed) refer(p.name),
              ],
              {
                for (final p in parameters)
                  if (p.isNamed) p.name: refer(p.name),
              },
              typeArguments,
            );
        final arguments = [for (final p in parameters) refer(p.name)];
        final returnType = member.returnType;
        final awaiting = invokeAwaiting(
          returnType,
          arguments,
          _closure(['args'], targetCall.code, lambda: true),
        );
        final (code, lambda) = switch (returnType) {
          VoidType() => body(
            invoke(
              arguments,
              _closure(
                ['args'],
                Block.of([
                  targetCall.statement,
                  literalNull.returned.statement,
                ]),
              ),
            ),
            direct,
            isVoid: true,
          ),
          _ when awaiting != null => body(awaiting, direct),
          _ => body(
            invoke(
              arguments,
              _closure(['args'], targetCall.code, lambda: true),
            ).asA(_anyType(returnType, element)),
            direct,
          ),
        };
        return Method(
          (m) => m
            ..docs.addAll(_proxyMemberDocs(proxy, member))
            ..annotations.add(refer('override'))
            ..name = member.name
            ..returns = _anyType(returnType, element)
            ..types.addAll([
              for (final typeParameter in member.typeParameters)
                TypeReference(
                  (t) => t
                    ..symbol = typeParameter.name
                    ..bound = typeParameter.bound == null
                        ? null
                        : _anyType(typeParameter.bound!, element),
                ),
            ])
            ..requiredParameters.addAll([
              for (final parameter in parameters)
                if (!parameter.isNamed && parameter.isRequired)
                  _proxyParameter(parameter, element),
            ])
            ..optionalParameters.addAll([
              for (final parameter in parameters)
                if (parameter.isNamed || !parameter.isRequired)
                  _proxyParameter(parameter, element),
            ])
            ..lambda = lambda
            ..body = code,
        );
    }
  }

  // A literal default is copied as source (the scanner checked it); any
  // other constant is re-created from its value.
  Parameter _proxyParameter(ProxyParameter parameter, Element element) =>
      Parameter(
        (p) => p
          ..name = parameter.name
          ..type = _anyType(parameter.type, element)
          ..named = parameter.isNamed
          ..required = parameter.isNamed && parameter.isRequired
          ..defaultTo = parameter.defaultValueCode != null
              ? Code(parameter.defaultValueCode!)
              : parameter.defaultValue != null
              ? _constant(parameter.defaultValue!, element).code
              : null,
      );

  // Whether [type] can be written in generated code as a type argument:
  // made of public classes only.
  bool _canCapture(DartType type) => switch (type) {
    InterfaceType(:final element, :final typeArguments) =>
      element.isPublic && typeArguments.every(_canCapture),
    DynamicType() || VoidType() || NeverType() => true,
    _ => false,
  };

  // `(bean) { bean.a(); bean.b(); }` for lifecycle callbacks.
  // Lifecycle callbacks: an `async` closure awaiting the asynchronous
  // methods when there are any (the callback's Future is awaited by
  // refreshAsync / closeAsync), else a plain one.
  Expression _calls(List<String> methods, BeanModel bean) {
    final asyncMethods = bean.asyncLifecycleMethods;
    final body = Block.of([
      for (final method in methods)
        if (asyncMethods.contains(method))
          refer('bean').property(method).call([]).awaited.statement
        else
          refer('bean').property(method).call([]).statement,
    ]);
    if (!methods.any(asyncMethods.contains)) {
      return _closure(['bean'], body);
    }
    return Method(
      (m) => m
        ..requiredParameters.add(Parameter((p) => p..name = 'bean'))
        ..modifier = MethodModifier.async
        ..body = body,
    ).closure;
  }

  Expression _propertySource(PropertySourceModel source) =>
      _spring('PropertySourceDeclaration').newInstance(
        [
          literalConstList([for (final l in source.locations) _str(l)]),
        ],
        {
          if (source.name case final name?) 'name': _str(name),
          if (source.ignoreResourceNotFound)
            'ignoreResourceNotFound': literalTrue,
          if (source.encoding case final encoding?) 'encoding': _str(encoding),
          if (source.factoryType case final factory?)
            'factory': _type(factory, factory.element).newInstance([]),
          if (source.conditions.isNotEmpty)
            'conditions': literalList([
              for (final condition in source.conditions)
                _condition(condition, source.element!),
            ]),
        },
      );

  // Profiles become a const `ProfileCondition`, condition types are
  // instantiated, condition annotations are re-created as constants.
  Expression _condition(ConditionModel condition, Element element) =>
      switch (condition) {
        ProfileConditionModel(:final profiles) =>
          _spring('ProfileCondition').constInstance([
            literalConstList([for (final p in profiles) _str(p)]),
          ]),
        TypeConditionModel(:final type) => _type(type, element).newInstance([]),
        AnnotationConditionModel(:final value) => _constant(value, element),
        GroupConditionModel(:final key, :final conditions) =>
          _spring('ConditionGroup').newInstance([
            _str(key),
            literalList([for (final c in conditions) _condition(c, element)]),
          ]),
      };

  // Declarative description of an injection point; the runtime uses it
  // to validate the bean graph at refresh (missing beans, cycles), not for
  // the lookup itself.
  Expression _dependency(InjectionPoint point, Element element) {
    final named = <String, Expression>{
      if (point.qualifier case final qualifier?) 'qualifier': _str(qualifier),
      if (point.optional || point.allowEmpty) 'optional': literalTrue,
    };
    final dependency = _spring('Dependency');
    return switch (point.kind) {
      PointKind.single when point.lazy != null => dependency.newInstanceNamed(
        'lazy',
        [_type(point.type, element)],
        {
          if (point.qualifier case final q?) 'qualifier': _str(q),
          if (point.name case final name?) 'name': _str(name),
        },
      ),
      PointKind.single => dependency.newInstance(
        [
          if (point.exactType case final exact?)
            _typeValue(exact, element)
          else
            _type(point.type, element),
        ],
        {...named, if (point.name case final name?) 'name': _str(name)},
      ),
      PointKind.list || PointKind.set => dependency.newInstanceNamed(
        'collection',
        [_type(point.type, element)],
        named,
      ),
      PointKind.map => dependency.newInstanceNamed('map', [
        _type(point.type, element),
      ], named),
      PointKind.provider => dependency.newInstanceNamed(
        'provider',
        [_type(point.type, element)],
        {
          if (point.qualifier case final q?) 'qualifier': _str(q),
          if (point.name case final name?) 'name': _str(name),
        },
      ),
      PointKind.value => dependency.newInstanceNamed(
        'value',
        [_str(point.expression!)],
        {if (point.optional) 'optional': literalTrue},
      ),
      PointKind.resource => dependency.newInstanceNamed(
        'resource',
        [_type(point.type, element), _str(point.name!)],
        {
          if (point.fallbackToType) 'fallbackToType': literalTrue,
          if (point.optional) 'optional': literalTrue,
        },
      ),
    };
  }

  // `r.containsBeanOfType(A) && ...` for the required single beans among
  // [arguments]; `null` when nothing has to be checked.
  Expression? _satisfiable(List<Argument> arguments, Element element) {
    final checks = [
      for (final Argument(:point) in arguments)
        if (point.kind == PointKind.single && !point.optional)
          refer('r')
              .property('containsBeanOfType')
              .call(
                [
                  if (point.exactType case final exact?)
                    _typeValue(exact, element)
                  else
                    _type(point.type, element),
                ],
                {if (point.qualifier case final q?) 'qualifier': _str(q)},
              ),
    ];
    return checks.isEmpty ? null : checks.reduce((a, b) => a.and(b));
  }

  // Body of `create: (r) => ...`: a constructor call, a static method call
  // or a method call on the owner bean looked up by name.
  Expression _creation(BeanModel bean) {
    final creation = bean.creation;
    final (positional, named) = _arguments(creation.arguments, bean.element);
    switch (creation) {
      // A full-mode @Configuration class: its generated subclass.
      case ConstructorCreation(configuration: final model?):
        return refer(model.className)
            .newInstance([refer('r'), ...positional], named);
      // A subclass proxy: the generated subclass forwards to the
      // constructor (after the bean factory for `@Lookup` methods); a
      // pruned one is not generated.
      case ConstructorCreation(:final lookup)
          when bean.proxy?.subclass != null && !bean.proxy!.pruned:
        return refer(
          bean.proxy!.className,
        ).newInstance([if (lookup != null) refer('r'), ...positional], named);
      // `@Lookup` methods: the generated subclass overriding them.
      case ConstructorCreation(lookup: final model?):
        return refer(model.className)
            .newInstance([refer('r'), ...positional], named);
      case ConstructorCreation(:final constructorName, :final alternatives):
        final type = _type(bean.type, bean.element);
        Expression call(String? name, List<Argument> arguments) {
          final (positional, named) = _arguments(arguments, bean.element);
          return name == null
              ? type.newInstance(positional, named)
              : type.newInstanceNamed(name, positional, named);
        }
        // `@Autowired(required: false)` constructors: the first (greediest)
        // whose beans exist, else the last one, like Spring's
        // ConstructorResolver.
        final candidates = [
          (constructorName, creation.arguments),
          for (final alternative in alternatives)
            (alternative.constructorName, alternative.arguments),
        ];
        var result = call(candidates.last.$1, candidates.last.$2);
        for (final (name, arguments) in candidates.reversed.skip(1)) {
          final satisfiable = _satisfiable(arguments, bean.element);
          result = satisfiable == null
              ? call(name, arguments)
              : satisfiable.conditional(call(name, arguments), result);
        }
        return result;
      case BeanMethodCreation():
        final Expression call;
        if (creation.enhanced case final enhanced?) {
          call = enhancedBeanMethodCall(creation, enhanced, bean.element);
        } else {
          final owner = creation.isStatic
              ? _type(creation.ownerType, bean.element)
              : refer('r')
                    .property('dependency')
                    .call(
                      [],
                      {'qualifier': _str(creation.ownerName)},
                      [_type(creation.ownerType, bean.element)],
                    );
          call = owner.property(creation.methodName).call(positional, named);
        }
        // The bean type was inferred from the method body: more specific
        // than the declared return type.
        return creation.declaredType == null
            ? call
            : call.asA(
                _type(
                  bean.type,
                  bean.element,
                ).rebuild((t) => t.isNullable = bean.nullable),
              );
      case InterfaceProxyCreation(:final model):
        return refer(model.className).property(r'$create').call([refer('r')]);
      // A bean a package's part makes: the part writes how.
      case PackageCreation():
        for (final generation in generations) {
          if (generation.beanCreation(bean, _emission) case final created?) {
            _packageCreators[bean] = generation;
            return created;
          }
        }
        throw StateError(
          'No starter part of the build makes the bean ${bean.name} '
          '(${creation.runtimeType}).',
        );
      case ConfigurationPropertiesCreation():
        return refer(
              'ConstructorBound',
              'package:spring_boot_dart/spring_boot_dart.dart',
            )
            .property('from')
            .call(
              [refer('r'), _str(bean.name)],
              {},
              [_type(bean.type, bean.element)],
            );
    }
  }

  // Splits arguments into positional and named resolver calls.
  (List<Expression>, Map<String, Expression>) _arguments(
    List<Argument> arguments,
    Element element,
  ) => (
    [
      for (final argument in arguments)
        if (argument.namedAs == null) _lookup(argument.point, element),
    ],
    {
      for (final argument in arguments)
        ?argument.namedAs: _lookup(argument.point, element),
    },
  );

  /// The call on the bean resolver `r` that supplies [point], such as
  /// `r.dependency<Clock>(name: r'clock')`.
  // Optional points use the `optional...` variants (returning `null`);
  // sets are built from the list lookup. A Dart default value or an
  // allowed-empty collection is applied with `??`.
  Expression _lookup(InjectionPoint point, Element element) {
    final lookup = _rawLookup(point, element);
    if (point.defaultValue case final value?) {
      return lookup.ifNullThen(_constant(value, element));
    }
    if (point.allowEmpty) {
      return lookup.ifNullThen(switch (point.kind) {
        PointKind.set => literalSet(const [], _type(point.type, element)),
        PointKind.map => literalMap(
          const {},
          refer('String'),
          _type(point.type, element),
        ),
        _ => literalList(const [], _type(point.type, element)),
      });
    }
    return lookup;
  }

  Expression _rawLookup(InjectionPoint point, Element element) {
    final r = refer('r');
    final type = switch (point.exactType) {
      final exact? => _anyType(exact, element),
      null => _type(point.type, element),
    };
    final qualifier = {if (point.qualifier case final q?) 'qualifier': _str(q)};
    final lenient = point.optional || point.allowEmpty;
    switch (point.kind) {
      case PointKind.single when point.lazy != null:
        return refer(point.lazy!.className).newInstance([
          r
              .property('lazyDependency')
              .call(
                [],
                {
                  ...qualifier,
                  if (point.name case final name?) 'name': _str(name),
                },
                [type],
              ),
        ]);
      case PointKind.single:
        return r
            .property(point.optional ? 'optionalDependency' : 'dependency')
            .call(
              [],
              {
                ...qualifier,
                if (point.name case final name?) 'name': _str(name),
              },
              [type],
            );
      case PointKind.list:
        return r
            .property(lenient ? 'optionalDependencyList' : 'dependencyList')
            .call([], qualifier, [type]);
      case PointKind.set:
        // From the map: like Spring, a Set keeps registration order (only
        // lists are sorted).
        final map = r
            .property(lenient ? 'optionalDependencyMap' : 'dependencyMap')
            .call([], qualifier, [type]);
        return (lenient
                ? map.nullSafeProperty('values')
                : map.property('values'))
            .property('toSet')
            .call([]);
      case PointKind.map:
        return r
            .property(lenient ? 'optionalDependencyMap' : 'dependencyMap')
            .call([], qualifier, [type]);
      case PointKind.provider:
        return r
            .property('provider')
            .call(
              [],
              {
                ...qualifier,
                if (point.name case final name?) 'name': _str(name),
              },
              [type],
            );
      case PointKind.value:
        return r
            .property(point.optional ? 'optionalValue' : 'value')
            .call([_str(point.expression!)], {}, [type]);
      case PointKind.resource:
        return r
            .property(point.optional ? 'optionalResource' : 'resource')
            .call(
              [_str(point.name!)],
              {if (point.fallbackToType) 'fallbackToType': literalTrue},
              [type],
            );
    }
  }

  Expression _listener(
    InterfaceType beanType,
    ListenerModel listener,
    Element element,
  ) {
    final bean = _type(beanType, element);
    final parameter = listener.parameterType;
    final named = <String, Expression>{
      if (listener.order case final order?) 'order': literalNum(order),
      if (listener.async)
        'async': _spring('Async').constInstance([
          if (listener.asyncExecutor case final executor?) _str(executor),
        ]),
      if (listener.resultType case final resultType?)
        'resultType': _spring('EventResultType')
            .constInstance([], {}, [_type(resultType, element)]),
    };
    // Common case: one event type equal to the parameter type, so the
    // runtime can check the type itself (`EventListenerMethod.of<B, E>`).
    if (listener.eventTypes.length == 1 &&
        parameter != null &&
        listener.eventTypes.single == parameter) {
      final eventType = _type(parameter, element);
      final handler = Method(
        (m) => m
          ..requiredParameters.addAll([
            Parameter((p) => p..name = 'bean'),
            Parameter((p) => p..name = 'event'),
          ])
          ..lambda = listener.returnsValue
          ..body = listener.returnsValue
              ? refer('bean')
                    .property(listener.methodName)
                    .call([refer('event')])
                    .code
              : Block.of([
                  refer('bean')
                      .property(listener.methodName)
                      .call([refer('event')])
                      .statement,
                  literalNull.returned.statement,
                ]),
      ).closure;
      // A `PayloadApplicationEvent<P>` listener matches on the payload's
      // runtime type (`EventListenerMethod.forPayload<B, P>`).
      final payload = _payloadApplicationEvent.isExactlyType(parameter)
          ? parameter.typeArguments.single
          : null;
      return _spring(
        'EventListenerMethod',
      ).property(payload is InterfaceType ? 'forPayload' : 'of').call(
        [_str(listener.id), handler],
        {
          ...named,
          if (listener.condition case final condition?)
            'condition': _functionReference(condition, element),
        },
        [
          bean,
          if (payload is InterfaceType) _type(payload, element) else eventType,
        ],
      );
    }

    // Several event types (and/or a parameterless method).
    final accepts = listener.eventTypes
        .map((t) => refer('candidate').isA(_type(t, element)))
        .reduce((a, b) => a.or(b));
    final acceptsFn = _closure(['candidate'], accepts.code, lambda: true);
    final matched = _spring('EventListenerMethod')
        .property('match')
        .call([refer('event'), acceptsFn]);
    final argument = parameter == null
        ? matched
        : matched.asA(_type(parameter, element));
    final handler = Method(
      (m) => m
        ..requiredParameters.addAll([
          Parameter((p) => p..name = 'bean'),
          Parameter((p) => p..name = 'event'),
        ])
        ..body = Block.of([
          if (listener.returnsValue)
            refer('bean')
                .property(listener.methodName)
                .call([if (parameter != null) argument])
                .returned
                .statement
          else ...[
            refer('bean')
                .property(listener.methodName)
                .call([if (parameter != null) argument])
                .statement,
            literalNull.returned.statement,
          ],
        ]),
    ).closure;
    final listenerType = TypeReference(
      (t) => t
        ..symbol = 'EventListenerMethod'
        ..url = _springUrl
        ..types.add(bean),
    );
    return listenerType.newInstanceNamed('matching', [], {
      'id': _str(listener.id),
      'accepts': acceptsFn,
      'invoke': handler,
      ...named,
      if (listener.condition case final condition?)
        'condition': _functionReference(condition, element),
    });
  }

  // The extension name of each `@Log` class: `$CheckoutLog`. Classes of
  // different libraries may share a simple name; the later ones (in scan
  // order) get a number, `$CheckoutLog2`, so the extensions do not clash.
  static List<(LogModel, String)> _logExtensionNames(List<LogModel> loggers) {
    final counts = <String, int>{};
    return [
      for (final log in loggers)
        (
          log,
          () {
            final name = '\$${log.element.name}Log';
            final count = counts[name] = (counts[name] ?? 0) + 1;
            return count == 1 ? name : '$name$count';
          }(),
        ),
    ];
  }

  // `extension $CheckoutLog on Checkout { SpringLog get log => ...; }` for
  // a `@Log` class (the raw type: a generic class's instances all match).
  Extension _logExtension(LogModel log, String extensionName) {
    final name = log.element.name!;
    return Extension(
      (e) => e
        ..docs.add(
          "/// `@Log` of [$name]: the logger '${_docText(log.topic)}'.",
        )
        ..name = extensionName
        ..on = refer(
          name,
          _importUrl(log.element.library.uri, log.element, name: name),
        )
        ..methods.add(
          Method(
            (m) => m
              ..type = MethodType.getter
              ..returns = _spring('SpringLog')
              ..name = log.fieldName
              ..lambda = true
              ..body = _spring('SpringLog')
                  .constInstance([_str(log.topic)])
                  .code,
          ),
        ),
    );
  }
}

/// What the emission hooks of a `PackageGeneration` get: the module being
/// written, and the emitter's ways of naming types and values from the
/// generated library, so a part writes its code as the core writes its own
/// (imports through public libraries, raw strings, `Type` values of
/// function and record types).
///
/// ```dart
/// // A part's bean definition:
/// emission.spring('BeanDefinition').newInstance([], {
///   'name': emission.string('screenRoutes#${emission.moduleName}'),
///   'create': emission.closure(['r'], routes.code, lambda: true),
/// }, [refer('ScreenRoutes', navigationUrl)]);
/// ```
final class ModuleEmission {
  ModuleEmission._(this._emitter, this.moduleName);

  final ModuleEmitter _emitter;

  /// The `BeanModule` name: the `@ComponentScan` variable, or
  /// `application`.
  final String moduleName;

  /// The module being written.
  ModuleModel get module => _emitter._module;

  /// A reference to [type], declared or used by [element], imported from
  /// the public library that declares or exports it.
  ///
  /// Throws `InvalidGenerationSource` when the library cannot be imported
  /// from the output (a file of another package outside `lib/`).
  TypeReference type(DartType type, Element element) =>
      _emitter._type(type, element);

  /// A reference to any [type] (a function or record type too) as a type
  /// argument or a declared type.
  Reference anyType(DartType type, Element element) =>
      _emitter._anyType(type, element);

  /// [type] as a `Type` value: a class's name, a function or record type's
  /// public alias, else `_$typeOf<T>()` (the module then declares it).
  Expression typeValue(DartType type, Element element) =>
      _emitter._typeValue(type, element);

  /// A reference to the public runtime type [name] of `spring_core_dart`
  /// (`BeanDefinition`).
  Reference spring(String name) => _spring(name);

  /// A raw string literal of [value], so `$` and backslashes are written as
  /// they are.
  Expression string(String value) => _str(value);

  /// [value] (a user string: a bean name) for a generated `///` comment,
  /// on one line.
  String docText(String value) => _docText(value);

  /// An untyped closure of [parameters] with [body] (an expression when
  /// [lambda], else a block); the parameter types are inferred from the
  /// runtime API's function types.
  Expression closure(
    List<String> parameters,
    Code body, {
    bool lambda = false,
  }) => _emitter._closure(parameters, body, lambda: lambda);

  /// Code that re-creates the constant [value] of [element] (an
  /// annotation, a default value): literals, collections, records, types,
  /// enum values, functions and `const` constructor calls. A type an
  /// annotation names joins the module's `typeTests`.
  Expression constant(DartObject value, Element element) =>
      _emitter._constant(value, element);

  /// The `TypeInfo` of [type], declared or used by [element]
  /// (`ClassType<T>`, `ListType<E>(...)`, `EnumType<E>(E.values)`...), and
  /// whether that expression is constant (an enum with `@JsonValue` needs
  /// a closure).
  (Expression, bool) typeInfo(DartType type, Element element) =>
      _emitter._typeInfo(type, element);

  /// The initial value of a field (the `value` of an `InitialValue`) as
  /// code: a literal, a referenced constant, or a `const` collection of
  /// those, with the type arguments of the field's declared [type].
  Expression initialValue(Object? value, Element element, [DartType? type]) =>
      _emitter._initialValue(value, element, type);

  /// The parameter [parameter] of a generated member that repeats a
  /// signature (a [ProxyMember]'s), with its type and default value.
  Parameter parameter(ProxyParameter parameter, Element element) =>
      _emitter._proxyParameter(parameter, element);
}

/// The sources of a module's generated files: its library, and the files
/// of what it holds by kind, `null` for a kind it has none of (the build
/// then writes no such file). Unformatted until the builder formats them
/// ([ModuleSources.formatted]).
final class ModuleSources {
  /// The sources of a module whose library is [module].
  const ModuleSources(
    this.module, {
    this.introspection,
    this.properties,
    this.proxies,
    this.parts = const {},
  });

  /// `<library>.spring.dart`: the bean definitions and the wiring, which
  /// imports the descriptions and declares the part of the proxies.
  final String module;

  /// `<library>.spring.introspection.dart`: a library with the descriptions of
  /// the classes the module uses (`$<module>Introspections`).
  final String? introspection;

  /// `<library>.spring.properties.dart`: a library with the binding of the
  /// module's `@ConfigurationProperties` classes, the descriptions only the
  /// binder uses (`$<module>PropertiesIntrospections`).
  final String? properties;

  /// `<library>.spring.proxies.dart`: a part of the module's library with its
  /// AOP proxy classes and lazy-resolution proxies.
  final String? proxies;

  /// The parts of an application's library the builder fills, by their
  /// ending ([applicationPartExtensions]): `<library>.spring.debug.dart`
  /// with what only debug and profile builds use (the fingerprint of the
  /// generated code, the hot-reload functions), `<library>.spring.env.dart`
  /// with the values of the `--dart-define`s. A part without declarations
  /// is not there.
  final Map<String, String> parts;

  /// These sources, each formatted by [format].
  ModuleSources formatted(DartFormat format) => ModuleSources(
    format.format(module),
    introspection: _formatted(introspection, format),
    properties: _formatted(properties, format),
    proxies: _formatted(proxies, format),
    parts: {
      for (final MapEntry(key: extension, value: source) in parts.entries)
        extension: format.format(source),
    },
  );

  static String? _formatted(String? source, DartFormat format) =>
      source == null ? null : format.format(source);
}

// The descriptions of a module's classes, written in the module's order into
// `<library>.spring.introspection.dart` and, for those only the binder of
// `@ConfigurationProperties` classes uses (`onlyForBinding`),
// `<library>.spring.properties.dart`: each a library of its own whose getter
// the module spreads into its `introspections:`.
final class _ModuleDescriptions {
  _ModuleDescriptions(this._module, this._variableName);

  final ModuleEmitter _module;

  // The module's getter (`$appBeans`), after which the getters of its
  // descriptions are named.
  final String _variableName;

  String get _introspectionGetter => '${_variableName}Introspections';

  String get _propertiesGetter => '${_variableName}PropertiesIntrospections';

  late final ({AssetId id, IntrospectionEmitter emitter}) _introspection =
      _file(introspectionExtension);

  late final ({AssetId id, IntrospectionEmitter emitter}) _properties = _file(
    propertiesExtension,
  );

  final _introspections = <Expression>[];

  final _bindings = <Expression>[];

  // The object methods' models of the classes
  // `<library>.spring.introspection.dart` describes, in its order: its
  // `copyWith`s and builders.
  final _objectMethods = <ObjectMethodsModel>[];

  ({AssetId id, IntrospectionEmitter emitter}) _file(String extension) {
    final id = moduleFileId(_module.output, extension);
    return (
      id: id,
      emitter: IntrospectionEmitter(
        CodeWriter(
          id,
          dependencies: _module.dependencies,
          annotationTypes: _module._writer.annotationTypes,
        ),
      ),
    );
  }

  // Writes [models], each into its file, and returns what the module's
  // `introspections:` spreads.
  List<Expression> describe(List<IntrospectionModel> models) {
    final binding = onlyForBinding(models);
    for (final model in models) {
      if (binding.contains(model)) {
        _bindings.add(_properties.emitter.introspection(model));
      } else {
        _introspections.add(_introspection.emitter.introspection(model));
        if (model.objectMethods case final methods?) {
          _objectMethods.add(methods);
        }
      }
    }
    return [
      if (_introspections.isNotEmpty)
        refer(
          _introspectionGetter,
          p.url.basename(_introspection.id.path),
        ).spread,
      if (_bindings.isNotEmpty)
        refer(_propertiesGetter, p.url.basename(_properties.id.path)).spread,
    ];
  }

  String? introspectionSource() => _introspections.isEmpty
      ? null
      : _introspection.emitter.library(
          getter: _introspectionGetter,
          doc:
              '/// The descriptions of the classes the module '
              '`${_variableName.substring(1)}` uses: its\n'
              '/// `@Introspected` classes, and those its beans read, write '
              'or call by\n'
              '/// name. The module hands them to the context; a unit test '
              'registers them\n'
              '/// without one (`Introspector.shared.registerAll(...)`).'
              '${_objectMethods.any((model) => model.hasCopyWith) ? '\n/// '
                        'The `copyWith`s of `@CopyWith` follow it.' : ''}',
          descriptions: _introspections,
          declarations: _introspection.emitter.objectMethodDeclarations(
            _objectMethods,
          ),
        );

  String? propertiesSource() => _bindings.isEmpty
      ? null
      : _properties.emitter.library(
          getter: _propertiesGetter,
          doc:
              '/// The binding of the `@ConfigurationProperties` classes of '
              'the module\n'
              '/// `${_variableName.substring(1)}`: the descriptions only '
              'its binder uses. The module hands\n'
              '/// them to the context.',
          descriptions: _bindings,
        );
}
