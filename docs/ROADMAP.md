# Documentation roadmap

Where the documentation is going: the pages still to write, how they are
kept correct, and the website they will become. The package READMEs stay
the short introductions that pub.dev shows; `docs/` is the full manual,
one topic per page.

## Status

| Page | Status |
|---|---|
| [Configuration](configuration.md) | Written: files, locations, precedence, profiles, imports, placeholders, binding, every property of the framework and the starters, Flutter's app widget, themes and fonts, YAML and `.properties` side by side |
| [Testing](testing.md) | Written: test classes with annotations and `springBootTest`, `ApplicationContextRunner`, matchers, logs, the generated code and its build errors |
| [Flutter testing](flutter-testing.md) | Written as a specification: `spring_boot_starter_flutter_test` (planned, [roadmap](../roadmap/spring_boot_starter_flutter_test.md)), widget tests, `pumpSpring`, themes, platforms, goldens; and how to test today with `SpringScope` |
| [Code style](style.md) | Written |
| [Dependencies](dependencies.md) | Written, checked by `tool/test/docs_dependency_graph_test.dart` |
| [Security](security.md), [OWASP ASVS](security-asvs.md), [Mutation testing](security-mutation.md) | Written |
| Getting started | Planned |
| Beans and injection | Planned |
| Lifecycle and events | Planned |
| Conditions and auto-configuration | Planned |
| AOP | Planned |
| SpEL | Planned |
| Validation and binding | Planned |
| JSON (`ObjectMapper`) | Planned |
| Logging | Planned (its properties are in Configuration) |
| Scheduling, caching | Planned |
| HTTP, Feign, WebSocket | Planned |
| Flutter | Planned: the app widget, beans in widgets, themes, fonts, assets, lifecycle, platform profiles, hot reload |
| Code generation | Planned: what the generator writes, its options (`build.yaml`), its build errors |
| Editor support | Planned: the Zed extensions, the language server, snippets |
| Differences from Spring | Planned: one page gathering the *Differences from Spring* sections that each package README has today (the root README links to all of them) |
| Migration between versions | Planned: one page per minor release with breaking changes |

## Next steps

1. **The guide pages** in the table above, one per topic. Their content
   exists today in the `spring_core_dart` README's *Guide* and in the
   other package READMEs; the root README's *Guide* is already a short
   tour that links to them. Each page follows the
   [conventions](#conventions-for-new-pages) below.
2. **Checked examples.** Done for [Configuration](configuration.md):
   `spring_core_dart/test/docs/configuration_examples_test.dart` loads
   every YAML and `.properties` block with the real loaders and checks
   that the two columns of each table mean the same properties, and
   `spring_boot_starter_flutter/test/docs_configuration_test.dart` starts
   an application with each Flutter example (every theme made). Next: the
   same for the other pages as they are written, and compiling the Dart
   blocks marked as complete programs (with the generator).
3. **Keys checked against the code.** A tool lists every property key the
   packages read (`getProperty`, `Binder`, property classes) and compares
   the list with the reference tables. A new key without documentation,
   or a documented key the code no longer reads, fails CI.
4. **Generated reference tables.** Built from the same list, with types
   and defaults, so the tables cannot drift from the code; the prose
   stays hand-written.

## Website

The pages are plain Markdown, so they render on GitHub today and can feed
a site later. To decide when the site starts:

- **Generator.** A static site built from `docs/`: Jaspr (Dart, so the
  site can run the examples' Dart and stay in the same toolchain) or a
  plain Markdown site generator. Hosted on GitHub Pages, built by a
  workflow on each release.
- **Versions.** One version of the docs per release (the `docs/` of the
  release tag), the latest shown by default, matching the packages'
  single version.
- **Side-by-side examples.** The YAML and `.properties` pairs become tabs
  or two columns on the site. In Markdown they are HTML tables with a
  code block per cell, which GitHub renders.
- **Search** over the pages and the property keys, with the property
  reference as its own searchable page.
- **API reference links:** each class name links to its dartdoc on
  pub.dev.
- **Editor integration:** the language server's hover on a property key
  links to its entry in the reference.

## Conventions for new pages

- One topic per page, the file name in kebab case
  (`beans-and-injection.md`).
- Written for a Dart or Flutter developer who does not know Spring, as
  the `///` comments are ([roadmap/documentation.md](../roadmap/documentation.md)):
  first what the feature is and why or when you need it, in two or three
  sentences; then a short example from a real situation, with `//`
  comments saying why; then the details.
- Configuration examples in both formats, side by side (see
  [configuration.md](configuration.md) for the markup).
- Every reference table: key or name, type, default, meaning.
- In each section, Spring's name for the same thing and the same code in
  Java (`Spring (Java):`), and a *Differences from Spring* section where
  they differ.
- Plain, short sentences, no marketing.
