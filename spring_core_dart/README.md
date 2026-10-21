# spring_core_dart

Spring Core for Dart: IoC container, environment and `application.properties`
configuration, events, messages, resources, type conversion, SpEL, validation
with data binding, and AOP. Pure Dart, works in Flutter (no `dart:mirrors`):
annotations are processed at build time by `spring_core_dart_generator`.

Repository: <https://github.com/farum-azula/spring_core_dart>.
Flutter widgets (bean builders, event listeners in the widget tree) will be a
separate library.

## Packages

| Package | Path | What it is |
|---|---|---|
| `spring_core_dart` | [`spring_core_dart/`](https://github.com/farum-azula/spring_core_dart/tree/main/spring_core_dart) | Runtime: annotations, container, environment, events, SpEL, validation, AOP. No dependencies. |
| `spring_core_dart_generator` | [`spring_core_dart_generator/`](https://pub.dev/packages/spring_core_dart_generator) | `build_runner` builder that turns annotations into `*.beans.dart` modules. |
| `spring_core_dart_example` | [`example/`](https://github.com/farum-azula/spring_core_dart/tree/main/example) | Every feature in use, with end-to-end tests over the generated code. |

Libraries of the runtime (import one, or `package:spring_core_dart/spring_core_dart.dart` for all):

| Library | Spring counterpart |
|---|---|
| `core.dart` | `spring-core`: `Environment`, property sources, profiles, `ConversionService`, resources, `AntPathMatcher`, Spring Boot config data |
| `beans.dart` | `spring-beans`: `BeanDefinition`, `DefaultListableBeanFactory`, `FactoryBean`, post-processors, scopes, `BeanWrapper`, introspection |
| `context.dart` | `spring-context`: annotations, `ApplicationContext`, conditions, events, lifecycle, `MessageSource` |
| `expression.dart` | `spring-expression` (SpEL) |
| `validation.dart` | `org.springframework.validation` + Bean Validation style constraints |
| `aop.dart` | `spring-aop`: aspects, advice, pointcut expressions, advisors |

## Installation

```yaml
dependencies:
  spring_core_dart: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0
```

Generator option (in your `build.yaml`):

```yaml
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        options:
          aop_proxies: all   # all (default) | interfaces | none
```

## Quick start

```properties
# config/application.properties
app.title=NEON
spring.profiles.active=dev
```

```dart
// lib/src/beans.dart — everything under lib/src/ is scanned
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/beans.beans.dart';

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

```dart
abstract interface class Greeter {
  String greet(String name);
}

@Service()
class EnglishGreeter implements Greeter {
  EnglishGreeter(@Value(r'${app.title}') this.title);

  final String title;

  @override
  String greet(String name) => 'Hello $name from $title';
}
```

```bash
dart run build_runner build   # or watch
```

```dart
Future<void> main(List<String> args) async {
  final environment = StandardEnvironment()
    ..propertySources.addFirst(SimpleCommandLinePropertySource(args));
  await ConfigDataEnvironment(environment).processAndApply();

  final context = ApplicationContext.run([appBeans], environment: environment);
  print(context.getBean<Greeter>().greet('Ada'));
  context.close();
}
```

## Guide

### Declaring beans

| Annotation | Meaning |
|---|---|
| `@Component([name])`, `@Service`, `@Repository`, `@Controller`, `@Named` | A bean. Default name: lowerCamelCase class name (`URLService` stays). Subclass `Component` for your own stereotypes. |
| `@Configuration([name])` | A bean whose `@Bean` methods declare more beans. `@Lazy` / `@Profile` / conditions on it apply to its `@Bean` methods. |
| `@Bean(name:, aliases:, initMethod:, destroyMethod:, autowireCandidate:)` | A bean produced by a method; type = declared return type; parameters are injected. Destroy method is inferred (`close`, `shutdown`, `dispose`) unless `destroyMethod: ''`. |
| `@Scope('prototype')` / `ScopeType.*` / custom name | Scope; custom scopes via `registerScope(name, CustomScope)` (e.g. `SimpleMapScope`). |
| `@Lazy()` | Singletons are eager by default; lazy ones are created on first use. |
| `@Primary()`, `@Fallback()`, `@Qualifier('x')` | Choosing between candidates. |
| `@DependsOn([...])`, `@Order(n)`, `@Description('...')` | Creation order, collection order, documentation. |

A bean is registered under its own type and all its public supertypes.
Generic supertypes are matched by the full type (`Store<User>`).
A `FactoryBean<T>` exposes its product by name and type; `&name` returns the
factory.

### Injection

```dart
@Service()
class OrderService {
  OrderService(
    this.repository,                         // single bean
    @Qualifier('fast') this.cache,          // by name / qualifier
    this.listeners,                          // List<Listener>: all, ordered
    {this.audit,                             // nullable = optional
    required this.reports,                   // ObjectProvider<Report>: lazy
    @Value(r'${orders.limit:100}') required this.limit});

  @Autowired()
  late final Clock clock;                    // field

  @Autowired()
  set metrics(Metrics value) {}              // setter

  @Autowired()
  void init(Environment environment) {}      // method

  ...
}
```

#### Primary constructors and other new syntax

Dart 3.13+ syntax works with the generator: primary constructors (also on
`@Configuration` and `@Introspected` classes, with annotations on their
parameters), `class const`, in-body `new(...)` / `new name(...)` /
`factory name(...)` constructors and private named parameters (injected
under their public name).

```dart
@Component()
class Settings(@Value(r'${pool.size:1}') final int capacity);

@Service()
class Inventory {
  final Settings settings;
  final Clock _clock;
  new(this.settings, {required this._clock}); // called as clock: ...
}

@Service()
class Report {
  final Inventory inventory;
  new _(this.inventory);

  @Autowired()
  factory of(Inventory inventory) => Report._(inventory);
}

@Introspected()
class StockForm(@NotBlank() var String sku, {@Min(1) var int quantity = 1});
```

Selection when several beans match: the only candidate, else the single
`@Primary`, else the only non-`@Fallback`, else the one named like the
parameter. A bean is never injected into itself (Spring's self-reference
rule), so a `@Primary` composite or decorator of `Greeter` receives the
*other* greeters. A constructor or `@Bean` parameter with a Dart default
value keeps the default when no bean (or property) is found, and a required
`List`/`Set`/`Map` there is empty when nothing matches (Spring's
single-constructor fallback; field and setter injection still require a
bean). `List<T>` / `Set<T>` / `Map<String, T>` receive every candidate
(also from parent contexts) sorted by `PriorityOrdered` → `Ordered` →
`@Order`. `BeanFactory`, `ApplicationContext`, `ApplicationEventPublisher`,
`ResourceLoader` and `Environment` can be injected.

`@Value` resolves `${key:default}` placeholders, evaluates `#{...}` SpEL and
converts the result to the target type (`int`, `Duration`, `List<String>`,
enums with `addEnum`, ...). A nullable target gets `null` when a placeholder
has no value.

`refresh()` validates the whole graph before creating the application's
beans (missing and ambiguous dependencies, unresolvable placeholders,
`@DependsOn` names, cycles), so configuration errors fail at startup. Only
post-processors and infrastructure beans (`messageSource`, ...) are created
before that check.

### Lifecycle

Creation: constructor → fields/setters/methods → `BeanNameAware` /
`BeanFactoryAware` → context aware interfaces (`EnvironmentAware`,
`ApplicationContextAware`, ...) → `postProcessBeforeInitialization` →
`@PostConstruct` → `InitializingBean.afterPropertiesSet` → init method →
`postProcessAfterInitialization`. Destruction (on `close()`, dependents
first): `DestructionAwareBeanPostProcessor` → `@PreDestroy` →
`DisposableBean.destroy` → destroy method.

`SmartInitializingSingleton` runs after all eager singletons;
`Lifecycle` / `SmartLifecycle` beans are started by phase (auto-startup at
refresh) and stopped in reverse on `stop()` / `close()`. Like Spring's
`doClose`, `close()` never throws because of a failing `ContextClosedEvent`
listener or a bean that fails to stop: the error is logged and shutdown
continues (a `close()` from inside a listener is ignored).

Problems the framework recovers from are logged through `SpringLog`
(warnings are printed by default): set `SpringLog.level` and
`SpringLog.handler` to route them, e.g. to `package:logging`.

### Environment and configuration

- `StandardEnvironment`: property sources (command line, OS environment,
  config files, `@PropertySource`), `${...}` placeholders with defaults,
  nesting and escapes, typed `getPropertyAs<T>`, required properties.
- Profiles: `spring.profiles.active` / `.default`, expressions
  `dev & (eu | us) & !prod`.
- `ConfigDataEnvironment` (Spring Boot config data): `application.properties`
  and `application-{profile}.properties` from `classpath:/` and
  `classpath:/config/` (= `lib/resources/`), overridden by `file:./` and
  `file:./config/`
  (or `spring.config.location` / `additional-location` / `name`), multi-doc
  files with `#---` and `spring.config.activate.on-profile`,
  `spring.config.import`, `spring.profiles.include` / `group.*`,
  `optional:` locations. Works with async-only resources (Flutter assets)
  via `processAndApply()`.
- `@PropertySource([...], factory: ...)` on a component adds files; the
  last declared wins. It is loaded only when the declaring class's
  conditions (`@Profile`, `@Conditional`, ...) match; classes pulled in with
  `@Import` inherit the importer's conditions.
- YAML: implement `PropertySourceLoader` (`yml`, `yaml`) for config data and
  `PropertySourceFactory` for `@PropertySource` — the core needs no change.

There is no `.env` support by design: configuration lives in property files.

### Conditions

`@Profile(['dev'])`, `@Conditional([MyCondition])`, or any const annotation
class that implements `Condition` (attribute-style conditions such as
`@ConditionalOnProperty('feature.x')`). Conditions see the environment and
the definitions registered before them.

### Modules

`@ComponentScan` generates a `BeanModule` per package (directory). Combine
modules in the application; `@Import([OtherConfig])` pulls in configuration
classes outside the scan. Contexts can have a parent; beans of the parent
are visible to the child.

### Events

```dart
@Component()
class Shipping {
  @EventListener()                       // payloads or ApplicationEvents
  OrderShipped onPlaced(OrderPlaced order) => OrderShipped(this, order.id);

  @EventListener(condition: isBigOrder)  // top-level / static predicate
  @Order(1)
  void onBig(OrderPlaced order) {}

  @EventListener(classes: [ContextRefreshedEvent, ContextClosedEvent])
  void onContext() {}
}
```

Non-null results are published again. `ApplicationListener<E>` beans work
too; `context.addListener<E>(...)` returns a removable registration. Events
published during refresh are delivered once listeners are ready; events
propagate to the parent context.

### Messages, resources, conversion

- `MessageSource`: `StaticMessageSource`, `PropertiesMessageSource`
  (`messages_ru_RU.properties` → `messages_ru` → base), locale fallback,
  `MessageFormat` placeholders, quotes, `number`, `choice`. Define a bean
  named `messageSource`; the context delegates to it.
- Resources: `lib/resources/` is the classpath — the generator embeds its
  files, so `classpath:...` works in CLI, AOT, Flutter and web without asset
  declarations; `@Value('classpath:templates/mail.txt') Resource template`.
  `ResourceLoader` with `classpath:`, `file:` and custom protocols
  (`ProtocolResolver`), `PathMatchingResourcePatternResolver` with
  `AntPathMatcher`.
- `DefaultConversionService` with Spring Boot duration syntax (`10s`,
  `PT5M`), collections and enums.

### SpEL

```dart
final parser = SpelExpressionParser();
parser.parseExpression("name.toUpperCase()").getValue(context, user);
parser.parseExpression('Total: #{price * 2}', ParserContext.template).getValue(context);
```

Literals, inline lists/maps, properties, indexing, safe navigation (`?.`,
short-circuiting the chain), methods, variables and functions, `T(Type)`
statics, constructors, `@bean` references, selection/projection,
assignment and `++`/`--`, all operators (`div`, `between`, `matches`,
Elvis, ternary). Dart has no reflection: user classes are reached through
`@Introspected` metadata, `FunctionPropertyAccessor` / `FunctionMethodResolver`
or maps. `SimpleEvaluationContext` restricts expressions for data binding.

### Validation and data binding

```dart
@Introspected()
@PasswordsMatch()                   // class-level constraint
class SignupForm {
  @NotBlank() @Size(max: 20) String name = '';
  @NotNull() @Email() String? email;
  @Min(18) int age = 0;
  @Valid() Address address = Address();
}

final binder = DataBinder(form, objectName: 'signup')
  ..validators.add(BeanValidator(introspector: context.getBean<BeanIntrospector>()))
  ..bind({'name': 'Ada', 'age': '36'})
  ..validate();
binder.bindingResult.fieldError('age');   // typeMismatch / Min ... with Spring codes
```

Constraints: `NotNull`, `MustBeNull`, `NotEmpty`, `NotBlank`, `Size`, `Min`,
`Max`, `Positive(OrZero)`, `Negative(OrZero)`, `Matches` (`@Pattern`),
`Email`, `Digits`, `AssertTrue/False`, `PastDate`, `FutureDate` and
`...OrPresentDate`, groups, `@Valid` cascade, custom `Constraint`
subclasses. Error codes and arguments follow Spring
(`NotBlank.signup.name`, `NotBlank.name`, `NotBlank.String`, `NotBlank`), so
messages come from a `MessageSource`.

### AOP

```dart
@Aspect()
@Component()
@Order(1)
class Auditing {
  @Pointcut('execution(* Calculator.*(..))')
  void calculator() {}

  @Before('calculator()')
  void before(JoinPoint joinPoint) {}

  @AfterReturning('calculator()')
  void returned(JoinPoint joinPoint, int result) {}

  @Around('@annotation(Timed)')
  Object? time(ProceedingJoinPoint joinPoint) => joinPoint.proceed();
}
```

Pointcuts: `execution`, `within`, `target`, `bean`, `@annotation`,
`@within`, named pointcuts, `&&` `||` `!`. Type patterns use simple names
(Dart has no packages): `com.x.Service` means `Service`, and a qualified
wildcard such as `within(com.x.service..*)` is rejected instead of
silently matching every bean. Argument binding (`@annotation(timed)`) is not
supported yet and is rejected too. Annotations are matched by names the
generator writes, so `@annotation(Timed)` also works in minified/obfuscated
release builds. Advice order follows Spring
(aspect `@Order`, then around → before → after → afterReturning →
afterThrowing). Methods returning `Future` are advised when the future
completes. `PointcutAdvisor` beans work as well.

Proxies are generated classes that implement the bean class (when it has
no private members) and its interfaces, so they can be injected by either;
`AopUtils.getTarget` unwraps them.

### Logging

`SpringLog` is the logging facade (Spring's commons-logging / SLF4J): the
framework, starters and applications log through it; a backend such as
`spring_boot_starter_logging` decides where records go. Without one,
warnings and errors are printed.

```dart
const log = SpringLog('neon.checkout');

log.info('order placed', fields: {'order': 42});
log.debug(() => 'basket: ${basket.dump()}');   // built only if enabled
log.error('payment failed', error: e, stackTrace: s);

SpringLog.setLevel('neon.checkout', SpringLogLevel.debug); // and below
SpringLog.withFields({'request': id}, () => handle(request)); // like MDC
```

With Spring Boot, levels come from `logging.level.*` properties.

### Other extension points

`BeanFactoryPostProcessor` / `BeanDefinitionRegistryPostProcessor`,
`BeanPostProcessor`, custom scopes, hand-written `BeanDefinition`s and
`BeanModule`s, `registerSingleton`, `@Configurable` + `autowireBean` for
objects created elsewhere (e.g. Flutter `State`).

## Differences from Spring

| Spring | Here | Why |
|---|---|---|
| Reflection, runtime classpath scanning | `build_runner` code generation, `@ComponentScan` per directory | No reflection in Flutter/AOT |
| `PropertySource` class | `AbstractPropertySource` | `@PropertySource` is the annotation |
| `Scope` SPI, `Pointcut` interface | `CustomScope`, `AopPointcut` | `@Scope`, `@Pointcut` are the annotations |
| `@Null`, `@Pattern`, `@Past`, `@Future` | `MustBeNull`, `Matches`, `PastDate`, `FutureDate` (codes unchanged) | Clashes with Dart core types |
| `Validator.supports(Class)` | `supports(Object target)` | Dart cannot test subtypes on a `Type` |
| CGLIB `@Configuration` proxies | Call other `@Bean`s through parameters | No subclass proxies |
| CGLIB / JDK proxies | Generated `implements` proxies | Final or private-member classes are proxied through interfaces only |
| Circular references (opt-in) | Always an error | Same as Spring Boot's default |
| Asynchronous initialization | Synchronous `refresh()`; load config first with `processAndApply()` | Predictable startup |
| Package-qualified AOP type patterns, argument binding | Simple type names; qualified wildcards and binding are rejected | No packages in Dart; binding not implemented yet |
| Optional `@Value` with `${x:#{null}}` | A nullable target gets `null` when a placeholder is missing | Dart null safety |

## Roadmap

- Flutter library: bean builders, event listener widgets, `@Configurable`
  `State` injection, asset resources.
- Spring Web and a Boot starter with auto-configuration (`@ConditionalOn...`).
- Rust bridge over rinf: Dart beans in Rust and Rust beans in Dart.

## License

Apache License 2.0. Spring is a trademark of Broadcom Inc.; this project is
an independent port and is not affiliated with or endorsed by the Spring
team.
