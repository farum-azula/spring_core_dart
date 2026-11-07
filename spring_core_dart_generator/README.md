# spring_core_dart_generator

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-core-dart-generator](https://farum-azula.org/components/spring-core-dart-generator)

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
  spring_core_dart: ^0.7.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.7.2
```

Mark a scan root: a top-level variable with `@ComponentScan()`. Every
class in that file's directory and below is scanned.

```dart
// lib/src/beans.dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/spring_gen/src/beans.spring.dart'; // written by the generator

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

Then generate, once or on every save:

```bash
dart run build_runner build
dart run build_runner watch
```

The generator writes `lib/spring_gen/beans.spring.dart` for `lib/beans.dart`. Pass
`appBeans` to the context: `ApplicationContext.run([appBeans])`. A
runnable walk-through is in the
[example](https://pub.dev/packages/spring_core_dart_generator/example).

## What it generates

The package registers nine builders in its `build.yaml`; all but `spring_properties` apply
automatically to every package that depends on it.

**`spring_core_dart`** (the main builder) writes `<file>.spring.dart` into the
`spring_gen/` folder of the source root (`lib/src/a.dart` gives
`lib/spring_gen/src/a.spring.dart`) for two kinds of library:

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
  and the `--dart-define` keys the application may read (below). A
  module declared with `@AutoConfigurationModule(build:
  AutoConfigurationBuild('<property>'))` is written by the property in
  the application's `application.yml` / `application.properties` (no
  profile): always (`true`), never (`false`: no code, no import), or,
  when not set, as its `whenMissing` says (by default under
  `if (!const bool.fromEnvironment('dart.vm.product'))`, so a release
  compiles it away). The proxies written for library beans follow the
  modules they come from. A property the build cannot read (`${FLAG}`
  without a default, a file that does not parse) fails the build naming
  the module; one set only in a profile's file is warned about.

Into that file it writes:

- one `BeanDefinition` per bean: its types, scope, laziness,
  primary / fallback, qualifiers, aliases, order, depends-on, conditions,
  declared dependencies, the `create` and `inject` closures, lifecycle
  callbacks, event listeners and factory bean product types;
- `@PropertySource` declarations, `@Configurable` configurers and
  introspection metadata (properties, methods, annotations), which the
  `ObjectMapper`, validation and SpEL read, for each class as far as the
  build saw it used ([below](#generate-only-what-runs));
- for `spring_boot_starter_data`, one `EntityIntrospection` for each
  `@Table` class and each class a `@Query` method returns (a DTO), held by
  one `EntityIntrospections` bean per module: the properties, and closures
  that read them, call the constructor and set one, and no more. A
  `@Table` class has no `BeanIntrospection` unless it is also
  `@Introspected`. A class the data layer could not create or fill (a
  required constructor parameter that names no field, a `final` field
  nothing sets) fails the build;
- for `spring_boot_starter_data`, a class for each repository (an
  interface extending `DataRepository`): it extends the starter's
  `SimpleRepository`, which has the CRUD methods, and adds one line for
  each method of the interface, so nothing is parsed or described when the
  application starts. A derived query (`findByTitleAndYear`) is read by the
  build into a constant `PartTree` and checked against the entity, the
  parameters and the return type; a wrong name, an unknown property or a
  parameter that does not fit fails the build, with every other problem of
  the interface (`BookRepository.findByTitel: ... did you mean 'title'?`).
  A `@Query` method is checked as well (the method against its annotation,
  the text's parameters and `{Entity.property}` placeholders, and tables and
  columns misspelled against the entities and the migrations of
  `lib/resources/`) and written as a small `QueryMethod`; its `:#{...}`
  SpEL values are compiled to Dart when the build can (`#book.titel` is a
  build error, `#book.title` is `(arguments[0] as Book).title`), else left
  to the interpreter;
- `@Aspect` advice metadata and the AOP proxy classes;
- generated subclasses of full-mode `@Configuration` classes and of beans
  with `@Lookup` methods;
- the files of `lib/resources/`, embedded so that `resources:` locations
  work on every platform without Flutter asset declarations. Text files
  stay text, other files are base64-encoded, and files above 1 MB are
  skipped with a warning. An application whose `main` is outside `lib/`
  (`example/`, `tool/demo/`) also gets the `lib/resources/` of every
  directory from the package root down to its own; the nearer to `main`,
  the higher the precedence.

**`spring_test`** (the test builder) writes
`test/spring_gen/<name>.test.spring.dart` for every `test/<name>_test.dart`
that declares `@SpringBootTest` or `@DataTest` classes. The file has a
`runSpringTests()` function that registers the tests of those classes
with `package:test`; the test's `main` calls it. A `@DataTest` class (of
`spring_boot_starter_data`) starts a slice of the application, the data
beans on an in-memory database, and runs each test in a transaction that is
rolled back: the generated file calls the data starter's
`package:spring_boot_starter_data/testing.dart` for it, so the starters stay
independent. `@Container()` and `@ServiceConnection()` fields start Docker
containers before the class's context and remove them after it. See
[`spring_boot_starter_test`](https://pub.dev/packages/spring_boot_starter_test)
and the testing guide
([data tests](../docs/testing.md#19-data-tests-datatest),
[containers](../docs/testing.md#20-containers-in-tests)).

**`spring_flutter_web`** writes `web_dev_config.yaml`, the file
`flutter run` reads on the web (Flutter 3.38 and later), from the
`spring.flutter.web.dev-server.*` properties of `lib/resources/` (see
[Flutter](#flutter-spring_boot_starter_flutter) below). Without those
properties it does not load the config, and writes and reports nothing,
whatever the config files hold (imports, placeholders an environment
variable sets, a file that does not parse): a pure Dart package builds as
if it were not there.

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

### Generate only what runs

The build knows what reflection would know, so a class is described only
for what the application does with it. Each use asks for some of the
parts below; a class reached by several uses gets the union, and what it
is made of (property types, constructor parameter types, `Page<Dto>`'s
argument, the subtypes of `@JsonSubTypes`) takes the same. The
annotations and the list of properties are always written.

| Part | What | Written when |
|---|---|---|
| getters | `BeanProperty.get` | the class is written out: a controller's return type (also in `Future`, `Stream`, `ResponseEntity`, `Page`), an `@ExceptionHandler`'s answer, a WebSocket reply, a client's argument, the static type of a value given to `ObjectMapper.writeValueAsString`, `valueToTree` or `convertValue`, or to a WebSocket session's `sendJson` and the registry's `broadcast`; `@ConfigurationProperties` |
| constructor and setters | `BeanConstructor`, `instantiate`, `set`, `fromJson` | the class is read in: `@RequestBody` and `@RequestPart`, a controller's return type and an `@ExceptionHandler`'s answer (a test reads the answer back with `mapper.readValue<BookDto>(res.body)`, and `test/` is not scanned), a WebSocket message, a client's answer (Feign, `@WebSocketClient`), the type argument of `ObjectMapper.readValue<T>`, `treeToValue`, `readList`, `readMap` or `convertValue<T>`; `@ConfigurationProperties` |
| the getters of constrained properties | `get` of the properties with a constraint, `@Valid()` or `@Each()` | the class is validated: `@RequestBody @Valid()` |
| methods | `BeanMethod` | a SpEL expression may call them: `@PreAuthorize`, `@PostAuthorize`, `@PreFilter`, `@PostFilter` and `@Cacheable`, `@CachePut`, `@CacheEvict` (keys and conditions) over the arguments or the result they name, a `@Query` with a `:#{...}` the build does not compile; also the methods a JSON annotation marks (`@JsonValue`, `@JsonAnyGetter` with the getters, `@JsonAnySetter` with the setters) |

The calls of the mapper count where the build sees their static types and
the class is in the package of the call (a library that names none of
those methods is not even resolved; `sendJson` and `broadcast` count only
in a library that imports the WebSocket starter); a value of type `Object` or
`dynamic` names no class.

`@Introspected()` keeps everything, and so does a class listed in
`@Introspected(classes: [...])` (and what they are made of): you asked for
it. A `@JsonView` class is only known. A class with
`@JsonInclude(JsonInclusion.nonDefault)` that is written out is also
described for creation, since the mapper compares each value with the one
of a new instance. A method of a custom `@BeanMethodAnnotation()` keeps
everything of its types; `@Scheduled`, `@Secured`, and a WebSocket
`@OnOpen`, `@OnClose` or `@OnError` describe nothing.

The description says what it holds (`BeanIntrospection.parts`). What the
build did not see used is left out, and code that needs it anyway, such as
a value cast to `Object` that is written as JSON, fails with a message that
names the class, the missing part and the fix, never with an empty object:

```text
Bad state: Book is described without its getters, but it is written out as
JSON. The build described only what it saw used, and did not see that: add
@Introspected() to Book.
```

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
The nested `@ComponentScan` modules of the package (a `lib/src/feature/`
with its own scan) count too.

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
`spring.flutter.web.dev-server.*` properties (host, port, base-href, HTTPS
certificate, headers, proxy rules) into `web_dev_config.yaml` in the
package directory, so `flutter run -d chrome` serves the app on a fixed
port without flags. It runs for every package that depends on the
generator, pure Dart servers included, so it never fails a build, and
says nothing, unless the app evidently uses the file: a config file it
can read without loading the config (any `.properties`, `.yml` or `.yaml`
file of `lib/resources/`, in any document, for any profile, or a file an
import names with a file hint, `[.yaml]` or `[encoding=iso-8859-1]` (a
file that is not UTF-8 is read only that way), its placeholders resolved
with their defaults or the files' values) sets a `spring.flutter.web.dev-server.*`
key or
`spring.flutter.security.web.mode`. An import whose name only the running
app knows (`resources:${ENV}.conf[.yaml]`) cannot be followed there, so
keys that only its file sets do not count. Without one, the config is not
loaded: nothing is written, a file generated before is deleted, and
imports, placeholders or a file that does not parse are left to the app's
start (except that while a generated file exists, a config file the app
reads that does not parse fails the build and keeps it). With one, the
config files are read as the app reads them in a browser:
`application.*`, then `application-web.*`, the profiles that
`spring.profiles.active` names in them and the files that
`spring.config.import` names (relative or `resources:` ones, from
`lib/resources/`); environment variables and `--dart-define` values do
not count. A placeholder only they can resolve is unknown at build time,
never a build error: a profile name with one in `spring.profiles.active`,
`.include`, `.default` or `.group.*` is left out, whatever else the name
holds (`dev,${ENV}-eu` is read as `dev`; a key in any form the app
reads, such as `spring.profiles.group[prod]` or `spring.profiles[active]`),
`spring.profiles.validate` or `spring.main.cloud-platform` with one is
read as unset, an import
location with one is not read (the other entries of its `;` group are),
and a document whose `spring.config.activate.*` guard has one is skipped,
each with a warning naming it. Where a key may be is still checked:
`spring.profiles.active` in `application-web.yaml` fails the build
whatever its value, as it fails the app's start. A placeholder in
`spring.flutter.security.web.mode`, as in a `spring.flutter.web.dev-server.*` value,
must resolve at build time. A `file:`, `configtree:` or `package:` import
(or an absolute path), with a wildcard or not, is not read from the build
machine's disk, as a browser has none: it is skipped, `optional:` or not;
when the properties give a file to write, a warning names the first
required one as written (the web version would fail to start with it).
An import the build cannot read (`asset:`, `http:`, `https:`, or a
`resources:` file missing from `lib/resources/`) is skipped silently, even
a required one, as it may exist at run time. An invalid value, or a
config file the app reads that does not parse, fails the build with the
error; the generated file is then left as it is.

```yaml
# lib/resources/application-web.yaml
spring:
  flutter:
    web:
      dev-server:
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

### Typed keys of the configuration

For an app that depends on `spring_boot_starter_flutter` (or the security
starter that brings it), the builder `spring_flutter_keys` reads
`lib/resources/` (every `.yml`, `.yaml` and `.properties` file, whatever the
profile and the theme: the union of the keys, as the values are read at run
time) and writes two files:

```
lib/
  main.dart                 # yours, with @ComponentScan (or @SpringBootApplication)
  spring_gen/
    main.spring.dart        # generated: the beans; it has the `part` lines
    theme.spring.dart       # generated: part of main.spring.dart, context.theme
    messages.spring.dart    # generated: part of main.spring.dart, context.messages
```

Import `spring_gen/main.spring.dart` in your widgets to get `context.theme` and
`context.messages`. The two files are parts of the `.spring.dart` of the
package's parent library (an app's `spring_gen/main.spring.dart`; a library package has
its own, and an app never sees the library's keys): the
`@SpringBootApplication` library if there is one, else the outermost
`@ComponentScan` (nested scans, as in `lib/src/feature/`, are fine). Unrelated
roots in one package stop the build and are named; with none, no key files
are written and a log line says why. The main builder decides the `part`
lines with the same computation as the keys builder (a part cannot be probed
with `canRead`: the keys builder writes in its own phase), so the keys builder
must not be disabled while the main one runs. Nothing is written without
`spring.flutter.theme.*` properties (theme file) or message files (messages
file).

- `context.theme` (`AppTheme`): `colors.<role>` (`Color`), `spacing.<name>`
  (`double`), `typography.<style>` (`TextStyle`; the 15 Material styles and
  `code`), `tokens.<group>...<key>` (any depth, a class per group: `Color` for
  `#RRGGBB` and references to colors, `double` for numbers,
  `Duration` for `250ms`, `List<Color>` / `List<double>` / `List<String>`,
  `ThemeImage` for a map with `source`, `String` otherwise; a token of
  different types in two themes is an error), `styles.<name>` (a typed
  `ThemeStyle` per `styles.*` entry, the class `AppStyle<Name>` with its
  values `AppStyle<Name>Values`, for `ThemeStates`), `motion.<name>`
  (`Duration`) and `motion.curves.<name>` (`Curve`), `animations.<name>`
  (`AnimationSpec`, for `ThemeAnimation`), `background` (nullable:
  `ThemeBackgroundData?`, `null` in a theme without one), and
  `AppThemes.<name>` (theme names for `ThemeSelection.select`).
- `context.messages` (`AppMessages`): from `<basename>.properties` and
  `<basename>_<locale>.properties` (`spring.messages.basename`, `messages` by
  default): a getter for a message without arguments, a method with `Object?`
  parameters for `{0}`...`{N-1}`, one class per key prefix. A key missing in
  a locale is a warning; a different argument count between locales, a key
  that is a message and a prefix, or a malformed placeholder is an error.
- Names: `-`/`_` start a new word (`surface-container-low` ->
  `surfaceContainerLow`), the first letter becomes lower case, a leading digit
  gets a `$` before it (`2xl` -> `$2xl`), a Dart keyword or `hashCode`,
  `toString`, ... a `$` after it. A name with other characters, or two keys
  with one Dart name, is an error and nothing is written.
- References in values (`$colors.primary`, `{ color: $colors.primary, alpha: 12% }`) are
  followed when the type of a token is decided, so a reference to a color is
  a `Color`. Values are classified as the starter does (its fixture
  `test/fixtures/theme_value_kinds.yaml` is checked by a generator test):
  numbers (`+5`, `.5`, `1e3`), durations (`250ms`, `250 ms`, `s`/`m`/`h`),
  colors (hex, Material names such as `grey.shade200` or `black54`, chained
  `alpha` / `mix` in any case); `$colors.<any Material role>` and
  `$shape.<scale name>` resolve without being declared. A reference whose
  first segment is a section of a theme (`colors`, `styles`, `loaders`,
  `syntax`, `frame-meter`, ...) is a path from the theme's root
  (`$frame-meter.good`), anything else a token. The values of `syntax.*`
  (the languages of code blocks, regular expressions) and of `glyphs` keys
  are taken as written, never as references. An image token is a
  token at least `tokens.<group>.<key>` deep with a `source` and only image
  keys (`refresh`, `source-sha256`, `headers`, `timeout`, `fallback`);
  with any other key it is a group.

```dart
// lib/spring_gen/theme.spring.dart (generated; part of main.spring.dart)
extension SpringThemeKeys on BuildContext {
  AppTheme get theme => AppTheme._(ThemeKeyReader(SpringTheme.of(this)));
}
final class AppThemeSpacing {
  double get m => _values.spacing('m');
}
// lib/spring_gen/messages.spring.dart (generated)
extension SpringMessageKeys on BuildContext {
  AppMessages get messages => AppMessages._(this);
}
final class AppMessagesBasket {
  String total(Object? arg0) =>
      _context.message('basket.total', args: [arg0]);
}
```

The files hold keys, not values.

### Loaders and the splash

For `loaders.<name>` and `splash` the keys add `context.theme.loaders.<name>`
(a `ThemeLoaderSpec`) and `context.theme.splash` (a `ThemeSplashData`). A
loader of a kind of the app's own, a class marked
`@ThemeLoaderKind('doors')` that extends `ThemeLoaderPainter<P>` or
`ThemeLoaderWidget<P>`, gets its props class `P` (`DoorsLoaderProps`),
written from the keys the themes give the loaders of that kind, typed like
tokens (`Color`, `double`, `Duration`, `bool`, `Curve` for a `curve`, an
`AnimationSpec` for a `{duration, curve, repeat}` map, `String`, lists; nested
maps are nested classes). The module registers the class into
`ThemeLoaderKinds` before it is built, so `kind: doors` finds it. A `kind`
that is neither built in nor declared in the package or a dependency (its
`spring_metadata.json` lists `loaderKinds`), a loader without a kind, a
`splash.loader` that names no loader, and keys that differ between themes or
between loaders of one kind stop the build, with a "did you mean".

```dart
// lib/spring_gen/theme.spring.dart (generated)
final class DoorsLoaderProps {
  const DoorsLoaderProps._(this.values);
  final LoaderValues values;
  static const List<String>? keys = ['door', 'seam'];
  DoorsLoaderPropsDoor get door => DoorsLoaderPropsDoor._(values.at('door'));
}
final class DoorsLoaderPropsDoor {
  Color get color => _v.color('color');
}
// lib/spring_gen/main.spring.dart (generated), in the module's getter
ThemeLoaderKinds.register<DoorsLoaderProps>(r'doors',
    painter: DoorsLoader(), props: DoorsLoaderProps._, keys: DoorsLoaderProps.keys);
```

**`spring_flutter_seo`** writes the pages of `spring.flutter.web.seo.*`
for a Flutter web app: a page per route and Markdown file (`<path>/index.html`,
or `<path>.html` with `page-files: html`, with the page's head and its text,
under the page loader), `<path>.md` (`web/index.md` for the root page),
`sitemap.xml`, `robots.txt`, `llms.txt` and `llms-full.txt`, into `web/`.
The head carries what link previews read (`og:site_name` from `site-name`,
`twitter:card`, `twitter:title`, `twitter:description`, `twitter:image`);
the canonical address matches what the host serves (`/` at the end with
`directory`, the default). `exclude` leaves files of every Markdown folder
out (`**/contents*.md`). See [docs/configuration.md, *The site's
pages*](../docs/configuration.md#the-sites-pages-springflutterwebseo).

**`spring_flutter_deep_links`** writes the deep links of
`spring.flutter.navigation.deep-links.*` (the scheme, the domains) into the
platforms' files between `spring:deep-links` markers, and the files the
domains serve (`apple-app-site-association`, `assetlinks.json`). It reads
the profiles as the app does: the platform's (`application-ios.yml`) after
`mobile` / `desktop`, so the platform's file wins.

**`spring_flutter_page_loader`** writes the page loader of the active
theme's `splash` into `web/index.html`: a block between
`<!-- spring:loader:start -->` and `<!-- spring:loader:end -->` (the markers
are inserted after `<body>` when missing; nothing else of the file is
touched; the block is rewritten on every build and removed, markers
included, when the theme has no splash; a page that does not exist is not
created). It is HTML, CSS and one small script, no external file: the
background, logo and title of the splash, the built-in loader kinds in CSS,
or for a kind of the app's own its `web:` HTML file (below the app's
directory or its `lib/resources/`, else `lib/resources/` of a package it
uses; or an address the build downloads, `https://...` or
`github:owner/repo/path@ref`, optionally pinned by `web-sha256`, kept in
`.dart_tool/spring/loaders/` for offline builds; `http://` only with
`spring.remote.allow-insecure`) with the loader's keys
as CSS variables named after the key path (`door.edge.color` is
`--door-edge-color`; colors are `#rrggbb` / `rgba()`, numbers are unitless,
durations `500ms`, curves CSS timing functions, texts quoted CSS strings; the
text of a theme never leaves its string or the page). Colors, references and
Material roles are resolved at build time from the theme (the seed makes the
roles). With `system` the dark theme's values go into a
`prefers-color-scheme: dark` rule. The script follows Flutter's loader
(`--spring-progress` 0 to 1 and `data-stage` on the loader), records the
start's first stages (`page`, `engine`) in `window.springLoader.stages`,
`data-splash-stage` and a `spring-splash-stage` event, from which the
Flutter splash goes on, honours `prefers-reduced-motion`, and removes the
loader when the Flutter side calls `window.springLoaderHandOff(progress)`, or
after a timeout. Its text never changes, and it is written with nothing else
between its tags, so spa mode's Content-Security-Policy allows it by hash;
with your own policy add that hash (`WebPageLoader.scriptHash`) to
`script-src`.

The same builder keeps the rest of `web/index.html` and `web/manifest.json`
in step with the configuration (`WebPageHead`): the title and description
of `spring.flutter.app.*` and the active theme's colors; Flutter's
`<meta name="viewport">` when the page has none;
`spring.flutter.web.page.translate: false` (`translate="no"` and
`<meta name="google" content="notranslate">`);
`spring.flutter.web.page.max-pixel-ratio` (a script capping the pixel ratio
Flutter draws at); `spring.flutter.web.page.swipe-to-close: false` (a block
keeping the page open on a swipe down in apps' own browsers). Spa mode's policy allows these scripts by hash too
(`WebPageHead.hashOf`). The profile files are read after the files without
one (`application-web.yml` wins over `application.yml`), as in the browser.

## Metadata for editors

For every package with Spring code the generator writes
`lib/spring_gen/spring_metadata.json`: the configuration properties
(`@ConfigurationProperties`, with `///` descriptions and literal defaults),
the beans (types, scope, conditions, injection points, members for SpEL),
the profiles and value hints. Everything is derived from the code, nothing
is written by hand: the `///` of a field is its description, a literal
initializer or constructor default its `default`, an enum type lists its
constants (each with its own `///`) as values, `@Range(min, max)` gives
`range`, `@WarnValues([...], 'why')` gives `warn`, and
`@PropertyValues([...])` (or `@PropertyValues.provider('profiles')`) the
values of a `String` field. Keys that are only read (`@Value('${a.b}')`,
`@ConditionalOnProperty`) are listed by name, without a description.
Commit it with the other generated files; it is published
with the package, so a language server reads the metadata of an app and of
all its dependencies. The format is in `roadmap/spring_metadata.md`.

Any editor can get completion and checks for `application.yml` from a JSON
Schema made from that metadata:

```sh
dart run tool/spring_schema.dart path/to/app     # in this repository
```

writes `path/to/app/spring-application.schema.json`. Point a YAML file at
it with a first line (the path is relative to the file; the YAML language
server also accepts a URL):

```yaml
# yaml-language-server: $schema=../../spring-application.schema.json
spring:
  profiles:
    active: dev
```

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
| `aop_prune` | `true`: with `aop_proxies: all`, the `@SpringBootApplication` output (which knows every module of the application), and the `@ComponentScan` modules of an application package (`publish_to: none`: nothing outside imports them), generate no proxy class for a bean that no advice of the application can match, wrapper or subclass proxy alike (`AopProxyFactory.pruned()`; the runtime's `AopProxyFactory.prunedReason` says why), and in the proxy of a bean that keeps one only the members some advice may match run through it: a wrapper forwards the others to the bean, a subclass inherits them. Advice registered at run time without the build seeing it is not applied to what was left out. The `@ComponentScan` modules of a library package are never pruned, since any module may import them; the `lib/` modules of a starter (a package with `lib/spring_auto_configuration.dart`) leave to the application the proxy classes only its aspects can match (`AopProxyFactory.deferred`), and the `@SpringBootApplication` output writes those its pointcuts may match (`BeanModule.aopProxies`). `false`: every bean keeps its proxy class, with every member, and the application writes every proxy left to it | `true` |
| `aop_defer` | `true`: the `lib/` modules of a library package without `lib/spring_auto_configuration.dart` leave to the application the proxy classes only its aspects can match, as a starter's do; for a library whose modules a starter's auto-configuration imports (`spring_boot_actuator`), where the `@SpringBootApplication` output finds them | `false` |
| `dart_defines_exclude` | A list of property name prefixes (`[spring.flutter.theme]`): the properties under them, in both forms (`spring.flutter.theme.mode`, `SPRING_FLUTTER_THEME_MODE`), are not written into `springApplication.dartDefines`, so `--dart-define` does not set them; config files, the environment and the arguments still do | `[]` |

Any other value of either option fails the build with an
`ArgumentError`.

The options only change how much code is generated: a bean without
matching advice is never wrapped at runtime either way. Public fields are
proxied as implicit getters and setters.

Pruning reads the advice of the application's other modules too
(`@Aspect` classes, aspects returned by `@Bean` methods, and advisor beans
whose `@Bean` method builds `DefaultPointcutAdvisor(ExpressionPointcut(
'<a constant expression>'), ...)`, `AnnotationMatchingPointcut<A>()` or a
pointcut declaring its annotations), and the advisors of the
auto-configurations: a starter's annotation pointcut declares the
annotations it matches in a `static const annotationTypes` list
(`@Transactional`, `@Cacheable`, method security, `@Validated`), and only
the beans carrying one keep their proxy. Nothing is pruned when a module
declares an advisor bean whose pointcut the build cannot read (an
expression from a variable, a hand-written pointcut), or when an
auto-configuration declares aspects or an advisor the build cannot read.
Annotations of the SDK (`@override`) and of `package:meta` never keep a
proxy.

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
turn red while you type. The existing file is read from the directory of
its own package, also when `build_runner build --workspace` builds every
package of a pub workspace from one directory.

- While a scanned library has syntax errors, the builder skips
  generation, writes the existing file again unchanged and logs one
  warning per output until the next successful generation.
- A generator error keeps the file too and is reported as the build
  error: `build_runner build` fails, the file just stays.
- Without an existing output (a cold build), both fail the build.

## Public API

`lib/builder.dart` has the nine builder factories that `build.yaml`
names; applications do not import it.

| Factory | Builder | `build.yaml` entry |
|---|---|---|
| `springCoreDartBuilder` | the main builder, with the `aop_proxies`, `aop_prune`, `aop_defer` and `dart_defines_exclude` options | `spring_core_dart`: `auto_apply: dependents`, `build_to: source`, `lib/{{}}.dart` → `lib/spring_gen/{{}}.spring.dart` (the same for `bin/`, `test/`, `example/`) |
| `springPropertiesBuilder` | the main builder for `lib/` only, in a phase before it, with its options | `spring_properties`: `auto_apply: none` (a hand-written starter turns it on in its `build.yaml` to generate the binding of its typed properties, which its example imports), `build_to: source`, `lib/{{}}.dart` → `lib/spring_gen/{{}}.spring.dart` |
| `springTestBuilder` | the test builder, no options | `spring_test`: `auto_apply: dependents`, `build_to: source`, `test/<name>_test.dart` → `test/spring_gen/<name>.test.spring.dart` |
| `springFlutterPageLoaderBuilder` | the page loader builder, no options | `spring_flutter_page_loader`: `auto_apply: dependents`, `build_to: source`, `$package$` → no declared output (writes `web/index.html` itself) |
| `springFlutterWebBuilder` | the `web_dev_config.yaml` builder, no options | `spring_flutter_web`: `auto_apply: dependents`, `build_to: source`, `$package$` → no declared output (writes `web_dev_config.yaml` itself) |
| `springFlutterSeoBuilder` | the site's pages, no options | `spring_flutter_seo`: `auto_apply: dependents`, `build_to: source`, `$package$` → no declared output (writes the pages into `web/` itself, after `spring_metadata` and `spring_flutter_page_loader`) |
| `springFlutterDeepLinksBuilder` | the deep links, no options | `spring_flutter_deep_links`: `auto_apply: dependents`, `build_to: source`, `$package$` → no declared output (writes its blocks into `Info.plist`, `Runner.entitlements`, `AndroidManifest.xml` and the domain files itself) |
| `springFlutterKeysBuilder` | the typed keys of the theme and messages, no options | `spring_flutter_keys`: `auto_apply: dependents`, `build_to: source`, `$package$` → `lib/spring_gen/theme.spring.dart`, `lib/spring_gen/messages.spring.dart` |
| `springMetadataBuilder` | the metadata for editors, no options | `spring_metadata`: `auto_apply: dependents`, `build_to: source`, `$package$` → `lib/spring_gen/spring_metadata.json` (before `spring_flutter_seo`) |

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
    test_builder.dart           @SpringBootTest, @DataTest → test/spring_gen/*.test.spring.dart
    web_dev_config_builder.dart spring.flutter.web.dev-server.* → web_dev_config.yaml
    web_page_loader.dart        the page loader block of web/index.html; web_page_loader_builder.dart writes it
build.yaml
test/                           generated output and every rejected declaration
```

## Status

Covers every annotation of the runtime. About 96% of the lines are
covered by tests.

## License

Apache License 2.0.
