# Editor extensions

## Zed extension `dart_spring`

Editor support for everything the framework does today. Available now:
navigation from injection points to beans and from `@Value` placeholders to
properties files, SpEL and placeholder highlighting, checks for invalid
SpEL, unknown keys and non-raw placeholder strings, hovers with property
values and candidate beans, navigation to `classpath:` / `file:` resources,
and pointcut highlighting, navigation (types, annotations, beans, named
pointcuts) and checks, snippets, and new Spring Boot projects
(`dart_spring_lsp create my_app`). Still planned from the list below: bean
markers, completion, reverse navigation (from a key or a bean to its usages,
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
  included; from `classpath:...` / `@PropertySource` locations to the
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
hood) plus support for the `spring_boot_starter_flutter` starter: platform profiles,
widget wrappers, hot reload helpers and Flutter snippets.
