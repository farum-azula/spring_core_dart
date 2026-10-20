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
