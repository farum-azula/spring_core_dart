# spring_core_dart_generator

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

`build_runner` builder for spring_core_dart. For every library with a
`@ComponentScan` variable it scans the library's directory recursively and
writes `<file>.spring.dart` with a `BeanModule`.

Full guide: [spring_core_dart](https://pub.dev/packages/spring_core_dart).

## Installation

```yaml
dependencies:
  spring_core_dart: ^0.4.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.0
```

Mark a scan root and run `dart run build_runner build` (or `watch`):

```dart
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:my_app/src/beans.spring.dart';

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

## `@Log`

A class of the scan with `@Log()` gets `extension $<Class>Log on <Class>`
with a getter (`log`, or `fieldName:`) returning
`const SpringLog('<package>.<Class>')` (or `topic:`). A private class (an
extension elsewhere cannot name it), an invalid or reserved getter name, or
a member of the class or its supertypes with that name (it would win over
the getter) fail the build.

## Flutter (`spring_boot_starter_flutter`)

For apps on `spring_boot_starter_flutter` (matched by URL like the starters'
annotations, so the generator does not depend on it):

- `@BuildContextAccess()` on a bean class or a `@Bean` method adds a getter to
  `extension SpringBeans on BuildContext`, written into the `.spring.dart`
  of the `@SpringBootApplication` / `@ComponentScan` (after the run and
  reload functions); import that file where widgets use the getters:

  ```dart
  @Component()
  @BuildContextAccess()
  class Basket { ... }

  // generated
  extension SpringBeans on BuildContext {
    Basket get basket => SpringScope.beanOf<Basket>(this, qualifier: r'basket');
  }
  ```

  The getter is named after the bean (`@BuildContextAccess(name: 'cart')` for
  another name) and typed with the bean's class (a `@Bean` method's
  declared return type, a `FactoryBean`'s product). A name that is not a
  public identifier, a reserved word, a member of `BuildContext` /
  `Object` / spring_boot_starter_flutter's `SpringBuildContext` (`bean`, `message`,
  `springContext`), two beans with one getter name, or `@BuildContextAccess` on
  a class that is no bean fail the build.
- Every class of the scan extending `SpringStatelessWidget<R>` (or a `State` extending
  `SpringState<W, R>`) with a concrete
  record `R` gets a binding in one `SpringWidgetBindings` bean of the
  module (`flutterSpringWidgetBindings#<module>`, not an autowire
  candidate): positional fields are beans by type, named fields by type
  and then by the field's name among several candidates, nullable fields
  optional (`findBean`). `SpringApplicationWidget` checks at startup that the required
  beans exist. A field that is no class or interface type (`dynamic`,
  `Object`, functions, records) or a concrete widget whose `R` is a type
  parameter fails the build; an abstract base class with a type parameter
  is skipped.

Nothing Flutter is written for modules without these.

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
| `aop_prune` | `true` — with `aop_proxies: all`, the `@SpringBootApplication` output (which knows every module of the application) generates no proxy class for a bean no pointcut of the application can match (its signatures stay, so an advisor that matches anyway fails the startup with the reason); `@ComponentScan` modules are never pruned, since any module may import them; `false` — every bean keeps its proxy class | `true` |

Beans without matching advice are never wrapped at runtime; the options only
control generated code size. Every advice and `@Pointcut` expression is
parsed with the runtime's parser at build time: a syntax error fails the build
with the aspect, the advice and the character position. Pruning reads the
aspects of the nested `@ComponentScan` modules too (`@Aspect` classes and
aspects returned by `@Bean` methods); nothing is pruned when no module has
advice, a module declares an advisor bean, or an auto-configuration
declares aspects or an advisor bean whose pointcut is not an
`AnnotationPointcut`, and a bean whose class or members carry an annotation
from outside `spring_core_dart` (or `@Validated`) keeps its proxy, because
those starters' advisors match by annotation.
Public fields are proxied as implicit getters and setters.

`@ComponentScan` itself takes Spring's scan options, evaluated at build
time: `includeFilters` / `excludeFilters` (`Filter(classes: [Plugin])` for
an annotation, `Filter(type: FilterType.assignableType, classes: [Handler])`,
`Filter(type: FilterType.regex, pattern: ['.*Repository'])` on the class
name; excludes win, abstract classes never match), `useDefaultFilters:
false` (only the includes make beans) and `lazyInit: true` (every scanned
bean lazy unless `@Lazy(false)`). A filter without the argument its type
uses, or with an invalid pattern, fails the build.

## Build errors

Generated code cannot name a private declaration (`_Foo`, `_default`): a
private bean class, `@Bean` return type, injected type (also as a type
argument), event type or default value (a private function, class or
constructor) fails the build with a message naming the declaration, its
library and the fix (make it public, or move it out of the scan / declare
a public supertype / drop the default) instead of a generated file that
does not compile. Every error points at the source element.

Independent problems of one build are reported together (`N problems in
this build:`, each with its message, library URI and location) instead of
one per build. Among them: `@Component` on a mixin, enum, extension or
extension type, `@Bean` on a top-level function, `@ComponentScan` anywhere
but on a top-level variable, two `@ComponentScan` roots in one directory,
an empty, blank or space-padded bean name or alias, an ambiguous
constructor choice and injecting or returning an extension type (erased at
runtime). The generated code itself is free of analyzer warnings and of the
`package:lints` recommended lints (`type=lint` is still ignored in it, as
your own lint set may differ).

An error in the sources never removes or changes an existing `*.spring.dart`
(`build_runner watch` while typing would otherwise delete and regenerate it
on every keystroke): while a scanned library has syntax errors the builder
skips generation, writes the existing file again unchanged and logs one
warning per output until the next successful generation; a generator error
keeps the file too and is reported as the build error (`build_runner build`
fails, the file just stays). Without an existing output (a cold build) both
fail the build.

## Public API

`lib/builder.dart`: `springCoreDartBuilder`, referenced from `build.yaml`
(`auto_apply: dependents`, `build_to: source`, `.dart` → `.spring.dart`).

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
