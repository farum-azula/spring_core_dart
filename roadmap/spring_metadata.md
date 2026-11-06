# Spring metadata: one file per package for editors (0.6.3)

**In 0.6.3** (the owner, November 2026), with the theme. Like Spring
Boot's `spring-configuration-metadata.json`, but wider: properties,
beans, profiles, the theme, later routes. The generator writes it; the
language server and the Zed extension read it for completion, hovers,
navigation and checks; a JSON Schema for `application.yml` is made from
it for any editor.

## Where

`lib/spring_gen/spring_metadata.json`, written by the generator for every
package with Spring code (an app, a starter, a library). It is published
with the package (like `META-INF` in a jar), so the language server reads
the app's file and those of all its dependencies (found through
`.dart_tool/package_config.json`). The file is generated whole from the
code; nothing is written by hand.
The starters also read their settings through the same classes (bound by
the `Binder`), so the description and the reading of a property cannot
drift apart; where a setting is read before any binder exists (the
environment's own `spring.config.*` and `spring.profiles.*`), a test
compares the class with the reader.

## Format (version 1)

```json
{
  "version": 1,
  "package": "spring_boot_starter_data",
  "properties": [
    {
      "name": "spring.datasource.url",
      "type": "String",
      "description": "The URL of the database.",
      "default": null,
      "deprecated": null,
      "source": "package:spring_boot_starter_data/src/data_properties.dart",
      "line": 42,
      "class": "DataSourceProperties"
    }
  ],
  "hints": [
    { "name": "logging.level.*",
      "values": [{ "value": "info", "description": "…" }] },
    { "name": "spring.profiles.active", "provider": "profiles" },
    { "name": "spring.flutter.web.dev-server.port", "range": [0, 65535],
      "warn": [{ "values": [5060, 5061], "message": "browsers refuse it" }] }
  ],
  "beans": [
    {
      "name": "basket",
      "type": "Basket",
      "types": ["Basket", "ChangeNotifier"],
      "scope": "singleton",
      "primary": false,
      "qualifiers": [],
      "profiles": ["!test"],
      "conditions": ["@ConditionalOnProperty('app.basket.enabled')"],
      "source": "package:app/src/basket.dart",
      "line": 12,
      "injects": [{ "parameter": "catalog", "type": "Catalog", "qualifier": null }],
      "members": [
        { "name": "total", "kind": "getter", "type": "double" },
        { "name": "add", "kind": "method", "type": "void", "parameters": ["Book book"] }
      ]
    }
  ],
  "profiles": ["dev", "prod"],
  "entities": [
    {
      "class": "Book",
      "table": "books",
      "source": "package:app/src/book.dart",
      "line": 12,
      "id": "id",
      "properties": [
        { "name": "title", "type": "String", "kind": "column",
          "column": "title", "relation": null,
          "source": "package:app/src/book.dart", "line": 18 },
        { "name": "author", "type": "AggregateReference<Author, int>?",
          "kind": "column", "column": "author",
          "relation": { "entity": "Author", "id": "int" },
          "source": "package:app/src/book.dart", "line": 21 }
      ]
    }
  ],
  "repositories": [
    {
      "name": "BookRepository",
      "entity": "Book",
      "id": "int",
      "source": "package:app/src/book_repository.dart",
      "line": 8,
      "methods": [
        { "name": "cardsSince", "kind": "query",
          "query": "select ... from {Book} b where b.year >= :year",
          "countQuery": null,
          "parameters": [{ "name": "year", "type": "int" }],
          "returns": "Future<List<BookCard>>", "line": 14 },
        { "name": "findByTitle", "kind": "derived", "query": null,
          "countQuery": null,
          "parameters": [{ "name": "title", "type": "String" }],
          "returns": "Future<List<Book>>", "line": 16 }
      ]
    }
  ],
  "theme": {
    "types": { "color": { "…": "…" } },
    "properties": [
      { "name": "components.app-bar.background-color", "type": "color",
        "states": true, "description": "…", "flutter": "AppBarTheme.backgroundColor" }
    ]
  }
}
```

- `properties`: from `@ConfigurationProperties` classes (names in
  kebab case; a list of classes as `foo[*].bar`, a map of classes as
  `foo.*.bar`, a map of plain values as `foo.*` with the value's `type`; a
  list of plain values stays `foo`, as a comma list binds there too), the
  `///` of the field as `description`, the field's initial value as
  `default` when it is a literal (also `Duration(seconds: 30)` as `30s` and
  `DataSize.ofMegabytes(10)` as `10MB`). `@Name('import')` renames a
  property.
- `hints`: an enum-typed property (also `List<Enum>` as `foo[*]` and
  `Map<String, Enum>` as `foo.*`) lists the constants as `values`, kebab
  case as the binder accepts them, each with the `///` of the constant.
  `@Range(min, max)` gives `range`, `@WarnValues([...], 'message')` gives
  `warn` (`[{values, message}]`), `@PropertyValues([...])` gives `values`
  for a `String` field and `@PropertyValues.provider('profiles')` a
  `provider`. The annotations are in `spring_core_dart`, check nothing at
  run time and are exported by `spring_boot_dart` too.
- `beans`: every registered bean (components, `@Bean` methods,
  auto-configurations) with types, scope, primary, qualifiers, profiles,
  conditions, source location, injection points, and the members SpEL
  can reach (public getters, fields, methods of the bean's type).
- `entities` and `repositories`: only for a package with a data layer
  (`spring_boot_starter_data`), from the same models the data generator
  writes its code from. An entity (`@Table` class) has its `table` (the
  `@Table` name or the class name in snake case), the `id` property and its
  `properties`: `kind` is `column`, `transient` (`@Transient`, not stored) or
  `collection` (`@MappedCollection`, rows in the children's table), `column`
  is the `@Column` name or the property name in snake case (`null` for a
  property without a column), `relation` names the entity and the id type of
  an `AggregateReference<X, ID>` or a `@Reference(X)` id, and `source`/`line`
  say where the field is (a superclass's too). With a `NamingStrategy` bean
  of the application the default names are not known: `table` and `column`
  are `null` unless spelled out. A repository has its `entity`, its `id`
  type and the `methods` the generated class writes (the CRUD methods of the
  starter are not listed): `kind` is `query` (with `query` and `countQuery`
  as written), `derived` or `locked`; `parameters`, `returns` and `line`.
- `loaderKinds`: only for a package with `@ThemeLoaderKind` classes
  (`spring_boot_starter_flutter`): `{name, class, source, line, props}`,
  where `name` is the value of `kind` in a theme, `class` the painter or
  widget, `source`/`line` where it is, and `props` the top-level keys the
  package's own themes give the loaders of that kind (besides `kind`,
  `phases` and `web`), left out when no theme uses it. The language server
  completes and checks `kind` and the keys of a loader from it, and the keys
  builder of a package that depends on this one knows the kind exists
  (`kind: doors` needs no class of its own). The `splash` and `loaders.*`
  keys of a theme are `theme` properties like the others (`loaders.*.*` is
  `open`: a kind of the app's own takes keys the metadata cannot list).
- `theme`: only in `spring_boot_starter_flutter`'s file (from
  `tool/theme_metadata.json`: `types`, the type schema incl. the color
  object, and `properties`). `properties` lists every key below
  `spring.flutter.theme` with names relative to a theme: the root keys
  (`active`, `extends`, `brightness`, `seed-color`, ...), `colors.<role>`,
  `typography.<style>.<key>`, `shape.*`, `spacing.*`, `elevation.*`,
  `motion.*`, `animations.*.{duration,curve,repeat}`, `loaders.*.*`,
  `splash.*` (the splash screen; a scalar `splash: ripple` is the tap ink),
  `background.*` (also
  under `background.screens.*`), `cupertino.*`, `components.<name>.*`, and
  the free maps `styles.*` and `tokens.*` (`open: true`: anything may
  follow). `scope` is `root` (only at the root of the theme) or `theme`
  (only inside `themes.<name>`); without it the key works in both. Editors
  read all of it from here: nothing about the theme is built into them.
- Keys read without `@ConfigurationProperties`: the generator adds the
  `${key:default}` placeholders of annotation arguments (`@Value`) and the
  names of `@ConditionalOnProperty` / `@ConditionalOnBooleanProperty`
  (type `String`, `bool` for the boolean one; by name only, no
  description). `tool/test/property_keys_test.dart` fails when a literal
  key read in `lib/` of a package (`getProperty(`, `containsProperty(`,
  `@Value`, `@ConditionalOnProperty`) is not bound by a
  `@ConfigurationProperties` class of that package or its dependencies;
  the few truly dynamic or non-property literals are listed there with a
  reason. Code that reads a key by name before any bean exists (the config
  data loading, `SpringApplication`, the logging system) has a
  `@ConfigurationProperties` class that only describes the key.
- JSON Schema: `tool/spring_schema.dart` (repo root) turns the
  properties, hints and theme of an app and its dependencies into
  `spring-application.schema.json`.

## Editor (language server + Zed extension)

From the metadata, in `application*.yml`, `.properties`, YAML under
`lib/resources/` and Dart:
completion and hovers of every key and value (enums, ranges, theme keys,
`$` references), unknown key / wrong type / out-of-range diagnostics with
"did you mean", `${key}` → where it is set (per profile), SpEL `#{@bean.member}`
completion, hovers and errors, injection points → candidate beans (none:
error, several without `@Primary`/`@Qualifier`: warning), `@Profile` with
an unknown profile, theme `$colors.primary` → its declaration (also in a
library's theme).

Dart repositories (`spring_boot_starter_data`), from `entities` and the
source: the SQL of `@Query` is coloured (keywords, names, numbers, strings,
comments, `:params`, `{Entity.property}`, SpEL) and checked (unknown entity
or property with "did you mean", `:param` without a parameter, a parameter
never used, SpEL with the parameters as `#name`, unbalanced quotes and
parentheses); `{Book}` and `{Book.author}` go to the class and the field,
`:year` to the parameter; completion after `{`, `{Entity.` and `:`. A derived
query name (`findByTitleAndYearGreaterThan`) is read with the build's grammar:
unknown property, parameter count, the SQL it stands for on hover, the
property part goes to the field. The source of the workspace wins over the
metadata, which only adds column names and the entities of dependencies.

## The color of a theme: one form

A plain value stays a string (`'#F2E35B'`, `white`, `$colors.primary`).
Anything applied to a color is an object; the one-line forms
(`$x alpha 12%`, `$x mix white 14%`, `on-surface@38%`) and bare role names
are gone (before 1.0, no compatibility):

```yaml
badge-fill:
  color: $colors.primary
  alpha: 12%
hover-fill:
  color: $colors.primary
  mix: { with: white, amount: 14% }
```

`mix` is applied first, then `alpha`. Validated by the same type schema in
the editor, at build time and at start.
