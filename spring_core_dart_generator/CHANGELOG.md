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
