# flutter_spring for Zed

Editor support for [`spring_core_dart`](https://pub.dev/packages/spring_core_dart),
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart) and the
`spring_boot_starter_*` packages. The extension version always equals the
framework version it supports.

## Snippets

Type the prefix in a Dart file and press Tab:

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

## Planned

A language server for navigation from injection points to beans and from
`@Value` placeholders to `application.properties`, bean markers, SpEL
highlighting and checks, completion of property keys and bean names, and
diagnostics for missing or ambiguous beans (see the roadmap in the
repository README).

## Development

In Zed: command palette → `zed: install dev extension` → choose this
folder (`extensions/zed/flutter_spring`).
