# Fix plan

Open differences from Spring found in reviews: first against Spring
Framework 6.2 / Spring Boot 3, then four times (October 2026) against
Spring Framework 7.0, Spring Boot 4.0, Spring Cloud OpenFeign 5.0 and
Jackson 3 across every package. The items below are from the last of
those (the third pre-0.2.0 review); bugs were confirmed with probe
programs.
Items marked **High** are the ones a Spring developer trips over first.
Before 1.0 renames are made outright, with no deprecated aliases.

**0.2.0** is released only when every item under "Before 0.2.0" is done and a new full
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
remaining pointcut designators and `@Lookup` methods. Sixth batch: every item of the
second pre-0.2.0 review — the validation auto-configuration, `@Bean`
aspects, nested value objects, cloud platforms, self-calls on subclass
proxies, `@DeclareParents`, `execution` type patterns, JSON enums,
`defaultImpl` and mixins, SpEL real numbers on the web (tested on node in
CI), Feign form bodies and raw responses, startup failures in the log file,
class-level cache annotations, `@ConditionalOnBean` without arguments,
ordered initializers, the HTTP types, logging patterns and charsets,
WebSocket retries and the test runner. Seventh batch: every item of the
third review — subclass proxies for classes with private members and a
base class, wildcard parameters, singleton advisors, int `@JsonValue`
enums, Spring 7 safe navigation, `JsonNode` per Jackson 3, SpEL reals on
node, URL resources probed with HEAD, registrars of skipped classes, lazy
listeners, early log lines at the final levels, Feign flags, the test
starter with parents and `@Primary`, WebSocket retries, `max-history=0` and
the smaller ones (an invalid `spring.main.cloud-platform` is ignored, as in
Boot 4). Eighth batch (fourth review): status 0 for browser opaque
redirects, no `max-delay >= delay` check, wildcard parameters in full-mode
`@Bean` methods, interface parameter constraints on subclass proxies and
`BeanWrapper` list growth. Ninth batch (fifth review): zero WebSocket reconnect delays, the list grow limit in `DataBinder.construct`, method annotations not inherited from superclasses for `@annotation`, and parenthesised ternary / Elvis in `toStringAST`; starters (cache, method validation) read annotations over the whole hierarchy like Spring's find semantics. Tenth batch (sixth review): selected imports before the importer's beans under registerBean-phase conditions, and cache defaults and class-level annotations from the declaring class and its superclasses. Eleventh batch (seventh review): import order per configuration class like Spring's parser and reader, and runners registered as singletons. Twelfth batch (eighth review): Boot's bean conditions decided when beans register, like `OnBeanCondition`, and one decision per configuration class for its imports and registrars. Thirteenth batch (ninth review): components and imported classes with bean conditions decided in the reader, in class order.

## How close to Spring (tenth pre-0.2.0 review, October 2026)

Per area: **API** — public names and signatures that match Spring
(a change forced by Dart counts half); **behaviour** — 15–50 behaviours
per area a Spring developer relies on, checked in the code and with probe
programs; **coverage** — share of the commonly used features of the Spring
counterpart. Estimates, ±5–10 points; the third review's numbers in
brackets.

| Area | API | Behaviour | Coverage |
|---|---|---|---|
| Container (`beans`) | 88% (88) | 88% (88) | 73% (73) |
| Context, events, lifecycle | 89% (88) | 86% (84) | 71% (70) |
| Configuration, resources (`core`) | 92% (92) | 87% (87) | 73% (73) |
| SpEL | 73% (73) | 85% (84) | 82% (82) |
| Validation, binding | 86% (86) | 84% (84) | 62% (62) |
| JSON (vs Jackson 3) | 74% (74) | 80% (80) | 50% (50) |
| AOP | 82% (82) | 74% (71) | 72% (72) |
| Annotations, generator | 92% (92) | 83% (80) | 77% (77) |
| `spring_boot_dart` | 74% (73) | 87% (86) | 64% (63) |
| `spring_web_dart` | 79% (79) | 80% (80) | 51% (51) |
| Feign starter | 80% (80) | 80% (79) | 57% (57) |
| WebSocket starter (declarative by design) | 64% (64) | 80% (79) | 59% (59) |
| Logging starter | 78% (78) | 81% (81) | 58% (58) |
| Scheduling starter | 76% (76) | 87% (86) | 62% (62) |
| Cache starter | 91% (91) | 89% (89) | 67% (67) |
| Test starter | 77% (77) | 79% (78) | 62% (62) |
| **All, weighted by code size** | **86%** (86) | **84%** (83) | **69%** (69) |

## Before 0.2.0

Nothing open. The tenth review found nothing blocking except one outdated
doc comment (`ConfigurationCondition`), fixed right after it.

