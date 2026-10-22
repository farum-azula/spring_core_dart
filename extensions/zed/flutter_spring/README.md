# flutter_spring for Zed

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
| `getBean<Clock>()`, `getBeanProvider<T>()`, ... | the beans of that type |
| `${shop.name}` in `@Value` (and `getProperty('shop.name')`, `@ConditionalOnProperty`) | the key in every `application*.properties` that defines it |
| `@ConfigurationProperties('shop')` | the `shop.*` keys |
| a bean name in SpEL: `#{appConfig.name}`, `#{@clock.now()}` | that bean |

**Hover** shows the value of a property in every profile file, and the
candidate beans of an injection point.

**Checks**, while typing:

- invalid SpEL (`#{1 +}`) — an error at the position the parser reports;
- `${key}` without a default that no properties file defines — a warning;
- `@Value('${key}')` in a normal (non-raw) string — an error: in Dart that
  is string interpolation; write `r'${key}'`.

**SpEL and placeholder highlighting** inside annotation strings: keywords,
operators, numbers, strings, `#variables`, `@beans`, methods, properties,
`T(Types)` and placeholder keys get their own colours (needs the
`semantic_tokens` setting below).

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
| `splog` | a `SpringLog` logger |
| `spreload` | rebuilding the beans after a Flutter hot reload |
| `sptest` | a test file with `springBootTest` and a `BeanOverride` |

## Setup

1. **Install the extension** in Zed: command palette →
   `zed: install dev extension` → choose `extensions/zed/flutter_spring`
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

1. `lsp.flutter-spring.binary.path` in Zed settings;
2. `flutter_spring_lsp` on the PATH — build it from this repository with
   `dart run tool/install_language_server.dart` (into `~/.pub-cache/bin`;
   also the way to go on platforms without a prebuilt binary, such as Intel
   Macs);
3. the downloaded binary.

```json
{
  "lsp": {
    "flutter-spring": {
      "binary": { "path": "/path/to/flutter_spring_lsp" }
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
