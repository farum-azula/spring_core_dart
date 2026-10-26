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

## Done: test classes with annotations

Tests written as in Spring: a class with `@SpringBootTest`, `@Autowired`
fields, `@TestBean` fakes and `@Test` methods, turned by the generator into
the functions above. Documented in [docs/testing.md](../docs/testing.md).

```dart
import 'spring/checkout.test.spring.dart';

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

- **Annotations** (`lib/src/test_annotations.dart`): `SpringBootTest`,
  `ActiveProfiles`, `TestPropertySource`, `TestEnvironment`,
  `DynamicPropertySource`, `ContextInitializer`, `TestBean`,
  `DirtiesContext`, `Test`, `DisplayName`, `Disabled`, `Tag`,
  `TestOptions`, `BeforeAll`, `BeforeEach`, `AfterEach`, `AfterAll`,
  `Nested`, `CapturedOutput`; `Autowired`, `Qualifier` and `Value` are the
  framework's. `package:test`'s `@Skip`, `@Timeout`, `@Tags`... only
  annotate libraries, hence `@Disabled`, `@Tag` and `@TestOptions`.
- **Runtime**: `SpringBootTestContext.findBean`, `getBeans`, `value`,
  `optionalValue`; `BeanOverride.named` (replaces a bean by name keeping
  its types); `package:spring_boot_starter_test/generated.dart` for the
  generated code.
- **Builder** `spring_core_dart_generator:spring_test`
  (`lib/src/test_builder.dart`): `test/{{}}_test.dart` →
  `test/spring/{{}}.test.spring.dart` (its own folder, one file per test
  file). It reads the test file as syntax and copies its
  imports, so bean types are never written out (`instance.checkout =
  app.getBean();`). Finds the `@SpringBootApplication` entry point of the
  package, or the one named by `application:`. Build errors with the
  file, line and column (docs/testing.md section 16).
- **Tests**: `spring_core_dart_generator/test/spring_test_builder_test.dart`
  (the generated code for every annotation, every build error),
  `spring_boot_starter_test/test/test_class_support_test.dart` (the
  runtime), and running classes in `example/spring_core_tour/test/`
  (`boot_class_test.dart`, the class version of `boot_test.dart`;
  `lifecycle_class_test.dart`, every annotation and the order they run in).

## Next

1. **Editor**: the `dart_spring` language server shows run buttons on
   `@Test` methods (tests in a group named after the class) and completes
   the annotations; snippets `sbt` (test class), `tst` (test method).
2. **Open to other starters**: the Flutter test starter
   ([spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md))
   adds `@WidgetTest`, `@TargetPlatformTest` and `@Golden` to the same
   generated file; the builder needs a way for a starter to add method
   annotations and what they generate.

### Open questions

- A shared context between classes with the same configuration (Spring's
  context cache): not planned while startup is fast.
- `@MockitoBean` as a name for `@TestBean`, for people coming from Spring:
  only if a mocking library is chosen (`mocktail` is a third-party package,
  so not a dependency of the starter).
- Test slices (`@WebMvcTest`-like) once the web and data starters exist.
