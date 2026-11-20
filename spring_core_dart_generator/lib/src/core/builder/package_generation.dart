import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/beans/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_directory.dart';
import 'package:spring_core_dart_generator/src/core/introspection/introspection_scanner.dart';

export 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart'
    show AnnotatedMethodNeeds, ModuleScan, SpelUse;
export 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart'
    show BuildInclusion;
export 'package:spring_core_dart_generator/src/core/introspection/introspection_model.dart'
    show IntrospectionNeed;
export 'package:spring_core_dart_generator/src/core/introspection/introspection_scanner.dart'
    show IntrospectionRequests, JsonWriter;

/// One package's part of a module build: what a package (a starter such as
/// `spring_boot_starter_flutter`, or a library such as `spring_web_dart`)
/// adds to the `.spring.dart` the main builder writes for a
/// `@ComponentScan` or `@SpringBootApplication` library, and to the
/// package's `spring_metadata.json`.
///
/// The core scans beans, writes their definitions and checks them; a
/// package's annotations (Flutter's widgets, the navigation's screens, the
/// signals, the data starter's entities and repositories) are read and
/// written by its part, and what they imply for the core's work is the
/// part's to say (which classes a controller's or a cache key's values
/// need described, what a cached method may not return). The builders ask
/// every part they start in turn, in the order of their list, at fixed
/// points of the build: the module before its libraries are scanned, each
/// class and mixin of a scanned library (before the core decides which
/// bean a class is, in place of the core for a bean the part makes, and
/// after the core), each annotated method and proxy the core reads, the
/// module once it is scanned, the files that are part of its library, the
/// generated classes, the bean definitions and how a part's bean is made,
/// the body of the module getter, the declarations after it, and the
/// metadata. A part handles what it recognises and leaves the rest; every
/// hook does nothing by default, so a part overrides only those it needs.
///
/// A part runs only when the package being built reaches the part's
/// package ([package]): an application without the Flutter starter runs
/// none of the Flutter code. A part may also leave the module build to a
/// property of the application's configuration, as an auto-configuration
/// module does ([build]). The built-in parts (`lib/src/packages.dart`) use
/// this class as another one would; the builder factories pass that list
/// to the builders.
///
/// ```dart
/// final class ClockGeneration extends PackageGeneration {
///   const ClockGeneration();
///
///   @override
///   String get package => 'spring_boot_starter_clock';
///
///   @override
///   void scanClass(ClassElement element, ModuleScan scan) =>
///       scan.collectErrors(() => scanClockTicks(element, scan.module));
/// }
/// ```
///
/// Spring (Java): the `BeanFactoryInitializationAotProcessor` and
/// `BeanRegistrationAotProcessor` implementations a module registers in
/// `aot.factories`, which Spring's AOT engine asks in turn to contribute
/// generated code for the beans it knows.
abstract class PackageGeneration {
  /// A part; parts keep no state of a build (that is in the module).
  const PackageGeneration();

  /// The package this part belongs to (`spring_boot_starter_flutter`,
  /// `spring_web_dart`): the builders start the part for a package that
  /// depends on it, directly or not.
  String get package;

  /// The property of the application's configuration that decides
  /// whether the part is in the module build, as
  /// `AutoConfigurationModule(build: AutoConfigurationBuild(...))` decides
  /// a module: so one key leaves out a package's module and all the part
  /// writes. Read when the generator runs, from `application.yml` and
  /// `application.properties` without a profile:
  ///
  /// - `true`: the part runs as one without a key;
  /// - `false`: it does not run, so the module has none of its code;
  /// - not set: [PackageBuild.whenMissing]; for
  ///   [BuildInclusion.notInRelease] the part runs and its bean
  ///   definitions (those it writes and those of the beans it makes), its
  ///   module statements, its lists of introspections and its resources
  ///   ([ModuleParts.resources]) are written under
  ///   `if (!const bool.fromEnvironment('dart.vm.product'))`, the constant
  ///   of such a module, so a release build compiles them away. Its
  ///   classes, declarations, part files and proxy mixins cannot be under
  ///   a condition (declarations are no statements); a release build drops
  ///   them as nothing else uses them. Its [applicationResources] are the
  ///   application's files once added, and are not under it either.
  ///
  /// `null` (the default): the part is in every build of a package that
  /// reaches the part's package. `spring_metadata.json` describes the
  /// sources whatever the key says.
  ///
  /// ```dart
  /// @override
  /// PackageBuild get build => const PackageBuild('spring.clock.enabled');
  /// ```
  PackageBuild? get build => null;

