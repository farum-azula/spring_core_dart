# spring_core_dart_generator

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

`spring_core_dart_generator` is the code generator of
[`spring_core_dart`](https://pub.dev/packages/spring_core_dart). It reads
the annotations of your classes (`@Service`, `@Value`, `@Bean`,
`@Aspect`, ...) at build time and writes plain Dart code that creates and
connects your objects.

**Why it exists.** Spring finds annotated classes at runtime with
reflection. Dart has no reflection in Flutter, AOT executables or on the
web (`dart:mirrors` is not available there), so this step happens at
build time instead, through `build_runner`. Every application that uses
`spring_core_dart`, `spring_boot_dart` or one of the starters needs it:
without it the annotations do nothing. You never call it from your code;
you only run `build_runner`.

The guide to the annotations themselves is the
[`spring_core_dart` README](https://pub.dev/packages/spring_core_dart).

## Installation

```yaml
dependencies:
  spring_core_dart: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2
```

Mark a scan root: a top-level variable with `@ComponentScan()`. Every
class in that file's directory and below is scanned.

```dart
// lib/src/beans.dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/beans.spring.dart'; // written by the generator

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

Then generate, once or on every save:

```bash
dart run build_runner build
dart run build_runner watch
```

The generator writes `beans.spring.dart` next to `beans.dart`. Pass
`appBeans` to the context: `ApplicationContext.run([appBeans])`. A
runnable walk-through is in the
[example](https://pub.dev/packages/spring_core_dart_generator/example).

## What it generates

The package registers three builders in its `build.yaml`; all apply
automatically to every package that depends on it.

**`spring_core_dart`** (the main builder) writes `<file>.spring.dart` next
to two kinds of library:

- **A library with a `@ComponentScan()` variable.** The output holds a
  `BeanModule` getter, named after the variable with a `$` prefix
  (`$appBeans`), for the beans of the file's directory and below. A
  subdirectory with its own `@ComponentScan` is left to that scan, and its
  module is imported instead.
- **A library whose `main` has `@SpringBootApplication()`**
  (`spring_boot_dart`). The output covers the whole package: `lib/` and
  the directory of `main` (only `example/` for an entry point under
  `example/`). It also declares `springApplication`, `runApplication`
  and the hot-reload functions, with the auto-configuration modules of
  every dependency (each starter's `lib/spring_auto_configuration.dart`)
  and the `--dart-define` keys the application may read (below).

Into that file it writes:

- one `BeanDefinition` per bean: its types, scope, laziness,
  primary / fallback, qualifiers, aliases, order, depends-on, conditions,
  declared dependencies, the `create` and `inject` closures, lifecycle
  callbacks, event listeners and factory bean product types;
- `@PropertySource` declarations, `@Configurable` configurers and
  `@Introspected` metadata (properties, methods, annotations), which the
  `ObjectMapper`, validation and SpEL read;
- `@Aspect` advice metadata and the AOP proxy classes;
- generated subclasses of full-mode `@Configuration` classes and of beans
  with `@Lookup` methods;
- the files of `lib/resources/`, embedded so that `classpath:` locations
  work on every platform without Flutter asset declarations. Text files
  stay text, other files are base64-encoded, and files above 1 MB are
  skipped with a warning. An application whose `main` is outside `lib/`
  (`example/`, `tool/demo/`) also gets the `lib/resources/` of every
  directory from the package root down to its own; the nearer to `main`,
  the higher the precedence.

**`spring_test`** (the test builder) writes
`test/spring/<name>.test.spring.dart` for every `test/<name>_test.dart`
that declares `@SpringBootTest` classes. The file has a
`runSpringTests()` function that registers the tests of those classes
with `package:test`; the test's `main` calls it. See
[`spring_boot_starter_test`](https://pub.dev/packages/spring_boot_starter_test).

**`spring_flutter_web`** writes `web_dev_config.yaml`, the file
`flutter run` reads on the web (Flutter 3.38 and later), from the
`spring.flutter.web.*` properties of `lib/resources/` (see
[Flutter](#flutter-spring_boot_starter_flutter) below). Without those
properties it writes nothing.

A short example of the main builder's output (simplified; the real file
uses import prefixes such as `_i1.`):

```dart
// You write:
@Service()
class Greeter {
  Greeter(@Value(r'${greeting.suffix:!}') this.suffix, this.clock);
  final String suffix;
  final Clock clock;
}

// It generates:
BeanModule get $appBeans => BeanModule(r'appBeans', [
  BeanDefinition<Greeter>(
    name: r'greeter',
    types: const [Greeter],
    dependencies: const [
      Dependency.value(r'${greeting.suffix:!}'),
      Dependency(Clock, name: r'clock'),
    ],
    create: (r) => Greeter(
      r.value<String>(r'${greeting.suffix:!}'),
      r.dependency<Clock>(name: r'clock'),
    ),
  ),
]);
```

Plain constructor calls and closures: fast, available in AOT, Flutter and
on the web, and unaffected by minification.

### New Dart syntax

The generator understands Dart 3.13 syntax: primary constructors
(annotations on declaring parameters inject through the constructor, not
as fields), `class const`, in-body `new` / `factory` constructor
declarations, and private named parameters (passed under their public
name).

### `--dart-define` keys

`flutter build --dart-define=SPRING_PROFILES_ACTIVE=prod` passes values
into the compiled program, but the program can only read them with a
constant key (`const String.fromEnvironment('KEY')`); on the web and in AOT
builds there is no other way. So the `@SpringBootApplication` output lists
every property name the application may read, each also in its
environment-variable form (`shop.currency` and `SHOP_CURRENCY`). The
names come from the `${...}` placeholders in annotation arguments,
`@ConditionalOnProperty` names, the fields of `@ConfigurationProperties`
classes, the keys and placeholders of the `application*` files in
`lib/resources/`, and a few properties read before the config files.

## `@Log`

A class of the scan with `@Log()` gets an extension
`extension $<Class>Log on <Class>` with a getter (`log`, or the
`fieldName:`) that returns `const SpringLog('<package>.<Class>')`, or the
`topic:`. The build fails for a private class (an extension elsewhere
cannot name it), an invalid or reserved getter name, or a member of the
class or its supertypes with that name (it would win over the getter).

## Flutter (`spring_boot_starter_flutter`)

For apps on
[`spring_boot_starter_flutter`](https://pub.dev/packages/spring_boot_starter_flutter).
Its annotations are matched by URL, like those of the other starters, so
the generator does not depend on that package. Nothing Flutter-specific
is written for modules that do not use them.

**`@BuildContextAccess()`** on a bean class or a `@Bean` method adds a
getter to `extension SpringBeans on BuildContext`. It is written into the
`.spring.dart` file of the `@SpringBootApplication` or `@ComponentScan`
(after the run and reload functions); import that file where widgets use
the getters.

```dart
@Component()
@BuildContextAccess()
class Basket { ... }

// generated
extension SpringBeans on BuildContext {
  Basket get basket => SpringScope.beanOf<Basket>(this, qualifier: r'basket');
}

// in a widget
Text('${context.basket.count}');
```

The getter is named after the bean (`@BuildContextAccess(name: 'cart')`
for another name) and typed with the bean's class: a `@Bean` method's
declared return type, a `FactoryBean`'s product. The build fails for a
name that is not a public identifier, a reserved word, a member of
`BuildContext`, `Object` or the starter's `SpringBuildContext` (`bean`,
`message`, `springContext`), two beans with one getter name, or
`@BuildContextAccess` on a class that is no bean.

**Widgets with beans.** Every class of the scan that extends
`SpringStatelessWidget<R>` (or a `State` that extends `SpringState<W, R>`)
with a concrete record type `R` gets a binding in one
`SpringWidgetBindings` bean of the module
(`flutterSpringWidgetBindings#<module>`, not an autowire candidate). The
binding fills the record: positional fields are beans by type, named
fields by type and then by the field's name among several candidates,
nullable fields are optional (`findBean`). `SpringApplicationWidget`
checks at startup that the required beans exist. The build fails for a
field that is no class or interface type (`dynamic`, `Object`, functions,
records), or a concrete widget whose `R` is a type parameter; an abstract
base class with a type parameter is skipped.

**`@ChangeNotifierComponent` and `@NotifyListeners`.** The generated proxy
of such a bean notifies the listeners after the marked methods and
setters, so widgets rebuild when the bean's state changes. For a
`@ChangeNotifierComponent` class that is not a `ChangeNotifier` itself,
the proxy also mixes `ChangeNotifier` in. The build fails when a name in `exclude` is not a
public method, setter or field of the class, or when a
`@ChangeNotifierComponent` class that is not a `ChangeNotifier` declares
one of `ChangeNotifier`'s members itself.

**The web dev server.** The `spring_flutter_web` builder turns the
`spring.flutter.web.*` properties (host, port, base-href, HTTPS
certificate, headers, proxy rules) into `web_dev_config.yaml` in the
package directory, so `flutter run -d chrome` serves the app on a fixed
port without flags. The config files are read as the app reads them in a
browser: `application.*`, then `application-web.*` and the profiles that
`spring.profiles.active` names in them; environment variables and
`--dart-define` values do not count. An invalid value fails the build
with the property's name.

```yaml
# lib/resources/application-web.yaml
spring:
  flutter:
    web:
      port: 5050
```

The file is no declared build output, because build_runner would
overwrite a hand-written `web_dev_config.yaml` of that name and delete it
once the builder stopped writing it. The builder manages the file itself
and only touches one that starts with its `# GENERATED FILE - DO NOT
MODIFY BY HAND.` header: it rewrites it while the properties are set
and deletes it when they are gone. With the properties set and a
hand-written file present, the build fails and asks to remove one of
them. build_runner re-runs the builder when a file of `lib/resources/`
changes, not when `web_dev_config.yaml` does: after deleting the file,
run `dart run build_runner clean` or change a config file.
See [the starter](https://pub.dev/packages/spring_boot_starter_flutter#the-web-versions-port)
for the properties.

## Options

```yaml
# build.yaml of your package
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        options:
          aop_proxies: interfaces
```

| Option | Values | Default |
|---|---|---|
| `aop_proxies` | `all`: a proxy class for every bean whose class or one of its interfaces can be implemented (and subclass proxies for the classes that can only be extended); `interfaces`: proxies only through a bean's abstract supertypes, so a bean without one gets no proxy; `none`: no proxies, so AOP cannot advise the beans of the module | `all` |
| `aop_prune` | `true`: with `aop_proxies: all`, the `@SpringBootApplication` output (which knows every module of the application) generates no proxy class for a bean that no pointcut of the application can match. Its signatures stay, so an advisor that matches it anyway fails the startup with the reason. `@ComponentScan` modules are never pruned, since any module may import them. `false`: every bean keeps its proxy class | `true` |

Any other value of either option fails the build with an
`ArgumentError`.

The options only change how much code is generated: a bean without
matching advice is never wrapped at runtime either way. Public fields are
proxied as implicit getters and setters.

Pruning reads the aspects of the nested `@ComponentScan` modules too
(`@Aspect` classes and aspects returned by `@Bean` methods). Nothing is
pruned when no module has advice, when a module declares an advisor bean,
or when an auto-configuration declares aspects or an advisor bean whose
pointcut is not an `AnnotationPointcut`. A bean whose class or members
carry an annotation from outside `spring_core_dart` (or `@Validated`)
keeps its proxy, because those starters' advisors match by annotation.

### Scan options

`@ComponentScan` itself takes Spring's scan options, evaluated at build
time:

- `includeFilters` / `excludeFilters`: `Filter(classes: [Plugin])` for an
  annotation, `Filter(type: FilterType.assignableType, classes: [Handler])`
  for subtypes, `Filter(type: FilterType.regex, pattern: ['.*Repository'])`
  on the class name. Excludes win; abstract classes never match.
- `useDefaultFilters: false`: only the includes make beans.
- `lazyInit: true`: every scanned bean is lazy unless `@Lazy(false)`.

A filter without the argument its type uses, or with an invalid pattern,
fails the build.

## Build-time checks

The generator checks what it can before the app ever runs, and every
error points at the source element:

```dart
@Service()
class Report {
  @Autowired()
  final Clock clock;
  // ✗ Injected field clock must be settable: declare it `late final` or non-final.
}

@Service()
class Shop {
  Shop(@Lazy() this.repo);
  final Repository? repo;
  // ✗ @Lazy on repo: a lazy dependency cannot be nullable; use
  //   ObjectProvider<Repository> for an optional lazy bean.
}
```

Among the checks:

- **AOP.** Every advice and `@Pointcut` expression is parsed with the
  runtime's own parser, so a pointcut accepted here is accepted at
  startup. A syntax error fails the build with the aspect, the advice and
  the character position. A reference to a pointcut of a class outside
  the module is left to the runtime.
- **Validation constraints** on a type they cannot check (`@Size` on an
  `int`, `@NotBlank` on a `List`), and invalid attributes
  (`@Size(min: -1)`, `min > max`, malformed `@DecimalMin` values and
  regular expressions).
- **JSON:** more than one `@JsonValue` in a class, or one on a member it
  cannot work on.
- **Flutter assets:** a literal `@Value('asset:<key>')` whose asset does
  not exist or is not declared under `flutter: assets:` in `pubspec.yaml`.
- **Starters:** a starter whose `requires` range does not allow the
  `spring_boot_dart` version in use.
- **Declarations:** `@Component` on a mixin, enum, extension or
  extension type; `@Bean` on a top-level function; `@ComponentScan`
  anywhere but on a top-level variable, or two `@ComponentScan` roots in
  one directory; an empty, blank or space-padded bean name or alias; two
  unconditional beans with the same name; an ambiguous constructor choice;
  injecting or returning an extension type (erased at runtime).
- **Private declarations.** Generated code cannot name a private
  declaration (`_Foo`, `_default`). A private bean class, `@Bean` return
  type, injected type (also as a type argument), event type or default
  value (a private function, class or constructor) fails the build with a
  message naming the declaration, its library and the fix (make it
  public, move it out of the scan, declare a public supertype, or drop
  the default), instead of a generated file that does not compile.

Independent problems of one build are reported together
(`N problems in this build:`, each with its message, library URI and
location) instead of one per build run.

Missing or ambiguous beans and dependency cycles depend on the whole
application, so they are reported when the context starts, before any of
your objects is created.

The generated code is free of analyzer warnings and of the
`package:lints` recommended lints. `type=lint` is still ignored in it,
because your own lint set may differ.

### An error never deletes the generated file

An error in the sources never removes or changes an existing
`*.spring.dart`. Otherwise `build_runner watch` would delete and
regenerate it on every keystroke, and every file that imports it would
turn red while you type.

- While a scanned library has syntax errors, the builder skips
  generation, writes the existing file again unchanged and logs one
  warning per output until the next successful generation.
- A generator error keeps the file too and is reported as the build
  error: `build_runner build` fails, the file just stays.
- Without an existing output (a cold build), both fail the build.

## Public API

`lib/builder.dart` has the three builder factories that `build.yaml`
names; applications do not import it.

| Factory | Builder | `build.yaml` entry |
|---|---|---|
| `springCoreDartBuilder` | the main builder, with the `aop_proxies` and `aop_prune` options | `spring_core_dart`: `auto_apply: dependents`, `build_to: source`, `.dart` → `.spring.dart` |
| `springTestBuilder` | the test builder, no options | `spring_test`: `auto_apply: dependents`, `build_to: source`, `test/<name>_test.dart` → `test/spring/<name>.test.spring.dart` |
| `springFlutterWebBuilder` | the `web_dev_config.yaml` builder, no options | `spring_flutter_web`: `auto_apply: dependents`, `build_to: source`, `$package$` → no declared output (writes `web_dev_config.yaml` itself) |

## Dependencies

| Package | Why |
|---|---|
| `analyzer` | The element model of the scanned libraries (moves with the Dart SDK) |
| `build`, `glob` | The builder API; scanning directories |
| `source_gen` | `TypeChecker`, `ConstantReader`, build errors |
| `code_builder`, `dart_style` | Emitting and formatting code with prefixed imports |
| `path` | Relative imports for scan roots outside `lib/` |
| `pub_semver` | A starter's `requires` range against the `spring_boot_dart` version |
| `yaml` | Reading `pubspec.yaml` (asset check) and the YAML config files (`--dart-define` keys) |
| `spring_core_dart` | Its pointcut parser: the build parses pointcuts with the parser the application runs. The build script resolves packages with your package config, so this is your version of `spring_core_dart` |

Annotations are matched by name and URL (`package:spring_core_dart`,
`spring_boot_dart`, the starters), not imported, so the generator does not
depend on `spring_boot_dart` or the starters.

Dev dependencies: `build_test`, `test`, `coverage`, `package_config`, and
`spring_boot_dart` (generated code under test imports the runtime).

## Structure

```
lib/
  builder.dart                  build_runner entry points and options
  src/
    spring_builder.dart         finds @ComponentScan / @SpringBootApplication, scans, writes output
    bean_scanner.dart           analyzer elements → models, validation
    bean_model.dart             intermediate models
    bean_type_inference.dart    the type a @Bean method really returns
    module_emitter.dart         models → Dart source
    configuration_scanning.dart full-mode @Configuration classes
    configuration_emitter.dart  their generated subclasses
    lookup_scanning.dart        @Lookup methods
    lookup_emitter.dart         their generated subclasses
    aop_analysis.dart           pointcut checks and proxy pruning
    constraint_checker.dart     validation constraints against their types
    json_annotation_checker.dart  @JsonValue and @JsonProperty checks
    log_scanning.dart           @Log
    flutter_scanning.dart       spring_boot_starter_flutter
    asset_check.dart            @Value('asset:...') against pubspec.yaml
    dart_define_keys.dart       --dart-define keys
    test_builder.dart           @SpringBootTest → test/spring/*.test.spring.dart
    web_dev_config_builder.dart spring.flutter.web.* → web_dev_config.yaml
build.yaml
test/                           generated output and every rejected declaration
```

## Status

Covers every annotation of the runtime. About 96% of the lines are
covered by tests.

## License

Apache License 2.0.
