## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs
- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- `Principal` (who acts, like `java.security.Principal`) moved here from `spring_web_dart`, which still exports it: the web layer and Spring Security share it without depending on each other.

## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds
- feat: spring_boot_starter_web, WebSocket server endpoints, uploads and downloads

## 0.3.1

- The example is a small Spring Boot application written by the generator (beans, `@Value`, SpEL, events) instead of hand-written bean definitions.
- README: loggers come from `@Log` (the logging section starts with it).

## 0.3.0

- feat(spring_boot_starter_flutter): themes from properties, free reads in Spring widgets

## 0.2.3

- add spring application handling
- docs(spring_boot_starter_flutter): add an example for pub.dev

## 0.2.2

- ci: run only the tests of the packages a change affects

## 0.2.1

- `@Log(topic:, fieldName:)`: a `log` getter generated for the class, like Lombok's `@Slf4j` (needs the matching generator)

## 0.2.0

- AOP: `MethodSignature.mergedAnnotations`: the annotations of the member and of every declaration it overrides or implements (superclasses, mixins, interfaces), most specific first, like Spring's `AnnotatedElementUtils` find semantics (`annotations` stays what `@annotation(...)` matches); method validation reads `@Validated` groups on a method from it, so those on an overridden superclass method apply (needs the matching `spring_core_dart_generator`)
- resources: `UrlResource.existsAsync()` sends a `HEAD` request (a `GET` when the server rejects `HEAD`), like Spring's `exists()`; config data (`spring.config.import=http://…`, its `-<profile>` variants, `optional:`) and `@PropertySource(ignoreResourceNotFound: true)` use it, so a 404 is a missing resource instead of a failed read
- `@Import` order per configuration class, like Spring's `ConfigurationClassParser` and `ConfigurationClassBeanDefinitionReader` (was per module): parsing (only parse-phase conditions count) loads a class's `@PropertySource`s and runs its `ImportSelector`s, whose modules are parsed at once (their `@PropertySource`s are visible to later parse-phase conditions) and whose classes are read before the importing class; the reader then goes class by class in parse order and decides each class once — skipped when every class importing it was skipped (Spring's `TrackedConditionEvaluator`), else by its `registerBean`-phase conditions — for the class, its `@Bean` methods and its imports alike: a kept class registers its `@Bean` methods (each one's own `registerBean`-phase conditions decided at that moment), then runs its registrars, so every later class sees their beans (a later `@ConditionalOnMissingBean` `@Bean` backs off for the beans of an earlier class's registrar); a skipped class registers nothing and runs no registrar, while its `@PropertySource`s still load; a class whose condition looks for the bean its imported class defines stays registered (one decision, cached per class key); a module selected by several classes is skipped only when all of them are, and no longer imported once registered directly; a class with `@Bean` methods or imports is a (lite) configuration class, decided in the reader like `@Configuration`, and so is any class-sourced definition (a scanned `@Component` or an `@Import`ed class) with a `registerBean`-phase condition, at its place in class order (Spring's lite configuration candidates; it was decided while parsing, so it missed earlier classes' `@Bean` and registrar beans); only a hand-written definition with neither a `source` nor a `factoryMethodName` is still decided at once; the condition evaluation report lists an outcome once per source; new `ImportDeclaration.importer` (the importing class, emitted by the matching `spring_core_dart_generator`)
- AOP: `MethodSignature.superclassAnnotations` (the annotations of each superclass and mixin of the class whose body runs for the member, nearest first) and `implementingTypeHierarchyAnnotations` (that class's, then those), the class hierarchy Spring's `AnnotationUtils.findAnnotation` searches (needs the matching `spring_core_dart_generator`)
- events: lazy `GenericApplicationListener` / `SmartApplicationListener` beans (`@Lazy`, `spring.main.lazy-initialization`) are created by the first event and receive it (they never received events); the `applicationListeners` doc says which listeners it lists
- logging: `SpringLog.hold()` / `SpringLogHold.release()` hold back every record (any level) and emit those that pass the levels of release time, like Boot's `DeferredLog`
- AOP: an `Advisor` registered with `registerSingleton` (e.g. by a `BeanFactoryPostProcessor`) is applied; it is found by instance, like Spring's `getBeanNamesForType(Advisor.class)` (was never applied)
- AOP: a call through a `@Lazy` reference to a bean that is a subclass proxy is advised also while the bean's own code runs (`@Lazy` self-injection, as in Spring); it was skipped like a `this.` call
- AOP: an unbound `this(Type)` matches the interfaces `@DeclareParents` adds to the proxy (new `introducedTypes:` on `pointcutMatchesBean`, `ExpressionPointcut.matchesBean` / `bind` and `ComposablePointcut.matchesBean`; `ProxyInvoker.introducedTypes`)
- AOP: an `execution(...)` return type pattern may have type arguments with spaces (`Map<String, int>`) and be a negated group (`!(String || int)`); both were rejected
- breaking: SpEL safe navigation follows Spring 7's `CompoundExpression`: a `?.` step on `null` gives `null` and the chain goes on, so `a?.b.c` with a `null` `a` fails with EL1007E on `.c` (was `null`); write `a?.b?.c`
- SpEL: inline lists and maps of literals are unmodifiable, like Spring's (`{1, 2}.add(3)` throws; `{1, 1 + 1}` is still a new mutable list)
- SpEL: the AST's `toString()` is Spring's `toStringAST` (`(a > b)`, `a?.b`, `a[0]`, `-x`, `!a`, `(a ? b : c)`, `(a ?: b)`; was `(a gt b)`, `a.b`, `a.[0]`, `minus(x)`)
- SpEL: a negative index reports the size (`EL1025E: The collection has '2' elements, index '-1' is invalid`, was `'?'`; EL1026E for strings)
- SpEL on the web: real literals keep their kind in `instanceof` (`2.0 instanceof T(Integer)` and `2 instanceof T(Double)` are false), and `T(String).valueOf` / `format` / `join`, `'...'.formatted(...)` and `{2.0}.toString()` print them like Java (`2.0`, `[2.0]`)
- JSON: an enum with an int `@JsonValue` is read by value (`20` or `"20"`), never by index, and an unmatched number fails (Jackson's `isFromIntValue`); other enums also accept an index as a string (`"1"`)
- JSON: a map key of a class with `@JsonValue` is written as that value (was `Instance of ...`)
- JSON: a negative `Duration` is written like Java's `Duration.toString` (`PT-1M-30S`, `PT-0.5S`; was `-PT1M30S`)
- JSON: a read-only (`access: readOnly`) property that a constructor requires is reported as such (was "missing property" although present)
- breaking: `JsonNode` follows Jackson 3: `NullNode` and `MissingNode` are not equal; `intValue()` throws for a fraction, NaN or infinity; `asString()`, `asInt()`, `asDouble()` and `asBoolean()` without a default throw a `JsonNodeException` for what cannot be converted (`"abc"` or `"1.5"` for `asInt()`, objects and arrays), with a default return it (the parameters are nullable now); `asString()` of `null` and a missing node is `''` (was `'null'`)
- beans: a `BeanWrapper` write past the end of a list fills the gap with `null`, like Spring (`tags[1]` into an empty `List<String?>` gives `[null, t]`), also without `autoGrowNestedPaths`; a list that cannot hold `null` gets, with `autoGrowNestedPaths` (on in `DataBinder`), the element type's empty value (`tags[2]` into a `List<String>` gives `['', '', z]`, `''` being Spring's `new String()`; new introspected objects, lists, sets, maps), else fails with Spring's "List does not support filling up gaps with null elements" (`List<int>`), which `DataBinder` no longer reports as a `typeMismatch` of the bound value; auto-growing a nested path through a `String` creates `''`
- validation: `DataBinder.construct` keeps list elements at their index (`tags[1]` alone gives `[null, t]`; was `[t]`); for non-nullable elements a gap is a `typeMismatch` error (`tags[0]`)
- validation: `DataBinder.construct` pads a list only below `autoGrowCollectionLimit` (256), like Spring's `createList`: a higher index (`notes[50000000]`) throws an `InvalidPropertyException` before anything is allocated (it allocated a list up to that index)
- config data: `spring.config.activate.on-cloud-platform` documents are active only on that platform (they were always active); new `CloudPlatform` (Boot's: Kubernetes from `KUBERNETES_SERVICE_HOST` / `_PORT` or any `*_SERVICE_HOST` + `*_SERVICE_PORT`, Heroku `DYNO`, Cloud Foundry `VCAP_APPLICATION` / `VCAP_SERVICES`, SAP, Nomad, Azure App Service, Amazon ECS), `spring.main.cloud-platform` enforces one or `none`
- conversion: a single value converts to a one-element `List` / `Set` (`ObjectToCollectionConverter`); `Map` → `Map<K, V>` (new `ConverterRegistry.addMapConverters<K, V>()`, defaults for `Map<String, V>`); `String` ↔ `Encoding`; `BigInt` → `int` (failing on overflow) / `double`, `num` → `BigInt`; an enum converts to its name (`red`, was `Color.red`), also in `${...}` placeholders; `addEnum` adds the `List<E>` / `Set<E>` converters
- resources: `http:` / `https:` locations are a new `UrlResource` (read asynchronously; was a missing resource); embedded classpath resources have a `filename` and `createRelative`
- `@PropertySource` locations with a pattern (`file:conf/*.properties`, `classpath*:`) load every match, none being fine (Spring 6.1)
- YAML integers beyond `int` are `BigInt` (were doubles)
- events: `EventListenerMethod(resultType:)` / `EventResultType<R>`: listener results are published as their declared type, so `PayloadApplicationEvent<R>` listeners get them (needs the matching `spring_core_dart_generator`)
- `ConfigurableApplicationContext.applicationListeners` (Spring's `getApplicationListeners`); `ConfigurableBeanFactory.registerAlias`
- `ReloadableResourceBundleMessageSource.defaultEncoding`
- `DynamicType.forVoid()` / `DynamicType.isVoid`: a `void` type argument (`ResponseEntity<void>`), so a handler can ignore the value.
- AOP: a generated subclass proxy no longer advises the calls the bean makes on itself (Spring: `[outer]`, was `[outer, inner]`): while one of its advised members runs (zone-aware for `Future` / `FutureOr` members), calls on the bean go straight to its code; `AopContext.currentProxy()` advises the one call made right after it
- AOP: `@DeclareParents` on subclass proxies (`AopProxyFactory.subclass(introductions:)`, `ProxyInvoker.notIntroduced`; needs the matching `spring_core_dart_generator`)
- AOP: `execution(...)` return and parameter type patterns: qualified names (`java.lang.String`), `Object+` (and `num+`, `Iterable+`, `Pattern+`), `!Type`, parenthesized `&&` / `||` (`(String || int)`), type arguments with spaces; `String||int` without parentheses and `Type+` of other types are errors with the reason
- AOP: new `AnnotationPointcut` marker for pointcuts that match by annotation (`AnnotationMatchingPointcut` and `MethodValidationPostProcessor.pointcut` are ones); the build keeps proxy pruning on for starters whose advisor beans use one
- SpEL on the web: integral doubles stay real through selection, projection, `#this`, `@Introspected` properties declared `double`, map entries SpEL built and `new Double(2)`; `2.0.toString()` is `'2.0'`; integer literals beyond 64 bits (`99999999999999999999`) fail with EL1035E there too
- SpEL: `{2.0} == {2}` is `false` like Java's `List.equals` (also maps and sets); `T(Objects)` (`isNull`, `requireNonNull`, `hash`, ...), `T(System)` (`currentTimeMillis`, `nanoTime`, `getenv`; `getProperty` gives its default), `new StringBuilder()` / `StringBuffer` (Dart's `StringBuffer` with Java's methods); a failed element write names the element type (`String` to `int`, was `List<int>`); new `ExpressionState.activeContextObjectIsReal` / `scopeRootIsReal` and `real:` on `pushActive` / `pushScope` / `withThis`
- SpEL: `StandardEvaluationContext` and `SimpleEvaluationContext` read the properties (and, `withInstanceMethods()`, the methods) of `@Introspected` classes of `BeanIntrospector.shared` by default
- JSON: enums without an `EnumType` at hand (`readValue<Color>`, `readList`, `readMap`, top-level values, `Object?` properties, map values and keys) use the one registered for the enum, so `@JsonValue` applies; introspections register the enums they use (new `BeanIntrospector.registerEnum`, `enumTypeFor`, `enumTypeOf`); an unknown enum is a clear error
- JSON: an unknown type id falls back to `@JsonTypeInfo(defaultImpl:)` like Jackson; `@JsonValue` on class properties, getters and methods (the object is written as that value, read back through a one-parameter constructor); `@JsonProperty` on enum constants; `JsonProperty(name, access: JsonPropertyAccess.readOnly / writeOnly, required: true)` (an empty name keeps the default one); reading a bounded generic class with type arguments is a clear error
- JSON: `DeserializationFeature.failOnNullForPrimitives` (`ObjectMapper(failOnNullForPrimitives:)`, on like Jackson 3): off reads a JSON `null` or missing constructor value for a non-nullable `int`, `double`, `num` or `bool` as `0` / `false`; `JsonNode.hashCode` no longer depends on the key order
- validation: `{jakarta.validation.constraints.X.message}` resolves to Hibernate's default messages without a message source; `\{`, `\}`, `\$` and `\\` are literal characters in messages (also `Constraint.interpolate`)
- `@Lookup([beanName])` (lookup method injection): every call of the method returns a bean of the container, by return type (`findBean` for a nullable type) or by name; an abstract `@Component` class with `@Lookup` methods is a bean; methods with parameters are not supported (needs the matching `spring_core_dart_generator`)
- beans: `create` may return `null` (a `@Bean` method declared `T?`): the bean is a `NullBean`, like Spring's: `getBeanByName` returns it, `getBean<T>()` and required injection points fail with `NoSuchBeanDefinitionException`, `findBean<T>()` and optional points get `null`, collections, `getBeansOfType` and providers leave it out, and it is neither post-processed, initialized nor destroyed; `NullBean.orNull` for inter-bean calls

- AOP: `within(Type)` / `@within(A)` match the class whose body runs (an inherited method is within its superclass, AspectJ's lexical scope); `@target` keeps the bean class; new `MethodSignature.implementingTypes`, `implementingTypeAnnotations`, `implementingTypeAnnotationTypes` (needs the matching `spring_core_dart_generator`)
- AOP: `args(Type)` tests the runtime argument (`ExpressionPointcut(typeTests:)`, `AspectMetadata.typeTests`); `@args(Annotation)` / `@args(name)` (`argumentAnnotations:`); `this(t)` / `target(t)` bound to `Object` (or a type only the proxy has) are decided by the parameter's type check per call instead of never matching
- AOP: `execution(public|protected|private ...)` (`protected`: `@protected` members, `MethodSignature.isProtected`); a `throws` clause is rejected with the reason (Dart declares no exceptions)
- AOP: `@Aspect('perthis(...)')` / `'pertarget(...)'` (`AspectMetadata.perClause`): one prototype aspect instance per proxy / target; a singleton per-instance aspect and `percflow` / `pertypewithin` fail with `AopConfigException`, as in Spring
- AOP: `@DeclareParents(value, defaultImpl:)` introductions: `Introduction`, `AopProxyFactory(introductions:)`, `ProxyInvoker.introduction(index)`; a registered declaring aspect proxies matching beans
- AOP: `ComposablePointcut` (`union` / `intersection`), `pointcutMatchesBean`; `ProxyFactory` / `AspectJProxyFactory` (`forBean`, `addAdvice`, `addAdvisor`, `addAspect`, `getProxy`)
- breaking: `Advised` has `addAdvisor`, `removeAdvisor`, `addAdvice`, `removeAdvice` (also on `ProxyInvoker`, whose `advisors` is a live view; `ProxyInvoker.notAdvised` for unadvised subclass proxies); `Aspect` takes an optional per-clause; `AspectAdviceInterceptor.aspect` is replaced by `aspectFor(invocation)` (new `AspectAdviceInterceptor.forInvocation`). Generated proxies need the matching `spring_core_dart_generator`
- breaking: JSON timestamps follow Jackson 3: `writeDatesAsTimestamps` writes epoch seconds with the fraction (`1700000000.123456`; milliseconds with `writeDateTimestampsAsNanoseconds: false`), integer timestamps read as seconds (`readDateTimestampsAsNanoseconds`), decimals always as seconds; durations have their own `writeDurationsAsTimestamps` (seconds)
- JSON reading: out-of-range integers fail (`readValue<int>('1e20')`) instead of saturating; a fraction into an `int` truncates (`acceptFloatAsInt`, Jackson's `ACCEPT_FLOAT_AS_INT`); `""` is `null` for nullable scalars; date strings are parsed strictly and read in the mapper's time zone (UTC) when they have no offset; enum map keys use `@JsonValue`; enums also read by index; on the web infinities are written as strings
- JSON: generic `@Introspected` classes (`GenericType<Page<Book>>`), `@JsonTypeInfo` / `@JsonSubTypes` / `@JsonTypeName`, `@JsonAlias`, `@JsonFormat`, `@JsonAnyGetter` / `@JsonAnySetter`, `@JsonUnwrapped`, `@JsonNaming`, `@JsonView` (`writerWithView` / `readerWithView`), `JsonInclusion.nonAbsent` / `nonDefault`, the `JsonNode` tree model (`readTree`), `JsonMapper.builder()` / `rebuild()` with Jackson's feature enums
- container (Spring 7): a destroyed `ApplicationListener` bean leaves the multicaster (new `removeApplicationListeners(predicate)`); jakarta `@Priority` (`package:spring_core_dart/jakarta.dart`) in candidate selection (after primary, lowest value wins, a tie is a `NoUniqueBeanDefinitionException`) and ordering (after `Ordered` / `@Order`); `SmartFactoryBean.supportsType` / `getObjectForType`; `ScopeNotActiveException` (an inactive scope is missing for `getIfAvailable` / `getIfUnique` / `ifAvailable`); the default `lifecycleProcessor` singleton; `ApplicationContextException` when a lifecycle bean fails to start (was the bean's error); a dangling alias blocking a definition is a `BeanDefinitionStoreException`; `DeferredImportSelector` (after every module, by order); `ConfigurationCondition` / `ConfigurationPhase` (register-bean conditions of `@Bean` / `@Configuration` definitions are decided once everything is loaded)
- validation: `DataBinder.allowedFields = []` allows every field (Spring: empty means all); invalid constraint attributes (`Size(min: -1)`, min > max, negative `Digits`, a malformed `DecimalMin` / `DecimalMax` value or regex) throw `ConstraintDeclarationException` (new `Constraint.checkParameters()`); a built-in constraint on a value type it cannot check throws `UnexpectedTypeException` (new `Constraint.supports(value)`)
- validation: `@Valid` on a `Set` reports `lucky[].city`; `@GroupSequence` on a class redefines its default group and `BeanValidator(groupSequences:)` declares sequence groups (validation stops at the first group with a violation; `GroupDefinitionException` for invalid sequences); `@ConvertGroup`; container element constraints `@Each([...])` (iterable elements, map values) and `@EachKey([...])` with Hibernate's paths (`names[1].<list element>`); `${validatedValue}` in messages
- events: `@EventListener` methods are registered once the eager singletons exist, before the `SmartInitializingSingleton` callbacks (Spring's `EventListenerMethodProcessor`), so an event published from a `@PostConstruct` while a listener bean is being created no longer fails the refresh with `BeanCurrentlyInCreationException`; like Spring, such startup events do not reach `@EventListener` methods (`ApplicationListener` beans still get them)
- beans: `SmartInitializingSingleton` callbacks run in bean definition order (was creation order); new `DefaultListableBeanFactory.addSingletonsInstantiatedCallback`
- beans: `@PostConstruct` runs at the place of Spring's `CommonAnnotationBeanPostProcessor` (new, `PriorityOrdered`, order `lowestPrecedence - 3`, registered by the context): after the `postProcessBeforeInitialization` of the `PriorityOrdered` processors before it, before the `Ordered` and plain ones; `afterPropertiesSet` and init methods still run after all of them
- beans: `InstantiationAwareBeanPostProcessor` (`postProcessBeforeInstantiation` short-circuit, `postProcessAfterInstantiation`, `postProcessProperties`), `SmartInstantiationAwareBeanPostProcessor.predictBeanType` (answers `getType`) and `MergedBeanDefinitionPostProcessor` (`postProcessMergedBeanDefinition` once per definition, `resetBeanDefinition` when it is replaced or removed)
- context: each `registerBean` / `BeanRegistry.registerBean` call is its own definition source, so two beans of one name are an override (or `BeanDefinitionOverrideException`) instead of the second being dropped silently
- lifecycle: a `SmartLifecycle` bean asked to start while its `stopWithCallback` callback is still pending (`restart()`, `start()` right after `stop()`) is started when the callback fires instead of ending up stopped
- breaking: `registerShutdownHook()` closes with `closeAsync()` before ending the process, so asynchronous `SmartLifecycle` stops and `@PreDestroy` callbacks finish
- SpEL: arguments of registered functions, String / List / Map built-ins, `T()` static methods and constructors are converted to the parameter types through the context's `TypeConverter` (Spring's `convertAllArguments`): `#half(3)` with a `double` parameter, `'abc'.substring('1')`, `'abc'.charAt(1.0)`, `T(Math).max('1', 2)`; new `VarargsFunction.convertArguments`
- SpEL: booleans are comparable (`true > false`, Java's `Boolean` is `Comparable`); `T(Math).rint` rounds ties to even like Java; on the web real literals in inline lists, maps and arrays (`{1.0, 2.0}[0] / 2`, `new double[]{1, 2}`) stay real when indexed
- `MessageFormat`: `{0,date}` / `{0,time}` with Java's styles (`short`, `medium` by default, `long`, `full`, US English) and `SimpleDateFormat` patterns (`{0,date,yyyy-MM-dd}`); a date without a type is Java's short date-time (`10/20/26, 9:05 AM`, was ISO); malformed elements throw even when their argument is missing or of another type (unknown types, bad number / date / choice patterns, like `applyPattern`)
- programmatic registration like Spring 7: `BeanRegistrar` / `BeanRegistry.registerBean<T>(supplier, name:, scope:, lazy:, primary:, fallback:, order:, description:, ...)` (unnamed beans are `T#0`), `ImportSelector` (returns `BeanModule`s) and `ImportBeanDefinitionRegistrar`, run while the modules load, through `@Import` (`BeanModule.registrars`, `ImportDeclaration`; needs the matching `spring_core_dart_generator`) or `context.register(...)`; `AnnotationConfigApplicationContext.registerBean<T>(...)`
- breaking: `ConfigurableApplicationContext.register` takes an `Object` (a `BeanModule`, `BeanRegistrar`, `ImportSelector` or `ImportBeanDefinitionRegistrar`; anything else is an `ArgumentError`); registering after `refresh()` fails with a `StateError` naming the context and what to do
- asynchronous events: `SimpleApplicationEventMulticaster(taskExecutor:)` calls the listeners on a `TaskExecutor` (new `TaskExecutor`, `SyncTaskExecutor`, `SimpleAsyncTaskExecutor`); `@Async([executor])` on `@EventListener` methods runs them on a `TaskExecutor` bean (switched on by having one, like `@EnableAsync`; `EventListenerMethod(async:)`)
- breaking: `EventListenerMethod.supports` checks the event type only; the new `shouldHandle` checks the condition, inside the multicaster's error handling (Spring's `ApplicationListenerMethodAdapter`), so a failing condition reaches the `errorHandler`
- lifecycle: a created singleton that is a `Lifecycle` is started and stopped even when its declared type is not (Spring matches the singleton's instance)
- post-processors are created in Spring's phases (`PriorityOrdered`, `Ordered`, rest), each after the previous one ran, re-querying the names before each phase; a bean created while the `BeanPostProcessor`s are registered is logged at info level, like Spring's `BeanPostProcessorChecker`
- `EmbeddedValueResolverAware` resolves `#{...}` SpEL after `${...}` placeholders (Spring's `EmbeddedValueResolver`)
- beans: scoped proxies like Spring's `ScopedProxyMode`: `@Scope('session', proxyMode: ScopedProxyMode.targetClass)` (or `interfaces`) and `BeanDefinition(scopedProxy:)` inject one proxy that asks the scope for the current instance on every call (no warning for singletons holding it; no graph edge, so it breaks cycles); generated by `spring_core_dart_generator` from the `@Lazy` proxy class
- new `package:spring_core_dart/jakarta.dart` (kept out of the main library: the names clash with `package:provider` and the core `Resource`): JSR-330 `Provider<T>` injection points get the lazy provider (`ObjectProvider` implements `Provider`, `get()`), and JSR-250 `@Resource` on fields and setters injects by bean name (the member name falling back to the type, or exactly `name:`), like Spring's `CommonAnnotationBeanPostProcessor`; `DependencyResolver.resource` / `optionalResource`, `Dependency.resource`
- breaking: `DependencyKind` has `resource`, `Dependency` has `fallbackToType`; `ObjectProvider` has `get()`; `DependencyResolver` has `resource()` / `optionalResource()`
- beans: a collection injection point whose only candidates are the configuration's own `@Bean` products gets them (Spring's final self-reference pass), never the configuration itself; before it got none
- beans: `FactoryBean.objectType` (Spring's `getObjectType()`, `T` by default): a `FactoryBean` given to `registerSingleton` is found by its product type (`getBean<T>()`, `getBeanNamesForType`, `isTypeMatch`, `getType`)
- `context.pause()` / `pauseAsync()` / `restart()` with `ContextPausedEvent` (a `ContextStoppedEvent`) and `ContextRestartedEvent` (a `ContextStartedEvent`) and `SmartLifecycle.isPauseable` (default `true`), like Spring 7: pause stops the running lifecycle beans except non-pauseable smart ones, restart stops the pauseable ones if running and starts the auto-startup beans again
- breaking: `LifecycleProcessor` has `onPause()`, `onPauseAsync()` and `onRestart()`; `ConfigurableApplicationContext` has `pause()`, `pauseAsync()`, `restart()` and `registerShutdownHook()`
- `context.registerShutdownHook()`: SIGINT / SIGTERM close the context and end the process with `130` / `143` (once per context, released on close, a no-op without `dart:io`), like Spring's `registerShutdownHook()`
- template hooks on `AnnotationConfigApplicationContext`, like Spring's: `postProcessBeanFactory(beanFactory)` after the modules are loaded, `onRefresh()` before the listeners and eager singletons, `onClose()` last in `close()` / `closeAsync()`
- breaking: `ApplicationEventPublisher.publishEvent` is generic (`publishEvent<T extends Object>(T event)`); a payload is wrapped in a `PayloadApplicationEvent<T>` of its static type (was `PayloadApplicationEvent<Object>`), so listeners of `PayloadApplicationEvent<T>` receive it; new `EventListenerMethod.forPayload<B, P>` matches on the payload's runtime type (used by the generator); `PayloadApplicationEvent` takes an optional `timestamp`
- events: `@EventListener` methods of a `FactoryBean` are invoked on the factory (`&name`), not on its product
- breaking: `ConditionContext` has `definition`, the `BeanDefinition` whose conditions are evaluated (Spring's `AnnotatedTypeMetadata`; `null` for `@PropertySource` conditions)
- breaking: a child context's `messageSource` falls back to the parent's message source instead of the parent context (Spring's `getInternalParentMessageSource`); a `conversionService` bean of an ancestor context is used for `@Value` conversion when the child has none
- AOP: a pointcut syntax error (`FormatException`) carries the character position (`offset`) of the designator or token at fault
- `@Autowired(required: false)` on constructors: several such constructors are candidates and the one with the most parameters whose beans exist is used, like Spring (needs the matching `spring_core_dart_generator`)
- config data: placeholders in a file's `spring.config.import` and on-profile guard resolve against the command line and environment before the file's own values (Boot's contributor order); an unresolvable placeholder in an `optional:` import skips it instead of failing
- config data: lists bind like Boot's binder: indexed keys from every source (`SPRING_PROFILES_INCLUDE_0_`), and the highest source with a list wins whole (`--spring.profiles.active[0]=x` replaces a file's list instead of merging item by item)
- config data: a non-optional wildcard location (`file:./config/*/`) without subdirectories fails with `ConfigDataLocationNotFoundException` (`contains no subdirectories`), like Boot; the exception has an optional `reason`
- `RandomValuePropertySource` (`${random.int}`, `random.int(10)`, `random.int[5,10]`, `random.long`, `random.uuid`, `random.value`), like Boot's
- breaking: `PropertySourceLoader` is an abstract class with an `encoding` (UTF-8 by default): implement it with `extends`; `PropertiesPropertySourceLoader(encoding: latin1)` reads ISO-8859-1 config files
- breaking: `PropertySourceFactory.createPropertySource` takes an `EncodedResource` (new, like Spring's) instead of a `Resource`; `@PropertySource(encoding: 'ISO-8859-1')` / `PropertySourceDeclaration.encoding` / `processPropertySource(encoding:)`; `PropertiesLoaderUtils` and `ResourcePropertySource` take an `encoding`
- async `@PropertySource`: `refreshAsync()` reads async-only resources (Flutter assets behind a `ProtocolResolver`) first through the new `PropertySourceProcessor.preload`; a synchronous refresh names the problem instead of failing in the factory
- resources: `package:` URIs resolve to the package's files (VM with a package config); `file:` URLs are percent-decoded (`FileSystemResource.fromFileUrl`); `FileSystemResource` of a directory exists but is not readable (`isDirectory`), like Spring's
- breaking: `PathMatchingResourcePatternResolver` follows Spring for classpath patterns: `classpath*:` (new) searches every classpath root and resolves non-patterns in each, `classpath:` patterns search only the first root with the base directory (was: every root); matching directories are returned and the walk skips directories the pattern cannot match; `ClasspathResources.resolveEmbedded`
- `AntPathMatcher.extractUriTemplateVariables` no longer fails on paths where a `**` search backtracks (a failed attempt left its variables behind)
- placeholders follow Spring 6.2's parser: `${a:b}` is first looked up as the key `a:b`; an unclosed `${` is text and later placeholders still resolve (`${a ${b}`)
- SpEL: Java's int/double semantics also on the web: real values are tracked through literals, operators, `?:`, ternaries, assignments and `T(Math)` / `T(Double)` functions (`7.0 / 2` is `3.5`, `'x' + 7.0` is `x7.0`)
- breaking: SpEL `^` on integers follows Spring 7's `OpPower` (a long above `Integer.MAX_VALUE`, else an `int` cast that saturates at `Integer.MIN_VALUE`: `(-2) ^ 33` is `-2147483648`); `==` on numbers uses Java's double semantics (`NaN != NaN`, `0.0 == -0.0`); integer `/ 0` and `% 0` throw `UnsupportedError('/ by zero')` on the VM and the web
- breaking: SpEL selection `.?[...]` on a list or set returns a list with the source's element type (`List<int>` from a `List<int>`), not `List<Object?>`
- SpEL: `T(Character)` / `char` (`new char[2]`), `new Integer(5)` / `Long` / `Double` / `Boolean`, `T(String).format` and `'...'.formatted(...)` (Java's format syntax), `getBytes()`, `chars()`, `List.removeAll` / `retainAll` / `sort(null)`
- config data: profile groups expand depth-first like Boot's `Profiles` (a listed member moves right after its group); `spring.config.on-not-found=ignore`; extension hints (`file:./conf[.yml]`); `configtree:` imports (`ConfigDataEnvironment.configTreePrefix`); a location without a known extension (such as a directory without a trailing `/`) fails with Boot's message
- breaking: `ConfigurationPropertyName` rejects `a..b` and `a.[0]` (empty elements), like Boot
- `@PropertySource` files are added above `defaultProperties`, which stays the last source (Boot's `PropertySourceOrderingBeanFactoryPostProcessor`)
- `ReloadableResourceBundleMessageSource.cacheMillis` (Spring's `setCacheMillis`); `cacheSeconds` is stored in it
- conditions: `ConditionEvaluation` / `ConditionEvaluationRecorder`; `AnnotationConfigApplicationContext.conditionEvaluations` lists every condition outcome of the last refresh (for Boot's condition evaluation report)
- breaking: `ConversionService.canConvertType<S>(Type)` (Spring's `canConvert(Class, Class)`); `num` → `int` truncates like Spring's `NumberUtils` (`1.9` is `1`; NaN and infinity fail), so SpEL `list[1.5]` is `list[1]`
- `DataSize` / `DataUnit` (Spring's, `10MB`, `512KB`) with conversions from strings and ints; `ChronoUnit` and `DurationStyle.parse(unit:)` for numbers without a unit

## 0.1.7

- `@ComponentScan(includeFilters:, excludeFilters:, useDefaultFilters:, lazyInit:)` with `Filter` / `FilterType` (`annotation`, `assignableType`, `regex`), like Spring's `@ComponentScan.Filter`; read by the generator at build time (needs the matching `spring_core_dart_generator`)
- AOP: `ExpressionPointcut` rejects a binding the expression never uses (an advice parameter the pointcut does not bind), like AspectJ's "formal unbound in pointcut", instead of passing `null` to the advice
- `refreshAsync()` / `closeAsync()` on the context (and `ApplicationContext.runAsync`): `@PostConstruct`, `afterPropertiesSet`, init methods, `@PreDestroy`, `DisposableBean.destroy` and destroy methods may return a `Future`, awaited there (each bean's callbacks in order, the bean injectable meanwhile; `refresh()` fails for an asynchronous init callback, `close()` logs an asynchronous destroy callback and goes on); `closeAsync()` waits for `SmartLifecycle.stopWithCallback` per phase, at most `DefaultLifecycleProcessor.timeoutPerShutdownPhase` (10 s) / `timeoutsForShutdownPhases`, logging the beans still running, like Spring
- breaking: `InitializingBean.afterPropertiesSet` and `DisposableBean.destroy` return `FutureOr<void>` (a `void` override still compiles); `BeanDefinition` init/destroy callbacks are `FutureOr<void> Function(T)`; `LifecycleProcessor` has `onCloseAsync()`; `ConfigurableListableBeanFactory` has `preInstantiateSingletonsAsync()` / `destroySingletonsAsync()`
- lifecycle: a bean's dependencies start before it and its dependents stop before it, whatever the phase (Spring's `doStart` / `doStop`); a plain `Lifecycle` dependency of an auto-startup bean starts at refresh; a failed refresh stops the beans started so far
- events: `GenericApplicationListener` beans (also behind another declared type) and listener objects given to `registerSingleton` receive events (Spring's `ApplicationListenerDetector`; a non-singleton one is warned about), each registered once; new `SmartApplicationListener` mixin; a `Future`-returning `@EventListener` publishes its value when it completes and routes an error to the multicaster's error handler (else logs it)
- breaking: early events are replayed when the listeners are registered (after the bean factory post-processors), like Spring's `registerListeners`, and events published while the singletons are created reach the listeners right away (a listener bean may be created early for it); they arrived after all eager singletons before
- breaking: `validateBeanGraph()` (so `refresh()`) reports a missing or ambiguous dependency as an `UnsatisfiedDependencyException` naming the bean and the injection point, with the `NoSuchBeanDefinitionException` / `NoUniqueBeanDefinitionException` as its `cause`, like a failure while the bean is created; missing `dependsOn` beans and cycles are reported as before
- beans: an injection point that fails while its bean is created (no bean, several candidates, a dependency that fails to create) is an `UnsatisfiedDependencyException` with the bean, the point (`Greeter 'greeter'`, `collection of Greeter('x')`) and the lookup error or the nested bean's failure as `cause`
- beans: aliases from `registerAlias` match `@Qualifier` and parameter names; `autowireCandidate: false` beans are excluded from qualified injection too but still found by `getBean` (by name, or as the only bean of their type)
- beans: `Set` and `Map` injection keep registration order (only lists are sorted); an `@Order` on a `@Bean` method beats the bean's `Ordered.order`, an `@Order` on its class does not
- config data: `spring.config.import` from the command line / `SPRING_CONFIG_IMPORT` (above every location); directory imports (`file:./config/` loads `application*` files); imported files get their `-{profile}` variants; new `ConfigDataLocationNotFoundException`
- breaking: a non-optional directory location that does not exist (`spring.config.location`, `spring.config.import`) fails like Boot's `ConfigDataLocationNotFoundException`; an existing directory without config files is fine
- breaking: profiles follow Boot's `Profiles` rules: programmatic active profiles are kept and merged with a file's `spring.profiles.active` (they replaced it before); `spring.profiles.include` is collected from the highest-precedence source first; `spring.profiles.default` from config files, the command line or the environment selects the profile-specific files (groups expanded) and is set on the environment; `ConfigDataEnvironment(additionalProfiles:)` adds profiles first
- config data: a `defaultProperties` source (`ConfigDataEnvironment.defaultPropertiesSourceName`) stays below the config files, as in Boot
- `@Value` to `Resource` goes through the context's resource loader (protocol resolvers, asset loaders), like Spring's `ResourceEditor`: `DefaultListableBeanFactory.resourceLoader`, set by the context
- SpEL limits like Spring 7: `SpelParserConfiguration.builder()` with `maximumExpressionLength` (10 000), `maximumNestingDepth` (1000), `maximumOperations` (10 000 per evaluation, `SpelMessage.maxOperationsExceeded`, default from `-Dspring.expression.maxOperations`), `autoGrowNullReferences` / `autoGrowCollections` / `maximumAutoGrowSize`; `'x' * n` over 256 characters, string `+` over 100 000 characters and `matches` patterns over 1000 characters or with nested quantifiers (`(a+)+`, `SpelMessage.flawedPattern`) are errors
- SpEL in `@Value`: `systemEnvironment`, `systemProperties` (the `--key=value` command-line arguments of the `environment` bean, as Dart has no system properties), `environment['a.b']`, `environment.getProperty('a.b', 'default')` and the other `Environment` methods; the factory's `ConversionService` converts (looked up at each conversion through `StandardTypeConverter.lazy`, Spring's supplier constructor), parsed expressions are cached per resolver, `-Dspring.context.expression.maxLength` sets the `@Value` length limit
- breaking: SpEL exceptions follow Spring: `ExpressionException` → `ParseException` / `EvaluationException` → `SpelParseException` / `SpelEvaluationException` with `messageCode`, `simpleMessage` (`EL1070E: ...`), `position` and the expression (`message` is `Expression [1 + * 2] @4: EL1070E: ...`); accessors and resolvers report failures with `AccessException`; an exception thrown by a user method or constructor propagates unwrapped; safe navigation is Spring 6.2's (a `null` before a `?.` step ends the whole chain, also for `?.[i]`, `?.?[]`, `?.![]`, `?.^[]`, `?.$[]`)
- breaking: `@Configuration({name, proxyBeanMethods = true})` (the name is a named argument now): full mode by default, the generated subclass makes inter-bean `@Bean` method calls return the container's beans; `proxyBeanMethods: false` keeps the methods as written (needs the matching `spring_core_dart_generator`)
- config data: YAML out of the box (`YamlPropertySourceLoader` on `package:yaml`, flattened like Boot: `a.b`, `a.hosts[0]`, `a.servers[0].name`, `~` / empty as `''`); `application.yml` / `.yaml`, profile variants, `---` documents and YAML lists for `spring.config.import`, `spring.profiles.include` / `active` / `group.*` and `on-profile`; invalid files fail with a `ConfigDataLoadException`
- breaking: config locations come in Boot's groups (`,` separates groups, `;` joins locations into one); `defaultSearchLocations` is `optional:classpath:/;optional:classpath:/config/` and `optional:file:./;optional:file:./config/;optional:file:./config/*/`, so external non-profile files beat packaged profile files; `ConfigDataEnvironment(defaultLocations:)` entries are groups
- breaking: in one location `.properties` beats `.yml` / `.yaml` (an earlier loader's files win, like Boot's; they lost before)
- config data: `*/` wildcard locations (`file:./config/*/`, `file:./etc/*/app.properties`): each subdirectory in alphabetical order, `..x` ones skipped; classpath wildcards are rejected
- relaxed names like Boot's attached `ConfigurationPropertySources` (attached by `ConfigDataEnvironment`): `getProperty('app.read-timeout')`, `${app.read-timeout}` and `@Value` find `app.readTimeout`, `app.read_timeout`, `APP_READTIMEOUT`, `APP_HOSTS_0_`; precedence decides, not the form. New `ConfigurationPropertyName`; breaking: the environment's first property source is now `configurationProperties`
- AOP: `Type+` subtype patterns in `within` / `execution`, `@target`, `this`, `args(...)`; `bean()` also matches aliases and qualifier values
- AOP: named pointcuts resolved per aspect (`orders()` in its own aspect, `AuditAspect.orders()` for another's)
- AOP: aspects ordered by `Ordered` as well as `@Order`; plain `Advisor` beans; aspects and advisors of parent contexts apply
- AOP: `AopContext.currentProxy()`; the auto proxy creator runs first among ordered post-processors (later post-processors see the proxy)
- AOP: `JoinPoint.args` is a copy, `proceed(args)` checks the argument count; async non-around advice is awaited on `Future` methods and rejected on synchronous ones
- AOP runtime: advice binding (`@annotation(timed)`, `args(id, ..)`, `@AfterReturning(returning:)`, `@AfterThrowing(throwing:)`) and subclass proxies (`AopProxyFactory.subclass`); the generator does not emit them yet
- breaking: `@PastDate`, `@PastOrPresentDate`, `@FutureOrPresentDate` are renamed to Jakarta's `@Past`, `@PastOrPresent`, `@FutureOrPresent` (`@FutureDate` stays: `@Future` clashes with Dart's `Future`)
- validation: `DecimalMin` / `DecimalMax`, `BigInt` and numeric strings in number constraints, `@Digits` like `BigDecimal`, Hibernate's `@Email`, `@NotBlank` trimming like Java, `@Pattern` flags, date-only values and an injectable clock (`ClockProvider`)
- validation: method validation (`@Validated`, `MethodValidationPostProcessor`, `ConstraintViolationException`); class-level violations on a property; `{key}` messages from a `MessageSource`; shared `@Valid` objects validated on every path
- binding: no constraint error on top of a binding failure; `DataBinder.construct` (constructor binding); collection auto-grow and element/key conversion in `BeanWrapper`; full `DefaultMessageCodesResolver` codes and Spring's error arguments
- messages: the parent `MessageSource` gets resolved arguments; locales with a script (`zh_Hant_TW`); basename-by-basename lookup; `MessageFormat` details (quotes, lone `}`, negative subpatterns, HALF_EVEN, locale symbols)
- beans: failed destroy callbacks are logged by `spring_core_dart.beans.factory.support.DisposableBeanAdapter` (Spring's logger name)
- breaking: `DefaultLifecycleProcessor` takes a `ConfigurableListableBeanFactory` and, like Spring, does not create lazy plain `Lifecycle` beans (only created singletons and `SmartLifecycle` beans are started and stopped)
- breaking: `SmartLifecycle` is an `abstract mixin class` with Spring's defaults (`isAutoStartup` `true`, `phase` `SmartLifecycle.defaultPhase`) and `stopWithCallback(callback)` (Spring's `stop(Runnable)`), which the lifecycle processor calls; classes that `implements SmartLifecycle` must add `stopWithCallback` or use `with SmartLifecycle`
- breaking: `isActive` is `true` from the start of `refresh()` until `close()` finishes; `close()` from a `ContextRefreshedEvent` listener closes the context
- breaking: `@EventListener` methods and `addListener` / `ApplicationListener` typed `Object` (or another non-`ApplicationEvent` type) receive the payload of a `PayloadApplicationEvent`, not the wrapper; an `ApplicationListener` bean that is `Ordered` is ordered by its order
- breaking: `publishEvent` before `refresh()` or after a failed refresh no longer throws: the event is only forwarded to the parent (Spring 7)
- breaking: the default context id is unique (`AnnotationConfigApplicationContext@1b2c3d`, like Spring's `ObjectUtils.identityToString`) instead of `application`; an explicit `id` is kept
- breaking: `PropertiesMessageSource` is renamed `ReloadableResourceBundleMessageSource`; `cacheMessages` is replaced by Spring's `cacheSeconds` (`-1` forever, `0` checks on every lookup, `n` at most every n seconds; changed files are re-read) and it gets `fallbackToSystemLocale` (default `true`: without a `defaultLocale`, `Locales.systemLocale` is tried)
- breaking: `AbstractMessageSource.fallbackToDefaultLocale` is removed (an empty `defaultLocale` means no fallback); subclasses can override `fallbackLocale`
- messages: `MessageSourceAccessor`; `Locales.systemLocale` (the platform locale, settable like `Locale.setDefault`)
- config data: profile names are validated like Boot 3.5+ (letters, digits, `-_.+@`, starting and ending with a letter or digit; `spring.profiles.validate=false` turns it off); the legacy `spring.profiles` key is rejected (`InvalidConfigDataPropertyException`); an empty `spring.config.activate.on-profile` is no guard; locations without a prefix are files (Boot's `LocationResourceLoader`)
- `SimpleCommandLinePropertySource`: a lone `--` ends the options (later arguments are non-option arguments) instead of throwing
- breaking: `containsProperty` on an environment / `PropertySourcesPropertyResolver` is `true` for a key with a `null` or empty value, like Spring
- breaking: converting a list or set to `String` gives `a,b` (Spring's `CollectionToStringConverter`) and a `Duration` gives ISO-8601 `PT1H30M` (Boot's `DurationToStringConverter`; `DurationStyle.formatIso`); ISO durations accept negative parts (`P-1D`)
- enums convert leniently like Boot (`my-value`, `MY_VALUE` and `myValue` all bind to `myValue`) in `addEnum` and constructor binding
- `MethodValidationPostProcessor` takes exclude filters on the class annotations (Boot's `MethodValidationExcludeFilter`)
- breaking: plain resource locations (`app.properties`, `/x.txt`) are classpath resources (`lib/resources/`), like Spring's `getResourceByPath`, in `DefaultResourceLoader`, `PathMatchingResourcePatternResolver` (which now expands classpath patterns) and contexts; use `file:` for the file system
- breaking: SpEL `SimpleEvaluationContext` rejects variable assignment in expressions (`#v = 5`, `#v++`) with `SpelMessage.variableAssignmentNotSupported` ("Assignment to variable '#v' is not supported"), through the new `EvaluationContext.assignVariable` (custom `EvaluationContext` implementations must add it); `setVariable` from Dart still works
- breaking: SpEL selection criteria must be booleans (`SpelMessage.resultOfSelectionCriteriaIsNotBoolean`, no conversion), and first/last selection on a map with no match is `null` instead of `{}`
- SpEL: enums of the same type compare by index (Java ordinal); `+` with a String converts the other operand with the context's `TypeConverter` (`'a' + {1,2}` is `a1,2`)
- breaking: JSON: local `DateTime`s are written with their offset (`2026-01-01T12:00:00.000+02:00`, like Jackson's `OffsetDateTime`) instead of none; `ObjectMapper(timeZone:)` (`UTC` or a fixed offset) writes dates in that offset
- breaking: JSON naming strategies translate like Jackson: `snakeCase` / `upperSnakeCase` keep acronyms together (`myURLValue` → `my_urlvalue`), `upperCamelCase` only capitalizes the first letter (`MyURLValue`), `lowerCase` lowercases the name as it is
- JSON: `NaN` and infinities are written as `"NaN"`, `"Infinity"`, `"-Infinity"` (Jackson's default) instead of throwing; `readValue<Map<String, dynamic>>` / `readValue<List<dynamic>>` without a type return the decoded JSON
- breaking: `ObjectMapper` writes the properties of an object sorted by JSON name, the constructor parameters first (Jackson 3's / Spring Boot 4's `SORT_PROPERTIES_ALPHABETICALLY` and `SORT_CREATOR_PROPERTIES_FIRST`), not in declaration order; `ObjectMapper(sortPropertiesAlphabetically: false)` brings the old order back
- `@JsonPropertyOrder(['id', 'title'])` and `@JsonPropertyOrder.alphabetic()`: listed properties first (JSON or Dart names), the rest in the mapper's order

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- add feign runner + web socket runner
- add web core + faign starter for http calling

## 0.1.4

- feat: ObjectMapper in core — JSON on generated metadata (@Introspected, @JsonProperty/@JsonIgnore/@JsonInclude/@JsonCreator/@JsonValue), spring.jackson.* in Boot

## 0.1.3

- add scheduling + cache starters
- fix extension add aop docs

## 0.1.2

- ci: release only from the release branch; fix version-dependent test; Node 24 actions
- fix tests

## 0.1.1

- `ClasspathResources.registerAll(owner:)`: a module registering again (after a hot reload) replaces its own embedded files; `BeanModule` passes its name.
- Example guide on pub.dev (`example/README.md`): every feature in short blocks with the annotations to write.

## 0.1.0

- `Advised` members are `aopTarget` and `aopAdvisors` (were `targetObject`
  and `advisors`), so domain methods named `advisors` can be proxied.
- `AopProxyFactory.unavailable` and `AopConfigException`: advice that
  matches a bean the generator could not proxy fails the startup with the
  reason instead of being skipped silently.
- `DataBinder.bind`: malformed keys (`items[`, `a..b`) are skipped like
  unknown fields (`InvalidPropertyException` when `ignoreUnknownFields` is
  off); setters that throw become `methodInvocation` field errors
  (`MethodInvocationException`), and binding continues.
- Config data: `spring.profiles.include` profiles come before the active
  ones, so `application-{active}` files override included profile files,
  as in Spring Boot.
- `@Lazy` on injection points (constructor parameters, fields, setters):
  a generated lazy proxy resolves the bean on every call, on behalf of the
  injecting bean (self-exclusion still applies). Breaks cycles and allows
  self-injection through the AOP proxy. `Dependency.lazy` is validated at
  refresh like a single dependency but is not an edge of the cycle check;
  `DependencyResolver.lazyDependency`.
- Lookups are cached per requester once the factory is frozen.
- `ClasspathResources.addDirectory`: directories searched before the
  embedded `lib/resources/` files (the test classpath).
- `SpringLog` is the logging facade of the family: per-logger levels
  inherited by dots (`setLevel`, `levelOf`), lazy messages
  (`log.debug(() => ...)`), structured `fields`, zone-scoped context
  (`SpringLog.withFields`, like MDC), `listen` for extra listeners, and
  records with `time` and `sequence`. `parseSpringLogLevel` reads property
  values.
- A bean is no longer injected into itself: `@Primary` composites and
  decorators receive the other beans of their type (Spring's
  self-reference rule).
- `@PropertySource` declarations carry the declaring class's conditions and
  are loaded only when they match.
- Config data: documents guarded by `spring.config.activate.on-profile`
  (including negated guards such as `!prod`) are evaluated only once the
  profiles are known; relative import cycles terminate.
- `close()` is exception-safe and re-entrant like Spring's `doClose`: a
  failing `ContextClosedEvent` listener or lifecycle bean is logged and the
  shutdown continues.
- Events published during `refresh()` reach the parent context once.
- Bean Validation messages are shown as written (no `MessageFormat`
  mangling of `can't` or `[A-Z]{2,3}`) unless they contain `{0}`
  placeholders; invalid `MessageFormat` patterns are returned raw.
- `DataBinder` canonicalizes property names (`roles['admin']` →
  `roles[admin]`) and matches `disallowedFields` case-insensitively, also
  against dotted map access.
- AOP: `@annotation` / `@within` match generated annotation names, so they
  work in minified and obfuscated release builds; package-qualified
  wildcards and argument binding are rejected instead of matching every or
  no bean.
- `ConditionGroup`: a configuration class's conditions are evaluated once
  for the class, its `@Bean` methods and property sources (all or nothing).
- Type index like Spring's `allBeanNamesByType` (cleared when definitions
  change) and a cache of resolved lookups once the configuration is frozen:
  `getBean<T>()` no longer scans every definition (~0.1 µs regardless of the
  number of beans).
- New `SpringLog` logger for problems the framework recovers from.
- `classpath:` resources: files of `lib/resources/` embedded by the
  generator (`BeanModule.resources`, `ClasspathResources`), read from disk
  as a fallback; config data looks in `classpath:/` and `classpath:/config/`
  first; `@Value('classpath:...') Resource` injection.


Initial release.

- IoC container: `ApplicationContext`, `DefaultListableBeanFactory`, bean
  definitions, singleton / prototype / custom scopes, lazy beans,
  `@Primary` / `@Fallback` / `@Qualifier`, collection and `ObjectProvider`
  injection, `FactoryBean`, aware and lifecycle callbacks, bean
  (factory) post-processors, `Lifecycle` / `SmartLifecycle`, parent
  contexts, bean graph validation at refresh.
- Annotations for `spring_core_dart_generator`: stereotypes,
  `@Configuration` / `@Bean`, `@Autowired`, `@Value`, `@PostConstruct` /
  `@PreDestroy`, `@Profile`, `@Conditional`, `@Import`, `@PropertySource`,
  `@EventListener`, `@Configurable`, `@Introspected`, AOP annotations.
- Environment: property sources, `${...}` placeholders, profiles and profile
  expressions, command-line arguments, `application.properties` config data
  with profile files, multi-document files and imports.
- Type conversion, resources and `AntPathMatcher`, `.properties` parser.
- Events, `MessageSource` with `MessageFormat`.
- SpEL: parser, evaluation contexts, templates, `#{...}` in `@Value`.
- Validation and data binding: constraints, `BeanValidator`, `DataBinder`,
  Spring message codes.
- AOP: aspects, advice, pointcut expressions, advisors, generated proxies.
