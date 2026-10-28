# spring_core_dart

The runtime: container, AOP, SpEL, validation, `ObjectMapper`. Open
differences from Spring found in reviews: [fix_plan.md](fix_plan.md).

## Logging like Spring's

The levels, groups, `logging.level.*` properties, `--debug` (the
conditions report) and changing levels at runtime are there; what the
framework logs is not. Found in October 2026:

- **The default level.** Without `spring_boot_starter_logging`,
  `SpringLog` shows only warnings and errors, so an application of
  `spring_boot_dart` alone (and the package examples) sees none of its
  `log.info` lines. Spring's default is INFO either way (logback in Boot,
  commons-logging over java.util.logging without it): make the root level
  INFO, then drop the workarounds in the examples
  (`setDefaultProperties({'logging.level.<topic>': 'info'})`,
  `SpringLog.level = SpringLogLevel.info`) and the last `print` of the
  `spring_web_dart` README.
- **The framework's own lines.** Almost none today (debug and trace
  calls: `spring_core_dart` 0, `spring_boot_dart` 0, the web starter 3,
  security 8), so `logging.level.root=debug` shows next to nothing. Port
  Spring's debug and trace lines for the main steps, with Spring's texts
  so they are recognised: the container (`Creating shared instance of
  singleton bean 'x'`, profiles, the config files loaded, events), the
  web starter (`GET "/api/books", parameters={}`, `Mapped to
  BookController#list()`, `Completed 200 OK`), security (`Securing GET
  /api/books`, `Secured GET /api/books`, `Set SecurityContextHolder to
  anonymous`, the chain's filters at startup), cache, scheduling, Feign,
  WebSocket, the OAuth2 client.
- **Boot's switches.** The predefined `web` group (`logging.level.web=debug`);
  `--debug` also turning on debug for a selection of the framework's
  loggers, and `--trace`, as Boot does.
- Tests: the lines appear at debug and trace and not at info.

## JSON, next steps

Polymorphic types (`sealed` hierarchies with `@JsonTypeInfo` /
`@JsonSubTypes`), date and number patterns (`@JsonFormat`), `@JsonAlias`,
getters as properties, streaming of large documents, editor checks of
`@JsonProperty` names.

## Generator: incremental output per library

Today one `@ComponentScan` / `@SpringBootApplication` root produces one
`<name>.spring.dart` with everything under it, so changing one class (a
Feign client, say) re-runs the whole scan and rewrites the whole file; on a
large project each change costs seconds.

Plan: split the work like source_gen's `SharedPartBuilder` +
`CombiningBuilder`:

- a per-library step writes a small intermediate output for each library
  with annotations (its bean definitions, proxies, metadata), depending only
  on that library and the types it uses;
- the root step only combines the per-library pieces (imports and module
  lists) into `<name>.spring.dart`, cheap and with no analysis of unchanged
  libraries;
- optionally, one generated file per starter / feature folder
  (`feign.spring.dart`, `cache.spring.dart`, ...) next to the root one, so a
  change in the Feign clients rewrites only the Feign file.

Goal: editing one class regenerates only what depends on it; build_runner's
own invalidation then does the rest.

## Jakarta annotations: keep or remove (open)

The JSR-330 / JSR-250 names Spring accepts besides its own are here only
for Java EE compatibility, which a Dart application has no use for, and
each duplicates a Spring one:

| Jakarta | Spring's own |
|---|---|
| `@Inject` | `@Autowired` |
| `@Named` (class / parameter) | `@Component('name')` / `@Qualifier('name')` |
| `Provider<T>` | `ObjectProvider<T>` |
| `@Resource` (a bean by name, not a file) | `@Autowired` + `@Qualifier` |
| `@Priority` | `@Order` |

`@Inject` and `@Named` are in the main library, the other three in
`package:spring_core_dart/jakarta.dart` (their names clash with `Resource`
and with other packages' `Provider`). Two ways for a reader to do one
thing, and `@Resource` next to the file type `Resource` confuses.

**Under question:** remove them all (annotations, `jakarta.dart`, their
handling in the bean factory and the generator, tests, docs, language
server) as a breaking change before 1.0. Stays for now. Not affected:
`@PostConstruct` / `@PreDestroy` and the validation constraints
(`@NotBlank`, `@Min`, ...), which Spring applications use every day.
