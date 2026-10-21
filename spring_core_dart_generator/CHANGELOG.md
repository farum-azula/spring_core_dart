## Unreleased

- Constructor and `@Bean` method parameters keep their Dart default value
  when no bean or property is found; required collections there resolve to
  an empty collection (Spring's single-constructor fallback).
- Objects returned from `@Bean` methods get their `@Autowired` / `@Value`
  members, `@PostConstruct` / `@PreDestroy` methods and event listeners
  processed; an init or destroy method that is also annotated runs once.
- `@Import`ed classes keep their explicit name and inherit the importer's
  conditions; `@PropertySource` declarations carry their class's
  conditions.
- `@SpringBootApplication` on `main`: scans `lib/` and the directory of
  `main`, and generates `springApplication` / `runApplication(args)`.
- Starters' `requires` ranges are checked against the `spring_boot_dart`
  version in use; an incompatible starter stops the build with an
  explanation.
- Class conditions are emitted as one `ConditionGroup` per class.
- `@SpringBootApplication`: auto-configuration modules of all dependencies
  (`lib/spring_auto_configuration.dart`) are discovered and passed to the
  generated `springApplication`; `runApplicationAsync` is generated too.
- Files under `lib/resources/` are embedded into generated modules as
  `classpath:` resources (text as-is, binaries base64, > 1 MB skipped).
- Proxy signatures include annotation type names (`annotationTypes`,
  `targetAnnotationTypes`) for release-safe `@annotation` matching.

## 0.1.0

Initial release.

- `@ComponentScan` modules with bean definitions for every stereotype and
  `@Bean` method, constructor / field / setter / method injection,
  collections, providers and `@Value`.
- Lifecycle callbacks, inferred destroy methods, event listeners,
  `FactoryBean` products, conditions, `@Import`, `@PropertySource`,
  `@Configurable` configurers.
- `@Introspected` metadata for data binding, validation and SpEL.
- `@Aspect` metadata and AOP proxy classes (`aop_proxies` option).
- Build-time validation with errors pointing at the source.
- Dart 3.13 syntax: primary constructors (annotations on declaring
  parameters), `class const`, `new` / `factory` constructor declarations,
  private named parameters.
