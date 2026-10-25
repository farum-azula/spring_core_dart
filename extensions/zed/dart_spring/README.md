# dart_spring for Zed

Editor support for [`spring_core_dart`](https://pub.dev/packages/spring_core_dart),
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) and the
`spring_boot_starter_*` packages, in the spirit of IntelliJ IDEA's Spring
support. The extension version always equals the framework version it
supports.

## Features

**Navigation** (Go to Definition, `F12` / `Cmd`-click). Results are added
to those of the Dart language server:

| Click on | Goes to |
|---|---|
| the type of an injection point: constructor parameter, field, `@Autowired` setter or method, `@Bean` method parameter | every bean of that type (`@Primary` first); `List<T>`, `Set<T>`, `ObjectProvider<T>` → beans of `T` |
| `this.payments` in a bean constructor | the beans of the field's type |
| a parameter or field with `@Qualifier('cash')`, or the `'cash'` string itself | the bean named / qualified `cash` |
| `@DependsOn`, `@ConditionalOnBean`, `@ConditionalOnMissingBean.named` strings | those beans |
| `getBean<Clock>()`, `getBeanProvider<T>()`, `context.bean<T>()`, ... | the beans of that type |
| `context.basket` (a getter generated for a `@BuildContextAccess` bean) | that bean |
| a type in the bean record of a widget: `SpringStatelessWidget<(Basket, {Clock utc})>`, `SpringStatefulWidget<...>`, `SpringState<W, (...)>` | the beans of that type (a named field picks by its name) |
| `${shop.name}` in `@Value` (and `getProperty('shop.name')`, `@ConditionalOnProperty`) | the key in every `application*.properties` that defines it |
| `@ConfigurationProperties('shop')` | the `shop.*` keys |
| a bean name in SpEL: `#{appConfig.name}`, `#{@clock.now()}` | that bean |
| `classpath:legacy.properties` (in `@PropertySource`, `@Value`, `getResource`), `file:config/app.properties`, `asset:assets/logo.png` | the file: `lib/resources/` of the package (`test/resources/` first in tests), `file:` and `asset:` relative to the package |
| in a pointcut (`@Pointcut`, `@Before`, `@Around`, ...): a type in `within(...)` / `execution(...)`, `@annotation(Timed)` | the class (wildcards like `*Service` give every match) |
| `pricing()`, `AuditAspect.pricing()` in a pointcut | the `@Pointcut` method |
| `#isbn` in a cache key or condition: `@Cacheable('books', key: '#isbn')` | the method parameter |
| `bean(order*)`, the method of `execution(* OrderService.place*(..))` | the matching beans, methods |

Navigation puts the cursor at the target without selecting it.

**Hover** shows the value of a property in every profile file, the
candidate beans of an injection point, the file a `classpath:` location
resolves to and the expression of a named pointcut.

**Checks**, while typing:

- invalid SpEL (`#{1 +}`) — an error at the position the parser reports;
- invalid pointcuts — checked by the runtime's own parser, with the
  project's `@Pointcut` methods: an unknown `ordrs()` is underlined;
- cache keys and conditions (`key:`, `condition:`, `unless:` of
  `@Cacheable`, `@CachePut`, `@CacheEvict`, also inside `@Caching`):
  SpEL syntax, and `#isbm` that is not a parameter (nor `#root`,
  `#result`, `#p0`) is a warning listing the parameters;
- `${key}` without a default that no properties file defines — a warning;
- `@Value('${key}')` in a normal (non-raw) string — an error: in Dart that
  is string interpolation; write `r'${key}'`;
- `@Value('asset:...')` (spring_boot_starter_flutter): a missing file, or
  one not declared under `flutter: assets:` in `pubspec.yaml` — a warning
  with the entry to add, as the generator's build error says.

**SpEL, placeholder and pointcut highlighting** inside annotation
strings: keywords, operators, numbers, strings, `#variables`, `@beans`,
methods, properties, `T(Types)` and placeholder keys (also in `@Scheduled`
cron and interval strings, and the plain-SpEL cache keys); in pointcuts the
designators (`execution`, `within`, `@annotation`, ...), `&&`/`||`/`!`,
types, annotations, bean patterns, method names and named pointcuts
(needs the `semantic_tokens` setting below).

**Snippets**: type the prefix in a Dart file and press Tab.

| Prefix | Inserts |
|---|---|
| `spboot` | `main` with `@SpringBootApplication` |
| `spscan` | a `@ComponentScan` module (without Boot) |
| `spservice`, `spcomponent`, `sprepository` | a bean class |
| `spiface` | an interface and its `@Service` implementation |
| `spconfig`, `spbean` | a `@Configuration` class, a `@Bean` method |
| `spvalue`, `spvalueparam` | `@Value(r'${key:default}')` field or parameter |
| `spautowired`, `spsetter` | field or setter injection |
| `spqualifier`, `spprimary`, `spprofile` | choosing between beans |
| `spself` | `@Lazy` self-injection (advice applies to self-calls) |
| `sppost`, `sppre` | `@PostConstruct`, `@PreDestroy` |
| `splistener`, `sppublish` | `@EventListener`, publishing an event |
| `spaspect` | an annotation and an `@Around` aspect for it |
| `spprops`, `spcondprop`, `sprunner` | `@ConfigurationProperties`, `@ConditionalOnProperty`, `CommandLineRunner` |
| `splog`, `splogger` | `@Log` (a generated `log` getter), a `SpringLog` constant |
| `sptest` | a test file with `springBootTest` and a `BeanOverride` |

