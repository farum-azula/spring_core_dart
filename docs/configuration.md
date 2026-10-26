# Configuration

Everything about configuring an application of the spring_core_dart family:
the config files and where they are read from, the two formats side by side,
profiles, imports, placeholders, how values are written, the order in which
sources override each other, and every property the framework and its
starters read, with types and defaults.

Spring (Java): Spring Boot's *Externalized Configuration* and its
*Common Application Properties*. Names and behaviour are Spring Boot's;
the differences are listed where they apply and at the
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

An application reads `application.properties`, `application.yml` or
`application.yaml` from `lib/resources/` (the classpath), plus
`application-{profile}.*` for each active profile. The generator embeds the
files of `lib/resources/` into the generated code, so they need no asset
declarations and work the same on the VM, in AOT builds, in Flutter and on
the web (up to 1 MB per file).

```
lib/
  main.dart
  resources/
    application.yml             # always
    application-dev.yml         # with the profile dev
    application-prod.properties # with the profile prod (formats can be mixed)
    messages.properties         # texts (see spring.messages.*)
```

Both formats mean the same; use either, or both (in one location,
`.properties` wins over `.yml`, which wins over `.yaml`).

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

Changing a file under `lib/resources/` changes the generated code: in
Flutter a hot reload restarts the application context with the new values
(see [Flutter](#17-reference-flutter)).

---

## 2. YAML and `.properties` side by side

### Nested keys

YAML nests; `.properties` writes the full key. Both produce the same flat
keys (`shop.payment.provider`).

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

A YAML list becomes indexed keys (`shop.hosts[0]`, `shop.hosts[1]`). In
`.properties` write indexes, or a comma-separated value; both bind to a
`List`. Indexes start at 0 without gaps.

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

A list comes whole from the highest source that has it: a command-line
`--shop.hosts[0]=local` replaces the file's list, it does not merge with it.

### Lists of objects

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

Map entries come from every source (a higher source wins per key). Keys
keep the form they are written in. To keep dots inside a key, wrap it in
brackets (quoted in YAML).

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

`~`, `null` and nothing after the colon are an empty string in YAML, like an
empty value in `.properties`. For a non-`String` target an empty value is
"not set", so defaults apply.

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

A file can hold several documents: `---` in YAML, a line `#---` (or `!---`)
in `.properties`. A later document overrides an earlier one, and a document
can be limited to profiles or a cloud platform (see [Profiles](#4-profiles)).

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

Both formats: `#` starts a comment. In `.properties` a comment must start
its line (`!` works too); an inline `#` is part of the value. In YAML a `#`
after a space starts a comment anywhere.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
# the shop
shop:
  color: '#673AB7'   # quoted: # would start a comment
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
# Separators: =, : or whitespace
shop.name=NEON
shop.city: Berlin
shop.country Germany

# A line ending in \ continues on the next (its leading spaces dropped)
shop.welcome=Welcome to NEON Books, \
             the shop of books.

# Escapes: \t \n \r \f \uXXXX; \= \: and "\ " keep those characters in keys
shop.greeting=Grüße
shop.key\=with\:colon=yes
```

`.properties` files are read as UTF-8 (Spring reads ISO-8859-1; see the
[differences](#differences-from-spring-boot)). A repeated key keeps its last
value; trailing spaces of a value are kept.

### Only in YAML

```yaml
# Anchors, aliases and merge keys
defaults: &defaults
  timeout: 5s
  retries: 3
shop:
  eu:
    <<: *defaults
    url: https://eu.neon.books
  us:
    <<: *defaults
    retries: 5           # the mapping's own keys win over merged ones
```

YAML is read as YAML 1.2: `on`, `off`, `yes`, `no` stay strings (they still
convert to `bool`), `0777` is the number 777, integers beyond 64 bits stay
exact. A duplicate key or invalid YAML fails the start with its line and
column.

---

## 3. Where files are read from

### Default locations

Two groups, the second overriding the first entirely:

| Group | Locations | Meaning |
|---|---|---|
| 1 (packaged) | `classpath:/`, `classpath:/config/` | `lib/resources/` and `lib/resources/config/`, embedded by the generator |
| 2 (next to the app) | `file:./`, `file:./config/`, `file:./config/*/` | files in the working directory (desktop and server apps) |

So `./application.properties` next to a server binary beats the packaged
`application-prod.properties`. Within a group, profile files win over the
plain ones, and the last active profile wins. All default locations are
optional.

In tests (`springBootTest`), `test/resources/` comes before
`lib/resources/` on the classpath: `test/resources/application-test.yml`
is found, and a file there shadows a packaged one with the same path.

### Changing the locations

These are read only from sources that exist before the config files: the
command line, `--dart-define`, the environment, default properties. Not
from the config files themselves.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.config.name` | comma list | `application` | Base names of the files (`application`, `shop` → `application*.*` and `shop*.*`; a later name wins) |
| `spring.config.location` | locations | the two groups above | Replaces the default locations; `,` separates groups, `;` joins locations into one group |
| `spring.config.additional-location` | locations | — | Groups searched after (overriding) the locations |
| `spring.config.on-not-found` | `fail` / `ignore` | `fail` | `ignore` makes every location optional |

```bash
dart run bin/main.dart --spring.config.location=optional:classpath:/,file:/etc/shop/
dart run bin/main.dart --spring.config.additional-location=file:./override.yml
```

### Location syntax

| Form | Meaning |
|---|---|
| `classpath:config/` | A directory of `lib/resources/`: every name and extension in it |
| `file:./config/app.yml` | One file (fails the start when missing) |
| `optional:file:./local.yml` | Never fails when missing |
| `file:./config/*/` | Each subdirectory (sorted); file locations only, one `*`, at the end |
| `file:./conf[.yml]` | A file without the extension, read as YAML |
| `configtree:/run/secrets/` | Kubernetes-style config tree: each file a property (`db/password` → `db.password`), its content the value |
| `https://cfg.example.com/app.yml` | Over HTTP, with asynchronous starts (`runAsync`, Flutter) only |
| `package:shop/defaults.yml` | A file of a package |
| `asset:config/app.yml` | A Flutter asset (spring_boot_starter_flutter) |
| a plain path | Treated as `file:` |

A non-optional file that does not exist fails the start; profile variants
of a file are always optional.

---

## 4. Profiles

### Profile files and activation

`application-{profile}.*` is read for each active profile, after the plain
file, so its values win. Profiles are activated by:

| Key | Type | Meaning |
|---|---|---|
| `spring.profiles.active` | comma list or YAML list | The active profiles; the first source that has the key wins (the command line beats a file) |
| `spring.profiles.include` | comma list or YAML list | Added to the active ones, from every source |
| `spring.profiles.default` | comma list | Profiles used while none is active (default `default`) |
| `spring.profiles.group.<name>` | comma list | Activating `<name>` activates these too (groups can nest) |
| `spring.profiles.validate` | bool | `true`: a profile name is letters, digits and `-_.+@`, starting and ending with a letter or digit |

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

```bash
dart run bin/main.dart --spring.profiles.active=prod
SPRING_PROFILES_ACTIVE=prod dart run bin/main.dart
flutter run --dart-define=SPRING_PROFILES_ACTIVE=prod
```

`spring.profiles.active`, `.default`, `.include` and `.group.*` may not
appear in a profile file or a profile-guarded document (the start fails),
as in Spring Boot. The legacy key `spring.profiles` is rejected.

In Flutter apps the platform is a profile too: `android`, `ios`, `web`,
`macos`, `windows`, `linux`, plus `mobile` (Android, iOS) and `desktop`
(macOS, Windows, Linux) — so `application-ios.yml` and
`application-desktop.properties` just work.

### Documents for some profiles or platforms

| Key | Meaning |
|---|---|
| `spring.config.activate.on-profile` | The document applies with these profiles: a profile expression (`!`, `&`, `\|`, parentheses; `&` and `\|` cannot be mixed without parentheses), a comma list meaning *or* |
| `spring.config.activate.on-cloud-platform` | The document applies on this platform (`kubernetes`, `heroku`, `cloud-foundry`, `azure-app-service`, `amazon-ecs`, `nomad`, `sap`, or `none`) |

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

The cloud platform is detected from environment variables like Spring
Boot's (`KUBERNETES_SERVICE_HOST` + `_PORT`, `DYNO`, `VCAP_APPLICATION`,
`WEBSITE_SITE_NAME` + …, `ECS_CONTAINER_METADATA_URI`, `NOMAD_ALLOC_ID`,
`HC_LANDSCAPE`), or forced with `spring.main.cloud-platform`.

---

## 5. Imports

`spring.config.import` loads more files; an imported file overrides the
file that imports it, and gets its own `-{profile}` variants. Relative
locations are relative to the importing file.

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

- Any [location form](#location-syntax) works, `optional:` included; a
  directory import searches `application*` files in it.
- From the command line or `SPRING_CONFIG_IMPORT`, imports form a group
  above every location.
- `${...}` in an import is resolved against the command line, the
  environment and the files read so far; an unresolvable `optional:` import
  is skipped.
- A file is loaded once, so import cycles are harmless.
- Not supported: `env:` imports.

---

## 6. Placeholders and random values

A value can refer to other properties: `${key}`, with a default
`${key:default}`. Defaults and keys can contain placeholders themselves.

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

- `\${` is a literal `${` (in `.properties` the backslash itself is
  escaped, `\\${`); `\:` keeps a colon in a key.
- `${db:url}` is first looked up as the key `db:url`, then as `db` with the
  default `url` (Spring 6.2).
- An unresolvable placeholder without a default fails where it is required
  (`@Value`, `getProperty`), and is kept as it is by `@ConfigurationProperties`
  binding.
- In Dart code, `@Value('${...}')` must be a raw string (`r'${shop.name}'`):
  `'${...}'` is Dart's string interpolation. The editor extension flags it.

**Random values**, a new one on every read:

| Placeholder | Value |
|---|---|
| `${random.int}`, `${random.long}` | any int / long (53 bits on the web) |
| `${random.int(10)}`, `${random.int[5,10]}`, `${random.long(…)}` | in a range (upper bound exclusive) |
| `${random.uuid}` | a v4 UUID |
| `${random.value}` (any other `random.*`) | 32 hex digits |

**SpEL** (`#{...}`) is evaluated only in `@Value` and
`@ConditionalOnExpression`, never in config files.

---

## 7. Writing values

### Durations

`10s`, `500ms`, `5m`, `1h`, `2d` (units `ns`, `us`, `ms`, `s`, `m`, `h`,
`d`, any case), ISO-8601 (`PT10S`, `PT1H30M`, `P1DT2H`), or a plain number
(milliseconds, or the unit of `@DurationUnit`). No ISO years or months.

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

`512B`, `10KB`, `5MB`, `1GB`, `1TB` (powers of 1024, whole numbers), or a
plain number of bytes (or the unit of `@DataSizeUnit`).

### Booleans

`true`, `on`, `yes`, `1` and `false`, `off`, `no`, `0`, in any case. Any
other value fails the start. (The `spring.jackson.*` switches are stricter:
only `true` is true.)

### Enums

Matched ignoring case and separators: `ON_SHOW_SELECTED`,
`only-show-selected` and `onlyShowSelected` are the same value.

### Numbers

Integers also as hex (`0x1F`, `#1F`); an empty value is "not set".

---

## 8. Other sources

### Relaxed names

A property has a canonical name in kebab case (`shop.max-basket-size`), and
every source may write it its own way: `shop.maxBasketSize`,
`shop.max_basket_size` and `SHOP_MAXBASKETSIZE` all set it. Inside `[...]`
the key is exact.

### Command line

```bash
dart run bin/main.dart --shop.max-basket-size=30 --spring.profiles.active=prod --debug
```

`--key=value`; `--flag` alone is an empty value; a repeated option joins
its values with commas; `--` ends the options. In Flutter desktop apps,
`SpringApplicationWidget(args: ...)`.

### Environment variables

`SHOP_MAXBASKETSIZE=20` sets `shop.max-basket-size`: split at `_`,
lower-cased, dashes ignored; a number becomes an index
(`SHOP_HOSTS_0=eu` → `shop.hosts[0]`). On a phone and on the web there is
no useful environment: a Flutter app reads it only when
`spring.flutter.scan-os-environment=true` is a `--dart-define`.

### `--dart-define` (Flutter and compiled apps)

Values given at build time are a property source above the environment,
with the same relaxed names. The generator lists every key the application
can read (placeholders, `@ConfigurationProperties` fields,
`@ConditionalOnProperty` names, keys of `lib/resources/application*`), so
`String.fromEnvironment` sees them in AOT and web builds.

```bash
flutter run --dart-define=SPRING_PROFILES_ACTIVE=prod --dart-define=SHOP_URL=https://neon.books
flutter build apk --dart-define-from-file=config/prod.json
```

A client app holds no secrets: `--dart-define` values, config files and
assets all end up in the APK, IPA or `main.dart.js`.

### `SPRING_APPLICATION_JSON`

A JSON object in the property `spring.application.json` (or the
environment variable `SPRING_APPLICATION_JSON`), flattened into properties
just above the environment:

```bash
SPRING_APPLICATION_JSON='{"shop":{"max-basket-size":30}}' dart run bin/main.dart
```

### In code

`SpringApplication(defaultProperties: {...})` sits below the config files;
`run(properties: ...)` (and `springBootTest(properties: ...)`) above
everything.

---

## 9. Which source wins

Highest first:

1. `run(properties: ...)` / `springBootTest(properties: ...)`
2. Command-line arguments
3. `--dart-define` values
4. `SPRING_APPLICATION_JSON`
5. OS environment variables (not read by Flutter apps unless switched on)
6. `${random.*}`
7. Config files: imports above their importer; `spring.config.import` from
   the environment, then `additional-location`, then the locations
   (`file:./` above `classpath:/`); within a group profile files above
   plain ones, the last profile highest; `.properties` above `.yml` above
   `.yaml`; a later document above an earlier one
8. `SpringApplication(defaultProperties: ...)`
9. `@PropertySource` files (below default properties; Spring Boot puts them
   above)

---

## 10. Your own properties

The application's own settings live in the same files, under a prefix of
its own (`shop.*` here). The Dart side reads them in four ways, from the
simplest:

| Way | For |
|---|---|
| [`@Value`](#one-value-value) | one value in a bean's constructor or field |
| [`@ConfigurationProperties`](#a-group-configurationproperties) | a typed object for a whole prefix: nested objects, lists, maps, validation |
| [`Environment`](#the-environment-directly) | reading by key in code |
| [`Binder`](#binder-structures-without-a-class) | binding a part of the configuration to a type on demand |

### One value: `@Value`

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
shop:
  title: NEON Books
  max-basket-size: 20
  checkout-timeout: 30s
  currencies: [EUR, USD]
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
    @Value(r'${shop.title}') this.title,                 // String
    @Value(r'${shop.max-basket-size}') this.maxItems,    // converted to int
    @Value(r'${shop.checkout-timeout}') this.timeout,    // 30s → Duration
    @Value(r'${shop.currencies}') this.currencies,       // EUR,USD → List<String>
    @Value(r'${shop.beta:false}') this.beta,             // with a default
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

- The string must be raw (`r'${...}'`): `'${...}'` is Dart's
  interpolation.
- The value is converted to the parameter's type (numbers, `bool`,
  `Duration`, `DataSize`, enums, lists); a value that cannot be converted
  fails the start naming the key.
- A missing key without a default fails the start; a nullable parameter
  (`String? motto`) gets `null` instead.
- `#{...}` evaluates SpEL after the placeholders:
  `@Value(r'#{${shop.max-basket-size} * 2}') int limit`.
- On a field: `@Value(r'${shop.title}') late final String title;`.

### A group: `@ConfigurationProperties`

A class for a prefix: every field is bound from the key with the field's
name in kebab case, nested classes from deeper keys. The class becomes a
bean; inject it wherever it is needed.

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

Using it, in a service and in a widget:

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
    final shop = context.bean<ShopProperties>();   // spring_boot_starter_flutter
    return Text('${shop.title}: up to ${shop.maxBasketSize} items');
  }
}
```

- The field's default is kept when its key is not set.
- `@Name('import')` binds a field from another key (for names that are
  Dart keywords).
- Lists come whole from one source (see [Lists](#lists)); map entries
  from every source, a higher source winning per key.
- Unknown keys under the prefix are ignored;
  `@ConfigurationProperties('shop', ignoreUnknownFields: false)` fails the
  start for them instead (catches typos).

**Immutable: constructor binding.** A class whose only constructor has
parameters is bound through it:

```dart
@ConfigurationProperties('shop.payment')
class PaymentProperties {
  const PaymentProperties(
    this.provider, {                              // required: must be set
    @DefaultValue('5s') required this.timeout,
    this.retries = 3,
    this.webhookSecret,                           // nullable: null when not set
  });

  final String provider;
  final Duration timeout;
  final int retries;
  final String? webhookSecret;
}
```

**Validated at the start.** `@Validated()` checks the constraint
annotations once the values are bound; an invalid value fails the start
with a report naming the key:

```dart
@ConfigurationProperties('shop')
@Validated()
class ShopLimits {
  @Min(1)
  @Max(100)
  int maxBasketSize = 10;

  @NotBlank()
  String title = 'Shop';

  @SizeConstraint(min: 1)        // @Size; SizeConstraint in Flutter apps
  List<String> currencies = ['EUR'];
}
```

```
***************************
APPLICATION FAILED TO START
***************************

Description:

Binding to target properties under 'shop' failed:

  - shop.max-basket-size must be greater than or equal to 1 (was "0")

Action:

Update the application's configuration (lib/resources/application.properties, command line or environment).
```

### The environment directly

Any bean can take the `Environment` and read by key (placeholders
resolved, relaxed names found):

```dart
@Service()
class FeatureFlags {
  FeatureFlags(this.env);
  final Environment env;

  bool get betaOn => env.getPropertyAs<bool>('shop.beta', defaultValue: false)!;
  int get maxItems => env.getPropertyAs<int>('shop.max-basket-size') ?? 10;
  String get title => env.getRequiredProperty('shop.title');   // fails when missing
  bool get hasMotto => env.containsProperty('shop.motto');
  String banner() => env.resolvePlaceholders(r'Welcome to ${shop.title}');
  bool get isProd => env.acceptsProfiles(Profiles.of(['prod']));
}
```

### `Binder`: structures without a class

`Binder` binds a part of the configuration to a type on demand, with the
same rules as `@ConfigurationProperties`:

```dart
final binder = Binder.get(environment);
final hosts = binder
    .bind('shop.hosts', const ListType(ClassType<String>()))
    .orElse(const []);
final limits = binder
    .bind('shop.limits', const MapType(ClassType<String>(), ClassType<int>()))
    .orElse(const {});
```

### Beans that depend on the configuration

```dart
@Service()
@ConditionalOnProperty('shop.beta', havingValue: 'true')
class BetaRecommendations implements Recommendations { ... }

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

`spring_boot_dart`.

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
| `spring.application.name` | string | — | The application's name: the context id and the startup log lines (`application` when not set) |
| `spring.main.banner-mode` | `console` / `log` / `off` | `console` (or `SpringApplication(bannerMode:)`) | Where the startup banner goes |
| `spring.banner.location` | location | `classpath:banner.txt` | The banner file; `${spring-boot.version}`, `${spring-boot.formatted-version}` and other `${...}` are replaced |
| `spring.main.log-startup-info` | bool | `true` | The "Starting …", active profiles and "Started … in N seconds" lines |
| `spring.main.lazy-initialization` | bool | `false` | Every bean created on first use |
| `spring.main.register-shutdown-hook` | bool | `false` (Boot: `true`) | Close the context on SIGINT / SIGTERM (VM only) |
| `spring.main.allow-bean-definition-overriding` | bool | `false` | A second definition of a bean name replaces the first instead of failing |
| `spring.main.cloud-platform` | platform name or `none` | detected | Forces the cloud platform |
| `spring.autoconfigure.exclude` | list | — | Auto-configurations not to apply (class or module names) |
| `debug` | any | — | Any value but `false` (`--debug`) logs the condition evaluation report |
| `spring.application.json` | JSON | — | See [above](#spring_application_json) |

### Messages

Texts in `lib/resources/messages*.properties`, used by
`context.getMessage` and Flutter's `context.message`. The `MessageSource`
is created when `messages.properties` (of a basename) exists.

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
| `spring.messages.basename` | list | `messages` | Base names (`i18n/errors` or `i18n.errors` → `i18n/errors_{locale}.properties`) |
| `spring.messages.encoding` | charset | UTF-8 | Encoding of the files |
| `spring.messages.cache-duration` | duration (plain number: seconds) | cached forever | How long a loaded file is kept |
| `spring.messages.fallback-to-system-locale` | bool | `true` | Fall back to the system locale before the plain file |
| `spring.messages.use-code-as-default-message` | bool | `false` | A missing code returns the code instead of failing |
| `spring.messages.always-use-message-format` | bool | `false` | Apply `MessageFormat` also without arguments |
| `spring.messages.default-locale` | locale | — | Tried before the system locale (not in Spring Boot) |
| `spring.messages.common-messages` | list of locations | — | Locale-independent texts (a later file wins) |

### JSON (`ObjectMapper`)

The auto-configured `ObjectMapper` (when the application declares none).
Each switch is on only when exactly `true`.

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
| `spring.jackson.property-naming-strategy` | `LOWER_CAMEL_CASE` | `SNAKE_CASE`, `UPPER_SNAKE_CASE`, `UPPER_CAMEL_CASE`, `LOWER_CAMEL_CASE`, `LOWER_CASE`, `KEBAB_CASE`, `LOWER_DOT_CASE` |
| `spring.jackson.default-property-inclusion` | `always` | `always`, `non_null`, `non_absent`, `non_empty`, `non_default` |
| `spring.jackson.time-zone` | — | `UTC`, `Z` or a fixed offset (`+02:00`); named zones are not supported |
| `spring.jackson.serialization.indent-output` | `false` | Pretty-printed JSON |
| `spring.jackson.serialization.write-dates-as-timestamps` | `false` | Dates as numbers (also `spring.jackson.datatype.datetime.…`, which wins) |
| `spring.jackson.serialization.write-durations-as-timestamps` | `false` | Durations as numbers |
| `spring.jackson.serialization.write-date-timestamps-as-nanoseconds` | `true` | Timestamps with fractions |
| `spring.jackson.deserialization.read-date-timestamps-as-nanoseconds` | `true` | Read timestamps with fractions |
| `spring.jackson.deserialization.fail-on-unknown-properties` | `false` | An unknown JSON property fails |
| `spring.jackson.deserialization.accept-float-as-int` | `true` | `1.0` reads into an `int` |
| `spring.jackson.deserialization.fail-on-null-for-primitives` | `true` | `null` for a non-nullable number or bool fails |
| `spring.jackson.mapper.sort-properties-alphabetically` | `true` | Properties in alphabetical order |
| `spring.jackson.mapper.default-view-inclusion` | `false` | Properties without `@JsonView` in every view |

Any other `spring.jackson.*` key (`date-format`, `locale`, `visibility`,
`generator.*`, `parser.*`, …) is logged as a warning and ignored.

---

## 12. Reference: logging

`spring_boot_starter_logging` (and `logging.level.*` / `logging.group.*`
in `spring_boot_dart`). Patterns follow Logback's syntax.

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
      enabled: always
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
spring.output.ansi.enabled=always
```

</td></tr>
</table>

Levels: `trace`, `debug`, `info`, `warn` (or `warning`), `error` (or
`fatal`), `off` (or `false`). An invalid level fails the start.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `logging.enabled` | bool | `true` | `false`: the starter configures nothing (no appenders, no buffer) |
| `logging.level.root` | level | `info` | The root level (also a plain `logging.level`) |
| `logging.level.<logger>` | level | inherited | A logger and its descendants (`LOGGING_LEVEL_SHOP=debug`) |
| `logging.group.<group>` | list | — | Logger names; `logging.level.<group>` sets them all (no predefined `web` / `sql` groups) |
| `logging.pattern.console` | pattern | Spring Boot's | Console format; empty switches the console off |
| `logging.pattern.file` | pattern | Spring Boot's | File format; empty means no file |
| `logging.pattern.dateformat` | date pattern | `yyyy-MM-dd'T'HH:mm:ss.SSSXXX` | `%d` in the default patterns (UTC only) |
| `logging.pattern.level` | pattern | `%5p` | The level column |
| `logging.pattern.correlation` | pattern | empty | The correlation column |
| `logging.exception-conversion-word` | pattern | `%wEx` | How exceptions are printed |
| `logging.include-application-name` | bool | `true` | `[spring.application.name]` in the default patterns |
| `logging.include-application-group` | bool | `true` | `[spring.application.group]` in the default patterns |
| `logging.console.enabled` | bool | `true` | The console appender |
| `logging.buffer.enabled` | bool | `true` | The in-memory `LogBuffer` |
| `logging.buffer.capacity` | int | `1000` | Records kept in the buffer |
| `logging.threshold.console` / `.file` / `.buffer` | level | `trace` | The lowest level per appender |
| `logging.file.name` | path | — | The log file (also `${LOG_FILE}` in patterns) |
| `logging.file.path` | directory | — | `<dir>/spring.log` when no name is set (`${LOG_PATH}`) |
| `logging.charset.file` | charset | UTF-8 | File encoding (`logging.charset.console` is only checked) |
| `logging.logback.rollingpolicy.max-file-size` | data size | `10MB` | Size at which the file rolls to `.1`, `.2`, … |
| `logging.logback.rollingpolicy.max-history` | int | `7` | Rolled files kept (a count) |
| `logging.logback.rollingpolicy.total-size-cap` | data size | `0B` (no limit) | Total size of the rolled files |
| `logging.logback.rollingpolicy.clean-history-on-start` | bool | `false` | Delete rolled files when the app starts |
| `spring.output.ansi.enabled` | `detect` / `always` / `never` | `detect` | Colors (`%clr`) on the console; `detect`: a terminal, or a Flutter debug/profile build |

Files are not written on the web (a warning says so).
`logging.logback.rollingpolicy.file-name-pattern` and the old
`logging.file.max-size` / `max-history` / … keys are ignored with a
warning; `logging.config`, `logback.xml` and `logging.structured.*` do not
exist.

---

## 13. Reference: scheduling

`spring_boot_starter_scheduling`.

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

```dart
@Scheduled(cron: r'${shop.report.cron}', zone: 'UTC')
void dailyReport() { ... }

@Scheduled(fixedRateString: r'${shop.report.every:1m}')
void refresh() { ... }
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.task.scheduling.enabled` | bool | `true` | `false`: no `@Scheduled` task runs (the task executor stays) |
| `spring.task.scheduling.shutdown.await-termination` | bool | `false` | Closing the context waits for running tasks (`closeAsync`) |
| `spring.task.scheduling.shutdown.await-termination-period` | duration | unbounded | The longest wait |

`@Scheduled` attributes accept placeholders (a missing key without a
default fails); a cron of `-` switches the task off; `zone` is `UTC`, `Z`,
`GMT` or empty (local time). Not supported: `spring.task.scheduling.pool.*`,
`thread-name-prefix`, `spring.task.execution.*` (Dart has no thread pools).

---

## 14. Reference: caching

`spring_boot_starter_cache`.

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

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.cache.type` | `generic` / `simple` / `none` | `generic` with `Cache` beans, else `simple` | `none`: methods always run (`NoOpCacheManager`); `generic`: the `Cache` beans; `simple`: in memory |
| `spring.cache.cache-names` | list | — (created on demand) | A fixed set of caches; other names are then an error |
| `spring.cache.simple.time-to-live` | duration | none | Entries expire this long after being written |
| `spring.cache.simple.max-size` | int | none | Entries per cache; the least recently used go first |
| `spring.cache.simple.caches.<name>.time-to-live` | duration | the global one | Per cache |
| `spring.cache.simple.caches.<name>.max-size` | int | the global one | Per cache |

The `spring.cache.simple.*` keys are this starter's own (Spring Boot's
simple cache has no settings). Not supported: `caffeine`, `redis` and other
stores.

---

## 15. Reference: Feign clients

`spring_boot_starter_feign`. `<client>` is `@FeignClient(contextId:)`, or
its `name`; `default` applies to every client, a client's own entry wins.

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

Keys under `spring.cloud.openfeign.client.config.<client>.`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `url` | URL | — | Base URL when `@FeignClient(url:)` is empty (`http://` added without a scheme) |
| `read-timeout` | duration | `60s` (`0`: none) | Longest wait for the response and between body chunks |
| `connect-timeout` | duration | `10s` (`0`: none) | **`default` only**: the shared transport's connect timeout |
| `logger-level` | `none` / `basic` / `headers` / `full` | `none` | Request logging under `feign.<Interface>` (debug level) |
| `dismiss404` | bool | `false` | A 404 returns `null` instead of throwing |
| `default-request-headers.<Header>` | list | — | Sent when the request has none of that name (`default` and the client's merged) |
| `default-query-parameters.<param>` | list | — | The same for query parameters |
| `follow-redirects` | bool | `true` | Follow redirects |
| `retryer` | bean or class name | never retry | The client's `Retryer` |
| `error-decoder` | bean or class name | `DefaultErrorDecoder` | The client's `ErrorDecoder` |
| `request-interceptors` | list of bean or class names | — | Added interceptors (`default`'s and the client's together) |
| `event-stream.reconnect` | bool | `true` | `EventStream<T>` reconnects when the connection ends |
| `event-stream.reconnect-delay` | duration | `3s` (or the server's `retry:`) | Wait before reconnecting |
| `event-stream.max-attempts` | int | no limit | Connections in a row without an event before giving up |

| Global key | Type | Default | Meaning |
|---|---|---|---|
| `spring.cloud.openfeign.client.decode-slash` | bool | `true` | `false` encodes `/` in path variables as `%2F` |

Not supported: service discovery and load balancing (every client needs a
URL), circuit breakers, per-client `connect-timeout`, compression,
`encoder` / `decoder` / `contract` / `capabilities` keys.

---

## 16. Reference: WebSocket clients

`spring_boot_starter_websocket` (this starter's own keys; Spring has no
such client). `<client>` is `@WebSocketClient(name:)`; `default` applies to
all.

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

Keys under `spring.websocket.client.config.<client>.`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `url` | `ws://` / `wss://` URL | — | When `@WebSocketClient(url:)` is not set |
| `connect-timeout` | duration | `10s` | Handshake timeout |
| `reconnect.enabled` | bool | `true` | Reconnect while someone listens |
| `reconnect.delay` | duration | `1s` | The first wait |
| `reconnect.multiplier` | number ≥ 1 | `2` | Growth of each wait (`1`: a fixed delay) |
| `reconnect.max-delay` | duration | `30s` | The longest wait |
| `reconnect.jitter` | duration | `0` | A random ± part, scaled like the delay |
| `reconnect.max-retries` | int | no limit | Attempts in a row before giving up |
| `default-request-headers.<Header>` | list | — | Sent with the handshake (not in browsers) |

Invalid `reconnect.*` values fail the start. Not supported: heartbeats,
STOMP, SockJS.

---

## 17. Reference: Flutter

`spring_boot_starter_flutter`: the app widget, themes, fonts, the app
lifecycle and hot reload. The theme is described in full in the starter's
README (*Themes from properties*); this is its property reference.

### The app widget

Used with `SpringApplicationWidget(home: ...)`, which builds the app
widget from these properties (with `child:` the app builds its own).

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
      locales: [en, ja, pt_BR]
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
| `spring.flutter.app.type` | `widgets` / `material` / `cupertino` | `widgets` | The app widget: `WidgetsApp`, `MaterialApp` (needed by `Scaffold`, `AppBar`) or `CupertinoApp` |
| `spring.flutter.app.title` | string | empty | The app's name for the OS (task switcher, browser tab) |
| `spring.flutter.app.debug-banner` | bool | `true` | Flutter's DEBUG banner |
| `spring.flutter.app.locales` | list of locales (`en`, `pt_BR`, `zh_Hant_TW`) | the languages of the messages files | The supported locales; by default `messages.properties` counts as English and each `messages_<locale>.properties` adds its locale (of `spring.messages.basename`) |

### Themes, step by step

How a theme is set up from properties and used from Dart. Every step
works alone; the [full property reference](#themes-every-property)
follows.

#### Step 1: a Material app with a palette from one color

`spring.flutter.app.type: material` makes the app a `MaterialApp` (needed
by `Scaffold`, `AppBar`, …); `seed-color` makes the whole Material 3
palette (primary, secondary, surfaces, …) from one color.

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

Any of the palette's roles can be set; the rest still comes from the seed.

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

Material widgets use them by themselves. Your own widgets read them like
any Material color, or through `SpringTheme` (which works in every app
type, `widgets` and `cupertino` too):

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
  // or by name, as in the properties:
  // theme.role('surface-container-low')
}
```

#### Step 3: fonts and text styles

Put the font files in any directory under `flutter: assets:`; the
starter loads them by the family each file names. Then name the families
per text role.

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

The shape scale changes every component using it (`medium` → cards);
`components.*` adjusts single components, with values naming the theme's
tokens.

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

Your own widgets take the same values:

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
differs: `dark` and `light` always exist; any other name is a theme of
your own; `extends` starts from another theme.

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

`active: system` shows `light` or `dark` with the device's mode
(`system-light` / `system-dark` pick other themes for it). Many themes are
easier to keep one file each:
`spring.config.import: classpath:themes/ocean.yml, classpath:themes/sepia.yml`.

#### Step 6: your own theme properties (tokens), and reading them in Dart

What Material has no place for — a brand color, a banner height, a badge
text — goes under `tokens.<group>.<key>`, and differs per theme like any
other value. `spacing.<name>`, `motion.duration-<name>` and
`motion.easing-<name>` take names of your own too.

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
    final theme = SpringTheme.of(context);           // the theme shown now
    return AnimatedContainer(
      duration: theme.duration('banner'),             // 600ms
      height: theme.tokenNumber('brand.banner-height'),  // 120
      padding: EdgeInsets.all(theme.space('gutter')),    // 20
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

Outside the widget tree (a service, a test), take a theme by name:
`themes.data('sepia').tokenColor('brand.accent')` with the `SpringThemes`
bean.

#### Step 7: switching themes from Dart

The `ThemeSelection` bean picks the theme shown; the app follows at once,
with Flutter's animation.

```dart
class ThemeMenu extends SpringStatelessWidget<(ThemeSelection, SpringThemes)> {
  const ThemeMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final (selection, themes) = beans;   // rebuilt when either changes
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

// from a service:
@Service()
class NightMode {
  NightMode(this.selection);
  final ThemeSelection selection;

  void on() => selection.select('dark');
  void followDevice() => selection.select('system');
}
```

#### Step 8: themes from a server

`SpringThemes.loadYaml` takes the same YAML at run time (with or without
the `spring.flutter.theme` prefix), checks every theme first (an invalid
one throws and changes nothing), and the app shows the change at once:

```dart
@Service()
class RemoteThemes {
  RemoteThemes(this.themes, this.selection, this.api);
  final SpringThemes themes;
  final ThemeSelection selection;
  final ThemesApi api;                       // e.g. a @FeignClient

  Future<void> refresh() async {
    themes.loadYaml(await api.themesYaml());  // themes: { winter: { seed-color: lightBlue } }
    selection.select('winter');
  }

  void reset() => themes.unload();            // back to the files' themes
}
```

#### Step 9: code instead of properties

Properties cover most themes; for the rest, beans:

```dart
@Configuration()
class AppTheme {
  // Replaces the `light` Material theme made from the properties
  // (`darkTheme` the dark one, a CupertinoThemeData bean the Cupertino ones).
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


The shared part at the root of `spring.flutter.theme`, the standard themes
`light` and `dark` and any number of custom ones under `themes.<name>`, each
holding only what differs. Every value Flutter's Material 3 has by default
stays so unless set; every theme is read and checked when the app starts
(an invalid value or a misspelled key fails the start).

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

**Which theme is shown** (at the root only):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `active` | `system` or a theme name | `system` | The theme shown; `system` follows the device's light or dark mode. `ThemeSelection.select(...)` changes it at run time |
| `system-light` | theme name | `light` | What `system` shows in light mode |
| `system-dark` | theme name | `dark` | What `system` shows in dark mode |

**A theme** (the root, and each `themes.<name>`; a theme starts from the
root, or from the theme it `extends`):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `extends` | theme name | — | (in `themes.<name>` only) Start from that theme instead of the root; chains allowed, cycles fail |
| `brightness` | `light` / `dark` | `dark` for `dark`, else `light` | The theme's brightness |
| `seed-color` | color | Material's baseline palette | The color the whole palette is made from |
| `scheme-variant` | `tonalSpot`, `fidelity`, `content`, `vibrant`, `expressive`, `monochrome`, `neutral`, `rainbow`, `fruitSalad` | `tonalSpot` | How the palette is made from the seed |
| `contrast` | number −1 … 1 | `0` | The palette's contrast |
| `colors.<role>` | color | from the seed | Any of the 46 `ColorScheme` roles in kebab case: `primary`, `on-primary`, `primary-container`, `on-primary-container`, `primary-fixed`, `primary-fixed-dim`, `on-primary-fixed`, `on-primary-fixed-variant`, the same eight for `secondary` and `tertiary`, `error`, `on-error`, `error-container`, `on-error-container`, `surface`, `on-surface`, `on-surface-variant`, `surface-dim`, `surface-bright`, `surface-container-lowest`, `surface-container-low`, `surface-container`, `surface-container-high`, `surface-container-highest`, `surface-tint`, `inverse-surface`, `on-inverse-surface`, `inverse-primary`, `outline`, `outline-variant`, `shadow`, `scrim` |
| `typography.font-family` | family | the platform's | The font of all text |
| `typography.font-family-fallback` | list of families | — | Fonts for glyphs the main one lacks |
| `typography.<style>.<property>` | see below | Material's | A text style: `defaults` (all), a group (`display`, `headline`, `title`, `body`, `label`: its three sizes), one of the 15 styles (`display-large` … `label-small`), or `code`; properties `font-family`, `size`, `weight` (`100` … `900`, `bold`, `semibold`, …), `height` (a multiple of the size), `letter-spacing` |
| `shape.<token>` | radius | Material 3's | The shape scale: `none` 0, `extra-small` 4, `small` 8, `medium` 12, `large` 16, `large-increased` 20, `extra-large` 28, `extra-large-increased` 32, `extra-extra-large` 48, `full`; a changed value reaches the components using it |
| `elevation.level0` … `level5` | number | 0, 1, 3, 6, 8, 12 | The elevation levels |
| `spacing.<name>` | number | `xs` 4, `s` 8, `m` 16, `l` 24, `xl` 32 | The app's spacing (`SpringTheme.of(context).space('m')`); any name |
| `visual-density` | `adaptive` / `standard` / `comfortable` / `compact` | Flutter's | Density of the components |
| `tap-target-size` | `padded` / `shrinkWrap` | Flutter's | Minimum tap targets |
| `splash` | `ripple` / `sparkle` / `none` | Flutter's | The ink splash |
| `motion.page-transition` | `platform`, `fadeUpwards`, `zoom`, `cupertino`, `none` | `platform` | Page transitions on every platform |
| `motion.duration-<name>` | duration | `short` 100ms, `medium` 250ms, `long` 450ms | Durations for the app's animations |
| `motion.easing-<name>` | four numbers | `standard`: Material's | Curves for the app's animations |
| `components.<component>.<property>` | see below | Material 3's | Adjusts one component |
| `tokens.<group>.<key>` | any value | — | The app's own tokens (`tokenColor('brand.accent')`, `tokenNumber(...)`) |
| `cupertino.primary-color` | color | `colors.primary`, else the seed's, else iOS blue | The Cupertino theme's primary color |

**Components** (values refer to the theme's tokens: a color role or a
color, a text style name or `code`, a shape token or a radius, an elevation
level or a number, insets as `all`, `horizontal, vertical` or
`left, top, right, bottom`):

| Component | Properties |
|---|---|
| `app-bar` | `center-title`, `elevation`, `scrolled-under-elevation`, `background`, `foreground`, `title-style`, `toolbar-height` |
| `button` (all four buttons) | `shape`, `padding`, `min-height`, `text-style` |
| `filled-button` | `shape`, `padding`, `min-height`, `text-style`, `background`, `foreground` |
| `elevated-button` | the same, plus `elevation` |
| `outlined-button` | `shape`, `padding`, `min-height`, `text-style`, `foreground`, `border-color` |
| `text-button` | `shape`, `padding`, `min-height`, `text-style`, `foreground` |
| `card` | `shape`, `elevation`, `color`, `margin` |
| `input` | `style` (`outline`, `underline`, `filled`), `shape`, `filled`, `fill-color`, `content-padding` |
| `chip` | `shape`, `background`, `label-style` |
| `dialog` | `shape`, `background`, `elevation` |
| `bottom-sheet` | `shape` (top corners), `background`, `elevation`, `show-drag-handle` |
| `navigation-bar` | `height`, `background`, `indicator-color`, `indicator-shape`, `label-behavior` (`alwaysShow`, `alwaysHide`, `onlyShowSelected`), `elevation` |
| `snack-bar` | `behavior` (`fixed`, `floating`), `shape`, `background`, `elevation` |
| `tooltip` | `shape`, `background`, `text-style` |
| `list-tile` | `dense`, `shape`, `tile-color` |
| `divider` | `thickness`, `color`, `space` |
| `floating-action-button` | `shape`, `elevation`, `background`, `foreground` |
| `tab-bar` | `indicator-color`, `label-style`, `label-color`, `unselected-label-color` |
| `popup-menu` | `shape`, `elevation`, `color` |

**Colors** are a `Colors` name (`deepPurple`, `deepPurple.shade200`,
`redAccent.shade100`, `black54`, also `deep-purple`) or `#RGB`, `#RRGGBB`,
`#AARRGGBB`. In YAML quote values starting with `#`.

A custom theme in its own file, imported from `application.yml`
(`spring.config.import: classpath:themes/ocean.yml`):

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

Themes can also come at run time, from a server:
`SpringThemes.loadYaml(yaml)` takes the same YAML (with or without the
`spring.flutter.theme` prefix), checks it, and the app shows it at once.

### Fonts

Every `.ttf` / `.otf` under `flutter: assets:` (any directory) is loaded
before the first frame, in the family the file names (`Inter-SemiBold.ttf`
→ `Inter`); the theme refers to families by name.

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
| `spring.flutter.fonts.auto-load` | bool | `true` | `false`: no font files are loaded (fonts of `flutter: fonts:` still work) |
| `spring.flutter.fonts.exclude` | list of globs (`*` within a directory, `**` across) | — | Font assets not to load |

A family the theme names but no asset and no `flutter: fonts:` provides is
logged as a warning (it may be the platform's own).

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
| `spring.flutter.lifecycle.pause-in-background` | bool | `true` | Pause the context in the background (`@Scheduled` tasks, WebSocket connections stop) and restart it in the foreground |
| `spring.devtools.restart.enabled` | bool | `true` | A hot reload restarts the context when the generated code changed (beans, annotations, `lib/resources/`); `false` keeps it (and the web server, its connections, the beans' state) until a hot restart. Flutter, and the Dart VM (`SpringHotReload`) |
| `spring.flutter.scan-os-environment` | bool, **`--dart-define` only** | `false` | Read the OS environment variables (desktop); a config file cannot set it, as it decides whether the environment is read at all |

```bash
flutter run --dart-define=spring.flutter.scan-os-environment=true
```

The platform profiles (`android`, `ios`, `web`, `macos`, `windows`,
`linux`, `mobile`, `desktop`) are always active: see [Profiles](#4-profiles).

---

## 18. Reference: web server

`spring_boot_starter_web`: Spring Boot's `server.*` keys for the `dart:io`
server, the shutdown, the server-sent events of the controllers, and the
limits of uploads (`spring.servlet.multipart.*`, see the starter's
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
| `server.port` | int | `8080` | The port; `0` picks a free one (the real one is then `local.server.port`) |
| `server.address` | IP or host name | all interfaces; **`127.0.0.1` in Flutter apps** | The address to listen on (`localhost` is `127.0.0.1`; a host name is looked up) |
| `server.shutdown` | `graceful` / `immediate` | `graceful` | Graceful: no new connections, running requests may finish; open event streams and WebSockets are closed at once (1001) |
| `spring.lifecycle.timeout-per-shutdown-phase` | duration | `30s` | How long a graceful shutdown waits for running requests (read by the web server only) |
| `server.servlet.context-path` | path | — | A prefix of every mapping (`/shop`; a missing leading `/` is added, a trailing one dropped); other paths are 404 |
| `server.max-http-request-body-size` | data size, or `-1` | `10MB` | A larger request body is a 413; `-1`: no limit (this starter's own key). Not applied to `multipart/*` requests: uploads have the `spring.servlet.multipart.*` limits |
| `server.compression.enabled` | bool (`true` only) | `false` | gzip for clients that accept it (`dart:io`'s `autoCompress`) |
| `server.ssl.enabled` | bool | `true` | `false` ignores the other `server.ssl.*` keys |
| `server.ssl.certificate` | file path (PEM) | — | The certificate chain; TLS is on when it is set |
| `server.ssl.certificate-private-key` | file path (PEM) | — | The private key; required with `certificate` |
| `server.ssl.key-password` | string | — | The password of an encrypted private key |
| `server.ssl.trust-certificate` | file path (PEM) | — | Certificates of trusted clients, for `client-auth` |
| `server.ssl.client-auth` | `none` / `want` / `need` | `none` | Ask clients for a certificate; with `need` a request without one is a 403 |
| `spring.main.web-application-type` | `none`, or anything else | — | `none`: the beans (and `MockMvc`) exist, no server starts; other values start it |
| `spring.mvc.async.request-timeout` | duration | no limit | The timeout of an `SseEmitter` created without one; it then completes (its `onTimeout` callbacks first) |
| `spring.mvc.sse.heartbeat-interval` | duration | — (none) | A comment line in every open event stream at this interval, so proxies keep idle streams open (this starter's own key) |
| `spring.servlet.multipart.enabled` | bool | `true` | `false`: `multipart/*` requests are not parsed (`@RequestPart` parameters then answer 400) |
| `spring.servlet.multipart.max-file-size` | data size, or `-1` | `1MB` | The largest file (or other part) of an upload; above it 413 (`MaxUploadSizeExceededException`); `-1`: no limit |
| `spring.servlet.multipart.max-request-size` | data size, or `-1` | `10MB` | The largest whole multipart request; above it 413; `-1`: no limit |
| `spring.servlet.multipart.file-size-threshold` | data size | `0B` | Files above this size are written to a temporary file, smaller ones stay in memory; `0B`: every file goes to a temporary file (in memory where there is no `dart:io`). Temporary files are deleted after the request |
| `spring.servlet.multipart.location` | directory path | the system's temporary directory | Where the temporary files of uploads are written |
| `spring.test.web-environment` | `mock` / `random-port` / `defined-port` / `none` | not set: a server starts | Set by `springBootTest(webEnvironment:)` (`mock` by default) and by `ApplicationContextRunner` (`mock`); only `random-port` (port `0`) and `defined-port` start a server in tests |
| `local.server.port` | int, **written** | — | The port the server listens on, set once it listens (also in `WebServerInitializedEvent`); read it, do not set it |

An invalid `server.port`, `server.shutdown` or `server.ssl.client-auth`,
or a certificate without its private key, fails the start naming the key.
The certificate files are paths in the file system, not `classpath:`
locations. Mappings are logged at debug level under `spring.web.mvc`
(`logging.level.spring.web.mvc=debug`), the server under
`spring.web.server`.

Not supported: `server.http2.*` (`dart:io` speaks HTTP/1.1),
`server.forward-headers-strategy`, `server.max-http-request-header-size`,
`server.compression.mime-types` / `min-response-size`, key stores and SSL
bundles (`server.ssl.key-store`, `server.ssl.bundle`), `server.error.*`
and `spring.mvc.problemdetails.enabled` (errors are always
`ProblemDetail`s), `spring.web.cors.*`, `spring.web.resources.*` (no
static files yet), the `server.tomcat.*` / `jetty` / `undertow` /
`netty` keys.

---

## 19. Tests

`spring_boot_starter_test`:

```dart
final app = springBootTest(
  springApplication,
  profiles: ['test'],                                   // spring.profiles.active
  properties: {'shop.max-basket-size': 3},              // above everything
  propertyFiles: ['test/resources/extra.properties'],   // below properties
  dynamicProperties: (registry) =>
      registry.add('shop.url', () => server.url),       // read on every access
);
```

- `test/resources/` comes first on the classpath:
  `test/resources/application-test.yml` is the test profile's file.
- The OS environment is not visible (`systemEnvironment: {}`), so tests do
  not depend on the machine.
- Log levels set by a test's configuration are restored afterwards.
- `ApplicationContextRunner().withPropertyValues(['shop.beta=true'])` for
  auto-configuration tests (no config files read there).
- With `spring_boot_starter_web`, a test starts no server unless it asks
  for one: `springBootTest(webEnvironment: WebEnvironment.randomPort)`
  (`server.port` becomes `0`, the real port is `local.server.port`), or
  `spring.test.web-environment=random-port` in an
  `ApplicationContextRunner` (see [section 18](#18-reference-web-server)).

---

## 20. Code generation options

The generator (`spring_core_dart_generator`) is configured in the package's
`build.yaml`, not in property files:

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
| `aop_proxies` | `all`, `interfaces`, `none` | `all` | Which beans get AOP proxy classes: every bean that can be proxied, only through abstract types, or none |
| `aop_prune` | bool | `true` | With `all`, the `@SpringBootApplication` output skips proxy classes for beans no pointcut can match |

Compile-time settings (`--dart-define`, not properties):
`spring.context.expression.maxLength` and
`spring.expression.maxOperations` limit SpEL expressions.

---

## Differences from Spring Boot

- `.properties` files are UTF-8 (Boot: ISO-8859-1); for Boot's behaviour
  use `PropertiesPropertySourceLoader(encoding: latin1)`.
- `@PropertySource` files sit below default properties (Boot: above).
- `spring.main.register-shutdown-hook` defaults to `false`.
- No `env:` imports, no `classpath*:` config locations, no classpath
  wildcards.
- `spring.messages.default-locale` and `spring.cache.simple.*` are this
  project's additions; so are all `spring.websocket.client.*` and
  `spring.flutter.*` keys, `server.max-http-request-body-size` and
  `spring.mvc.sse.heartbeat-interval`.
- The web server (`spring_boot_starter_web`) reads the `server.*` and
  `spring.servlet.multipart.*` keys of
  [section 18](#18-reference-web-server) only (Boot's names, though there
  is no servlet container): no HTTP/2, forwarded
  headers, key stores, `server.error.*` or server-specific
  (`server.tomcat.*`, ...) keys. `server.ssl.*` takes PEM file paths.
  Errors are always `ProblemDetail`s. The `shop.*` keys in the examples
  are an application's own.
- `spring.main.web-application-type` knows only `none` (no server);
  `spring.lifecycle.timeout-per-shutdown-phase` applies to the web
  server's graceful shutdown only.
- Not read: `allow-circular-references`, `keep-alive`,
  `spring.task.execution.*`, `spring.task.scheduling.pool.*`,
  `spring.aop.*`, `management.*`, `info.*`, `logging.config`,
  `logging.structured.*`, other `spring.jackson.*` keys than listed (warned
  and ignored), cache stores other than `simple`.
- Jackson time zones: only UTC and fixed offsets.
- Log dates are UTC.
- There is no `.env` support: configuration lives in property files.
