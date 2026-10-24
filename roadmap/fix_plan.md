# Fix plan

Open differences from Spring found in reviews: first against Spring
Framework 6.2 / Spring Boot 3, then (October 2026) against Spring Framework
7.0, Spring Boot 4.0 and Spring Cloud OpenFeign 5.0 across every package.
Items marked **High** are the ones a Spring developer trips over first.
Before 1.0 renames are made outright, with no deprecated aliases.

**0.2.0** is released only when every item below is done and a new full
review against Spring Framework 7 / Boot 4 / OpenFeign 5 (every package,
like the October 2026 one) finds nothing left to fix; until then releases
are patches (0.1.x).

Already fixed (with regression tests): Dart default values of
constructor parameters, empty collections for constructors and `@Bean`
methods, `@Bean` products processed like components, `@PropertySource` /
`@Import` gated by the declaring class's conditions, negated `on-profile`
documents, relative import cycles, self-references (composites,
decorators), early events reaching the parent twice, exception-safe and
re-entrant `close()`, violation messages mangled by `MessageFormat`,
`disallowedFields` bypasses, release-safe `@annotation` matching,
package-qualified AOP wildcards, SDK types as beans (`HttpClient`,
`Uint8List`, `List<String>`), proxies for `Future<T>?` members,
`toString` with parameters, members named like `Advised`'s and classes
with the same name in two directories, advice silently skipped for beans
that cannot be proxied, optional fields and setters overwritten with
`null`, `DataBinder.bind` throwing on malformed keys and failing setters,
and the order of `spring.profiles.include`. Fixed after the October 2026
review: the whole validation, binding and messages section; the logging,
cache and test starters; cron day names and lists, `@Scheduled(scheduler:)`;
in AOP `Type+`, `@target`, `this`, `args`, per-aspect named pointcuts,
`bean()` aliases and qualifiers, `Ordered` aspects, plain and ancestor
advisors, the auto proxy creator's order, `AopContext.currentProxy()`,
argument copies, async advice and `Future` methods throwing synchronously.
Second batch: `ObjectProvider` injection points, the container's exception
hierarchy, callbacks, `FactoryBean` names, ancestors in sorted beans,
registration after freezing, superclass-first injection, `ObjectFactory`;
lifecycle (lazy beans, `SmartLifecycle` defaults, `isActive`), payload
listeners, `publishEvent` before refresh, the bundle message source and
`MessageSourceAccessor`, unique context ids; profile names, legacy keys,
`--`, null values, `Duration`, lenient enums, classpath plain paths; Boot's
`@Validated` properties, validation auto-configuration, failure analyzers,
startup logging, `spring.main.*`, dotted basenames; SpEL assignment in
`SimpleEvaluationContext`, enum order, boolean selection, `+` conversion,
map selection; JSON dates with offsets and `spring.jackson.time-zone`,
serializer beans, naming acronyms, raw maps/lists, `NaN`; the HTTP types,
Feign and WebSocket items except optional paths. Third batch: YAML out of
the box, location groups and `config/*/`, relaxed binding in the
environment (camelCase Feign/WebSocket keys), `@ConfigurationProperties`
lists, maps and constructor binding, application events, full-mode
`@Configuration`, conditional beans sharing a name, inferred `@Bean` types.

## How close to Spring (October 2026)

Per area: **API** — public names and signatures that match Spring
(a change forced by Dart counts half); **behaviour** — 15–50 behaviours
per area a Spring developer relies on, checked in the code and with probe
tests; **coverage** — share of the commonly used features of the Spring
counterpart. Estimates, ±5–10 points, measured before those fixes.

| Area | API | Behaviour | Coverage |
|---|---|---|---|
| Container (`beans`) | 86% | 65% | 69% |
| Context, events, lifecycle | 87% | 65% | 66% |
| Configuration, resources (`core`) | 91% | 63% | 67% |
| SpEL | 64% | 67% | 77% |
| Validation, binding | 84% | 62% | 58% |
| JSON (vs Jackson) | 70% | 67% | 44% |
| AOP | 80% | 66% | 66% |
| Annotations, generator | 91% | 77% | 73% |
| `spring_boot_dart` | 67% | 60% | 56% |
| `spring_web_dart` | 73% | 55% | 45% |
| Feign starter | 77% | 60% | 52% |
| WebSocket starter (declarative by design) | 62% | 64% | 56% |
| Logging starter | 70% | 66% | 50% |
| Scheduling starter | 71% | 78% | 55% |
| Cache starter | 90% | 81% | 63% |
| Test starter | 73% | 70% | 58% |
| **All, weighted by code size** | **81%** | **67%** | **64%** |
