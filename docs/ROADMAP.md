# Documentation roadmap

Where the documentation goes: the pages to write, how they are kept
correct, and the website they become. The package READMEs stay the short
introductions pub.dev shows; `docs/` is the full manual.

## Status

| Page | Status |
|---|---|
| [Configuration](configuration.md) | written: files, locations, precedence, profiles, imports, placeholders, binding, every property of the framework and the starters, Flutter's app widget, themes and fonts, YAML and `.properties` side by side |
| Getting started | planned |
| Beans and injection | planned |
| Lifecycle and events | planned |
| Conditions and auto-configuration | planned |
| AOP | planned |
| SpEL | planned |
| Validation and binding | planned |
| JSON (`ObjectMapper`) | planned |
| Logging | planned (its properties are in Configuration) |
| Scheduling, caching | planned |
| HTTP, Feign, WebSocket | planned |
| [Testing](testing.md) | written: today's `springBootTest`, `ApplicationContextRunner`, matchers, logs; the specification of test classes with annotations (planned, [roadmap](../roadmap/spring_boot_starter_test.md)) |
| [Flutter testing](flutter-testing.md) | written as a specification: `spring_boot_starter_flutter_test` (planned, [roadmap](../roadmap/spring_boot_starter_flutter_test.md)), widget tests, `pumpSpring`, themes, platforms, goldens; today's `SpringScope` way |
| Flutter | planned: the app widget, beans in widgets, themes, fonts, assets, lifecycle, platform profiles, hot reload |
| Code generation | planned: what the generator writes, its options (`build.yaml`), its build errors |
| Editor support | planned: the Zed extensions, the language server, snippets |
| Differences from Spring | planned (now in the root README) |
| Migration between versions | planned: one page per minor release with breaking changes |

## Next steps

1. **The guide pages** above, one per topic, taken from the root README's
   *Guide* (which then shrinks to a short overview with links here) and
   from the package READMEs. Each page: a short introduction, the Spring
   equivalent, runnable examples, the reference, the differences from
   Spring.
2. **Checked examples.** Done for [Configuration](configuration.md):
   `spring_core_dart/test/docs/configuration_examples_test.dart` loads
   every YAML and `.properties` block with the real loaders and checks
   that the two columns of each table mean the same properties;
   `spring_boot_starter_flutter/test/docs_configuration_test.dart` starts
   an application with each Flutter example (every theme made). Next: the
   same for the other pages as they come, and the Dart blocks marked as
   complete programs (compiled with the generator).
3. **Keys checked against the code.** A tool lists every property key the
   packages read (`getProperty`, `Binder`, property classes) and compares
   it with the reference tables: a new key without documentation, or a
   documented key the code no longer reads, fails CI.
4. **Generated reference tables.** From the same list, with types and
   defaults, so the tables cannot drift; the prose stays hand-written.

## Website

The pages are plain Markdown so they render on GitHub today and feed a site
later. To decide when it starts:

- **Generator.** A static site from `docs/`: Jaspr (Dart, so the site can
  run the examples' Dart and live in the same toolchain) or a plain
  Markdown site generator; GitHub Pages for hosting, built by a workflow on
  each release.
- **Versions.** One version of the docs per release (the release tag's
  `docs/`), the latest by default, like the packages' lockstep versions.
- **Side-by-side examples.** The YAML / `.properties` pairs become tabs or
  two columns on the site; in Markdown they are HTML tables with a code
  block per cell, which GitHub renders.
- **Search** over the pages and the property keys; the property reference
  as its own searchable page.
- **API reference** links: each class name links to its dartdoc on pub.dev.
- **Editor integration:** the language server's hovers on a property key
  link to its entry in the reference.

## Conventions for new pages

- One topic per page, the file name in kebab case (`beans-and-injection.md`).
- Start with what the feature is for, in two or three sentences, then a
  minimal example, then the details.
- Configuration examples in both formats, side by side (see
  [configuration.md](configuration.md) for the markup).
- Every reference table: key or name, type, default, meaning.
- Spring's name for the same thing in each section (`Spring (Java):`), and
  a *Differences from Spring* section where they differ.
- Plain, short sentences; no marketing.
