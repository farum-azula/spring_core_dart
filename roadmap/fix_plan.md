# Fix plan

Open differences from Spring found in reviews: first against Spring
Framework 6.2 / Spring Boot 3, then three times (October 2026) against
Spring Framework 7.0, Spring Boot 4.0, Spring Cloud OpenFeign 5.0 and
Jackson 3 across every package. The items below are from the third of
those (the second pre-0.2.0 review); bugs were confirmed with probe
programs.
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
Fourth batch: every item of the October 2026 review (container, context,
configuration, SpEL, generator, AOP, JSON, HTTP), including async
lifecycle, `BeanRegistrar`, async events, pause/restart, scoped proxies,
Jakarta `Provider` / `@Resource`, `classpath*:`, SpEL numbers on the web,
pointcut validation and constructor selection. Fifth batch: every item of
the pre-0.2.0 review — `@EventListener`
registration after the singletons, cron on the web, SpEL argument
conversion, JSON timestamps in seconds, polymorphism, generic classes and
the Jackson annotations, validation groups and container elements, the new
post-processor kinds, Boot's environment and config-data items, conditions,
`EnvironmentPostProcessor`, per-client Feign configuration, the HTTP types,
proxy pruning across modules, null / function / record / generic beans,
`args` / `within` by runtime and declaring type, `ProxyFactory`, the
remaining pointcut designators and `@Lookup` methods.

## How close to Spring (second pre-0.2.0 review, October 2026)

Per area: **API** — public names and signatures that match Spring
(a change forced by Dart counts half); **behaviour** — 15–50 behaviours
per area a Spring developer relies on, checked in the code and with probe
programs; **coverage** — share of the commonly used features of the Spring
counterpart. Estimates, ±5–10 points; the previous review's numbers in
brackets.

| Area | API | Behaviour | Coverage |
|---|---|---|---|
| Container (`beans`) | 88% (88) | 87% (80) | 73% (72) |
| Context, events, lifecycle | 88% (88) | 85% (75) | 70% (69) |
| Configuration, resources (`core`) | 92% (92) | 87% (84) | 72% (71) |
| SpEL | 73% (72) | 85% (85) | 82% (82) |
| Validation, binding | 86% (86) | 82% (79) | 62% (61) |
| JSON (vs Jackson) | 73% (72) | 78% (75) | 49% (47) |
| AOP | 82% (82) | 74% (74) | 72% (71) |
| Annotations, generator | 92% (92) | 84% (83) | 77% (76) |
| `spring_boot_dart` | 72% (70) | 84% (76) | 62% (60) |
| `spring_web_dart` | 78% (74) | 77% (72) | 50% (47) |
| Feign starter | 80% (78) | 78% (74) | 57% (55) |
| WebSocket starter (declarative by design) | 64% (64) | 74% (72) | 58% (58) |
| Logging starter | 72% (72) | 75% (74) | 52% (52) |
| Scheduling starter | 74% (73) | 84% (80) | 59% (58) |
| Cache starter | 90% (90) | 85% (85) | 65% (65) |
| Test starter | 74% (74) | 76% (76) | 60% (60) |
| **All, weighted by code size** | **85%** (84) | **82%** (78) | **68%** (67) |

## Open

Nothing open: the next step is the next full review.