## After 0.2.0

Found while writing the guides (`example/server_guide`,
`example/flutter_guide`, October 2026); each is worked around there:

- `@ConditionalOnMissingBean()` without arguments on a `@Bean` method
  checks the type of the returned value (`SystemClock`), not the declared
  return type (`Clock`) as Spring does: a user `Clock` does not make it back
  off.
- `@EventListener(condition:)` takes a function, not a SpEL string like
  Spring's.
- `FetchHttpTransport` (the web) sends no credentials
  (`credentials: 'include'`), so a session cookie cannot be kept across
  origins: a Flutter web app cannot log in with a session.
- Flutter starter: no routes in `spring.flutter.app.*` (`routes`,
  `onGenerateRoute`, `routerConfig`), no locale property, and
  `SpringApplicationWidget` takes no `BeanOverride`s for tests.
- `MockMvc` cannot send a target starting with `//` (parsed as a host).
- The name of a `@Valid @RequestBody` object for message codes is the
  parameter's name, not Spring's type-derived one (`newBook`).
- `@ConfigurationProperties` validation messages ignore the
  `MessageSource`.
- The scheduling starter logs "Bean 'taskScheduler' ... not eligible for
  getting processed by all BeanPostProcessors" at every start (its
  post-processor depends on the scheduler eagerly; the cache starter had
  the same and is fixed).
- A model class named `Order` clashes with the `@Order` annotation, and
  the generator reports only "cannot be forwarded by a proxy".

Found while rewriting the documentation comments (October 2026); the
comments now describe what the code does:

