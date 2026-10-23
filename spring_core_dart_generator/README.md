# spring_core_dart_generator

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

`build_runner` builder for spring_core_dart. For every library with a
`@ComponentScan` variable it scans the library's directory recursively and
writes `<file>.beans.dart` with a `BeanModule`.

Full guide: [spring_core_dart](https://pub.dev/packages/spring_core_dart).

## Installation

```yaml
dependencies:
  spring_core_dart: ^0.1.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.1.0
```

Mark a scan root and run `dart run build_runner build` (or `watch`):

```dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/beans.beans.dart';

@ComponentScan()
final BeanModule appBeans = $appBeans;
```

See the [example](https://pub.dev/packages/spring_core_dart_generator/example).

## Responsibility

- Read annotations with the analyzer, validate declarations (errors point to
  the source element) and emit plain Dart:
  - `BeanDefinition`s: types, scope, laziness, primary/fallback, qualifiers,
    aliases, order, depends-on, conditions, declared dependencies, `create`
    and `inject` closures, lifecycle callbacks, event listeners, factory
    bean product types;
  - `@PropertySource` declarations, `@Configurable` configurers,
    `@Introspected` metadata (properties, methods, annotations);
  - `@Aspect` advice metadata and AOP proxy classes.
- Supports Dart 3.13 syntax: primary constructors (annotations on declaring
  parameters inject through the constructor, not as fields), `class const`,
  `new` / `factory` constructor declarations and private named parameters
  (passed under their public name).
- Does NOT depend on the runtime package: annotations are matched by name in
  `package:spring_core_dart`.

## Options

```yaml
# build.yaml of your package
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        options:
          aop_proxies: interfaces
```

| Option | Values | Default |
|---|---|---|
| `aop_proxies` | `all` — proxy classes for every bean that can be implemented (class and interfaces); `interfaces` — only through abstract types; `none` — no proxies | `all` |

Beans without matching advice are never wrapped at runtime; the option only
controls generated code size.

## Public API

`lib/builder.dart`: `springCoreDartBuilder`, referenced from `build.yaml`
(`auto_apply: dependents`, `build_to: source`, `.dart` → `.beans.dart`).

## Dependencies

| Package | Why |
|---|---|
| `analyzer` | Element model (moves with the Dart SDK) |
| `build`, `glob` | Builder API, directory scanning |
| `source_gen` | `TypeChecker`, `ConstantReader`, errors |
| `code_builder`, `dart_style` | Emitting and formatting code with prefixed imports |
| `path` | Relative imports for scan roots outside `lib/` |

Dev: `spring_core_dart`, `build_test`, `test`, `coverage`.

## Structure

```
lib/
  builder.dart                  build_runner entry point and options
  src/
    spring_builder.dart         finds @ComponentScan, scans, writes output
    bean_scanner.dart           analyzer elements → models, validation
    bean_model.dart             intermediate models
    module_emitter.dart         models → Dart source
build.yaml
test/spring_builder_test.dart   generated output and every rejected declaration (64 tests)
```

## Status

Covers every annotation of the runtime (~99% lines).

## License

Apache License 2.0.
