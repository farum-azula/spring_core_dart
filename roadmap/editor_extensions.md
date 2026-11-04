# Editor extensions

## Zed extension `dart_spring`

Editor support for everything the framework does today. Available now:
navigation from injection points to beans and from `@Value` placeholders to
properties files, SpEL and placeholder highlighting, checks for invalid
SpEL, unknown keys and non-raw placeholder strings, hovers with property
values and candidate beans, navigation to `resources:` / `file:` resources,
and pointcut highlighting, navigation (types, annotations, beans, named
pointcuts) and checks, spring_boot_starter_flutter support (`context.<bean>`
getters, `context.bean<T>()` and the bean records of Spring widgets go to
the beans, `asset:` locations to the file, checked against `flutter:
assets:`), snippets (Flutter ones included, and theme snippets for `application.yml` and `.properties`), and new Spring Boot projects
(`dart_spring_lsp create my_app`). Done in 0.6.3, from the Spring metadata of
the package and its dependencies (`roadmap/spring_metadata.md`): completion,
hovers and checks of config keys and values (nested YAML, enums, ranges,
profiles, warnings), the theme (`spring.flutter.theme.*`, the color object,
`$` references and their navigation into a dependency's theme), `${key}`
per profile, SpEL `#{@bean.member}` (completion, hovers, unknown bean or
member), the beans of dependencies at injection points (none: error,
several without `@Primary` / `@Qualifier`: warning) and unknown `@Profile`
names; a package without metadata shows one note to run build_runner. Still
planned from the list below: bean
markers, reverse navigation (from a key or a bean to its usages,
from a pointcut to the methods it advises), event navigation, beans of
dependencies. Its version always equals the framework version (part of the
release train, set by `tool/version.dart` and checked in CI), so extension
0.4.0 understands spring_core_dart 0.4.0.

- SpEL highlighting and completion inside `@Value`, `@Query`,
  `@ConditionalOnExpression`, pointcut and `@EventListener(condition:)`
  strings; errors in expressions shown while typing.
- Bean markers next to components, `@Bean` methods and injection points
  (gutter icons where Zed allows it, otherwise inlay hints), with the
  bean name, scope, profile and conditions.
- Navigation: from an injection point to the bean(s) it receives (and
  back: where a bean is injected); from `@Value(r'${shop.name}')` to the
  key in `application*.properties` (every profile file that defines it)
  and from a key to its usages, `@ConfigurationProperties` fields
  included; from `resources:...` / `@PropertySource` locations to the
  file in `lib/resources/`; from `@annotation(Timed)` and pointcuts to the
  advised methods; from an event to its listeners.
- Navigation and completion in every string that names a bean or a
  key: `@Qualifier`, `@DependsOn`, `@Component('name')`,
  `@ConditionalOnBean` / `@ConditionalOnMissingBean.named`,
  `@ConditionalOnProperty`, `@ConfigurationProperties('prefix')`,
  `@Profile`, `@Value`, `@Query`.
- Completion and diagnostics for property keys (unknown key, wrong type,
  deprecated), profile names, bean names in `@Qualifier`, and missing or
  ambiguous beans before running the app.
- The generator's build errors as diagnostics while typing, at the exact
  range, with a message that says what is wrong and what to do — today
  they only show up in the build_runner output, where a duplicate bean
  name reads like an unexplained failure. First: two declarations of one
  bean name without conditions (`@Bean(name: 'string_bean')` twice, a
  `@Component('x')` and a `@Bean` method named `x`) underlined on both,
  "Bean name 'string_bean' is already declared by AppConfig.newBean
  (lib/config.dart:5); use another name or a condition (@Profile,
  @ConditionalOn...) on one of them"; then every other generator check
  (private types, classes a full-mode `@Configuration` cannot extend,
  `final` classes that need a proxy, unknown beans in `@Qualifier` /
  `@DependsOn`, wrong `@ComponentScan` filters, unbound advice parameters).
  The language server runs the generator's scanner on the open files, so
  the messages are the same as the build's.
- Placeholders and raw strings: in Dart `"${shop.name}"` is string
  interpolation (a compile error), so placeholders need `r'${shop.name}'`
  or `'\${shop.name}'`. Typing `${` in `@Value` / `@Query` adds the `r`,
  and a quick fix turns `@Value("${shop.name}")` into a raw string;
  navigation works for both spellings.
- Built as a Dart language server on top of the generator's analysis, so
  the same server can later back VS Code and IntelliJ plugins.

The generator keeps the generated code untouched while the sources have
errors; the editor-side watch is tracked in zed_editor_extensions.

## Zed extension for Flutter (`spring_boot_starter_flutter`)

Everything `dart_spring` does (it uses the same language server under the
hood) plus support for the `spring_boot_starter_flutter` starter. The
starter's navigation, `asset:` checks and snippets already live in
`dart_spring` (Zed runs both extensions on Dart files); still planned:
platform profiles in run configurations and hot reload helpers.

## Theme properties in the language server

`spring_boot_starter_flutter/tool/theme_metadata.json` lists every theme
component property the starter reads: its key, value type, choices, whether
it takes a value per state, the Flutter field it sets, a plain description
and the default. It is built from the reader and Flutter's own docs
(`tool/theme_metadata.dart`) and is the source of the pages under
`docs/flutter/theme/components`. Done (0.6.3): the generator puts it in the `theme` section of
`spring_boot_starter_flutter`'s `lib/spring_gen/spring_metadata.json`, and
the language server loads it from there for completion, hover and checks of
`spring.flutter.theme.components.*` in `application.yml` and `.properties`.
Until that file has the section, the components are accepted as written and
the server keeps a built-in table for the top-level theme keys (brightness,
colors, shape, ...), which the metadata overrides when it lists the same key.

## VS Code and JetBrains (the owner, November 2026)

**Planned, after 0.6.3** (first VS Code, then JetBrains; it may run next
to the navigation starter, they do not touch each other). Everything the
editor does lives in the `dart_spring` language server (config and theme
checks, `$` references, `${key}`, SpEL, injection points, `@Query` SQL and
derived queries, semantic tokens), so both are thin clients like the Zed
extension: start the server, add the snippets.

- **VS Code** (`extensions/vscode`, TypeScript, `vscode-languageclient`):
  the server from `lsp.dart-spring` settings, else `dart_spring_lsp` on
  the PATH, else the binary of the extension's version downloaded from the
  GitHub release (the same order as Zed); the snippets of
  `extensions/zed/dart_spring/snippets` converted; `.properties` support;
  colours for the server's token types (`closureParameter`, SQL
  `comment`). Published to the VS Code Marketplace and Open VSX (Cursor
  reads it) — the publisher accounts are the owner's. About a day.
- **JetBrains** (`extensions/jetbrains`, Kotlin, Gradle): through Red Hat's
  LSP4IJ, so it works in every IntelliJ IDE including the free ones and
  Android Studio (where many Flutter developers are), not only where the
  platform's own LSP API exists; settings page for the server path;
  plugin verifier against the supported IDE versions. Published to the
  JetBrains Marketplace (the owner's account). Two to three days.
- Both get their version from `tool/version.dart` like the Zed extension,
  are built and tested in CI, and their packages are attached to the
  GitHub release next to the language server binaries.
