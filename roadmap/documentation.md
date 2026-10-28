# Documentation comments

**First thing after the 0.4.x release.** Every documentation comment (`///`)
of every package is rewritten so that a reader who does not know Spring
understands what the thing is, why it exists and when they would need it.
About 29 000 lines of `///` in `lib/` today.

## What is wrong now

Many comments describe a type by where it appears or by its Spring name,
not by what it is for:

```dart
/// Everything a bean factory offers, like Spring's
/// `ConfigurableListableBeanFactory`.
///
/// This is what `BeanFactoryPostProcessor`s receive and what
/// `ConfigurableApplicationContext.beanFactory` returns.
///
/// ```dart
/// final factory = context.beanFactory;
/// factory.getBeanDefinition('reports').lazy = true;
/// factory.registerResolvableDependency(Clock, SystemClock());
/// ```
```

"Everything ... offers" says nothing; "what X receives and Y returns" is a
cross-reference, not an explanation; the example lists unrelated calls with
no reason to make them. Knowing Spring is assumed.

## What a comment says

In this order, in plain words and short sentences:

1. **What it is**, in one sentence, without "like Spring's ...".
2. **Why it exists and when you need it**: the problem it solves, and, when
   it is so, that most applications never touch it (and what they use
   instead).
3. **How it is used**: one example from a real situation, with the reason
   in a comment (where the object comes from, why the call is made).
4. **Spring**: the comparison stays as it is today — the Spring
   counterpart and the same code in Java (`Spring (Java):` and a `java`
   block), with the differences that matter.

Members (methods, getters, constructors, parameters): what it does, when to
call it, what it returns or throws. No repeating the name ("Gets the bean"
for `getBean`); say what is special.

The same comment, rewritten:

```dart
/// The container's full control: besides handing out beans, it lets code
/// change bean definitions and the container's setup before any bean is
/// created.
///
/// Most applications never need it: beans are declared with annotations
/// and the generator registers them. It is for code that adjusts the
/// container itself, such as a library that makes some beans lazy,
/// registers an object that is not a bean as injectable, or checks the
/// bean graph. That code gets it in a [BeanFactoryPostProcessor] (called
/// after the definitions are registered, before beans are created).
///
/// ```dart
/// // The slow `reports` bean starts on first use, not at startup.
/// @Component()
/// class LazyReports implements BeanFactoryPostProcessor {
///   @override
///   void postProcessBeanFactory(ConfigurableListableBeanFactory factory) {
///     factory.getBeanDefinition('reports').lazy = true;
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class LazyReports implements BeanFactoryPostProcessor {
///   @Override
///   public void postProcessBeanFactory(ConfigurableListableBeanFactory factory) {
///     factory.getBeanDefinition("reports").setLazyInit(true);
///   }
/// }
/// ```
```

## How

- Package by package, the ones applications touch first: `spring_web_dart`
  and the starters (annotations, configuration), `spring_boot_dart`, then
  `spring_core_dart` (container, SpEL, JSON, validation), the security
  packages, the generator's public API, the language server.
- Inside a package: the public API before `src` internals, the types a
  user writes (annotations, interfaces they implement) before the ones the
  framework hands them.
- Behaviour does not change: comments only. Examples in comments must
  compile (the doc tests of `spring_core_dart` read some of them; keep
  them passing).
- The READMEs and `docs/` follow the same rule where they explain a type.
- Done when every package has been read through; tick them off here.

| Package | Done |
|---|---|
| `spring_web_dart` | October 2026 |
| `spring_boot_starter_web` | October 2026 |
| `spring_boot_starter_feign` | October 2026 |
| `spring_boot_starter_websocket` | October 2026 |
| `spring_boot_starter_logging` | October 2026 |
| `spring_boot_starter_scheduling` | October 2026 |
| `spring_boot_starter_cache` | October 2026 |
| `spring_boot_starter_flutter` | October 2026 |
| `spring_boot_starter_test` | October 2026 |
| `spring_boot_dart` | October 2026 |
| `spring_core_dart` | October 2026 |
| `spring_security_core` | October 2026 |
| `spring_boot_starter_security` | October 2026 |
| `spring_core_dart_generator` | October 2026 |
| `extensions/language_server` | October 2026 |
