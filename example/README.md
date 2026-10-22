# NEON Books — a runnable tour of spring_core_dart

Every feature of the library used in one small bookstore app. Run it and
read what each feature actually did:

```bash
dart run build_runner build      # regenerate lib/src/app.beans.dart and bin/shop.beans.dart (committed)
dart run bin/main.dart           # the whole tour
dart run bin/shop.dart           # the same shop as a Spring Boot app (@SpringBootApplication on main)
dart run bin/main.dart --section=aop
dart run bin/main.dart --spring.profiles.active=prod --app.name=Demo
DB_PASSWORD=s3cret SHOP_MOTTO="Read more" dart run bin/main.dart --section=config
dart test                        # asserts the tour's output
```

| Section | What you see | Where |
|---|---|---|
| (layout) | `lib/resources/` is the classpath: `application*.properties`, `messages/`, `templates/`, a binary `logo.png` — embedded by the generator, no asset declarations | `lib/resources/` |
| `config` | environment variables in property files (`db.password=${DB_PASSWORD:changeme}`) and as relaxed overrides (`SHOP_MOTTO` → `shop.motto`), `config/application*.properties`, profile files, a `!prod` multi-document guard, `spring.config.import`, profile groups, `@PropertySource` (gated by `@Profile`, pulled in by `@Import`), placeholders, typed properties, `@Profile` beans and expressions, condition annotations, `@Conditional`; the same module started again with `prod` | `lib/resources/`, `lib/src/payments/`, `lib/src/features/`, `lib/src/config/` |
| `beans` | `@Value('classpath:...') Resource` (text and binary), stereotypes, `@Configuration`/`@Bean` (static, prototype, alias, lazy, `initMethod`, inferred destroy), constructor/field/setter/method injection, Dart default values, `List`/`Map` injection ordered by `@Order`, an empty list for a missing collection, a `@Primary` composite that gets the *other* beans of its type, `@Qualifier`, `@Fallback`, `@Value` with conversion, SpEL and nullable values, a `@Bean` product with its own `@PostConstruct`/`@Autowired`, `@Import`, `@Configurable` + `autowireBean` | `lib/src/catalog/`, `lib/src/config/`, `lib/external/`, `lib/src/ui/` |
| `lifecycle` | every callback in order (aware interfaces, `@PostConstruct`, `afterPropertiesSet`, `initMethod`), `SmartInitializingSingleton`, `SmartLifecycle` phases, `stop()`/`start()` | `lib/src/lifecycle/` |
| `extensions` | your own `BeanPostProcessor`, `DestructionAwareBeanPostProcessor`, `BeanFactoryPostProcessor`, a registry post-processor registering a hand-written `BeanDefinition`, a custom scope used through `ObjectProvider` | `lib/src/extension/` |
| `events` | payload events, `ApplicationEvent`s, `@EventListener` with `condition`/`@Order`/`classes`, returned events republished, `ApplicationListener`, removable lambda listeners | `lib/src/events/` |
| `messages` | `messageSource` bean with `classpath:messages/messages*.properties`, locale fallback, `MessageFormat` choice/number | `lib/resources/messages/` |
| `spel` | arithmetic, selection/projection, safe navigation, Elvis, functions, `T(...)`, templates, `SimpleEvaluationContext`, `@Introspected` objects | `lib/tour.dart` |
| `validation` | `DataBinder` with type mismatches and `disallowedFields`, constraints, a class-level constraint, `@Valid` cascade, groups, localized messages, `BeanWrapper` | `lib/src/validation/` |
| `aop` | `@Aspect` with a named `@Pointcut`, all advice kinds and their order, `@annotation(Timed)`, `within()`, `bean()`, async methods, an advisor bean, `AopUtils.getTarget`, self-invocation: `this` vs a `@Lazy` self reference | `lib/src/aop/` |
| `scheduling` | `@Scheduled` with a fixed delay from properties (`${shop.stock-refresh}`) and a cron expression, the registered tasks and the next cron run (`spring_boot_starter_scheduling`) | `lib/src/jobs/` |
| `cache` | `@Cacheable` with a SpEL key, `@CacheEvict`, an async method whose `null` result is not stored (`unless`) (`spring_boot_starter_cache`) | `lib/src/cache/` |
| `hierarchy` | parent and child contexts from hand-written `BeanModule`s, events reaching the parent | `lib/tour.dart` |
| `failures` | startup validation: a missing dependency and a cycle reported before anything is created | `lib/tour.dart` |
| `shutdown` | `ContextClosedEvent`, lifecycle stop, destroy callbacks in reverse creation order | — |

`bin/shop.dart` is the Spring Boot entry point: `@SpringBootApplication` on
`main`, one import of the generated `shop.beans.dart`, a
`@ConfigurationProperties('shop')` class and a `CommandLineRunner`
(`lib/src/boot/`). Try `dart run bin/shop.dart --shop.max-basket-size=0` for
the startup failure report.

The Boot app also shows the two starters:

- `spring_boot_starter_logging` is only a dependency: the generator finds
  its auto-configuration. `Checkout.pay` and the runner log through
  `SpringLog` (levels and pattern in `application.properties`, fields via
  `SpringLog.withFields`), and `ConsoleLogScreen` prints the injected
  `LogBuffer` to the console the way a Flutter log screen would show it. Try
  `LOGGING_LEVEL_NEON=info dart run bin/shop.dart`.
- `spring_boot_starter_test` drives `test/boot_test.dart`: `springBootTest`
  with the `test` profile reading `test/resources/application-test.properties`
  (test-only config, not embedded), arguments and environment, a `BeanOverride` replacing the sandbox
  payment gateway with a fake, and `captureLogs`.

`tool/release_check.dart` runs the AOP part, `@Cacheable` and the
`@Scheduled` methods as minified JavaScript (`dart compile js -O4`) to make
sure nothing depends on class names that release builds rename.

`bin/shop.dart` keeps running because of its `@Scheduled` tasks, like any
Spring Boot application with scheduling; stop it with Ctrl+C, or start it
with `--spring.task.scheduling.enabled=false`.