Flutter (`spring_boot_starter_flutter`):

| Prefix | Inserts |
|---|---|
| `spflutter` | `main` with `@SpringBootApplication` under `SpringApplicationWidget` |
| `spstateless`, `spstateful` | a `SpringStatelessWidget<(...)>`, a `SpringStatefulWidget` with its `SpringState`, reading `beans` |
| `spnotifier` | a `@ChangeNotifierComponent` with `@BuildContextAccess` (state in a bean, `context.<name>`) |
| `spaccess`, `spnotify` | `@BuildContextAccess(name: ...)`, a `ChangeNotifier` bean with `@NotifyListeners` |
| `spasset` | a `@Value('asset:...')` parameter |
| `splifecycle` | an `@EventListener` for `AppLifecycleStateEvent` |
| `spwidgettest` | a widget test with `springBootTest` and `SpringScope` |

Themes and the app widget, in `application.yml` and in `.properties` files
(the same prefixes in both; the `.properties` ones need a Properties
language, e.g. from the Java extension):

| Prefix | Inserts |
|---|---|
| `spapp` | `spring.flutter.app`: type, title, debug banner |
| `sptheme` | `spring.flutter.theme`: active theme, seed color, fonts, shapes, components, the dark theme |
| `spthemeall` | (YAML) every theme property, commented out, with its values |
| `spthemenew` | a custom theme (`themes.<name>`, `extends`), in its own file in YAML |
| `spcolors`, `sptypography`, `spshape` | color roles, fonts per text role, the shape scale |
| `spcomponents`, `sptokens` | Material components from the tokens, the app's own tokens |
| `spfonts` | `spring.flutter.fonts`: auto-load, exclude |

## New project

The language server also creates Spring Boot applications, like Spring
Initializr. Run it in a terminal (Zed's too: `` ctrl-` ``):

```sh
# macOS
"$HOME/Library/Application Support/Zed/extensions/work/dart-spring/bin/dart_spring_lsp" create my_app

# Linux
~/.local/share/zed/extensions/work/dart-spring/bin/dart_spring_lsp create my_app

# Windows (PowerShell)
& "$env:LOCALAPPDATA\Zed\extensions\work\dart-spring\bin\dart_spring_lsp.exe" create my_app

# a server on the PATH (dart run tool/install_language_server.dart)
dart_spring_lsp create my_app
```

The extension keeps the server it downloaded at that path; it is there
once a Dart file has been opened with the extension installed.

| Command | Does |
|---|---|
| `create my_app` | a new folder `my_app` with the project |
| `create .` | the project in the current, empty folder |
| `--name=shop` | the package name (default: from the folder name) |
| `--no-pub` | skip `dart pub get` and `build_runner build` |
| `--force` | write into a folder that is not empty |
| `--help` | the options |

What you get:

```text
my_app/
  bin/main.dart                               @SpringBootApplication + runApplication
  bin/main.spring.dart                         generated
  lib/src/greeting/app_properties.dart        @ConfigurationProperties('app')
  lib/src/greeting/greeting_service.dart      @Service
  lib/src/greeting/greeting_runner.dart       ApplicationRunner
  lib/resources/application.properties        configuration (the classpath)
  lib/resources/application-dev.properties    --spring.profiles.active=dev
  test/main_test.dart                         springBootTest
  test/resources/application-test.properties  test-only settings
  pubspec.yaml                                spring_boot_dart, logging and test starters, the generator
```

Then:

```sh
cd my_app
dart run bin/main.dart     # my_app says: Hello, world!
dart test
```

Zed extensions cannot add commands to the command palette yet, so there
is no palette entry for this.

## Setup

1. **Install the extension** in Zed: command palette →
   `zed: install dev extension` → choose `extensions/zed/dart_spring`
   (Zed builds the Rust part itself; it needs Rust from rustup).
2. **Turn on semantic highlighting** for Dart (for the SpEL colours) in
   Zed's `settings.json`:
   ```json
   {
     "languages": {
       "Dart": { "semantic_tokens": "combined" }
     }
   }
   ```

The language server is downloaded automatically the first time a Dart
file is opened: the extension takes the native binary of its own version
from the GitHub release `v<version>` (macOS Apple Silicon, Linux x64/arm64,
Windows x64) and keeps it in its own folder; Zed shows the download in the
status bar. Navigation, hover and checks work without step 2.

The server is looked up in this order, so a local build wins during
development:

1. `lsp.dart-spring.binary.path` in Zed settings;
2. `dart_spring_lsp` on the PATH — build it from this repository with
   `dart run tool/install_language_server.dart` (into `~/.pub-cache/bin`;
   also the way to go on platforms without a prebuilt binary, such as Intel
   Macs);
3. the downloaded binary.

```json
{
  "lsp": {
    "dart-spring": {
      "binary": { "path": "/path/to/dart_spring_lsp" }
    }
  }
}
```

Problems show up in Zed's log (command palette → `zed: open log`) and in
the language server log (`dev: open language server logs`).

## How it works

The language server (`extensions/language_server`) parses the project's
Dart files (syntax only, so it works before `pub get` and stays fast),
finds beans — classes with `@Component`, `@Service`, `@Repository`,
`@Controller`, `@Configuration`, `@ConfigurationProperties` or a custom
stereotype extending `Component`, and `@Bean` methods — and reads every
`*.properties` file. SpEL is tokenized and parsed by `spring_core_dart`
itself, so the editor reports exactly what the runtime would reject.
Beans declared by hand (`BeanDefinition(...)`) and beans of dependencies
(starters) are not indexed yet.
