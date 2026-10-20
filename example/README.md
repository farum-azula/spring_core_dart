# spring_core_dart_example

Every spring_core_dart feature in one small package, plus end-to-end tests
that run the real generated code.

Full guide: [../README.md](../README.md).

## Structure

```
config/example.properties       loaded with @PropertySource
lib/src/
  beans.dart                    @ComponentScan root
  beans.beans.dart              generated (committed)
  greeting/                     stereotypes, @Primary, @Qualifier, @Named/@Inject,
                                prototype scope, every injection style, @Value,
                                collections, ObjectProvider, @PostConstruct/@PreDestroy
  data/                         generic Store<User>, @Lazy, @Autowired constructor,
                                FactoryBean
  config/app_config.dart        @Configuration, @Bean options, inferred destroy,
                                @PropertySource, @Import, @DependsOn, SpEL @Value
  events/orders.dart            @EventListener (payloads, conditions, classes,
                                returned events), ApplicationListener
  conditions/features.dart      annotation conditions, @Conditional, @Profile, @Fallback
  forms/signup_form.dart        @Introspected form with constraints, groups, @Valid
  aop/                          aspects, pointcuts, all advice kinds, advisor bean
  modern/inventory.dart         Dart 3.13 syntax: primary constructors, class const,
                                new/factory constructors, private named parameters
  ui/screen_state.dart          @Configurable + autowireBean
external/legacy_config.dart     outside the scan, pulled in by @Import
test/example_test.dart          20 end-to-end tests
test/modern_syntax_test.dart    5 end-to-end tests of the new syntax
```

## Usage

```bash
dart run build_runner build
dart test
```