  /// Text whose presence in a library of `lib/` or `bin/` makes the
  /// package one with Spring code, for which `spring_metadata.json` is
  /// written (`@ScreenRoute`), besides the core's own markers.
  List<String> get markers => const [];

  /// Text files the part adds to the resources of an application (the
  /// module of a `@SpringBootApplication` library), by path below
  /// `lib/resources/`, unless the application has a file of its own there:
  /// the actuator's `build-info.properties`, which its `info` endpoint
  /// shows. From then on they are the application's files: the build
  /// reads them with its own (the configuration it decides by, a part's
  /// [ModuleBuild.resources]) and embeds them, so a build key cannot put
  /// them under a condition. Asked before [prepareModule].
  Future<Map<String, String>> applicationResources(
    BuildStep buildStep,
  ) async => const {};

  /// Reads, before the module's libraries are scanned, what the scan and
  /// the emission need that is in no library of the module: files of the
  /// package, declarations of its dependencies, the dependencies
  /// themselves (the data starter's stores and its drivers' glue). The
  /// part keeps it in its model of the module ([ModuleModel.packageModel]).
  /// Only the main builder asks it: the metadata's scan knows none of
  /// this.
  Future<void> prepareModule(ModuleBuild build) async {}

  /// Reads [element], a class of a scanned library, before the core
  /// decides which bean it is: the classes the part's runtime reads (the
  /// data starter's `@Table` entities). It runs in the core's own check of
  /// the class, so a problem it throws ends that check (the class becomes
  /// no bean) and is reported with the core's problems.
  void describeClass(ClassElement element, ModuleScan scan) {}

  /// Whether the part makes the bean of [element], a class of a scanned
  /// library that is no interface proxy, itself: it adds the bean
  /// ([ModuleScan.addGeneratedBean], with a [PackageCreation] of its own)
  /// or decides that the class is none (a generic base of others), and the
  /// core does not scan the class as a component. The first part that
  /// claims a class has it. The data starter's repositories, interfaces
  /// extending `DataRepository`, are beans so, annotated or not.
  bool claimClass(ClassElement element, ModuleScan scan) => false;

  /// The classes, reached from [element] (a class of a scanned library),
  /// whose fields' initial values the part reads while scanning
  /// ([ModuleScan.initialValueOf]): the build resolves their initializers
  /// before the scan, with those of the classes they are made of. The data
  /// starter's entities and the DTOs of its `@Query` methods.
  Iterable<ClassElement> initialValueClasses(
    ClassElement element,
    ModuleScan scan,
  ) => const [];

  /// Reads [element], a class of a scanned library, into the module of
  /// [scan]. Called for every class, after the core has scanned it; a
  /// problem is reported through [ModuleScan.collectErrors], one call per
  /// independent check, so the build lists them all.
  void scanClass(ClassElement element, ModuleScan scan) {}

  /// Reads [element], a mixin of a scanned library, as [scanClass] does a
  /// class.
  void scanMixin(MixinElement element, ModuleScan scan) {}

  /// The classes the generated proxy class of a bean mixes in, given the
  /// bean's [proxy] model: `ChangeNotifier` for a
  /// `@ChangeNotifierComponent`. Such a proxy is never pruned nor left to
  /// the application, since the bean the container hands out must carry
  /// them.
  Iterable<ProxyMixin> proxyMixins(ProxyModel proxy) => const [];

  /// Checks [proxy], the proxy model of a bean (or of a generated class),
  /// before the build goes on with it: what the part's annotations cannot
  /// do on its members fails the build (throw `InvalidGenerationSource`),
  /// as the cache starter's `@Cacheable` on a method returning a `Stream`,
  /// which can be listened to only once.
  void checkProxy(ProxyModel proxy) {}

