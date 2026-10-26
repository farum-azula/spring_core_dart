# spring_boot_starter_test

## Done

- `springBootTest(...)`: the whole application once per test file
  (`@SpringBootTest`), with `args`, `properties`, `propertyFiles`,
  `dynamicProperties`, `profiles`, `systemEnvironment`, `overrides`
  (`BeanOverride`), `initializers`, `test/resources/` first on the
  classpath, `markDirty()` for a fresh context.
- `ApplicationContextRunner` for auto-configuration tests.
- Matchers: `hasSingleBean`, `hasBean`, `doesNotHaveBean`, `hasBeanNamed`,
  `hasFailed`.
- `captureLogs()`.
- Works under `package:test` and `flutter_test`.

Flutter gets its own starter on top of this one:
[spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md).

## Next: test classes with annotations

Tests written as in Spring: a class with `@SpringBootTest`, `@Autowired`
fields, `@TestBean` fakes and `@Test` methods, turned by the generator into
today's functions. The full specification, with every annotation, the
generated code and the build errors, is the documentation page
[docs/testing.md](../docs/testing.md) (sections 3–11, 15, 16).

```dart
import 'checkout.test.spring.dart';

@SpringBootTest(args: ['--shop.name=Night Books'])
@ActiveProfiles(['dev', 'test'])
class CheckoutTest {
  @Autowired()
  late Checkout checkout;

  @TestBean(name: 'sandbox')
  final gateway = FakeGateway();

  @Test('checkout pays through the fake')
  void pays() {
    checkout.pay(3);
    expect(gateway.charged, [3]);
  }
}

void main() => runSpringTests();
```

### Steps

1. **Annotations** in `spring_boot_starter_test` (const classes, no
   behaviour): `SpringBootTest`, `ActiveProfiles`, `TestPropertySource`,
   `TestEnvironment`, `DynamicPropertySource`, `ContextInitializer`,
   `TestBean`, `DirtiesContext`, `Test`, `DisplayName`, `BeforeAll`,
   `BeforeEach`, `AfterEach`, `AfterAll`, `Nested`, `CapturedOutput`.
   `Autowired`, `Qualifier` and `Value` are the framework's own. `@Skip`,
   `@Timeout`, `@Tags` stay `package:test`'s.
2. **A test builder** in `spring_core_dart_generator`: input
   `test/**_test.dart`, output `{{}}.test.spring.dart` (not
   `_test.spring.dart`, which `dart test` would run as a test). Only files
   with a `@SpringBootTest` class get output.
3. **The application of the package**: the generator finds the entry
   points it generated (`bin/*.dart`, `lib/main.dart`); one is the
   default, several need `@SpringBootTest(application: 'bin/x.dart')`.
4. **Generated code**: one `group` per class, `springBootTest(...)` from
   the class annotations, `setUp` injecting the `@Autowired` / `@Value`
   fields (again after a restart), `@TestBean` fields as `BeanOverride`s,
   `@Test` methods as `test`, lifecycle methods as `setUpAll` / `setUp` / `tearDown`
   / `tearDownAll`, `@DirtiesContext` as `markDirty()`, `@Nested` fields
   as nested groups, `package:test` annotations as `skip:`, `timeout:`,
   `tags:`.
   The test builder is open to other starters: a starter can register
   method and class annotations of its own and what they generate (the
   Flutter test starter adds `@WidgetTest`, `@TargetPlatformTest`,
   `@Golden`).
5. **Build errors** of docs/testing.md section 16, each with a test in the
   generator.
6. **Examples**: `example/spring_core_tour/test/boot_test.dart` gets a
   class version next to the function version; the docs examples run in
   CI.
7. **Editor**: the `dart_spring` language server shows run buttons on
   `@Test` methods (they are tests in a group named after the class) and
   completes the annotations; snippets `sbt` (test class), `tst` (test
   method).

### Open questions

- A shared context between classes with the same configuration (Spring's
  context cache): not planned while startup is fast.
- `@MockitoBean` as a name for `@TestBean`, for people coming from Spring:
  only if a mocking library is chosen (`mocktail` is a third-party package,
  so not a dependency of the starter).
- Test slices (`@WebMvcTest`-like) once the web and data starters exist.
