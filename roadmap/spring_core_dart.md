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