- Web: `@CrossOrigin()` without `methods` allows GET/HEAD/POST only
  (Spring: the mapping's own methods), so a PUT/DELETE pre-flight gets 403;
  `${...}` in a mapping's `headers` is resolved by clients, not the server;
  a `HEAD` on a multi-chunk `StreamingResponseBody` reports the first
  chunk's length; after `MultipartFile.transferTo` the file can no longer
  be read or moved again; the session error suggests a non-existent
  `spring.web.session.enabled`; the "(https)" start line looks at
  `server.ssl.certificate`, not the real settings; `afterCompletion` gets
  the exception even when an `@ExceptionHandler` answered it; a second
  `Validator` bean without `@Primary` turns `@Valid()` bodies off silently.
- HTTP types: `MediaType` parameters in single quotes split on `,`/`;`;
  a duplicated cookie name keeps the last value; a bad `%xx` in
  `filename*` throws `FormatException`; SSE: the last event id does not
  carry over and an empty `id:` sends an empty `Last-Event-ID`;
  `EventStream.fromEvents`/`of` fail a second listener on a
  single-subscription source; `CloseStatus` range checked by an `assert`
  only; the browser WebSocket session drops errors after opening;
  `closeStatus` may stay null after a drop.
- WebSocket starter: a `@SendMessage` value that is not JSON throws
  synchronously from a `Future` method; a handler error is ignored by
  `AbstractWebSocketHandler` (Spring closes with 1011);
  `setAllowedOrigins`/`setAllowedOriginPatterns`/`setSupportedProtocols`
  add instead of replace; a bad `reconnect.multiplier`/`max-retries` fails
  with a `FormatException` that does not name the property.
- Security: `{pbkdf2}` uses the v5_8 settings while Spring 6 maps it to
  v5_5, so Java `{pbkdf2}` hashes may not verify; `offload_io.dart` catches
  `ArgumentError` from the work itself and checks the password twice;
  hash upgrades at login run on the main isolate; the global strategy's
  `runWithContext` restores at the first `await`; with only `issuer-uri`,
  `jws-algorithms` is ignored; `headers().defaultsDisabled()` ignores later
  header calls; users from `HttpSecurity.userDetailsService(...)` never get
  hash upgrades; form login reads at most 64 KB, but when the CSRF token
  comes as a form field the CSRF filter has already read the form with the
  1 MiB limit and the login filter reuses it, so its own limit never
  applies.
- Boot: a `spring.jackson.*` boolean typo silently means false;
  auto-configuration `before`/`after` match short names only, exclusion by
  `Type` matches the simple name; `@ConfigurationProperties` validation
  builds its own `BeanValidator`; `defaultValidator` has no
  `validationMessageSource`, so `{key}` in constraint messages stays as is.
- Context and container: `addBeanFactoryPostProcessor` after refresh is
  ignored silently (`register` throws); the `parent` setter is not guarded
  after refresh; `startupDate` is public and mutable; an `@EventListener`
  whose id ends in `.onApplicationEvent` is taken for an
  `ApplicationListener`; `ReloadableResourceBundleMessageSource` is not
  `ResourceLoaderAware`; `ObjectProvider.isEmpty`/`length` count null beans
  that iteration skips; `NullValueInNestedPathException` from
  `_readSegment` names the whole path.
- Configuration: an invalid profile name throws a plain `StateError`;
  `urlExists` is true on the web, so an `optional:` URL import fails there;
  `validateRequiredProperties` throws on an unresolvable placeholder
  instead of listing the key; random ranges over 2^32 are slightly biased;
  `ConfigurationPropertyName` accepts a leading digit its message forbids.
- SpEL: `SpelType.constructors` entries other than `''` are ignored;
  `MapAccessor.canWrite` is true for every map; `keys`/`keySet` give a
  `List` as properties, a `Set` as methods; `.5` reports EL1044E (Spring
  EL1047E). AOP: advice of one kind is sorted with the unstable
  `List.sort`; the README says named pointcuts are shared as `name()`, the
  code needs `Type.name()` for another aspect's.
- Starters: cache `invalidate()` returns true for an empty or only-expired
  cache; two `sync: true` methods on the same cache and key share one
  pending result; `LogQuery.copyWith` cannot clear `fields` with null;
  Flutter `ThemeConfig` is public API but not exported; widgets sharing a
  beans record share one binding. Test starter: a misspelt
  `BeanOverride(name:)` adds a second bean; without a name and a bean of
  `T` it may replace an unrelated bean named `defaultBeanName(T)`; the
  replacement keeps only type `T`; `andExpect(json:)` on a non-JSON body
  throws `FormatException`; the runner ignores initializers' `order`.


Found while rewriting the READMEs and `docs/` (October 2026):

- Objects made by hand without an introspector (`StandardEvaluationContext()`,
  `DataBinder`, `BeanValidator`, `ObjectMapper`) read only
  `BeanIntrospector.shared`, while the generated `@Introspected`
  descriptions go to each context's introspector: they do not see
  generated classes unless given the context's `BeanIntrospector` bean.
- Configuration read before any `BeanModule` is created misses the
  embedded `lib/resources/` files outside `dart run` (an AOT executable
  started from another directory).
- Flutter starter: `spring.flutter.app.locales` and `spring.messages.basename`
  are read as single values (a YAML list is ignored), and a basename with
  dots (`i18n.messages`) finds no locale files, while Boot's
  `MessagesBundleCondition` reads both; after a hot-reload restart missing
  font families are not logged again.
- A non-numeric Feign `event-stream.max-attempts` fails with a
  `FormatException` that does not name the property.
- Test classes: an `@Autowired() Map<String, T>` field ignores
  `@Qualifier` (`test_builder.dart`).
- Not verified: `@Log` in a Boot app without `@ComponentScan` generates the
  `log` getter into the scan's file (`bin/main.spring.dart`), which a
  `lib/` library cannot import.

Found by the reviews, not blocking:

- Tenth review: unconditional `@Bean` methods are registered while parsing, not in the reader in class order (earlier bean conditions see them; registration order `[h2, h1]` vs Spring's `[h1, h2]` affects unordered `List<T>` injection) — document or defer; plain (non-`ConfigurationCondition`) conditions on `@Bean` methods evaluated while parsing; a component's `@ConditionalOnMissingBean` of its own type; `@ConditionalOnBean(B)` on a component when B is a later conditional component; `@ConditionalOnMissingBean()` without arguments on a class should fail like Boot; `UrlResource.existsAsync()` status rules (204, 500 with a body); `@Bean` products with private members get interface-only proxies (`BeanNotOfRequiredTypeException` when injected by class; README should say subclass proxies are for component classes); operators (`[]`) on subclass proxies aren't advised; a `*String` delay resolving to whitespace.

- Ninth review: excluding an auto-configuration doesn't exclude the configuration classes it `@Import`s (inlined under their own source); a registrar / selector `@Import`ed by two generated classes uses only the first importer's conditions; a user `DeferredImportSelector`'s beans make auto-configurations back off (Boot runs it after `AutoConfigurationImportSelector`); `SpringLogHold.release()` of a non-innermost hold; blank per-client Feign flags vs `config.default`; the condition report shows a whole auto-configuration as not matched for one backed-off bean; `max-history=0` with `total-size-cap`.

- Eighth review: several `TaskScheduler` beans without a primary or `taskScheduler` fail the start (Spring falls back to a local scheduler); the example tour closes with sync `close()` (use `closeAsync()`); SpEL on the web `{{2.0}}.toString()` and `'' + {2.0}`; JSON `intValue()` of `1e20`; README row for list-gap padding; a private default value leaves a subclass-proxy method unadvised.

- Seventh review: `@CacheConfig` on an implemented interface; `initialDelay` with a blank `initialDelayString`; `reconnect.delay=0` with jitter; `DataBinder` / `BeanWrapper` writing into a `const []` default (copy to a growable list or record a field error); 64-bit overflowing indexes; `@Configuration` classes are never AOP proxy candidates (Spring advises them; at least document); `mergedAnnotations` order (interfaces before superclasses); enum names accepted next to `@JsonValue`; `DataBinder.construct` shifting elements after a failed conversion; `#x = 2.0` not `instanceof T(Double)` on the web (document).

- Sixth review: `DataBinder.bind` drops a write into a gap of a `List<int>` silently (document); `BeanWrapper` appending at the grow limit; concurrent `runAsync` holds interleave; held lines of a failed start filtered at WARN; superclass and interface `@Cacheable` together; `@Scheduled` on an overridden superclass method; `default.reconnect.*` errors reported under the client key; empty client-level Feign flags; Feign example README "Dart 3.9.0"; SpEL `{-1, 2}` unmodifiable and quote escaping in AST text; `BeanWrapper` gap exception types.

- Fifth review: `@Scheduled(initialDelay:)` with a blank `initialDelayString`; Feign query spaces as `+` (OpenFeign `%20`); held early lines reach the console in the default format; `DataBinder.construct` gaps in `List<String>` should be `''` like `BeanWrapper`; parameter constraints added on an override should be rejected (`ConstraintDeclarationException`); SpEL real literal `toString` on the web, `Assign` spacing; `StringNode(" 3").asInt()`; `on-profile` inside a profile-specific file should fail; `BeanWrapper` index above the grow limit should raise `InvalidPropertyException` out of `bind()`.

- Fourth review: the lazy-listener stand-in ignores `Ordered.order` and doesn't retry a failed creation; empty comma-list elements (`1,,2`) should bind null; `ignoreInvalidFields` on indexed lists stops at the bad index in Boot; `UrlResource.existsAsync()` and `Content-Length`; document that `SpringLog.hold()` is isolate-wide and that the `--debug` report is INFO; blank resolved `cron` should count as unset; `clean-history-on-start` with `max-history=0`; a connect in flight when the last WebSocket listener cancels; sync `close()` with an open WebSocket logs a not-awaited warning; Feign example README omits timestamps; `JoinPoint` declaring type for interface methods under subclass proxies (CGLIB reports the class); the `@Lazy` through-proxy flag after an unadvised inherited member.

- Context / Boot: `@EventListener` results by runtime class; YAML hex integers beyond 64 bits; nested generic conversion (`Map<String, List<String>>`), `Encoding` aliases (`UTF8`), `canConvert(map, List<int>)`; `AbstractFailureAnalyzer` over the cause chain; `ResourceBanner` `${AnsiColor.*}` / `${application.*}`; `ApplicationAvailability` / `LivenessState`; `methodValidationPostProcessor` with `search: current`; log a throwing exit code generator; async `common-messages`; a class `@Import`ed by two generated classes skipped only when both are (selected modules are); `supportsAsyncExecution()`, `Scope.resolveContextualObject`, `BeanRegistry` spec options.
- SpEL: regex `replaceAll` / `replaceFirst`; `char` arithmetic; 32-bit int literals and overflow; `T(Arrays)`, `Collections`, `UUID`, `LocalDate`, `Duration`, `BigDecimal`; `.class`; conversion on writes to typed map / list elements.
- JSON: `1.0` written as `1` on the web (document); timestamp fraction digits; Dart enum names next to `@JsonValue` values; JSON Pointer `01`; `JsonNode.from(nan)`; `findValue(s)`, `findParent`, `required`, `withObject` / `withArray`, `setAll`; constructor properties first when sorting is off; `1` → `true`.
- Validation: message EL beyond `${validatedValue}`; default message only for `{0}`; canonical `requiredFields`.
- AOP / generator: `(A || B).*`, `@Ann *` in `execution`; `@Pointcut` holder classes turning pruning off; error wording.
- Web / Feign: custom `HttpMethod`s; body-less `ResponseEntity.ok()` builder, `allow` / `cacheControl` / `varyBy`; multipart, `@SpringQueryMap`, `FallbackFactory`, streamed downloads, placeholders in client names, `default.url` per client only; empty `id:` SSE events.
- WebSocket: STOMP client, ping / keep-alive, send-time / buffer / message-size limits, session details, handshake failure status.
- Cache: `Cache.get(key, valueLoader)`, async `retrieve()`; interface vs implementation cache annotations. Scheduling: `SchedulingConfigurer` / `ScheduledTaskRegistrar`, README on ignored `pool.size` / `thread-name-prefix`. Test starter: `prepare()`, `withBean` customizers, output capture. Logging: `logging.structured.*`, time-based rolling and `.gz`, `web` / `sql` groups.
