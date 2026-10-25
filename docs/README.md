# spring_core_dart documentation

The documentation of the spring_core_dart family: Spring Framework and
Spring Boot for Dart and Flutter. The pages here go deeper than the
packages' READMEs (which stay the short introduction on pub.dev) and are
written to become the project's website; see the [roadmap](ROADMAP.md).

| Page | What it covers |
|---|---|
| [Configuration](configuration.md) | Everything that can be configured: config files (YAML and `.properties` side by side), where they are read from and in which order, profiles, imports, placeholders, every property of the framework and of each starter, Flutter's app widget, themes and fonts |

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