  /// What the framework does with the values of [method], a method of a
  /// bean with [annotation] (whose class is marked
  /// `@BeanMethodAnnotation()`): for its result and each parameter, in
  /// order, whether a value is read from JSON, written to it, validated or
  /// reached by an expression. The build describes the classes of the
  /// bean's package they are made of for that only (a controller's bodies
  /// are read in, its answers written out); `null` when the annotation is
  /// not the part's. The first part that answers decides; an annotation no
  /// part knows is described entirely, since its framework may do anything
  /// with the values.
  AnnotatedMethodNeeds? methodNeeds(
    InterfaceType annotation,
    MethodElement method,
    ModuleScan scan,
  ) => null;

  /// Where the expressions of [annotation], an annotation of a bean's
  /// method, look: at the arguments, the result, the bean (cache keys,
  /// security conditions). The build describes the classes they reach so
  /// their methods can be called; `null` when the annotation is not the
  /// part's. The first part that answers decides.
  SpelUse? expressionUse(DartObject annotation, ModuleScan scan) => null;

  /// The methods of the package that write an argument out as JSON through
  /// the `ObjectMapper` (the WebSocket session's `sendJson(value)`): the
  /// build describes the classes of the package a call's argument names,
  /// as it does for the mapper's own calls, in the libraries that import
  /// the writer's package.
  List<JsonWriter> get jsonWriters => const [];

  /// Checks the module of [build] once every library is scanned (and the
  /// core has checked the bean names), before the errors are thrown: what
  /// needs the whole module or the files of the package.
  Future<void> checkModule(ModuleBuild build) async {}

  /// The generated files that are `part of` the library of the build
  /// step's input, with the imports they need (a part has none of its
  /// own); [ModuleParts.none] when there are none.
  Future<ModuleParts> moduleParts(BuildStep buildStep) async =>
      ModuleParts.none;

  /// The classes the part generates, written among the module's generated
  /// classes after the implementations of the interface proxies (and
  /// before the subclasses of the configuration classes): the classes its
  /// beans are made of (the data starter's repositories).
  Iterable<Spec> classes(ModuleEmission emission) => const [];

  /// How [bean], a bean of the module whose creation is a [PackageCreation],
  /// is made: the body of its definition's `create: (r) => ...`
  /// (`_$BookRepositoryImpl.$create(r)`), or `null` when the bean is
  /// another part's. The first part that answers writes it.
  Expression? beanCreation(BeanModel bean, ModuleEmission emission) => null;

  /// The bean definitions written after those of the module's beans.
  Iterable<Expression> beanDefinitions(ModuleEmission emission) => const [];

  /// The statements the module getter runs before it returns the
  /// `BeanModule` (a getter without any is written as `=>`).
  Iterable<Code> moduleStatements(ModuleEmission emission) => const [];

  /// The top-level declarations written right after the module getter,
  /// before the caller's own (`springApplication`): the code the part's
  /// bean definitions call (the data starter's drivers' glue).
  Iterable<Spec> leadingDeclarations(ModuleEmission emission) => const [];

  /// The top-level declarations written after the module getter and the
  /// caller's own (`springApplication`), before the core's `@Log`
  /// extensions.
  Iterable<Spec> declarations(ModuleEmission emission) => const [];

  /// The entries the part adds to `spring_metadata.json`, after the
  /// core's, in the order to write them; an entry is left out when it has
  /// nothing to say, so the files of other packages stay as they are.
  Future<Map<String, Object?>> metadata(MetadataBuild build) async => const {};
}

/// The parts of [generations] whose package is among the [reachable]
/// packages, in their order; all of them when [reachable] is `null` (the
/// dependencies could not be read).
List<PackageGeneration> startedGenerations(
  List<PackageGeneration> generations,
  Set<String>? reachable,
) => [
  for (final generation in generations)
    if (reachable == null || reachable.contains(generation.package)) generation,
];

/// The parts of [started] that the build keys of the application's
/// configuration ([keys]) leave in the module build
/// ([PackageGeneration.build]), in their order, with the condition the code
/// of each one only in debug and profile builds is under.
({List<PackageGeneration> built, Map<PackageGeneration, String> conditions})
builtGenerations(List<PackageGeneration> started, BuildKeys keys) {
  final built = <PackageGeneration>[];
  final conditions = <PackageGeneration, String>{};
  for (final generation in started) {
    final key = generation.build;
    final inclusion = key == null
        ? BuildInclusion.always
        : keys.decide(
            key.property,
            whenMissing: key.whenMissing,
            subject: "${generation.package}'s generator part",
            noun: 'part',
          );
    switch (inclusion) {
      case BuildInclusion.never:
        continue;
      case BuildInclusion.notInRelease:
        conditions[generation] = notInReleaseCondition;
      case BuildInclusion.always:
        break;
    }
    built.add(generation);
  }
  return (built: built, conditions: conditions);
}

