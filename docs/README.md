# spring_core_dart documentation

The manual of the spring_core_dart family: Spring Framework and Spring
Boot for Dart and Flutter. Each package README is the short introduction
that pub.dev shows; the pages here go deeper into one topic each, across
the packages. They are written to become the project's website (see the
[documentation roadmap](ROADMAP.md)).

New to the project? Start with the [repository README](../README.md):
what the family is, a quick start, and the list of packages.

| Page | What it covers | Read it when |
|---|---|---|
| [Configuration](configuration.md) | Everything that can be configured: config files (YAML and `.properties` side by side), where they are read from and in which order, profiles, imports, placeholders, every property of the framework and of each starter (SQL databases and migrations included), Flutter's app widget, themes and fonts | you look up a property, or wonder why a value is not the one you set |
| [Flutter themes](flutter/theme/index.md) | The theme reference of `spring_boot_starter_flutter`, one page per topic: properties, colors, typography, shape, spacing and elevation, tokens and references, styles and states, motion, background, images, Cupertino, and every Material component | you set the look of a Flutter app from YAML |
| [Testing](testing.md) | Tests of an application and of its starters: `springBootTest`, replacing beans, test properties and profiles, logs, `ApplicationContextRunner`, matchers, test classes with annotations written the way Spring writes them (`@SpringBootTest`, `@Autowired`, `@TestBean`, `@Test`), data tests (`@DataTest`, rolled back after each test) and containers in tests (`@Container`, `@ServiceConnection`, PostgreSQL and Keycloak modules) | you write the tests of an application or a starter |
| [Flutter testing](flutter-testing.md) | Widget tests with the application's beans and fakes, themes, platforms and golden files. What works today, and the specification of the planned `spring_boot_starter_flutter_test` | you test a Flutter app |
| [Code style](style.md) | The recommended style of an application, as a file to copy ([`style/analysis_options.yaml`](style/analysis_options.yaml)): formatting (trailing commas keep a column), analysis, the beans of a widget, placeholders, imports | you start a project |
| [Dependencies](dependencies.md) | Every package the family uses and who publishes it, the graph of what depends on what, what an application downloads, and the rule: only packages of the Dart and Flutter teams, every other package forbidden unless listed as an exception | you add a dependency, or audit what an application pulls in |
| [Security](security.md) | What the two security packages promise, against whom, and how it is shown; how to report a security problem | you rely on the security packages, or found a problem in them |
| [Spring Security features](security-spring-comparison.md) | Every feature of Spring Security 7 and Spring Boot 4's security auto-configuration, with its status here: done, partial, missing, or left out on purpose and why | you come from Spring and wonder whether a feature works here |
| [OWASP ASVS](security-asvs.md) | The OWASP ASVS 4.0.3 level 2 requirements a framework can meet, each with its status and the test that shows it | you check the security packages against a standard |
| [Mutation testing](security-mutation.md) | How the tests of the security packages are checked by changing the code one small way at a time, and the changes no test can notice | you want to know how well those tests catch mistakes |

More pages are planned: see the [documentation roadmap](ROADMAP.md).

## Conventions

- **Both formats, side by side.** Every configuration example is shown in
  YAML and in `.properties`, next to each other, meaning the same thing.
  Both formats work everywhere; pick one per file.
- **Spring's names first.** Names and behaviour are Spring's. Where the
  Dart port differs, or Spring has no such thing, the page says so.
- **Every key with its default.** Reference tables give the key, the
  type, the default and what it does.
- **Examples that are checked.** The examples are real configuration of
  this version. For the [Configuration](configuration.md) page, CI loads
  every YAML and `.properties` block, checks that both columns of a table
  mean the same properties, and starts a real Flutter application with
  each Flutter example. The other pages get the same checks as they are
  written ([roadmap](ROADMAP.md#next-steps)).

## Pages of the website

Some pages, such as the [Flutter themes](flutter/theme/index.md) reference,
become pages of the documentation website and of its `llms.txt`. They start
with a front matter block that the site reads. Keep this exact shape:

```
---
title: "<Page title> — Spring for Dart"
description: "<one sentence, at most 160 characters>"
slug: /docs/<path of the page without .md>
section: <Section> / <Subsection>
order: <number that sorts the page inside its section>
keywords: [word, another word]
---
```

- `slug` is the page's address. An `index.md` takes the address of its
  folder (`flutter/theme/index.md` is `/docs/flutter/theme`).
- Then one `#` heading, a short introduction, complete YAML examples written
  as nested YAML (never dotted keys such as `spring.flutter.theme.x:`), and a
  table `Property | Type | Values | Default | What it does` for every property.
- Links between pages are relative (`colors.md`, `components/index.md`).
- Pages under `flutter/theme/components/` are generated from the component
  metadata; do not edit them by hand.
