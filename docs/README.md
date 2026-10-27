# spring_core_dart documentation

The documentation of the spring_core_dart family: Spring Framework and
Spring Boot for Dart and Flutter. The pages here go deeper than the
packages' READMEs (which stay the short introduction on pub.dev) and are
written to become the project's website; see the [roadmap](ROADMAP.md).

| Page | What it covers |
|---|---|
| [Configuration](configuration.md) | Everything that can be configured: config files (YAML and `.properties` side by side), where they are read from and in which order, profiles, imports, placeholders, every property of the framework and of each starter, Flutter's app widget, themes and fonts |
| [Testing](testing.md) | Tests of the application and its starters: `springBootTest`, replacing beans, test properties and profiles, logs, `ApplicationContextRunner`, matchers, and test classes with annotations, as in Spring (`@SpringBootTest`, `@Autowired`, `@TestBean`, `@Test`) |
| [Flutter testing](flutter-testing.md) | Widget tests with the application's beans and fakes, themes, platforms and golden files; the planned `spring_boot_starter_flutter_test` |
| [Code style](style.md) | The recommended style of an application, as a file to copy ([`style/analysis_options.yaml`](style/analysis_options.yaml)): formatting (trailing commas keep a column), analysis, the beans of a widget, placeholders, imports |
| [Dependencies](dependencies.md) | Every package the family uses and who publishes it, the graph of what depends on what, what an application gets, and the rule: only packages of the Dart and Flutter teams, everything else forbidden |

More pages are planned in the [documentation roadmap](ROADMAP.md).

## Conventions

- **Both formats, side by side.** Every configuration example is shown in
  YAML and in `.properties`, next to each other, meaning the same thing.
  Both formats are supported everywhere; pick one per file.
- **Spring first.** Names and behaviour are Spring's; where the Dart port
  differs (or Spring has no such thing), the page says so.
- **Every key with its default.** Reference tables give the key, the type,
  the default and what it does.
- **Examples that run.** The examples are real configuration of this
  version, checked in CI: both columns of a table must mean the same
  properties, and the Flutter examples start a real application.
