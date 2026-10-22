## 0.1.3

- add scheduling + cache starters
- fix extension add aop docs

## 0.1.2

- ci: release only from the release branch; fix version-dependent test; Node 24 actions
- fix tests

## 0.1.1

- Example on pub.dev (`example/`) and a description within 180 characters.

## 0.1.0

Initial version.

- `springBootTest` (`@SpringBootTest`): the `test/resources/` test
  classpath (`resourceDirectories`), `propertyFiles`
  (`@TestPropertySource`), properties, profiles, environment,
  initializers, `markDirty` (`@DirtiesContext`), restored `SpringLog`
  state.
- `BeanOverride` (`@MockitoBean` / `@TestBean`), keeping name, aliases,
  qualifiers and `@Primary` / `@Fallback`.
- `ApplicationContextRunner` with `AssertableApplicationContext`.
- Matchers: `hasSingleBean`, `hasBean`, `doesNotHaveBean`, `hasBeanNamed`,
  `hasFailed`.
- `captureLogs`.
- Built on `test_api` + `matcher` for `flutter_test` compatibility.