/// When a [PackageGeneration] is in the module build: by [property] of the
/// application's configuration, as `AutoConfigurationBuild` decides a
/// module (`true`: in every build; `false`: in none; not set:
/// [whenMissing]).
final class PackageBuild {
  /// The part by [property]; [whenMissing] when it is not set.
  const PackageBuild(
    this.property, {
    this.whenMissing = BuildInclusion.notInRelease,
  });

  /// The property that decides (`spring.clock.enabled`).
  final String property;

  /// What the build does when the configuration does not set [property].
  final BuildInclusion whenMissing;
}

/// What [PackageGeneration.prepareModule] and
/// [PackageGeneration.checkModule] get: the module's scan, and what the
/// main builder knows of the module's library: its build step, the
/// package's directories for the files the build does not see, the
/// module's resources and the packages it may import.
final class ModuleBuild extends ModuleScan {
  /// The build of the module [scanner] fills, in [buildStep].
  ModuleBuild(
    super.scanner, {
    required this.buildStep,
    required this.packageDirectories,
    this.resources = const {},
    this.dependencies,
    this.importablePackages,
  });

  /// The step writing the module's library.
  final BuildStep buildStep;

  /// Where the packages are on disk (`PackageDirectories.current` in a
  /// real build).
  final PackageDirectories packageDirectories;

  /// The text of the module's resources, by path below their directory
  /// (`application.yml`, `db/migration/V1__books.sql`): those of
  /// `lib/resources/`, and of the entry point's directories for an
  /// application.
  final Map<String, String> resources;

  /// The packages the package lists itself (`dependencies`, and
  /// `dev_dependencies` for a module outside `lib/` and `bin/`), itself
  /// included; `null` when its pubspec cannot be read.
  final Set<String>? dependencies;

  /// The packages the module's library may import besides [dependencies]:
  /// those the package reaches (the data starter brought by the Supabase
  /// starter). `null` for a module in the `lib/` of a published package,
  /// whose imports pub.dev checks against its `dependencies`, and when
  /// they cannot be read.
  final Set<String>? importablePackages;
}

/// The generated files that are `part of` a module's library, the imports
/// they need, the lists of introspections they declare and the resources
/// that come with them, from [PackageGeneration.moduleParts].
final class ModuleParts {
  /// The [parts] (paths relative to the library) needing [imports], whose
  /// [introspections] the module spreads and whose [resources] it embeds.
  const ModuleParts(
    this.parts,
    this.imports, {
    this.introspections = const [],
    this.resources = const {},
  });

  /// No parts.
  static const none = ModuleParts([], []);

  /// The `part` directives' paths, relative to the library.
  final List<String> parts;

  /// The libraries the parts use, each as `url` or `url as prefix`.
  final List<String> imports;

  /// The names of the lists of `Introspection`s the parts declare, which
  /// the module's `introspections:` spreads after its own
  /// (`_$jsonSchemaIntrospections`).
  final List<String> introspections;

  /// Files embedded among the module's resources, after its own, by path
  /// (a part's file replaces one of the module's of the same path): the
  /// downloaded JSON Schemas.
  final Map<String, ({String? text, String? base64})> resources;
}

/// What [PackageGeneration.metadata] gets: the package's libraries as the
/// metadata builder scanned them.
final class MetadataBuild {
  /// The metadata of [module], scanned from [libraries].
  const MetadataBuild({
    required this.buildStep,
    required this.module,
    required this.libraries,
    required this.packageDirectories,
  });

  /// The step writing `spring_metadata.json` (its input is the package).
  final BuildStep buildStep;

  /// What the scan of the package's `lib/` and `bin/` found.
  final ModuleModel module;

  /// The text of each library scanned, in scan order.
  final Map<AssetId, String> libraries;

  /// Where the packages are on disk, for the files the build does not see.
  final PackageDirectories packageDirectories;
}
