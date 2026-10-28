# Configuration

Configuration is the settings that change from one place to another while
the code stays the same: a server URL, a port, a timeout, a feature
switch, a log level, a theme. They live outside the code, in config files,
on the command line, in environment variables or in `--dart-define`
values. That way one build runs on a laptop, in tests and in production.
Each place gets its own values, and nothing is recompiled.

This page covers the whole subject for every package of the family:

- the config files, where they are read from and the two formats side by
  side;
- profiles, imports and placeholders;
- how durations, sizes and other values are written;
- which source wins when several set the same key;
- how Dart code reads its own settings;
- a reference of every property the framework and its starters read, with
  its type and default.

Spring (Java): this is Spring Boot's *Externalized Configuration* and its
*Common Application Properties*. The file names, keys and rules are Spring
Boot's, so configuration from a Spring project usually works unchanged.
The differences are listed where they apply and again at the
[end](#differences-from-spring-boot).

**Contents**

1. [The config files](#1-the-config-files)
2. [YAML and `.properties` side by side](#2-yaml-and-properties-side-by-side)
3. [Where files are read from](#3-where-files-are-read-from)
4. [Profiles](#4-profiles)
5. [Imports](#5-imports)
6. [Placeholders and random values](#6-placeholders-and-random-values)
7. [Writing values: durations, sizes, booleans, enums](#7-writing-values)
8. [Other sources: command line, environment, `--dart-define`](#8-other-sources)
9. [Which source wins](#9-which-source-wins)
10. [Your own properties](#10-your-own-properties)
11. [Reference: the application](#11-reference-the-application)
12. [Reference: logging](#12-reference-logging)
13. [Reference: scheduling](#13-reference-scheduling)
14. [Reference: caching](#14-reference-caching)
15. [Reference: Feign clients](#15-reference-feign-clients)
16. [Reference: WebSocket clients](#16-reference-websocket-clients)
17. [Reference: Flutter](#17-reference-flutter)
18. [Reference: web server](#18-reference-web-server)
19. [Tests](#19-tests)
20. [Code generation options (`build.yaml`)](#20-code-generation-options)
21. [Differences from Spring Boot](#differences-from-spring-boot)

---

## 1. The config files

An application keeps its settings in a file named `application.yml`,
`application.yaml` or `application.properties` in `lib/resources/`. That
folder is the application's *classpath*, the name Spring uses and the one
behind every `classpath:` location on this page. For each active
[profile](#4-profiles), the file `application-{profile}.*` is read as well,
and its values win over the plain file.

You declare nothing in `pubspec.yaml`. The generator embeds every file of
`lib/resources/` into the generated code, so the files work the same on
the Dart VM, in AOT builds, in Flutter and on the web. A file larger than
1 MB is not embedded (the build warns); ship such a file as a Flutter
asset or as a file next to the program instead.

```
lib/
  main.dart
  resources/
    application.yml             # always read
    application-dev.yml         # read when the profile dev is active
    application-prod.properties # read with prod (the formats can be mixed)
    messages.properties         # translated texts (see spring.messages.*)
```

YAML and `.properties` mean the same thing, so use the one you prefer, or
both. When one location has both, `.properties` wins over `.yml`, which
wins over `.yaml`.

<table>
<tr><th>application.yml</th><th>application.properties</th></tr>
<tr><td>

```yaml
spring:
  application:
    name: shop
  profiles:
    active: dev
shop:
  title: NEON Books
  url: http://localhost:8080
  max-basket-size: 20
```

</td><td>

```properties
spring.application.name=shop
spring.profiles.active=dev
shop.title=NEON Books
shop.url=http://localhost:8080
shop.max-basket-size=20
```

</td></tr>
</table>

The `spring.*` keys configure the framework. The `shop.*` keys belong to
the application; [section 10](#10-your-own-properties) shows how Dart code
reads them.

Because the files are part of the generated code, changing one changes
that code. In Flutter, a hot reload then restarts the application context
with the new values (see [Flutter](#17-reference-flutter)).

---

## 2. YAML and `.properties` side by side

Both formats end up as the same flat list of keys and values, such as
`shop.payment.provider=stripe`. This section shows how each format writes
the common shapes. Every example on this page has the two versions next to
each other, and a test checks that they mean the same.

### Nested keys

YAML nests the parts of a key; `.properties` writes the full key on each
line. Both give the keys `shop.payment.provider` and
`shop.payment.timeout`.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  payment:
    provider: stripe
    timeout: 5s
```

</td><td>

```properties
shop.payment.provider=stripe
shop.payment.timeout=5s
```

</td></tr>
</table>

### Lists

A YAML list becomes indexed keys: `shop.hosts[0]`, `shop.hosts[1]`. In
`.properties`, write the indexes yourself, or one comma-separated value.
Both forms bind to a `List` in [`@ConfigurationProperties`](#a-group-configurationproperties).
Indexes start at 0 and have no gaps.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  hosts:
    - eu.neon.books
    - us.neon.books
  currencies: [EUR, USD]
```

</td><td>

```properties
shop.hosts[0]=eu.neon.books
shop.hosts[1]=us.neon.books
shop.currencies=EUR,USD
```

</td></tr>
</table>

A list always comes whole from the highest source that has it. A
command-line `--shop.hosts[0]=local` replaces the file's list; it does not
merge with it.

A YAML list has no value under the plain key: `shop.currencies` itself is
not set, only `shop.currencies[0]` and `shop.currencies[1]` are. Code that
reads one value by key (`@Value(r'${shop.currencies}')`,
`environment.getProperty`) therefore finds nothing. For such code, write a
comma-separated value in YAML too: `currencies: EUR,USD`. Spring Boot
behaves the same way.

### Lists of objects

Each item of the list has its own keys.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  servers:
    - name: eu
      url: https://eu.neon.books
    - name: us
      url: https://us.neon.books
```

</td><td>

```properties
shop.servers[0].name=eu
shop.servers[0].url=https://eu.neon.books
shop.servers[1].name=us
shop.servers[1].url=https://us.neon.books
```

</td></tr>
</table>

### Maps

A map's entries are the keys below a prefix, here `shop.prices`. Unlike a
list, a map collects entries from every source, and a higher source wins
per key. Keys keep the form they are written in. To keep dots inside a
key, wrap the key in brackets; in YAML the bracketed key must also be
quoted.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  prices:
    book: 12
    e-book: 8
  headers:
    "[X-Shop.Id]": neon
```

</td><td>

```properties
shop.prices.book=12
shop.prices.e-book=8
shop.headers[X-Shop.Id]=neon
```

</td></tr>
</table>

### Empty values

In YAML, `~`, `null` and nothing after the colon all give an empty string,
like an empty value in `.properties`. For a target that is not a `String`,
an empty value counts as "not set", so the default applies.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  banner:
  motto: ~
```

</td><td>

```properties
shop.banner=
shop.motto=
```

</td></tr>
</table>

### Several documents in one file

One file can hold several documents, each a block of settings. YAML
separates them with `---`; `.properties` with a line `#---` (or `!---`).
A later document overrides an earlier one. A document can be limited to
some profiles or to a cloud platform (see [Profiles](#4-profiles)), so one
file can carry the development values and the production overrides.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  url: http://localhost:8080
---
spring:
  config:
    activate:
      on-profile: prod
shop:
  url: https://neon.books
```

</td><td>

```properties
shop.url=http://localhost:8080
#---
spring.config.activate.on-profile=prod
shop.url=https://neon.books
```

</td></tr>
</table>

### Comments

`#` starts a comment in both formats, with one difference. In
`.properties`, a comment must start its line (`!` works too), and a `#`
later in the line is part of the value. In YAML, a `#` after a space
starts a comment anywhere, so a value that starts with `#` must be quoted.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
# the shop
shop:
  color: '#673AB7'   # quoted, or # would start a comment
```

</td><td>

```properties
# the shop
shop.color=#673AB7
```

</td></tr>
</table>

### Only in `.properties`

```properties
# The separator between key and value is =, : or whitespace.
shop.name=NEON
shop.city: Berlin
shop.country Germany

# A line ending in \ continues on the next one; the next line's
# leading spaces are dropped.
shop.welcome=Welcome to NEON Books, \
             the shop of books.

# Escapes: \t \n \r \f \uXXXX. In a key, \= \: and "\ " keep
# those characters.
shop.greeting=Grüße
shop.key\=with\:colon=yes
```

`.properties` files are read as UTF-8, so `Grüße` can be written as is.
Spring reads them as ISO-8859-1 (see the
[differences](#differences-from-spring-boot)). When a key appears twice,
the last value counts. Trailing spaces of a value are kept.

### Only in YAML

YAML can share a block of settings with an anchor (`&defaults`) and merge
it elsewhere (`<<: *defaults`). The mapping's own keys win over the merged
ones.

```yaml
defaults: &defaults
  timeout: 5s
  retries: 3
shop:
  eu:
    <<: *defaults
    url: https://eu.neon.books
  us:
    <<: *defaults
    retries: 5           # wins over the merged 3
```

YAML is read as YAML 1.2. In practice:

- `on`, `off`, `yes` and `no` stay strings (they still convert to `bool`
  where a `bool` is expected);
- `0777` is the number 777, not an octal number;
- integers beyond 64 bits keep their exact value;
- a duplicate key or invalid YAML fails the start, with its line and
  column.

---

## 3. Where files are read from

Most applications only use `lib/resources/`. A server or desktop app may
also want a file next to the program, so an operator can change a setting
without a new build. That is why config files are searched in several
places.

### Default locations

The locations come in two groups. The second group overrides the first
one entirely:

| Group | Locations | What they are |
|---|---|---|
| 1 (packaged) | `classpath:/`, `classpath:/config/` | `lib/resources/` and `lib/resources/config/`, embedded by the generator |
| 2 (next to the program) | `file:./`, `file:./config/`, `file:./config/*/` | Files in the working directory, for desktop and server apps |

So `./application.properties` next to a server binary wins over the
packaged `application-prod.properties`. Within a group, profile files win
over plain ones, and the last active profile wins. Every default location
is optional: a missing one is skipped.

In tests (`springBootTest`), `test/resources/` comes before
`lib/resources/` on the classpath. So `test/resources/application-test.yml`
is found, and a file there replaces a packaged file with the same path.

### Changing the locations

Four keys change where files are searched. They are read only from
sources that exist before the files are read: the command line,
`--dart-define`, the environment and default properties. A config file
cannot set them.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.config.name` | comma list | `application` | The base names of the files. `application,shop` reads `application*.*` and `shop*.*`; a later name wins |
| `spring.config.location` | locations | the two groups above | Replaces the default locations. `,` separates groups; `;` joins locations into one group |
| `spring.config.additional-location` | locations | — | Groups searched after the locations, so they win over them |
| `spring.config.on-not-found` | `fail` / `ignore` | `fail` | `ignore` makes every location optional |

```bash
# Packaged files, then /etc/shop/ (which wins).
dart run bin/main.dart --spring.config.location=optional:classpath:/,file:/etc/shop/
# The usual locations, then one more file on top.
dart run bin/main.dart --spring.config.additional-location=file:./override.yml
```

### Location syntax

The same forms work in the keys above and in [imports](#5-imports).

| Form | Meaning |
|---|---|
| `classpath:config/` | A directory of `lib/resources/`; every file name and extension in it is searched |
| `file:./config/app.yml` | One file; the start fails when it is missing |
| `optional:file:./local.yml` | One file that may be missing |
| `file:./config/*/` | Each subdirectory, in alphabetical order; only for file locations, with one `*` at the end |
| `file:./conf[.yml]` | A file without the extension, read as YAML |
| `configtree:/run/secrets/` | A config tree, as Kubernetes mounts secrets: each file is one property named by its path (`db/password` is `db.password`), its content the value |
| `https://cfg.example.com/app.yml` | A file over HTTP; only with asynchronous starts (`runAsync`, Flutter) |
| `package:shop/defaults.yml` | A file of a Dart package |
| `asset:config/app.yml` | A Flutter asset (`spring_boot_starter_flutter`) |
| a plain path | A file, as with `file:` |

A required file that does not exist fails the start. Profile variants of
a file are always optional. A location without a known extension must end
with `/` (a directory) or carry an extension hint (`[.yml]`).

---

## 4. Profiles

A profile is a name for a situation the application runs in, such as
`dev`, `test`, `prod` or `eu`. Activating a profile reads the config files
and creates the beans meant for that situation. The rest of the setup stays
shared. Use profiles when environments differ by more than one or two
values: another database, a fake payment service in development, other
URLs per region.

### Profile files and activation

For each active profile, `application-{profile}.*` is read after the plain
file, so its values win. These keys decide which profiles are active:

| Key | Type | Meaning |
|---|---|---|
| `spring.profiles.active` | comma list or YAML list | The active profiles. The first source that has the key wins, so the command line beats a file |
| `spring.profiles.include` | comma list or YAML list | Profiles added to the active ones, from every source |
| `spring.profiles.default` | comma list | The profiles used while none is active; `default` when not set |
| `spring.profiles.group.<name>` | comma list | Activating `<name>` activates these too; groups can contain groups |
| `spring.profiles.validate` | bool | `true` (the default) checks the names: letters, digits and `-_.+@`, starting and ending with a letter or digit |

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  profiles:
    active: prod
    include: metrics
    group:
      prod: [eu, monitoring]
```

</td><td>

```properties
spring.profiles.active=prod
spring.profiles.include=metrics
spring.profiles.group.prod=eu,monitoring
```

</td></tr>
</table>

With this file, the active profiles are `metrics`, `prod`, `eu` and
`monitoring`. Profiles are usually chosen at launch rather than in the
file:

```bash
dart run bin/main.dart --spring.profiles.active=prod
SPRING_PROFILES_ACTIVE=prod dart run bin/main.dart
flutter run --dart-define=SPRING_PROFILES_ACTIVE=prod
```

`spring.profiles.active`, `.default`, `.include` and `.group.*` may not
appear in a profile file or in a document limited to a profile; the start
fails, as in Spring Boot. The pre-2.4 key `spring.profiles` is rejected
too.

In Flutter apps, the platform is a profile as well: `android`, `ios`,
`web`, `macos`, `windows` or `linux`, plus `mobile` (Android, iOS) or
`desktop` (macOS, Windows, Linux). So `application-ios.yml` and
`application-desktop.properties` are read on those platforms with no
setup.

### Documents for some profiles or platforms

Instead of a separate file, a document inside a file can be limited to
some profiles or to a cloud platform:

| Key | Meaning |
|---|---|
| `spring.config.activate.on-profile` | The document applies when this profile expression matches. An expression combines names with `!` (not), `&` (and), `\|` (or) and parentheses; `&` and `\|` cannot be mixed without parentheses. A comma list means "any of" |
| `spring.config.activate.on-cloud-platform` | The document applies on this platform: `kubernetes`, `heroku`, `cloud-foundry`, `azure-app-service`, `amazon-ecs`, `nomad`, `sap`, or `none` (no platform) |

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  region: local
---
spring:
  config:
    activate:
      on-profile: "prod & !us"
shop:
  region: eu
---
spring:
  config:
    activate:
      on-cloud-platform: kubernetes
shop:
  region: cluster
```

</td><td>

```properties
shop.region=local
#---
spring.config.activate.on-profile=prod & !us
shop.region=eu
#---
spring.config.activate.on-cloud-platform=kubernetes
shop.region=cluster
```

</td></tr>
</table>

The cloud platform is detected from environment variables, as Spring Boot
does it:

| Platform | Detected when these are set |
|---|---|
| `kubernetes` | `KUBERNETES_SERVICE_HOST` and `KUBERNETES_SERVICE_PORT` |
| `heroku` | `DYNO` |
| `cloud-foundry` | `VCAP_APPLICATION` or `VCAP_SERVICES` |
| `azure-app-service` | `WEBSITE_SITE_NAME`, `WEBSITE_INSTANCE_ID`, `WEBSITE_RESOURCE_GROUP` and `WEBSITE_SKU` |
| `amazon-ecs` | `ECS_CONTAINER_METADATA_URI` or `ECS_CONTAINER_METADATA_URI_V4` |
| `nomad` | `NOMAD_ALLOC_ID` |
| `sap` | `HC_LANDSCAPE` |

`spring.main.cloud-platform` forces a platform, or turns detection off
with `none`.

---

## 5. Imports

`spring.config.import` reads more files from inside a config file. Use it
to split a large configuration (one file per theme, per region), or to
add a file the operator provides, such as local overrides or mounted
secrets.

An imported file overrides the file that imports it, and gets its own
`-{profile}` variants. Relative locations are relative to the importing
file.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  config:
    import:
      - classpath:themes/ocean.yml
      - optional:file:./local.yml
      - configtree:/run/secrets/
```

</td><td>

```properties
spring.config.import=classpath:themes/ocean.yml,optional:file:./local.yml,configtree:/run/secrets/
```

</td></tr>
</table>

- Every [location form](#location-syntax) works, `optional:` included.
  Importing a directory searches the `application*` files in it.
- Given on the command line or as `SPRING_CONFIG_IMPORT`, imports form a
  group above every location.
- `${...}` in an import is resolved against the command line, the
  environment and the files read so far. An `optional:` import whose
  placeholder cannot be resolved is skipped.
- A file is read once, so import cycles do no harm.
- Not supported: `env:` imports.

---

## 6. Placeholders and random values

A value can contain other properties: `${key}` is replaced by the value of
`key`, and `${key:default}` uses `default` when `key` is not set. This
keeps one fact in one place: the shop's URL is written once and the API
address is built from it. Defaults and keys can contain placeholders
themselves.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  name: NEON Books
  title: ${shop.name} (${spring.profiles.active:local})
  url: ${SHOP_URL:http://localhost:8080}
  api: ${shop.url}/api/v${shop.api-version:1}
  literal: \${not.a.placeholder}
```

</td><td>

```properties
shop.name=NEON Books
shop.title=${shop.name} (${spring.profiles.active:local})
shop.url=${SHOP_URL:http://localhost:8080}
shop.api=${shop.url}/api/v${shop.api-version:1}
shop.literal=\\${not.a.placeholder}
```

</td></tr>
</table>

- `\${` gives a literal `${`. In `.properties` the backslash itself must
  be escaped, so write `\\${`. `\:` keeps a colon in a key.
- `${db:url}` is first looked up as the key `db:url`, then as `db` with
  the default `url`, as in Spring 6.2.
- A placeholder that cannot be resolved and has no default fails where
  the value is needed (`@Value`, `getProperty`). `@ConfigurationProperties`
  binding keeps it as written.
- In Dart code, write `@Value` strings as raw strings
  (`r'${shop.name}'`), because `'${...}'` is Dart's string interpolation.
  The editor extension flags the mistake.

### Random values

`${random.*}` gives a new random value on every read. It is meant for
values that must differ per run, such as an instance id or a port for a
test server. Read the value once and keep it when it must stay the same.

| Placeholder | Value |
|---|---|
| `${random.int}`, `${random.long}` | Any int or long (at most 53 bits on the web) |
| `${random.int(10)}`, `${random.int[5,10]}`, `${random.long(100)}` | A number in a range; the upper bound is excluded |
| `${random.uuid}` | A random version 4 UUID |
| `${random.value}`, or any other `random.*` | 32 random hex digits |

### SpEL

`#{...}` is a SpEL expression (a small expression language). It is
evaluated only in `@Value` and `@ConditionalOnExpression`, never in config
files.

---

## 7. Writing values

Every value in a config file is text. When it is bound to a typed field,
the text is converted. This section lists the forms each type accepts.

### Durations

- With a unit: `10s`, `500ms`, `5m`, `1h`, `2d`. Units are `ns`, `us`,
  `ms`, `s`, `m`, `h` and `d`, in any case.
- ISO-8601: `PT10S`, `PT1H30M`, `P1DT2H`. Years and months are not
  accepted.
- A plain number: milliseconds, or the unit of `@DurationUnit` on the
  field.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  timeout: 30s
  retry-after: PT1M30S
  poll: 250
```

</td><td>

```properties
shop.timeout=30s
shop.retry-after=PT1M30S
shop.poll=250
```

</td></tr>
</table>

### Data sizes

`512B`, `10KB`, `5MB`, `1GB`, `1TB`, in any case. The units are powers of
1024 and the number must be whole (`1.5MB` fails). A plain number is
bytes, or the unit of `@DataSizeUnit` on the field.

### Booleans

`true`, `on`, `yes` and `1` are true; `false`, `off`, `no` and `0` are
false, in any case. Any other value fails the start. The `spring.jackson.*`
switches are stricter: they are on only when the value is `true`.

### Enums

An enum value is matched ignoring case and separators, so
`ONLY_SHOW_SELECTED`, `only-show-selected` and `onlyShowSelected` are the
same value.

### Numbers

Integers can also be written in hex (`0x1F`, `#1F`). An empty value counts
as "not set".

---

## 8. Other sources

Config files hold the values an application ships with. The sources in
this section change them at launch or at build time, without editing a
file.

### Relaxed names

A property has a canonical name in kebab case: lower-case words joined by
`-`, such as `shop.max-basket-size`. Each source may write the name its own
way, and the name still matches: `shop.maxBasketSize`,
`shop.max_basket_size` and `SHOP_MAXBASKETSIZE` all set it. Inside `[...]`,
a map key is taken exactly as written.

### Command line

```bash
dart run bin/main.dart --shop.max-basket-size=30 --spring.profiles.active=prod --debug
```

- `--key=value` sets `key`; only the first `=` separates.
- `--flag` alone sets `flag` to an empty value.
- A repeated option keeps all its values, joined with commas.
- A lone `--` ends the options.

A Flutter desktop app passes its arguments with
`SpringApplicationWidget(args: ...)`.

### Environment variables

`SHOP_MAXBASKETSIZE=20` sets `shop.max-basket-size`. The name is split at
`_` and lower-cased, and dashes do not matter. A part that is a number
becomes an index: `SHOP_HOSTS_0=eu` sets `shop.hosts[0]`.

Phones and browsers have no useful environment. A Flutter app reads it
only when the build defines `spring.flutter.scan-os-environment=true` (see
[Flutter](#lifecycle-hot-reload-environment)).

### `--dart-define` (Flutter and compiled apps)

Values given at build time with `--dart-define` are a property source just
below the command line, with the same relaxed names as environment
variables. They are how a Flutter app gets per-build settings, such as the
backend URL of a release build. The generator lists every key the
application can read (placeholders, `@ConfigurationProperties` fields,
`@ConditionalOnProperty` names, keys of `lib/resources/application*`). That
is needed because AOT and web builds only see defines whose names are
known at compile time.

```bash
flutter run --dart-define=SPRING_PROFILES_ACTIVE=prod --dart-define=SHOP_URL=https://neon.books
flutter build apk --dart-define-from-file=config/prod.json
```

A client app cannot keep secrets. `--dart-define` values, config files
and assets all end up inside the APK, the IPA or `main.dart.js`.

### `SPRING_APPLICATION_JSON`

A JSON object in the property `spring.application.json`, or in the
environment variable `SPRING_APPLICATION_JSON`. It is flattened into
properties just above the environment variables. This is handy where a
platform passes configuration as one variable.

```bash
SPRING_APPLICATION_JSON='{"shop":{"max-basket-size":30}}' dart run bin/main.dart
```

### In code

`SpringApplication(defaultProperties: {...})` gives values that sit below
the config files: fallbacks that any file can override.
`run(properties: ...)` (and `springBootTest(properties: ...)` in tests)
gives values that sit above everything.

---

## 9. Which source wins

When several sources set the same key, the highest one wins. From the
highest:

1. `run(properties: ...)` and `springBootTest(properties: ...)`
2. Command-line arguments
3. `--dart-define` values
4. `SPRING_APPLICATION_JSON`
5. OS environment variables (not read by Flutter apps unless switched on)
6. `${random.*}`
7. Config files, in this order:
   - an imported file above the file that imports it;
   - `spring.config.import` given on the command line or in the
     environment, then `additional-location`, then the locations, with
     `file:./` above `classpath:/`;
   - within a group, profile files above plain ones, the last active
     profile highest;
   - `.properties` above `.yml` above `.yaml`;
   - a later document above an earlier one.
8. `@PropertySource` files
9. `SpringApplication(defaultProperties: ...)`

---

## 10. Your own properties

An application's own settings live in the same files as the framework's,
under a prefix of its own (`shop.*` here). Dart code reads them in four
ways, from the simplest:

| Way | For |
|---|---|
| [`@Value`](#one-value-value) | One value in a bean's constructor or field |
| [`@ConfigurationProperties`](#a-group-configurationproperties) | A typed object for a whole prefix: nested objects, lists, maps, validation |
| [`Environment`](#the-environment-directly) | Reading a key in code, when the key is only known at run time |
| [`Binder`](#binder-structures-without-a-class) | Binding a part of the configuration to a type on demand, without a class |

### One value: `@Value`

`@Value` injects one setting into a bean. It suits a value or two; for
more, a [`@ConfigurationProperties`](#a-group-configurationproperties)
class keeps them together.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  title: NEON Books
  max-basket-size: 20
  checkout-timeout: 30s
  currencies: EUR,USD
  beta: true
```

</td><td>

```properties
shop.title=NEON Books
shop.max-basket-size=20
shop.checkout-timeout=30s
shop.currencies=EUR,USD
shop.beta=true
```

</td></tr>
</table>

```dart
@Service()
class Checkout {
  Checkout(
    @Value(r'${shop.title}') this.title,                 // a String as is
    @Value(r'${shop.max-basket-size}') this.maxItems,    // converted to int
    @Value(r'${shop.checkout-timeout}') this.timeout,    // 30s → Duration
    @Value(r'${shop.currencies}') this.currencies,       // EUR,USD → List<String>
    @Value(r'${shop.beta:false}') this.beta,             // false when not set
    @Value(r'${shop.motto:}') this.motto,                // empty when not set
  );

  final String title;
  final int maxItems;
  final Duration timeout;
  final List<String> currencies;
  final bool beta;
  final String motto;
}
```

- Write the string as a raw string (`r'${...}'`), because `'${...}'` is
  Dart's string interpolation.
- The value is converted to the parameter's type: numbers, `bool`,
  `Duration`, `DataSize`, enums, lists. A value that cannot be converted
  fails the start, naming the key.
- A missing key without a default fails the start. A nullable parameter
  (`String? motto`) gets `null` instead.
- `@Value` reads one key, so a YAML list (`currencies: [EUR, USD]`) is not
  found: write the list as a comma-separated value, as above (see
  [Lists](#lists)).
- `#{...}` evaluates SpEL after the placeholders are replaced:
  `@Value(r'#{${shop.max-basket-size} * 2}') int limit`.
- On a field: `@Value(r'${shop.title}') late final String title;`.

Spring (Java):

```java
@Service
class Checkout {
  Checkout(@Value("${shop.title}") String title,
           @Value("${shop.beta:false}") boolean beta) { ... }
}
```

### A group: `@ConfigurationProperties`

A `@ConfigurationProperties` class gives a whole prefix a typed home. Each
field is bound from the key with the field's name in kebab case
(`maxBasketSize` reads `shop.max-basket-size`), and nested classes from
deeper keys. The class becomes a bean, so you inject it wherever the
settings are needed. Use it as soon as a feature has more than a couple of
settings: the keys are listed in one place, typed, and can be validated at
the start.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  title: NEON Books
  max-basket-size: 20
  checkout-timeout: 30s
  currencies: [EUR, USD]
  payment:
    provider: stripe
    timeout: 5s
  servers:
    - name: eu
      url: https://eu.neon.books
    - name: us
      url: https://us.neon.books
  headers:
    X-Shop: neon
  warehouses:
    berlin:
      capacity: 5000
      open: true
    madrid:
      capacity: 2000
```

</td><td>

```properties
shop.title=NEON Books
shop.max-basket-size=20
shop.checkout-timeout=30s
shop.currencies=EUR,USD
shop.payment.provider=stripe
shop.payment.timeout=5s
shop.servers[0].name=eu
shop.servers[0].url=https://eu.neon.books
shop.servers[1].name=us
shop.servers[1].url=https://us.neon.books
shop.headers.X-Shop=neon
shop.warehouses.berlin.capacity=5000
shop.warehouses.berlin.open=true
shop.warehouses.madrid.capacity=2000
```

</td></tr>
</table>

```dart
@ConfigurationProperties('shop')
class ShopProperties {
  String title = 'Shop';                          // shop.title
  int maxBasketSize = 10;                         // shop.max-basket-size
  Duration checkoutTimeout = const Duration(minutes: 1);
  List<String> currencies = ['EUR'];              // a comma list or [0], [1]
  Payment payment = Payment();                    // a nested object
  List<Server> servers = [];                      // a list of objects
  Map<String, String> headers = {};               // a map of values
  Map<String, Warehouse> warehouses = {};         // a map of objects
}

class Payment {
  String provider = 'none';
  Duration timeout = const Duration(seconds: 10);
}

class Server {
  String name = '';
  String url = '';
}

class Warehouse {
  int capacity = 0;
  bool open = false;
}
```

A service and a widget use it like any other bean:

```dart
@Service()
class Shipping {
  Shipping(this.shop);
  final ShopProperties shop;

  int capacityOf(String city) => shop.warehouses[city]?.capacity ?? 0;
  Uri serverUrl(String name) =>
      Uri.parse(shop.servers.firstWhere((s) => s.name == name).url);
}

class BasketHeader extends StatelessWidget {
  const BasketHeader({super.key});

  @override
  Widget build(BuildContext context) {
    // spring_boot_starter_flutter gives widgets the beans.
    final shop = context.bean<ShopProperties>();
    return Text('${shop.title}: up to ${shop.maxBasketSize} items');
  }
}
```

- A field keeps its default when its key is not set.
- `@Name('import')` binds a field from another key. It is needed when the
  key is a Dart keyword such as `import` or `default`.
- A list comes whole from one source (see [Lists](#lists)). Map entries
  come from every source, and a higher source wins per key.
- Keys under the prefix that match no field are ignored.
  `@ConfigurationProperties('shop', ignoreUnknownFields: false)` fails the
  start for them instead, which catches typos.

**Immutable classes: constructor binding.** A class whose only
constructor has parameters is bound through that constructor, so its
fields can be `final`:

```dart
@ConfigurationProperties('shop.payment')
class PaymentProperties {
  const PaymentProperties(
    this.provider, {                              // required: must be set
    @DefaultValue('5s') required this.timeout,    // 5s when not set
    this.retries = 3,                             // a Dart default works too
    this.webhookSecret,                           // nullable: null when not set
  });

  final String provider;
  final Duration timeout;
  final int retries;
  final String? webhookSecret;
}
```

**Checked at the start.** With `@Validated()`, the constraint annotations
are checked once the values are bound. An invalid value stops the start
with a report that names the key, so a wrong setting never reaches a
running application:

```dart
@ConfigurationProperties('shop')
@Validated()
class ShopLimits {
  @Min(1)
  @Max(100)
  int maxBasketSize = 10;

  @NotBlank()
  String title = 'Shop';

  @SizeConstraint(min: 1)        // @Size; named SizeConstraint in Flutter apps
  List<String> currencies = ['EUR'];
}
```

With `shop.max-basket-size=0`, the start fails with:

```
***************************
APPLICATION FAILED TO START
***************************

Description:

Binding to target properties under 'shop' failed:

  - shop.max-basket-size: must be greater than or equal to 1 (was "0")

Action:

Update the application's configuration (lib/resources/application.properties, command line or environment).
```

Spring (Java):

```java
@ConfigurationProperties("shop")
@Validated
public class ShopLimits {
  @Min(1) @Max(100) private int maxBasketSize = 10;
  // getters and setters
}
```

Differences from Spring: no `@EnableConfigurationProperties` or
`@ConfigurationPropertiesScan` is needed, because the annotation makes the
class a bean. Fields are bound directly, without getters and setters.

### The environment directly

Any bean can take the `Environment` and read a key in code. Placeholders
are resolved and relaxed names are found. Use it when the key is only
known at run time, or for a one-off check:

```dart
@Service()
class FeatureFlags {
  FeatureFlags(this.env);
  final Environment env;

  bool get betaOn => env.getPropertyAs<bool>('shop.beta', defaultValue: false)!;
  int get maxItems => env.getPropertyAs<int>('shop.max-basket-size') ?? 10;
  String get title => env.getRequiredProperty('shop.title');   // throws when missing
  bool get hasMotto => env.containsProperty('shop.motto');
  String banner() => env.resolvePlaceholders(r'Welcome to ${shop.title}');
  bool get isProd => env.acceptsProfiles(Profiles.of(['prod']));
}
```

### `Binder`: structures without a class

`Binder` binds a part of the configuration to a type on demand, with the
same rules as `@ConfigurationProperties`. It is for code that needs a
list or a map once, such as a starter reading its settings, where a class
of its own would be too much:

```dart
final binder = Binder.get(environment);
// A YAML list, indexed keys or a comma list: all give a List.
final hosts = binder
    .bind('shop.hosts', const ListType(ClassType<String>()))
    .orElse(const []);
final limits = binder
    .bind('shop.limits', const MapType(ClassType<String>(), ClassType<int>()))
    .orElse(const {});
```

### Beans that depend on the configuration

A setting can also decide whether a bean exists at all.
`@ConditionalOnProperty` creates the bean only when a key has a given
value, and `@Profile` only when a profile is active. A feature can then
be switched on per environment without an `if` in the code:

```dart
// Only when shop.beta=true.
@Service()
@ConditionalOnProperty('shop.beta', havingValue: 'true')
class BetaRecommendations implements Recommendations { ... }

// Only with the prod profile.
@Service()
@Profile(['prod'])
class StripePayments implements Payments { ... }
```

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  beta: true
```

</td><td>

```properties
shop.beta=true
```

</td></tr>
</table>

---

## 11. Reference: the application

These keys belong to `spring_boot_dart`, which every application uses.
They name the application and change how it starts.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  application:
    name: shop
  main:
    banner-mode: log
    log-startup-info: true
    lazy-initialization: false
    register-shutdown-hook: true
    allow-bean-definition-overriding: false
  banner:
    location: classpath:banner.txt
  autoconfigure:
    exclude:
      - cacheAutoConfiguration
debug: false
```

</td><td>

```properties
spring.application.name=shop
spring.main.banner-mode=log
spring.main.log-startup-info=true
spring.main.lazy-initialization=false
spring.main.register-shutdown-hook=true
spring.main.allow-bean-definition-overriding=false
spring.banner.location=classpath:banner.txt
spring.autoconfigure.exclude=cacheAutoConfiguration
debug=false
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.application.name` | string | — | The application's name: the context's id, and the name in the startup lines (`application` when not set) |
| `spring.main.banner-mode` | `console` / `log` / `off` | `console`, or `SpringApplication(bannerMode:)` | Where the startup banner goes: printed, logged, or nowhere |
| `spring.banner.location` | location | `classpath:banner.txt` | The banner file. `${spring-boot.version}`, `${spring-boot.formatted-version}` and other `${...}` in it are replaced |
| `spring.main.log-startup-info` | bool | `true` | Logs the "Starting …", active profiles and "Started … in N seconds" lines |
| `spring.main.lazy-initialization` | bool | `false` | Creates every bean on first use instead of at the start: a faster start, but a broken bean fails later |
| `spring.main.register-shutdown-hook` | bool | `false` (Spring Boot: `true`) | Closes the context on SIGINT or SIGTERM, so `@PreDestroy` methods run (VM only). Off by default because listening for signals keeps a Dart program alive |
| `spring.main.allow-bean-definition-overriding` | bool | `false` | A second bean with the same name replaces the first instead of failing the start |
| `spring.main.cloud-platform` | platform name or `none` | detected | Forces the [cloud platform](#documents-for-some-profiles-or-platforms) |
| `spring.autoconfigure.exclude` | list | — | Auto-configurations not to apply, by class or module name |
| `debug` | any | — | Any value but `false` (for example `--debug`) logs the condition evaluation report: which auto-configured beans were created, and why the others were not |
| `spring.application.json` | JSON | — | Properties as one JSON object (see [`SPRING_APPLICATION_JSON`](#spring_application_json)) |

### Messages

Translated texts live in `lib/resources/messages.properties`, with one
`messages_<locale>.properties` per language (`messages_de.properties`).
Code reads them by key with `context.getMessage`, and Flutter widgets with
`context.message`. The message source is created when `messages.properties`
of a configured base name exists.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  messages:
    basename: [messages, i18n/errors]
    encoding: UTF-8
    cache-duration: 10s
    fallback-to-system-locale: true
    use-code-as-default-message: false
    always-use-message-format: false
    default-locale: en
    common-messages: classpath:common.properties
```

</td><td>

```properties
spring.messages.basename=messages,i18n/errors
spring.messages.encoding=UTF-8
spring.messages.cache-duration=10s
spring.messages.fallback-to-system-locale=true
spring.messages.use-code-as-default-message=false
spring.messages.always-use-message-format=false
spring.messages.default-locale=en
spring.messages.common-messages=classpath:common.properties
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.messages.basename` | list | `messages` | The base names of the files. `i18n/errors` (or `i18n.errors`) reads `i18n/errors_{locale}.properties` |
| `spring.messages.encoding` | charset | UTF-8 | The files' encoding; an unknown one fails the start |
| `spring.messages.cache-duration` | duration (a plain number is seconds) | kept forever | How long a loaded file is kept before it is read again |
| `spring.messages.fallback-to-system-locale` | bool | `true` | Tries the system's locale before the file without a locale |
| `spring.messages.use-code-as-default-message` | bool | `false` | A missing key returns the key itself instead of failing |
| `spring.messages.always-use-message-format` | bool | `false` | Formats messages without arguments too, so `''` becomes `'` |
| `spring.messages.default-locale` | locale | — | A locale tried before the system's (not in Spring Boot) |
| `spring.messages.common-messages` | list of locations | — | Texts shared by every locale; a later file wins |

### JSON (`ObjectMapper`)

These keys configure the `ObjectMapper` that reads and writes JSON, such
as request and response bodies. They apply to the auto-configured mapper,
the one the application gets when it declares none. Each switch is on only
when its value is exactly `true`; any other value turns it off.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  jackson:
    property-naming-strategy: SNAKE_CASE
    default-property-inclusion: non_null
    time-zone: UTC
    serialization:
      indent-output: true
      write-dates-as-timestamps: false
    deserialization:
      fail-on-unknown-properties: true
    mapper:
      sort-properties-alphabetically: false
```

</td><td>

```properties
spring.jackson.property-naming-strategy=SNAKE_CASE
spring.jackson.default-property-inclusion=non_null
spring.jackson.time-zone=UTC
spring.jackson.serialization.indent-output=true
spring.jackson.serialization.write-dates-as-timestamps=false
spring.jackson.deserialization.fail-on-unknown-properties=true
spring.jackson.mapper.sort-properties-alphabetically=false
```

</td></tr>
</table>

| Key | Default | Meaning |
|---|---|---|
| `spring.jackson.property-naming-strategy` | `LOWER_CAMEL_CASE` | How field names become JSON names: `SNAKE_CASE`, `UPPER_SNAKE_CASE`, `UPPER_CAMEL_CASE`, `LOWER_CAMEL_CASE`, `LOWER_CASE`, `KEBAB_CASE`, `LOWER_DOT_CASE` |
| `spring.jackson.default-property-inclusion` | `always` | Which properties are written: `always`, `non_null`, `non_absent`, `non_empty`, `non_default` |
| `spring.jackson.time-zone` | — | `UTC`, `Z` or a fixed offset (`+02:00`); named zones such as `Europe/Berlin` fail, as Dart has no time zone database |
| `spring.jackson.serialization.indent-output` | `false` | Pretty-printed JSON |
| `spring.jackson.serialization.write-dates-as-timestamps` | `false` | Dates as numbers. `spring.jackson.datatype.datetime.write-dates-as-timestamps` does the same and wins |
| `spring.jackson.serialization.write-durations-as-timestamps` | `false` | Durations as numbers |
| `spring.jackson.serialization.write-date-timestamps-as-nanoseconds` | `true` | Timestamps with a fraction |
| `spring.jackson.deserialization.read-date-timestamps-as-nanoseconds` | `true` | Reads timestamps with a fraction |
| `spring.jackson.deserialization.fail-on-unknown-properties` | `false` | An unknown JSON property fails the read |
| `spring.jackson.deserialization.accept-float-as-int` | `true` | `1.0` can be read into an `int` |
| `spring.jackson.deserialization.fail-on-null-for-primitives` | `true` | `null` for a non-nullable number or `bool` fails the read |
| `spring.jackson.mapper.sort-properties-alphabetically` | `true` | Writes properties in alphabetical order |
| `spring.jackson.mapper.default-view-inclusion` | `false` | Properties without `@JsonView` appear in every view |

The other three `datetime` timestamp switches also have a
`spring.jackson.datatype.datetime.*` form that wins over the one above.
Any other `spring.jackson.*` key (`date-format`, `locale`, `visibility`,
`generator.*`, `parser.*`, …) is logged as a warning and ignored.

---

## 12. Reference: logging

`spring_boot_starter_logging` gives an application formatted console
lines, a log file that rolls over and an in-memory buffer for an in-app
log screen. The `logging.level.*` and `logging.group.*` keys work without
the starter too: `spring_boot_dart` applies them. Patterns use Logback's
syntax.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
logging:
  level:
    root: info
    shop: debug
    spring_boot_dart: warn
  group:
    payments: [shop.payments, shop.billing]
  pattern:
    console: "%d %-5level %logger{36} - %msg%n"
    dateformat: "HH:mm:ss.SSS"
  file:
    name: logs/shop.log
  logback:
    rollingpolicy:
      max-file-size: 10MB
      max-history: 7
  threshold:
    file: info
  buffer:
    capacity: 2000
spring:
  output:
    ansi:
      enabled: never
```

</td><td>

```properties
logging.level.root=info
logging.level.shop=debug
logging.level.spring_boot_dart=warn
logging.group.payments=shop.payments,shop.billing
logging.pattern.console=%d %-5level %logger{36} - %msg%n
logging.pattern.dateformat=HH:mm:ss.SSS
logging.file.name=logs/shop.log
logging.logback.rollingpolicy.max-file-size=10MB
logging.logback.rollingpolicy.max-history=7
logging.threshold.file=info
logging.buffer.capacity=2000
spring.output.ansi.enabled=never
```

</td></tr>
</table>

The levels are `trace`, `debug`, `info`, `warn` (or `warning`), `error`
(or `fatal`) and `off` (or `false`). An unknown level fails the start.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `logging.enabled` | bool | `true` | `false`: the starter sets up nothing, no outputs and no buffer |
| `logging.level.root` | level | `info` | The level of every logger without one of its own; a plain `logging.level` works too |
| `logging.level.<logger>` | level | inherited | The level of a logger and the loggers below it (`LOGGING_LEVEL_SHOP=debug` as a variable) |
| `logging.group.<group>` | list | — | Logger names; `logging.level.<group>` then sets them all. There are no predefined `web` or `sql` groups |
| `logging.pattern.console` | pattern | Spring Boot's | The console line format; an empty pattern turns the console off |
| `logging.pattern.file` | pattern | Spring Boot's | The file line format; an empty pattern means no file |
| `logging.pattern.dateformat` | date pattern | `yyyy-MM-dd'T'HH:mm:ss.SSSXXX` | The format of `%d` in the default patterns (times are UTC) |
| `logging.pattern.level` | pattern | `%5p` | The level column |
| `logging.pattern.correlation` | pattern | empty | The correlation column |
| `logging.exception-conversion-word` | pattern | `%wEx` | How exceptions are printed |
| `logging.include-application-name` | bool | `true` | Puts `[spring.application.name]` into the default patterns |
| `logging.include-application-group` | bool | `true` | Puts `[spring.application.group]` into the default patterns |
| `logging.console.enabled` | bool | `true` | The console output |
| `logging.buffer.enabled` | bool | `true` | The in-memory `LogBuffer` |
| `logging.buffer.capacity` | int | `1000` | How many records the buffer keeps |
| `logging.threshold.console` / `.file` / `.buffer` | level | `trace` | The lowest level each output takes |
| `logging.file.name` | path | — | The log file; `${LOG_FILE}` in patterns |
| `logging.file.path` | directory | — | Writes `<dir>/spring.log` when no name is set; `${LOG_PATH}` in patterns |
| `logging.charset.file` | charset | UTF-8 | The file's encoding. `logging.charset.console` is only checked |
| `logging.logback.rollingpolicy.max-file-size` | data size | `10MB` | The size at which the file rolls over to `.1`, `.2`, … |
| `logging.logback.rollingpolicy.max-history` | int | `7` | How many rolled files are kept |
| `logging.logback.rollingpolicy.total-size-cap` | data size | `0B` (no limit) | The largest total size of the rolled files |
| `logging.logback.rollingpolicy.clean-history-on-start` | bool | `false` | Deletes the rolled files when the application starts |
| `spring.output.ansi.enabled` | `always` / `detect` / `never` | `always` | Colours on the console: `%clr`, or the time, level and logger of a pattern without colours. `never` gives plain text, for logs read by a program. `detect` colours only on a terminal or in a Flutter debug or profile build (Spring Boot's default) |

Log files are not written on the web; a warning says so.
`logging.logback.rollingpolicy.file-name-pattern` and the old
`logging.file.max-size`, `max-history`, `total-size-cap` and
`clean-history-on-start` keys are ignored with a warning. There is no
`logging.config`, `logback.xml` or `logging.structured.*`.

---

## 13. Reference: scheduling

`spring_boot_starter_scheduling` runs `@Scheduled` methods: a report
every morning, a cache refresh every five minutes. With the starter as a
dependency, scheduling is on; no `@EnableScheduling` is needed.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  task:
    scheduling:
      enabled: true
      shutdown:
        await-termination: true
        await-termination-period: 30s
shop:
  report:
    cron: "0 0 6 * * MON-FRI"
    every: 5m
```

</td><td>

```properties
spring.task.scheduling.enabled=true
spring.task.scheduling.shutdown.await-termination=true
spring.task.scheduling.shutdown.await-termination-period=30s
shop.report.cron=0 0 6 * * MON-FRI
shop.report.every=5m
```

</td></tr>
</table>

The schedule itself can come from the configuration, so each environment
runs its jobs at its own times:

```dart
// 6:00 UTC on weekdays; the cron comes from shop.report.cron.
@Scheduled(cron: r'${shop.report.cron}', zone: 'UTC')
void dailyReport() { ... }

// Every shop.report.every, or every minute when it is not set.
@Scheduled(fixedRateString: r'${shop.report.every:1m}')
void refresh() { ... }
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.task.scheduling.enabled` | bool | `true` | `false`: no `@Scheduled` method runs, which keeps tests predictable. The task executor stays |
| `spring.task.scheduling.shutdown.await-termination` | bool | `false` | Closing the context with `closeAsync()` waits for the runs going on |
| `spring.task.scheduling.shutdown.await-termination-period` | duration | no limit | The longest such wait |

The `@Scheduled` attributes accept placeholders; a missing key without a
default fails the start. A cron of `-` switches the task off, so
`cron: r'${jobs.cleanup:-}'` runs only where a property sets it. `zone` is
`UTC` (also `Z` or `GMT`) or empty for local time; other zones fail, as
Dart has no time zone database. Not supported, because Dart has no thread
pools: `spring.task.scheduling.pool.*`, `thread-name-prefix` and
`spring.task.execution.*`.

---

## 14. Reference: caching

`spring_boot_starter_cache` keeps the results of `@Cacheable` methods, so
a slow call (a remote price list, a heavy query) runs once per key. These
keys choose the cache store and limit it.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  cache:
    type: simple
    cache-names: [books, prices]
    simple:
      time-to-live: 10m
      max-size: 500
      caches:
        prices:
          time-to-live: 30s
```

</td><td>

```properties
spring.cache.type=simple
spring.cache.cache-names=books,prices
spring.cache.simple.time-to-live=10m
spring.cache.simple.max-size=500
spring.cache.simple.caches.prices.time-to-live=30s
```

</td></tr>
</table>

Here every cache keeps at most 500 entries for 10 minutes, and `prices`
keeps its entries only 30 seconds.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.cache.type` | `generic` / `simple` / `none` | `generic` with `Cache` beans, else `simple` | `simple` keeps entries in memory; `generic` uses the application's `Cache` beans; `none` caches nothing, so the methods always run (`NoOpCacheManager`) |
| `spring.cache.cache-names` | list | — (caches are created on demand) | A fixed set of caches; an annotation that names another cache then fails |
| `spring.cache.simple.time-to-live` | duration | none | An entry expires this long after it was written |
| `spring.cache.simple.max-size` | int | none | The most entries per cache; when full, the least recently used entry goes |
| `spring.cache.simple.caches.<name>.time-to-live` | duration | the global one | The same, for one cache |
| `spring.cache.simple.caches.<name>.max-size` | int | the global one | The same, for one cache |

The `spring.cache.simple.*` keys are this starter's own; Spring Boot's
simple cache has no settings. Not supported: Caffeine, Redis and the
other stores.

---

## 15. Reference: Feign clients

`spring_boot_starter_feign` turns an annotated interface into an HTTP
client. These keys set each client's URL, timeouts, logging and default
headers, so they can differ per environment without code.

`<client>` is the client's `contextId`, or else its name, as in
`@FeignClient('catalog')`. The entry `default` applies to every client;
a client's own entry wins over it.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  cloud:
    openfeign:
      client:
        decode-slash: true
        config:
          default:
            connect-timeout: 5s
            read-timeout: 30s
            logger-level: basic
          catalog:
            url: https://api.neon.books
            read-timeout: 10s
            dismiss404: true
            default-request-headers:
              X-Client: [shop]
            default-query-parameters:
              lang: [en]
            retryer: catalogRetryer
            request-interceptors: [authInterceptor]
            event-stream:
              reconnect-delay: 2s
```

</td><td>

```properties
spring.cloud.openfeign.client.decode-slash=true
spring.cloud.openfeign.client.config.default.connect-timeout=5s
spring.cloud.openfeign.client.config.default.read-timeout=30s
spring.cloud.openfeign.client.config.default.logger-level=basic
spring.cloud.openfeign.client.config.catalog.url=https://api.neon.books
spring.cloud.openfeign.client.config.catalog.read-timeout=10s
spring.cloud.openfeign.client.config.catalog.dismiss404=true
spring.cloud.openfeign.client.config.catalog.default-request-headers.X-Client=shop
spring.cloud.openfeign.client.config.catalog.default-query-parameters.lang=en
spring.cloud.openfeign.client.config.catalog.retryer=catalogRetryer
spring.cloud.openfeign.client.config.catalog.request-interceptors=authInterceptor
spring.cloud.openfeign.client.config.catalog.event-stream.reconnect-delay=2s
```

</td></tr>
</table>

The keys under `spring.cloud.openfeign.client.config.<client>.`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `url` | URL | — | The base URL when `@FeignClient(url:)` is empty; `http://` is added when the scheme is missing |
| `read-timeout` | duration | `60s` (`0`: none) | The longest wait for the response, then between two chunks of the body; not a limit for the whole call |
| `connect-timeout` | duration | `10s` (`0`: none) | **Under `default` only**: the connect timeout of the transport all clients share |
| `logger-level` | `none` / `basic` / `headers` / `full` | `none` | How much of each call is logged, under the logger `feign.<Interface>` at debug level |
| `dismiss404` | bool | `false` | A 404 gives `null` (or a `ResponseEntity`) instead of an exception; `void` methods still throw |
| `default-request-headers.<Header>` | list | — | Headers sent when the request has none of that name; `default`'s and the client's are merged |
| `default-query-parameters.<param>` | list | — | The same for query parameters |
| `follow-redirects` | bool | `true` | Follows redirects; with `false` a 3xx answer is an error |
| `retryer` | bean or class name | never retries | The client's `Retryer` |
| `error-decoder` | bean or class name | `DefaultErrorDecoder` | The client's `ErrorDecoder` |
| `request-interceptors` | list of bean or class names | — | More interceptors: `default`'s, then the client's, after those the client has anyway |
| `event-stream.reconnect` | bool | `true` | An `EventStream<T>` method connects again when the connection ends |
| `event-stream.reconnect-delay` | duration | `3s`, or the server's `retry:` | The wait before connecting again |
| `event-stream.max-attempts` | int | no limit | How many connections in a row may end without an event before the stream gives up |

| Global key | Type | Default | Meaning |
|---|---|---|---|
| `spring.cloud.openfeign.client.decode-slash` | bool | `true` | `false` encodes `/` in path variables as `%2F` |

`retryer`, `error-decoder` and `request-interceptors` name beans. Spring
takes class names and creates the class; here a class name must match
exactly one bean. The `event-stream.*` keys are this starter's own, as
Spring Cloud OpenFeign cannot stream. Not supported: service discovery
and load balancing (every client needs a URL), circuit breakers, a
per-client `connect-timeout`, compression, and the `encoder`, `decoder`,
`contract` and `capabilities` keys.

---

## 16. Reference: WebSocket clients

`spring_boot_starter_websocket` turns an annotated interface into a
WebSocket client that reconnects by itself. These keys set its address,
handshake timeout, reconnection and headers. They are this starter's own:
Spring Boot has no properties for WebSocket clients.

`<client>` is the name in `@WebSocketClient('prices')`; the entry
`default` applies to all clients, and a client's own entry wins.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  websocket:
    client:
      config:
        default:
          connect-timeout: 10s
          reconnect:
            delay: 1s
            multiplier: 2
            max-delay: 30s
        prices:
          url: wss://ws.neon.books/prices
          reconnect:
            jitter: 500ms
            max-retries: 10
          default-request-headers:
            Authorization: [Bearer token]
```

</td><td>

```properties
spring.websocket.client.config.default.connect-timeout=10s
spring.websocket.client.config.default.reconnect.delay=1s
spring.websocket.client.config.default.reconnect.multiplier=2
spring.websocket.client.config.default.reconnect.max-delay=30s
spring.websocket.client.config.prices.url=wss://ws.neon.books/prices
spring.websocket.client.config.prices.reconnect.jitter=500ms
spring.websocket.client.config.prices.reconnect.max-retries=10
spring.websocket.client.config.prices.default-request-headers.Authorization=Bearer token
```

</td></tr>
</table>

After a lost connection, the client waits `delay`, then twice as long
after each further failure, never more than `max-delay`. `jitter` adds or
takes a random part, so many clients do not reconnect at the same moment.

The keys under `spring.websocket.client.config.<client>.`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `url` | `ws://` or `wss://` URL | — | The address, when `@WebSocketClient(url:)` is not set |
| `connect-timeout` | duration | `10s` | The longest a handshake may take |
| `reconnect.enabled` | bool | `true` | Reconnects while someone listens to the messages |
| `reconnect.delay` | duration | `1s` | The first wait |
| `reconnect.multiplier` | number ≥ 1 | `2` | What each further wait is multiplied by; `1` for a fixed delay |
| `reconnect.max-delay` | duration | `30s` | The longest wait |
| `reconnect.jitter` | duration | `0` | A random part added or taken, scaled like the delay |
| `reconnect.max-retries` | int | no limit | Attempts in a row before giving up |
| `default-request-headers.<Header>` | list | — | Headers sent with the handshake; not possible in browsers |

An invalid `reconnect.*` value fails the start. Not supported: heartbeats,
STOMP and SockJS.

---

## 17. Reference: Flutter

`spring_boot_starter_flutter` reads the keys of this section to build the
app widget, its themes and fonts, and to follow the app's lifecycle and
hot reloads. The starter's README introduces the themes in
[Themes from properties](../spring_boot_starter_flutter/README.md#themes-from-properties);
this section is the full reference.

### The app widget

`SpringApplicationWidget(home: ...)` builds the app widget
(`MaterialApp`, `CupertinoApp` or `WidgetsApp`) from these keys. An app
that passes `child:` instead builds its own app widget, and the keys are
not used.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    app:
      type: material
      title: NEON Books
      debug-banner: false
      locales: en, ja, pt_BR
```

</td><td>

```properties
spring.flutter.app.type=material
spring.flutter.app.title=NEON Books
spring.flutter.app.debug-banner=false
spring.flutter.app.locales=en,ja,pt_BR
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.app.type` | `widgets` / `material` / `cupertino` | `widgets` | The app widget: `WidgetsApp`, `MaterialApp` (needed by `Scaffold` and `AppBar`) or `CupertinoApp` |
| `spring.flutter.app.title` | string | empty | The app's name for the OS, shown in the task switcher or the browser tab |
| `spring.flutter.app.debug-banner` | `true` / `false` | `true` | Flutter's DEBUG banner in debug builds |
| `spring.flutter.app.locales` | comma list of locales (`en`, `pt_BR`, `zh_Hant_TW`) | the languages of the messages files | The locales the app supports. By default `messages.properties` counts as English, and each `messages_<locale>.properties` of `spring.messages.basename` adds its locale |

Write `locales`, and in Flutter apps `spring.messages.basename`, as one
comma-separated value, also in YAML. The app widget reads them as single
values, so a YAML list (`[en, ja]`) is not seen.

### Themes, step by step

The theme can be set entirely from properties: colours, fonts, shapes,
components, a dark theme and themes of your own. Designers and
developers then change the look in one file, per profile or per
platform, without touching widget code. The steps below build a theme
from properties and use it from Dart. Each step works on its own; the
[full property reference](#themes-every-property) follows.

#### Step 1: a Material app with a palette from one color

`spring.flutter.app.type: material` makes the app a `MaterialApp`, which
`Scaffold`, `AppBar` and the other Material widgets need. `seed-color`
makes the whole Material 3 palette (primary, secondary, surfaces, …) from
one color.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    app:
      type: material
    theme:
      seed-color: deepPurple
```

</td><td>

```properties
spring.flutter.app.type=material
spring.flutter.theme.seed-color=deepPurple
```

</td></tr>
</table>

```dart
@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const HomePage(),   // the MaterialApp is built from the properties
  ),
);
```

#### Step 2: your own colors, and reading them in Dart

Any role of the palette can be set; the others still come from the seed.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      seed-color: '#0057B8'
      colors:
        secondary: '#FFD700'
        error: '#B3261E'
        surface: '#FAFAFA'
        surface-container-low: grey.shade100
```

</td><td>

```properties
spring.flutter.theme.seed-color=#0057B8
spring.flutter.theme.colors.secondary=#FFD700
spring.flutter.theme.colors.error=#B3261E
spring.flutter.theme.colors.surface=#FAFAFA
spring.flutter.theme.colors.surface-container-low=grey.shade100
```

</td></tr>
</table>

Material widgets use the colors by themselves. Your own widgets read them
like any Material color, or through `SpringTheme`, which works with every
app type, `widgets` and `cupertino` included:

```dart
@override
Widget build(BuildContext context) {
  final colors = Theme.of(context).colorScheme;          // Material apps
  final theme = SpringTheme.of(context);                 // any app type
  return Container(
    color: colors.surfaceContainerLow,
    child: Text(
      'Sale',
      style: TextStyle(color: theme.colorScheme.secondary),
    ),
  );
  // Or by the name used in the properties:
  // theme.role('surface-container-low')
}
```

#### Step 3: fonts and text styles

Put the font files in any directory listed under `flutter: assets:`. The
starter loads each file under the family name stored in the font itself,
so `Inter-SemiBold.ttf` becomes a weight of `Inter` and
`PlayfairDisplay-Bold.ttf` one of `Playfair Display`. Then name the
families per text style.

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/fonts/        # Inter-Regular.ttf, Inter-SemiBold.ttf, PlayfairDisplay-Bold.ttf
```

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      typography:
        font-family: Inter
        font-family-fallback: [Noto Sans JP]
        display: { font-family: Playfair Display, weight: bold }
        title-large: { weight: semibold, size: 24 }
        body-medium: { height: 1.5 }
        code: { font-family: JetBrains Mono, size: 13 }
```

</td><td>

```properties
spring.flutter.theme.typography.font-family=Inter
spring.flutter.theme.typography.font-family-fallback=Noto Sans JP
spring.flutter.theme.typography.display.font-family=Playfair Display
spring.flutter.theme.typography.display.weight=bold
spring.flutter.theme.typography.title-large.weight=semibold
spring.flutter.theme.typography.title-large.size=24
spring.flutter.theme.typography.body-medium.height=1.5
spring.flutter.theme.typography.code.font-family=JetBrains Mono
spring.flutter.theme.typography.code.size=13
```

</td></tr>
</table>

```dart
Text('NEON Books', style: Theme.of(context).textTheme.displaySmall);   // Playfair Display
Text(isbn, style: SpringTheme.of(context).textStyle('code'));          // JetBrains Mono
```

#### Step 4: shapes and components

The shape scale changes every component that uses it (`medium` is the
cards' radius, for example). `components.*` adjusts one component; its
values name the theme's own tokens, such as a color role or a shape.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      shape:
        medium: 16
        large: 24
      components:
        button: { shape: full, min-height: 44 }
        card: { shape: large, color: surface-container-low, elevation: level0 }
        input: { style: outline, shape: small }
        app-bar: { center-title: true, title-style: title-large }
        navigation-bar: { label-behavior: onlyShowSelected }
```

</td><td>

```properties
spring.flutter.theme.shape.medium=16
spring.flutter.theme.shape.large=24
spring.flutter.theme.components.button.shape=full
spring.flutter.theme.components.button.min-height=44
spring.flutter.theme.components.card.shape=large
spring.flutter.theme.components.card.color=surface-container-low
spring.flutter.theme.components.card.elevation=level0
spring.flutter.theme.components.input.style=outline
spring.flutter.theme.components.input.shape=small
spring.flutter.theme.components.app-bar.center-title=true
spring.flutter.theme.components.app-bar.title-style=title-large
spring.flutter.theme.components.navigation-bar.label-behavior=onlyShowSelected
```

</td></tr>
</table>

Your own widgets read the same values:

```dart
final theme = SpringTheme.of(context);
DecoratedBox(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(theme.shape('large')),   // 24
  ),
);
```

#### Step 5: the dark theme and themes of your own

Everything above is shared by every theme. `themes.<name>` holds only what
a theme changes. `dark` and `light` always exist; any other name is a
theme of your own, and `extends` starts it from another theme.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      active: system
      seed-color: deepPurple
      themes:
        dark:
          seed-color: deepPurple.shade200
        ocean:
          seed-color: teal
          scheme-variant: vibrant
        ocean-night:
          extends: ocean
          brightness: dark
        sepia:
          colors:
            surface: '#F4ECD8'
            on-surface: '#5B4636'
          splash: none
```

</td><td>

```properties
spring.flutter.theme.active=system
spring.flutter.theme.seed-color=deepPurple
spring.flutter.theme.themes.dark.seed-color=deepPurple.shade200
spring.flutter.theme.themes.ocean.seed-color=teal
spring.flutter.theme.themes.ocean.scheme-variant=vibrant
spring.flutter.theme.themes.ocean-night.extends=ocean
spring.flutter.theme.themes.ocean-night.brightness=dark
spring.flutter.theme.themes.sepia.colors.surface=#F4ECD8
spring.flutter.theme.themes.sepia.colors.on-surface=#5B4636
spring.flutter.theme.themes.sepia.splash=none
```

</td></tr>
</table>

`active: system` shows `light` or `dark` following the device's mode;
`system-light` and `system-dark` pick other themes for each mode. Many
themes are easier to keep in one file each, imported with
`spring.config.import: classpath:themes/ocean.yml, classpath:themes/sepia.yml`
(see [a theme in its own file](#a-theme-in-its-own-file)).

#### Step 6: your own theme properties (tokens), and reading them in Dart

Some values have no place in Material's theme: a brand color, a banner
height, a badge text. They go under `tokens.<group>.<key>` and can differ
per theme like any other value. `spacing.<name>`, `motion.duration-<name>`
and `motion.easing-<name>` take names of your own too.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      tokens:
        brand:
          accent: '#FF6B00'
          banner-height: 120
          badge-text: NEW
      spacing:
        gutter: 20
      motion:
        duration-banner: 600ms
      themes:
        sepia:
          tokens:
            brand:
              accent: '#8B4513'
```

</td><td>

```properties
spring.flutter.theme.tokens.brand.accent=#FF6B00
spring.flutter.theme.tokens.brand.banner-height=120
spring.flutter.theme.tokens.brand.badge-text=NEW
spring.flutter.theme.spacing.gutter=20
spring.flutter.theme.motion.duration-banner=600ms
spring.flutter.theme.themes.sepia.tokens.brand.accent=#8B4513
```

</td></tr>
</table>

```dart
class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.of(context);               // the theme shown now
    return AnimatedContainer(
      duration: theme.duration('banner'),                 // 600ms
      height: theme.tokenNumber('brand.banner-height'),   // 120
      padding: EdgeInsets.all(theme.space('gutter')),     // 20
      color: theme.tokenColor('brand.accent'),            // #FF6B00, #8B4513 in sepia
      child: Text(theme.token('brand.badge-text') ?? ''), // NEW
    );
  }
}
```

A typed view keeps the token names in one place:

```dart
extension BrandTheme on SpringThemeData {
  Color get brandAccent => tokenColor('brand.accent') ?? colorScheme.primary;
  double get bannerHeight => tokenNumber('brand.banner-height') ?? 96;
}

// SpringTheme.of(context).brandAccent
```

Outside the widget tree, in a service or a test, take a theme by name
from the `SpringThemes` bean:
`themes.data('sepia').tokenColor('brand.accent')`.

#### Step 7: switching themes from Dart

The `ThemeSelection` bean decides which theme is shown. Selecting another
one changes the app at once, with Flutter's animation:

```dart
typedef ThemeMenuBeans = (
  ThemeSelection,
  SpringThemes,
);

class ThemeMenu extends SpringStatelessWidget<ThemeMenuBeans> {
  const ThemeMenu({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the selection or the themes change.
    final (
      selection,
      themes,
    ) = beans;
    return PopupMenuButton<String>(
      onSelected: selection.select,
      itemBuilder: (_) => [
        for (final name in ['system', ...themes.names])
          CheckedPopupMenuItem(
            value: name,
            checked: selection.active == name,
            child: Text(context.message('theme.$name', defaultMessage: name)),
          ),
      ],
    );
  }
}

// From a service, for example at night:
@Service()
class NightMode {
  NightMode(this.selection);
  final ThemeSelection selection;

  void on() => selection.select('dark');
  void followDevice() => selection.select('system');
}
```

#### Step 8: themes from a server

`SpringThemes.loadYaml` takes the same YAML at run time, with or without
the `spring.flutter.theme` prefix. It checks every theme first, so an
invalid one throws and changes nothing; otherwise the app shows the
change at once. A shop can ship a seasonal theme without a release:

```dart
@Service()
class RemoteThemes {
  RemoteThemes(this.themes, this.selection, this.api);
  final SpringThemes themes;
  final ThemeSelection selection;
  final ThemesApi api;                       // for example a @FeignClient

  Future<void> refresh() async {
    themes.loadYaml(await api.themesYaml());  // themes: { winter: { seed-color: lightBlue } }
    selection.select('winter');
  }

  void reset() => themes.unload();            // back to the files' themes
}
```

#### Step 9: code instead of properties

Properties cover most themes. For what they cannot express, declare
beans:

```dart
@Configuration()
class AppTheme {
  // Replaces the `light` Material theme made from the properties.
  // A `darkTheme` bean replaces the dark one; a CupertinoThemeData bean
  // the Cupertino ones.
  @Bean()
  ThemeData theme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    pageTransitionsTheme: const PageTransitionsTheme(),
  );
}

// Or adjust every Material theme made from the properties:
@Component()
@Order(10)
class RoundedChips implements ThemeCustomizer {
  @override
  ThemeData customize(ThemeData theme, SpringThemeData spring) => theme.copyWith(
    chipTheme: theme.chipTheme.copyWith(shape: const StadiumBorder()),
  );
}
```

#### Step 10: in tests

A test picks the theme with a property:

```dart
final app = springBootTest(
  springApplication,
  properties: {'spring.flutter.theme.active': 'dark'},
);

testWidgets('the dark theme', (tester) async {
  await tester.pumpWidget(SpringScope(
    applicationContext: app.context,
    child: const SpringApp(home: HomePage()),
  ));
  expect(SpringTheme.of(tester.element(find.byType(HomePage))).name, 'dark');
});
```

### Themes: every property

The theme properties have three parts. The root of `spring.flutter.theme`
is shared by every theme. `light` and `dark` always exist. Any number of
themes of your own live under `themes.<name>`, each holding only what it
changes. A value that is not set keeps Flutter's Material 3 default. Every
theme is read and checked when the app starts, so an invalid value or a
misspelled key fails the start instead of showing a wrong theme.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      active: system
      system-light: light
      system-dark: dark
      seed-color: deepPurple
      scheme-variant: tonalSpot
      contrast: 0
      colors:
        error: '#B3261E'
        surface-container-low: grey.shade100
      typography:
        font-family: Roboto
        font-family-fallback: [Noto Sans JP]
        defaults: { letter-spacing: 0.1 }
        display: { font-family: Roboto Condensed, weight: bold }
        title-large: { size: 22, weight: 500, height: 1.27 }
        code: { font-family: JetBrains Mono, size: 13 }
      shape:
        medium: 16
        large: 20
      elevation:
        level1: 2
      spacing:
        m: 16
      visual-density: adaptive
      tap-target-size: padded
      splash: sparkle
      motion:
        page-transition: zoom
        duration-medium: 250ms
        easing-standard: '0.2, 0, 0, 1'
      components:
        app-bar: { center-title: true, scrolled-under-elevation: level2 }
        button: { shape: full }
        card: { shape: large, color: surface-container-low }
        input: { style: outline, shape: small }
      tokens:
        brand: { accent: '#FF6B00', hero-height: 240 }
      cupertino:
        primary-color: '#007AFF'
      themes:
        dark:
          seed-color: deepPurple.shade200
        ocean:
          seed-color: teal
          shape: { large: 28 }
        ocean-night:
          extends: ocean
          brightness: dark
```

</td><td>

```properties
spring.flutter.theme.active=system
spring.flutter.theme.system-light=light
spring.flutter.theme.system-dark=dark
spring.flutter.theme.seed-color=deepPurple
spring.flutter.theme.scheme-variant=tonalSpot
spring.flutter.theme.contrast=0
spring.flutter.theme.colors.error=#B3261E
spring.flutter.theme.colors.surface-container-low=grey.shade100
spring.flutter.theme.typography.font-family=Roboto
spring.flutter.theme.typography.font-family-fallback=Noto Sans JP
spring.flutter.theme.typography.defaults.letter-spacing=0.1
spring.flutter.theme.typography.display.font-family=Roboto Condensed
spring.flutter.theme.typography.display.weight=bold
spring.flutter.theme.typography.title-large.size=22
spring.flutter.theme.typography.title-large.weight=500
spring.flutter.theme.typography.title-large.height=1.27
spring.flutter.theme.typography.code.font-family=JetBrains Mono
spring.flutter.theme.typography.code.size=13
spring.flutter.theme.shape.medium=16
spring.flutter.theme.shape.large=20
spring.flutter.theme.elevation.level1=2
spring.flutter.theme.spacing.m=16
spring.flutter.theme.visual-density=adaptive
spring.flutter.theme.tap-target-size=padded
spring.flutter.theme.splash=sparkle
spring.flutter.theme.motion.page-transition=zoom
spring.flutter.theme.motion.duration-medium=250ms
spring.flutter.theme.motion.easing-standard=0.2, 0, 0, 1
spring.flutter.theme.components.app-bar.center-title=true
spring.flutter.theme.components.app-bar.scrolled-under-elevation=level2
spring.flutter.theme.components.button.shape=full
spring.flutter.theme.components.card.shape=large
spring.flutter.theme.components.card.color=surface-container-low
spring.flutter.theme.components.input.style=outline
spring.flutter.theme.components.input.shape=small
spring.flutter.theme.tokens.brand.accent=#FF6B00
spring.flutter.theme.tokens.brand.hero-height=240
spring.flutter.theme.cupertino.primary-color=#007AFF
spring.flutter.theme.themes.dark.seed-color=deepPurple.shade200
spring.flutter.theme.themes.ocean.seed-color=teal
spring.flutter.theme.themes.ocean.shape.large=28
spring.flutter.theme.themes.ocean-night.extends=ocean
spring.flutter.theme.themes.ocean-night.brightness=dark
```

</td></tr>
</table>

**Which theme is shown.** These keys exist at the root only:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `active` | `system` or a theme name | `system` | The theme shown. `system` follows the device's light or dark mode. `ThemeSelection.select(...)` changes it at run time |
| `system-light` | theme name | `light` | What `system` shows in light mode |
| `system-dark` | theme name | `dark` | What `system` shows in dark mode |

**A theme.** These keys exist at the root and in each `themes.<name>`. A
theme starts from the root, or from the theme it `extends`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `extends` | theme name | — | In `themes.<name>` only: start from that theme instead of the root. Chains are allowed; a cycle fails |
| `brightness` | `light` / `dark` | `dark` for `dark`, else `light` | The theme's brightness |
| `seed-color` | color | Material's baseline palette | The color the whole palette is made from |
| `scheme-variant` | `tonalSpot`, `fidelity`, `content`, `vibrant`, `expressive`, `monochrome`, `neutral`, `rainbow`, `fruitSalad` | `tonalSpot` | How the palette is made from the seed |
| `contrast` | number from −1 to 1 | `0` | The palette's contrast |
| `colors.<role>` | color | from the seed | Any of the 46 `ColorScheme` roles in kebab case: `primary`, `on-primary`, `primary-container`, `on-primary-container`, `primary-fixed`, `primary-fixed-dim`, `on-primary-fixed`, `on-primary-fixed-variant`, the same eight for `secondary` and `tertiary`, `error`, `on-error`, `error-container`, `on-error-container`, `surface`, `on-surface`, `on-surface-variant`, `surface-dim`, `surface-bright`, `surface-container-lowest`, `surface-container-low`, `surface-container`, `surface-container-high`, `surface-container-highest`, `surface-tint`, `inverse-surface`, `on-inverse-surface`, `inverse-primary`, `outline`, `outline-variant`, `shadow`, `scrim` |
| `typography.font-family` | family | the platform's | The font of all text |
| `typography.font-family-fallback` | list of families | — | Fonts for the characters the main font lacks |
| `typography.<style>.<property>` | see the next sentence | Material's | One text style, or several. `<style>` is `defaults` (all styles), a group (`display`, `headline`, `title`, `body` or `label`, which sets its three sizes), one of the 15 styles (`display-large` … `label-small`), or `code`. `<property>` is `font-family`, `size`, `weight` (`100` … `900`, `bold`, `semibold`, …), `height` (a multiple of the size) or `letter-spacing` |
| `shape.<token>` | radius | Material 3's | The shape scale: `none` 0, `extra-small` 4, `small` 8, `medium` 12, `large` 16, `large-increased` 20, `extra-large` 28, `extra-large-increased` 32, `extra-extra-large` 48, `full`. A changed value reaches every component using it |
| `elevation.level0` … `level5` | number | 0, 1, 3, 6, 8, 12 | The elevation levels |
| `spacing.<name>` | number | `xs` 4, `s` 8, `m` 16, `l` 24, `xl` 32 | The app's spacing, read with `SpringTheme.of(context).space('m')`; any name |
| `visual-density` | `adaptive` / `standard` / `comfortable` / `compact` | Flutter's | How dense the components are |
| `tap-target-size` | `padded` / `shrinkWrap` | Flutter's | The minimum tap target size |
| `splash` | `ripple` / `sparkle` / `none` | Flutter's | The ink splash on taps |
| `motion.page-transition` | `platform`, `fadeUpwards`, `zoom`, `cupertino`, `none` | `platform` | The page transition, on every platform |
| `motion.duration-<name>` | duration | `short` 100ms, `medium` 250ms, `long` 450ms | Durations for the app's animations |
| `motion.easing-<name>` | four numbers | `standard`: Material's | Curves for the app's animations |
| `components.<component>.<property>` | see the next table | Material 3's | Adjusts one component |
| `tokens.<group>.<key>` | any value | — | The app's own values, read with `tokenColor('brand.accent')`, `tokenNumber(...)` or `token(...)` |
| `cupertino.primary-color` | color | `colors.primary`, else the seed, else iOS blue | The Cupertino theme's primary color |

**Components.** The values refer to the theme's tokens: a color role or a
color; a text style name or `code`; a shape token or a radius; an
elevation level or a number. Insets are written `all`,
`horizontal, vertical` or `left, top, right, bottom`.

| Component | Properties |
|---|---|
| `app-bar` | `center-title`, `elevation`, `scrolled-under-elevation`, `background`, `foreground`, `title-style`, `toolbar-height` |
| `button` (all four buttons) | `shape`, `padding`, `min-height`, `text-style` |
| `filled-button` | `shape`, `padding`, `min-height`, `text-style`, `background`, `foreground` |
| `elevated-button` | the same as `filled-button`, plus `elevation` |
| `outlined-button` | `shape`, `padding`, `min-height`, `text-style`, `foreground`, `border-color` |
| `text-button` | `shape`, `padding`, `min-height`, `text-style`, `foreground` |
| `card` | `shape`, `elevation`, `color`, `margin` |
| `input` | `style` (`outline`, `underline`, `filled`), `shape`, `filled`, `fill-color`, `content-padding` |
| `chip` | `shape`, `background`, `label-style` |
| `dialog` | `shape`, `background`, `elevation` |
| `bottom-sheet` | `shape` (the top corners), `background`, `elevation`, `show-drag-handle` |
| `navigation-bar` | `height`, `background`, `indicator-color`, `indicator-shape`, `label-behavior` (`alwaysShow`, `alwaysHide`, `onlyShowSelected`), `elevation` |
| `snack-bar` | `behavior` (`fixed`, `floating`), `shape`, `background`, `elevation` |
| `tooltip` | `shape`, `background`, `text-style` |
| `list-tile` | `dense`, `shape`, `tile-color` |
| `divider` | `thickness`, `color`, `space` |
| `floating-action-button` | `shape`, `elevation`, `background`, `foreground` |
| `tab-bar` | `indicator-color`, `label-style`, `label-color`, `unselected-label-color` |
| `popup-menu` | `shape`, `elevation`, `color` |

**Colors** are a name from Flutter's `Colors` (`deepPurple`,
`deepPurple.shade200`, `redAccent.shade100`, `black54`; `deep-purple`
works too) or `#RGB`, `#RRGGBB` or `#AARRGGBB`. In YAML, quote a value
that starts with `#`.

#### A theme in its own file

A custom theme can live in a file of its own, imported from
`application.yml` with `spring.config.import: classpath:themes/ocean.yml`:

<table>
<tr><th>themes/ocean.yml</th><th>themes/ocean.properties</th></tr>
<tr><td>

```yaml
spring.flutter.theme.themes.ocean:
  extends: light
  seed-color: teal
  scheme-variant: vibrant
  components:
    card: { elevation: level0 }
```

</td><td>

```properties
spring.flutter.theme.themes.ocean.extends=light
spring.flutter.theme.themes.ocean.seed-color=teal
spring.flutter.theme.themes.ocean.scheme-variant=vibrant
spring.flutter.theme.themes.ocean.components.card.elevation=level0
```

</td></tr>
</table>

Themes can also arrive at run time, from a server, with
`SpringThemes.loadYaml(yaml)` (see
[step 8](#step-8-themes-from-a-server)).

### Fonts

Every `.ttf` and `.otf` file under `flutter: assets:`, in any directory,
is loaded before the first frame. Its family is the name stored in the
font file (its `name` table), so `Inter-SemiBold.ttf` becomes a weight of
`Inter`, and the theme refers to families by that name. So a font is used
by dropping its files into an asset directory, without a `flutter: fonts:`
section. A file whose family cannot be read, such as a `.ttc` collection,
is skipped with a warning.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    fonts:
      auto-load: true
      exclude: [assets/pdf/**]
```

</td><td>

```properties
spring.flutter.fonts.auto-load=true
spring.flutter.fonts.exclude=assets/pdf/**
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.fonts.auto-load` | bool | `true` | `false`: no font file is loaded this way; the fonts of `flutter: fonts:` still work |
| `spring.flutter.fonts.exclude` | list of globs (`*` within a directory, `**` across directories) | — | Font assets not to load, such as fonts only used to make PDFs |

A family that the theme names, but that no asset and no `flutter: fonts:`
entry provides, is logged as a warning. It may still be a font of the
platform.

### Lifecycle, hot reload, environment

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    lifecycle:
      pause-in-background: true
  devtools:
    restart:
      enabled: true
```

</td><td>

```properties
spring.flutter.lifecycle.pause-in-background=true
spring.devtools.restart.enabled=true
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.lifecycle.pause-in-background` | bool | `true` | Pauses the context while the app is in the background, so `@Scheduled` tasks and WebSocket connections stop, and starts it again in the foreground |
| `spring.devtools.restart.enabled` | bool | `true` | A hot reload restarts the context when the generated code changed: beans, annotations or `lib/resources/`. `false` keeps the context, with the web server, its connections and the beans' state, until a hot restart. Works in Flutter and on the Dart VM (`SpringHotReload`) |
| `spring.flutter.scan-os-environment` | bool, **`--dart-define` only** | `false` | Reads the OS environment variables, which is useful on desktop. A config file cannot set it, because it decides whether the environment is read at all |

```bash
flutter run --dart-define=spring.flutter.scan-os-environment=true
```

The platform profiles (`android`, `ios`, `web`, `macos`, `windows`,
`linux`, `mobile`, `desktop`) are always active; see
[Profiles](#profile-files-and-activation).

---

## 18. Reference: web server

`spring_boot_starter_web` runs the application's controllers on a
`dart:io` HTTP server. It reads Spring Boot's `server.*` keys for the
port, TLS and shutdown, the keys of the controllers' server-sent events,
and the upload limits (`spring.servlet.multipart.*`; see the starter's
[Files](../spring_boot_starter_web/README.md#files-uploads-and-downloads)
section).

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
server:
  port: 8080
  address: 0.0.0.0
  shutdown: graceful
  servlet:
    context-path: /shop
  max-http-request-body-size: 10MB
  compression:
    enabled: true
  ssl:
    certificate: /etc/shop/cert.pem
    certificate-private-key: /etc/shop/key.pem
    key-password: s3cret
    trust-certificate: /etc/shop/clients.pem
    client-auth: want
spring:
  lifecycle:
    timeout-per-shutdown-phase: 20s
  mvc:
    async:
      request-timeout: 30m
    sse:
      heartbeat-interval: 15s
  servlet:
    multipart:
      enabled: true
      max-file-size: 5MB
      max-request-size: 20MB
      file-size-threshold: 64KB
      location: /var/tmp/shop-uploads
```

</td><td>

```properties
server.port=8080
server.address=0.0.0.0
server.shutdown=graceful
server.servlet.context-path=/shop
server.max-http-request-body-size=10MB
server.compression.enabled=true
server.ssl.certificate=/etc/shop/cert.pem
server.ssl.certificate-private-key=/etc/shop/key.pem
server.ssl.key-password=s3cret
server.ssl.trust-certificate=/etc/shop/clients.pem
server.ssl.client-auth=want
spring.lifecycle.timeout-per-shutdown-phase=20s
spring.mvc.async.request-timeout=30m
spring.mvc.sse.heartbeat-interval=15s
spring.servlet.multipart.enabled=true
spring.servlet.multipart.max-file-size=5MB
spring.servlet.multipart.max-request-size=20MB
spring.servlet.multipart.file-size-threshold=64KB
spring.servlet.multipart.location=/var/tmp/shop-uploads
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `server.port` | int | `8080` | The port. `0` picks a free one; the real port is then in `local.server.port` |
| `server.address` | IP address or host name | all interfaces; **`127.0.0.1` in Flutter apps** | The address to listen on. `localhost` is `127.0.0.1`; a host name is looked up. Flutter apps default to `127.0.0.1` so they open no port to the network by accident |
| `server.shutdown` | `graceful` / `immediate` | `graceful` | `graceful` accepts no new connections and lets running requests finish. Open event streams and WebSockets are closed at once (code 1001) |
| `spring.lifecycle.timeout-per-shutdown-phase` | duration | `30s` | How long a graceful shutdown waits for running requests (read by the web server only) |
| `server.servlet.context-path` | path | — | A prefix of every mapping, such as `/shop`. A missing leading `/` is added and a trailing one dropped; other paths answer 404. The old key `server.context-path` is read when this one is not set |
| `server.max-http-request-body-size` | data size, or `-1` | `10MB` | A larger request body is answered with 413; `-1` means no limit. This starter's own key. Uploads (`multipart/*`) have the `spring.servlet.multipart.*` limits instead |
| `server.compression.enabled` | bool (only `true` turns it on) | `false` | gzip for clients that accept it (`dart:io`'s `autoCompress`) |
| `server.ssl.enabled` | bool | `true` | `false` ignores the other `server.ssl.*` keys |
| `server.ssl.certificate` | file path (PEM) | — | The certificate chain; TLS is on when it is set |
| `server.ssl.certificate-private-key` | file path (PEM) | — | The private key; required with `certificate` |
| `server.ssl.key-password` | string | — | The password of an encrypted private key |
| `server.ssl.trust-certificate` | file path (PEM) | — | The certificates of trusted clients, for `client-auth` |
| `server.ssl.client-auth` | `none` / `want` / `need` | `none` | Asks clients for a certificate; with `need`, a request without one is answered with 403 |
| `spring.main.web-application-type` | `none`, or anything else | — | `none`: the beans (and `MockMvc`) exist, but no server starts. Other values start it |
| `spring.mvc.async.request-timeout` | duration | no limit | The timeout of an `SseEmitter` created without one; when it passes, the emitter completes after running its `onTimeout` callbacks |
| `spring.mvc.sse.heartbeat-interval` | duration | — (none) | Sends a comment line in every open event stream at this interval, so proxies keep idle streams open. This starter's own key |
| `spring.servlet.multipart.enabled` | bool | `true` | `false`: `multipart/*` requests are not parsed, and `@RequestPart` parameters answer 400 |
| `spring.servlet.multipart.max-file-size` | data size, or `-1` | `1MB` | The largest file (or other part) of an upload; above it the answer is 413 (`MaxUploadSizeExceededException`). `-1` means no limit |
| `spring.servlet.multipart.max-request-size` | data size, or `-1` | `10MB` | The largest multipart request as a whole; above it the answer is 413. `-1` means no limit |
| `spring.servlet.multipart.file-size-threshold` | data size | `0B` | Files above this size are written to a temporary file; smaller ones stay in memory. With `0B` every file goes to a temporary file (in memory where there is no `dart:io`). Temporary files are deleted after the request |
| `spring.servlet.multipart.location` | directory path | the system's temporary directory | Where uploads' temporary files are written |
| `spring.test.web-environment` | `mock` / `random-port` / `defined-port` / `none` | not set: a server starts | Set by `springBootTest(webEnvironment:)` (`mock` by default) and by `ApplicationContextRunner` (`mock`). In tests only `random-port` (port `0`) and `defined-port` start a server |
| `local.server.port` | int, **written by the server** | — | The port the server listens on, set once it listens (also in `WebServerInitializedEvent`). Read it; do not set it |

An invalid `server.port`, `server.shutdown` or `server.ssl.client-auth`,
or a certificate without its private key, fails the start naming the key.
The certificate files are paths in the file system, not `classpath:`
locations. Mappings are logged at debug level under the logger
`spring.web.mvc` (`logging.level.spring.web.mvc=debug`), and the server
under `spring.web.server`.

Not supported:

- `server.http2.*`: `dart:io` speaks HTTP/1.1;
- `server.forward-headers-strategy` and
  `server.max-http-request-header-size`;
- `server.compression.mime-types` and `min-response-size`;
- key stores and SSL bundles (`server.ssl.key-store`, `server.ssl.bundle`);
- `server.error.*` and `spring.mvc.problemdetails.enabled`: errors are
  always `ProblemDetail`s;
- `spring.web.cors.*`;
- `spring.web.resources.*`: there are no static files yet;
- the `server.tomcat.*`, `jetty`, `undertow` and `netty` keys.

---

## 19. Tests

`spring_boot_starter_test` starts the application in a test with its own
configuration, so a test can use other values than the application ships
with:

```dart
final app = springBootTest(
  springApplication,
  profiles: ['test'],                                   // spring.profiles.active
  properties: {'shop.max-basket-size': 3},              // above every other source
  propertyFiles: ['classpath:extra.properties'],        // just below properties
  dynamicProperties: (registry) =>
      registry.add('shop.url', () => server.url),       // read on every access
);
```

- `profiles` replaces the config files' `spring.profiles.active`.
- `properties` wins over every other source, the command line and
  `propertyFiles` included. `dynamicProperties` wins even over
  `properties`: use it for values known only once the tests run, such as
  the port of a server started in `setUpAll`.
- `propertyFiles` are resource locations of `.properties` files; a later
  file wins. A plain path is a classpath location, and `test/resources/`
  is on the classpath. A missing file fails the start.
- `test/resources/` comes first on the classpath, so
  `test/resources/application-test.yml` is the `test` profile's file, and
  a file there replaces a packaged file with the same path.
- The OS environment is not visible (`systemEnvironment: {}` by default),
  so tests do not depend on the machine they run on.
- Log levels set by a test's configuration are restored afterwards.
- `const ApplicationContextRunner().withPropertyValues(['shop.beta=true'])`
  is for auto-configuration tests. It reads no config files.
- With `spring_boot_starter_web`, a test starts no server unless it asks
  for one: `springBootTest(webEnvironment: WebEnvironment.randomPort)`
  (`server.port` becomes `0`; the real port is `local.server.port`), or
  `spring.test.web-environment=random-port` with an
  `ApplicationContextRunner` (see [section 18](#18-reference-web-server)).

---

## 20. Code generation options

The generator (`spring_core_dart_generator`) is configured in the
package's `build.yaml`, not in property files. Its options only change
how much code is generated: advice applies the same way either way.

```yaml
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        options:
          aop_proxies: all      # all | interfaces | none
          aop_prune: true
```

| Option | Values | Default | Meaning |
|---|---|---|---|
| `aop_proxies` | `all`, `interfaces`, `none` | `all` | Which beans get AOP proxy classes: every bean that can be proxied, only beans with an abstract supertype (proxied through that type), or none |
| `aop_prune` | bool | `true` | With `all`, the `@SpringBootApplication` output leaves out the proxy classes of beans that no pointcut can match |

Two limits of SpEL expressions are compile-time defines (`-D` or
`--dart-define`), not properties: `spring.context.expression.maxLength`
(the longest `@Value` expression) and `spring.expression.maxOperations`.

---

## Differences from Spring Boot

- `.properties` files are read as UTF-8; Spring Boot reads ISO-8859-1. For
  Spring Boot's behaviour use
  `PropertiesPropertySourceLoader(encoding: latin1)`.
- `spring.main.register-shutdown-hook` is `false` by default, because
  listening for signals keeps a Dart program alive.
- No `env:` imports, no `classpath*:` config locations and no classpath
  wildcards.
- These keys are this project's own: `spring.messages.default-locale`,
  `spring.cache.simple.*`, every `spring.websocket.client.*` and
  `spring.flutter.*` key, the Feign `event-stream.*` keys,
  `server.max-http-request-body-size` and
  `spring.mvc.sse.heartbeat-interval`.
- The web server (`spring_boot_starter_web`) reads only the `server.*` and
  `spring.servlet.multipart.*` keys of
  [section 18](#18-reference-web-server). They keep Spring Boot's names,
  though there is no servlet container. There is no HTTP/2, no forwarded
  headers, no key stores, no `server.error.*` and no server-specific keys
  such as `server.tomcat.*`. `server.ssl.*` takes PEM file paths. Errors
  are always `ProblemDetail`s.
- `spring.main.web-application-type` knows only `none` (no server).
  `spring.lifecycle.timeout-per-shutdown-phase` applies to the web
  server's graceful shutdown only.
- Not read: `allow-circular-references`, `keep-alive`,
  `spring.task.execution.*`, `spring.task.scheduling.pool.*`,
  `spring.aop.*`, `management.*`, `info.*`, `logging.config`,
  `logging.structured.*`, `spring.jackson.*` keys other than those listed
  (they are warned about and ignored), and cache stores other than
  `simple`.
- Jackson time zones and `@Scheduled` zones: only UTC and fixed offsets
  (`@Scheduled`: UTC or local time), as Dart has no time zone database.
- Log dates are UTC.
- There is no `.env` support: configuration lives in property files.
- The `shop.*` keys in the examples are an application's own.
