# spring_core_dart

The runtime: container, AOP, SpEL, validation, `ObjectMapper`. Open
differences from Spring found in reviews: [fix_plan.md](fix_plan.md).

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
