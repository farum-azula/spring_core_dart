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
19. [Reference: OAuth2 clients](#19-reference-oauth2-clients)
20. [Reference: SQL databases](#20-reference-sql-databases)
21. [Tests](#21-tests)
22. [Code generation options (`build.yaml`)](#22-code-generation-options)
23. [Differences from Spring Boot](#differences-from-spring-boot)

---

## 1. The config files

An application keeps its settings in a file named `application.yml`,
`application.yaml` or `application.properties` in `lib/resources/`. That
folder is what Spring calls the *classpath*, and the `resources:` prefix of
every location on this page points into it. For each active
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

The list keys that decide which files are read (`spring.config.import`,
`.location`, `.additional-location`, `.name`, `spring.profiles.active`,
`.include`, `.default`, `spring.config.activate.on-profile`) are bound as
Spring Boot binds them: where a source has no plain value, its
bracketed elements must be `[0]`, `[1]`... without a gap, or the start
fails ("left unbound": `spring.config.import[x]`, `[1]` without `[0]`,
`[0].a`). `spring.config.activate.on-cloud-platform` and
`spring.main.cloud-platform` take one value; their list form
(`on-cloud-platform[0]`) is ignored, as in Spring Boot.

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

As in Spring Boot, a `.properties` separator is the whole line: `#---` or
`!---` at the start of the line (no spaces before it), exactly three
hyphens, nothing after them but spaces, tabs or form feeds. It does not
count on the line right after a comment with the same prefix (`# prod`
then `#---` are two comments: leave a blank line, or use `!---`), nor
where the line before continues (`a=base\` then `#---` sets `a` to
`base#---`). Spring Boot also joins a document whose first line is a
comment to the document before it, so put a comment below the
`on-profile` line, not right after the separator; here the two documents
stay apart (see the [differences](#differences-from-spring-boot)).

### Comments

`#` starts a comment in both formats, with one difference. In
`.properties`, a comment is a line whose first character is `#` (`!`
works too), spaces, tabs and form feeds before it allowed; a `#` later
in the line is part of the value. In YAML, a `#` after a space
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

# A key ending in [] is a list, comma-separated (shop.hosts[0], [1]).
shop.hosts[]=a.neon.books, b.neon.books
```

`.properties` files are read as UTF-8, so `Grüße` can be written as is.
Spring reads them as ISO-8859-1 (see the
[differences](#differences-from-spring-boot)); a file that is not valid
UTF-8 fails the start with a `ConfigDataLoadException` naming it. A file
in another encoding can say so where it is named, as in Spring Boot 4.1:
`spring.config.import=resources:legacy.properties[encoding=iso-8859-1]`
(see [Location syntax](#location-syntax)). When a key appears twice,
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
| 1 (packaged) | `resources:/`, `resources:/config/` | `lib/resources/` and `lib/resources/config/`, embedded by the generator |
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
| `spring.config.additional-location` | locations | — | Groups searched after the locations, so they win over them, also where a location is named in both: `file:./config/` puts `./config/application.properties` above `./config/*/` |
| `spring.config.on-not-found` | `fail` / `ignore` | `fail` | `ignore` makes every location optional |

```bash
# Packaged files, then /etc/shop/ (which wins).
dart run bin/main.dart --spring.config.location=optional:resources:/,file:/etc/shop/
# The usual locations, then one more file on top.
dart run bin/main.dart --spring.config.additional-location=file:./override.yml
```

### Location syntax

The same forms work in the keys above and in [imports](#5-imports).

| Form | Meaning |
|---|---|
| `resources:config/` | A directory of `lib/resources/`; every file name and extension in it is searched |
| `file:./config/app.yml` | One file; the start fails when it is missing |
| `optional:file:./local.yml` | One file that may be missing |
| `file:./config/*/` | Each subdirectory, in alphabetical order; only for file locations, with one `*` as the last directory (`file:./config/*/app.yml` reads that file in each) |
| `file:./conf[.yml]` | A file without the extension, read as YAML |
| `file:./legacy.properties[encoding=iso-8859-1]` | A file in that encoding (`.properties` only; YAML is always UTF-8) |
| `file:./legacy.conf[.properties][encoding=latin1]` | Both hints, in any order |
| `configtree:/run/secrets/` | A config tree, as Kubernetes mounts secrets: each file is one property named by its path (`db/password` is `db.password`), its content the value. It must end with `/`; `configtree:/run/*/` reads each subdirectory |
| `https://cfg.example.com/app.yml` | A file over HTTP; only with asynchronous starts (`runAsync`, Flutter) |
| `package:shop/defaults.yml` | A file of a Dart package |
| `asset:config/app.yml` | A Flutter asset (`spring_boot_starter_flutter`) |
| a plain path | A file, as with `file:` |

A directory location ends with `/`, also on Windows (Spring Boot also
takes the platform's separator there, `\`). A file named by several
locations is read once, where it wins (see [Imports](#5-imports)).

A required file that does not exist fails the start, and so does a
required location that finds nothing: a directory that does not exist,
or a wildcard location with no subdirectory, or no file of that name in
any. That holds wherever the location is written: an import in a profile
file (`application-dev.yml`), in a document limited to a profile, or in a
file one of them imports is as required as any other, as in Spring Boot.
Only the profile variants searched by name (`application-dev.yml` for
`application.yml`, `local-dev.yml` for an imported `local.yml`) are
always optional.

As in Spring Boot, whether a location found anything is decided once the
profile files are read, and its profile variants count:
`file:./config/*/app.yml` with only `config/eu/app-dev.yml` loads that file
when `dev` is active, and fails otherwise. A `resources:` directory counts
only when a file is found in it, as Boot cannot see classpath
directories. A missing single file still fails at once, even when its
profile variant exists.

In `spring.config.location`, `spring.config.additional-location` and
every `spring.config.import` value (on the command line or in a config
file, each comma-separated or list item), a group joined with `;` is one
location, as in Boot: it is optional when its first entry is `optional:`,
and found when any of its entries finds something. So
`file:./;file:./conf/` does not fail when `./conf/` is missing, and
`optional:nodir/;extra.yml` reads `extra.yml`. A required entry that is a
missing file still fails at once, unless the group is optional. A
location that is not found is reported as written, as in Boot: the whole
group, a relative import as it is (not resolved against the importing
file), its extension hint kept (`Config data location 'conf/;local/'
cannot be found`, `... via location 'local[.yml]' cannot be found`), so
`optional:` put before that text makes it optional.

A location without a known extension must end with `/` (a directory) or
carry an extension hint (`[.yml]`). As in Spring Boot, an extension or a
hint is matched without case, and the loader's spelling names the file:
`x.YAML` reads `x.yaml` (on a case-sensitive file system or the
classpath, a file spelled `x.YAML` is not found that way; name it with a
hint, `x.YAML[.yaml]`), and `x.conf[.YML]` reads `x.conf` as YAML.

A file location takes Spring Boot 4.1's file hints: `[.ext]` (with its
dot) names the format, `[encoding=...]` the charset, several in any
order, the last of a kind winning (`x.conf[.properties][encoding=utf-8]`,
`x.conf[encoding=utf-8][.yml]`). As in Boot, every bracketed part is
taken out of a file location, wherever it is and whatever it holds
(`conf[x]/app.yml[foo]` reads `conf/app.yml`), while in a directory
location (ending with `/`) brackets are part of the path. The encoding
applies to `.properties` files and to their profile variants (YAML is
read as UTF-8 whatever it says, as Boot's YAML loader ignores it). The
charsets are UTF-8, ISO-8859-1 and US-ASCII, by Java's names and aliases
without case (`utf8`, `latin1`, `l1`, `8859_1`, `ascii`, `us`...; not
`Latin-1`, which Java does not know either). Any other charset fails the
start with a `ConfigDataLoadException` naming it, even for an
`optional:` location or a YAML file, as an unknown charset fails Boot.
`ConfigDataEnvironment.fileHints` reads a location that way.

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
| `spring.profiles.group.<name>` | comma list | Activating `<name>` activates these too; groups can contain groups. `<name>` is matched exactly, as in Spring Boot: `group.Prod` or `group.my-prod` is no group of `prod` or `myprod` |
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

The profiles are decided before the profile files are read, as in Spring
Boot, so those files cannot change them:

- A profile file (`application-dev.yml`, or `local-dev.yml` for an
  imported `local.yml`) may not set `spring.profiles.active`, `.default`
  or `.include`, in any of its documents; the start fails, as in Spring
  Boot. Its `spring.profiles.group.*` is ignored.
- A document limited to a profile, in a file read before the profiles are
  decided (`application.yml` and what it imports), may set none of the
  four keys; the start fails when the document applies (see
  [Differences](#differences-from-spring-boot)).
- In a file read after the profiles are decided, one that a profile file
  or a document limited to a profile imports, the four keys are ignored,
  as in Spring Boot.

The pre-2.4 key `spring.profiles` is rejected everywhere. These keys are
found under any spelling relaxed names allow, as in Spring Boot:
`spring.profiles.Active`, `spring.profiles.ACTIVE` or
`spring.profiles.de-fault` in a profile file fail the start too
(`SPRING_PROFILES_ACTIVE` is that key only in environment variables).

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
`-{profile}` variants, which win over the profile files of the file that
imports it, as in Spring Boot: when `application.properties` imports
`x.properties`, `x-dev.properties` wins over `application-dev.properties`.
Relative locations are relative to the importing file.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  config:
    import:
      - resources:themes/ocean.yml
      - optional:file:./local.yml
      - configtree:/run/secrets/
```

</td><td>

```properties
spring.config.import=resources:themes/ocean.yml,optional:file:./local.yml,configtree:/run/secrets/
```

</td></tr>
</table>

- Every [location form](#location-syntax) works, `optional:` included.
  Importing a directory searches the `application*` files in it.
- Given on the command line or as `SPRING_CONFIG_IMPORT`, imports form a
  group above every location.
- `${...}` in an import is resolved against the command line, the
  environment and the active documents read so far, at the moment the
  importing document's imports are read (for a document with
  `on-profile`, after the profiles are decided; Spring Boot resolves it
  earlier, see [differences](#differences-from-spring-boot)). An
  `optional:` import whose placeholder cannot be resolved is skipped.
- A file is read once, so import cycles do no harm. Named at several
  places, it counts at the one Spring Boot keeps, the one that wins: the
  later item of a list (`x.properties,y.properties,x.properties` puts `x`
  above `y`, in `spring.config.location` and
  `spring.config.additional-location` too), the command line's
  `spring.config.import` before `additional-location` before the
  locations (so `--spring.config.additional-location=file:./config/`
  puts `./config/application.properties` above `./config/*/`), and
  within a `;` group the first of two identical entries. The encoding
  hint written at that place is the one that applies; the file is not
  read at the other places.
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
false, in any case. Any other value fails the start. The `spring.json.*`
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
   - an imported file above the file that imports it, and its profile
     variants above those of the file that imports it;
   - a file named at several places counts once, at the strongest
     place (see [Imports](#5-imports));
   - `spring.config.import` given on the command line or in the
     environment, then `additional-location`, then the locations, with
     `file:./` above `resources:/`;
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

### Completion and checks in the editor

The generator writes `lib/spring_gen/spring_metadata.json` for every
package with Spring code: the properties of your `@ConfigurationProperties`
classes (with their `///` comments as descriptions), value hints (enum
constants, each with its `///`) and, for the Flutter starter, the theme.
Spring: the same job as `spring-configuration-metadata.json`. All of it
comes from the code: put `@Range(min, max)`, `@WarnValues([...], 'why')` or
`@PropertyValues([...])` on a field for bounds, warned values and values of
a `String` field. Nothing is written by hand (there is no
`spring_metadata_additional.json`), and the starters read their settings
through the same classes they are described by, so the editor's keys,
defaults and values cannot differ from what the code accepts. A map field
(`Map<String, V> headers`) is listed as `headers.*`, a list of classes as
`routes[*].path`, a map of classes as `registration.*.client-id`.

Any editor with the YAML language server (Red Hat's `yaml-language-server`:
VS Code, Zed, IntelliJ) can complete and check `application*.yml` from a
JSON Schema made from the metadata of the app and its dependencies:

```sh
dart run tool/spring_schema.dart example/server_guide
```

This writes `example/server_guide/spring-application.schema.json`
(JSON Schema draft 2020-12). Name it in the first line of the YAML file:

```yaml
# yaml-language-server: $schema=../../spring-application.schema.json
spring:
  profiles:
    active: dev
```

The path is relative to the YAML file; a URL works too. A `${...}`
placeholder is accepted wherever a number or a flag is expected. Run the
tool again after `build_runner build` when properties change.

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
    location: resources:banner.txt
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
spring.banner.location=resources:banner.txt
spring.autoconfigure.exclude=cacheAutoConfiguration
debug=false
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.application.name` | string | — | The application's name: the context's id, and the name in the startup lines (`application` when not set) |
| `spring.main.banner-mode` | `console` / `log` / `off` | `console`, or `SpringApplication(bannerMode:)` | Where the startup banner goes: printed, logged, or nowhere |
| `spring.banner.location` | location | `resources:banner.txt` | The banner file. `${spring-boot.version}`, `${spring-boot.formatted-version}` and other `${...}` in it are replaced |
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
    common-messages: resources:common.properties
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
spring.messages.common-messages=resources:common.properties
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
  json:
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
spring.json.property-naming-strategy=SNAKE_CASE
spring.json.default-property-inclusion=non_null
spring.json.time-zone=UTC
spring.json.serialization.indent-output=true
spring.json.serialization.write-dates-as-timestamps=false
spring.json.deserialization.fail-on-unknown-properties=true
spring.json.mapper.sort-properties-alphabetically=false
```

</td></tr>
</table>

| Key | Default | Meaning |
|---|---|---|
| `spring.json.property-naming-strategy` | `LOWER_CAMEL_CASE` | How field names become JSON names: `SNAKE_CASE`, `UPPER_SNAKE_CASE`, `UPPER_CAMEL_CASE`, `LOWER_CAMEL_CASE`, `LOWER_CASE`, `KEBAB_CASE`, `LOWER_DOT_CASE` |
| `spring.json.default-property-inclusion` | `always` | Which properties are written: `always`, `non_null`, `non_absent`, `non_empty`, `non_default` |
| `spring.json.time-zone` | — | `UTC`, `Z` or a fixed offset (`+02:00`); named zones such as `Europe/Berlin` fail, as Dart has no time zone database |
| `spring.json.serialization.indent-output` | `false` | Pretty-printed JSON |
| `spring.json.serialization.write-dates-as-timestamps` | `false` | Dates as numbers. `spring.json.datatype.datetime.write-dates-as-timestamps` does the same and wins |
| `spring.json.serialization.write-durations-as-timestamps` | `false` | Durations as numbers |
| `spring.json.serialization.write-date-timestamps-as-nanoseconds` | `true` | Timestamps with a fraction |
| `spring.json.deserialization.read-date-timestamps-as-nanoseconds` | `true` | Reads timestamps with a fraction |
| `spring.json.deserialization.fail-on-unknown-properties` | `false` | An unknown JSON property fails the read |
| `spring.json.deserialization.accept-float-as-int` | `true` | `1.0` can be read into an `int` |
| `spring.json.deserialization.fail-on-null-for-primitives` | `true` | `null` for a non-nullable number or `bool` fails the read |
| `spring.json.mapper.sort-properties-alphabetically` | `true` | Writes properties in alphabetical order |
| `spring.json.mapper.default-view-inclusion` | `false` | Properties without `@JsonView` appear in every view |

The other three `datetime` timestamp switches also have a
`spring.json.datatype.datetime.*` form that wins over the one above.
Any other `spring.json.*` key (`date-format`, `locale`, `visibility`,
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
    rolling-policy:
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
logging.file.rolling-policy.max-file-size=10MB
logging.file.rolling-policy.max-history=7
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
| `logging.file.rolling-policy.max-file-size` | data size | `10MB` | The size at which the file rolls over to `.1`, `.2`, … |
| `logging.file.rolling-policy.max-history` | int | `7` | How many rolled files are kept |
| `logging.file.rolling-policy.total-size-cap` | data size | `0B` (no limit) | The largest total size of the rolled files |
| `logging.file.rolling-policy.clean-history-on-start` | bool | `false` | Deletes the rolled files when the application starts |
| `spring.output.ansi.enabled` | `always` / `detect` / `never` | `always` | Colours on the console: `%clr`, or the time, level and logger of a pattern without colours. `never` gives plain text, for logs read by a program. `detect` colours only on a terminal or in a Flutter debug or profile build (Spring Boot's default) |

Log files are not written on the web; a warning says so.
`logging.file.rolling-policy.file-name-pattern` and the old
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
| `spring.cache.simple.time-to-live` | duration, `0` or more | none | An entry expires this long after it was written, measured on a monotonic clock as Caffeine's ticker (setting the system clock moves no expiry). `0` keeps nothing; a negative value fails the start (an `ArgumentError` naming the property), as Caffeine's `expireAfterWrite` refuses one |
| `spring.cache.simple.max-size` | int, `0` or more | none | The most entries per cache; when full, the least recently used entry goes. `0` keeps nothing; a negative value fails the start (an `ArgumentError` naming the property) |
| `spring.cache.simple.caches.<name>.time-to-live` | duration, `0` or more | the global one | The same, for one cache; a negative value fails the start too |
| `spring.cache.simple.caches.<name>.max-size` | int, `0` or more | the global one | The same, for one cache; a negative value fails the start too |

A cache name with dots goes in brackets, as in any Spring Boot map:
`spring.cache.simple.caches[books.byIsbn].max-size=2` (YAML key
`"[books.byIsbn]":`); the plain form
`spring.cache.simple.caches.books.byIsbn.max-size` is read too (the end
of the key that is `max-size` or `time-to-live`, in any relaxed form, is
the property). Every per-cache value is checked at the start.

As environment variables, the forms Spring Boot binds work:
`SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE=5` or
`SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAXSIZE=5`, and `_TIME_TO_LIVE=30s` or
`_TIMETOLIVE=30s`, for the cache `books`. Variables give lower-case
names, so a cache name with capitals or dashes needs a config file; a
`_` inside the name is read as a dot (`..._BOOKS_BYISBN_MAX_SIZE` is the
cache `books.byisbn`, which Boot does not bind).

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
  feign:
    client:
      decode-slash: true
      config:
        default:
          connect-timeout: 5s
          read-timeout: 30s
          call-timeout: 45s
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
spring.feign.client.decode-slash=true
spring.feign.client.config.default.connect-timeout=5s
spring.feign.client.config.default.read-timeout=30s
spring.feign.client.config.default.call-timeout=45s
spring.feign.client.config.default.logger-level=basic
spring.feign.client.config.catalog.url=https://api.neon.books
spring.feign.client.config.catalog.read-timeout=10s
spring.feign.client.config.catalog.dismiss404=true
spring.feign.client.config.catalog.default-request-headers.X-Client=shop
spring.feign.client.config.catalog.default-query-parameters.lang=en
spring.feign.client.config.catalog.retryer=catalogRetryer
spring.feign.client.config.catalog.request-interceptors=authInterceptor
spring.feign.client.config.catalog.event-stream.reconnect-delay=2s
```

</td></tr>
</table>

The keys under `spring.feign.client.config.<client>.`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `url` | URL | — | The base URL when `@FeignClient(url:)` is empty; `http://` is added when the scheme is missing |
| `read-timeout` | duration | `60s` (`0`: none) | The longest wait for the response, then between two chunks of the body; not a limit for the whole call |
| `connect-timeout` | duration | `10s` (`0`: none) | **Under `default` only**: the connect timeout of the transport all clients share |
| `call-timeout` | duration | none (`0` or less: none) | The longest one call may take **in all**: every attempt, the pauses of the `Retryer` and the wait for the answer. When it passes, the call throws `FeignCallTimeoutException` (not retried, whatever the retryer says; a pause that would end past the limit ends the call at once); the client's `fallback` still answers. It is the earlier of this and the `RequestDeadline` the call runs under (a web request with `server.request-timeout`, [section 18](#deadlines-one-limit-for-a-request-and-the-calls-it-makes)), and the connect and read timeouts of each attempt are capped by what remains. For an `EventStream<T>` method it limits establishing each connection (up to the status and headers), not the stream's life. This starter's own key: Spring Cloud OpenFeign has only `connect-timeout` and `read-timeout` |
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
| `spring.feign.client.decode-slash` | bool | `true` | `false` encodes `/` in path variables as `%2F` |

`retryer`, `error-decoder` and `request-interceptors` name beans. Spring
takes class names and creates the class; here a class name must match
exactly one bean. The `event-stream.*` keys are this starter's own, as
Spring Cloud OpenFeign cannot stream, and so is `call-timeout`. Not supported: service discovery
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

Two keys apply to every client, through the default `webSocketTransport`
bean (on `dart:io`; the browser has no such limits):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.websocket.client.max-text-message-size` | data size, or `-1` | `8KB` | The largest text message a client reads, in UTF-8 bytes (Tomcat counts characters); a larger one closes the connection with 1009 (message too big). Tomcat's default for Spring's `StandardWebSocketClient`; this starter's own key (Spring sets the limit in code, on the client's `WebSocketContainer`) |
| `spring.websocket.client.max-binary-message-size` | data size, or `-1` | `8KB` | The same for binary messages |

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


The window of a desktop app (macOS, Windows, Linux) has keys of its own.
They carry `desktop` in their name because only desktop apps read them: a
phone or the web ignores them, even a malformed value. A value for one OS
goes into that platform's profile file (`application-macos.properties`).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.desktop.window.title` | text | the runner's (normally the app name) | The window's title: what the OS shows in the title bar when it is visible (not with `title-bar=transparent` or `hidden`) and in the Dock, taskbar and window switcher (macOS `NSWindow.title`, Windows `SetWindowTextW`, GTK `gtk_window_set_title`; any Unicode). Surrounding blanks are trimmed; a blank value is the same as none, so the runner's title stays |
| `spring.flutter.desktop.window.title-bar` | `default` / `transparent` / `hidden` | `default` | `default`: the OS's title bar, untouched. `transparent`: the content is drawn under a transparent title bar and the window buttons stay over it (macOS: transparent title bar, hidden title, full-size content view; Windows: the frame extended into the client area, the system's caption buttons over the content; Linux: GTK draws no content under a header bar, so it becomes a flat header bar with no title, with the window buttons). `hidden`: no title bar and no window buttons (the app draws its own; macOS and Windows: no caption, Linux: no decoration). `DesktopWindow.insetsOf(context)` says how much room the buttons take (macOS: the traffic lights at the left, Windows: the caption buttons at the right, 0 elsewhere); `WindowDragArea` moves the window |
| `spring.flutter.desktop.window.initial-size` | `<width>x<height>`, logical pixels | the runner's size | The size of the window's content area when it opens, centered on the screen (not under Wayland, where the compositor places windows). A malformed value (`1280x`, a negative or zero number) stops the start with the expected format |
| `spring.flutter.desktop.window.min-size` | `<width>x<height>`, logical pixels | none | The smallest content size the user can drag the window to (macOS `contentMinSize`, Windows `WM_GETMINMAXINFO`, GTK `gtk_window_set_geometry_hints`). An `initial-size` smaller than it stops the start naming both values |
| `spring.flutter.desktop.window.max-size` | `<width>x<height>`, logical pixels | none | The largest content size the user can drag the window to (macOS `contentMaxSize`, Windows `WM_GETMINMAXINFO` `ptMaxTrackSize`, scaled to the monitor's DPI like `min-size`, GTK `GDK_HINT_MAX_SIZE` set together with the minimum). Maximizing: macOS zoom stops at it; Windows maximizes to the largest allowed size, not the whole screen; GTK depends on the window manager, which may refuse to maximize past it. `min-size` larger than `max-size`, or an `initial-size` outside min..max, stops the start naming both values |

```properties
spring.flutter.desktop.window.title=NEON Books
spring.flutter.desktop.window.title-bar=transparent
spring.flutter.desktop.window.initial-size=1280x800
spring.flutter.desktop.window.min-size=800x600
spring.flutter.desktop.window.max-size=1920x1080
```

The properties are applied before the first frame is shown, so the window
does not open at the runner's size first. The runners show the window with
the first frame; the starter holds that frame back until the native side has
answered (at most five seconds), then the window appears already as set.

### Themes, step by step

> The full theme reference, one page per topic, is in [Flutter themes in YAML](flutter/theme/index.md).

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
        card: { shape: large, color: $colors.surface-container-low, elevation: level0 }
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
spring.flutter.theme.components.card.color=$colors.surface-container-low
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
`spring.config.import: resources:themes/ocean.yml, resources:themes/sepia.yml`
(see [a theme in its own file](#a-theme-in-its-own-file)).

#### Step 6: your own theme properties (tokens), and reading them in Dart

Some values have no place in Material's theme: a brand color, a banner
height, a badge text. They go under `tokens.<group>.<key>` and can differ
per theme like any other value. `spacing.<name>`, `motion.durations.<name>`
and `motion.curves.<name>` take names of your own too.

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
        durations:
          banner: 600ms
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
spring.flutter.theme.motion.durations.banner=600ms
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
      duration: context.theme.motion.banner,             // 600ms, 0 with reduce motion
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

##### Typed keys (generated)

The string keys above fail at run time when a property is renamed. With the
generator (`dart run build_runner build`) the Flutter app gets
`lib/spring_gen/theme.spring.dart`, where `context.theme` has a getter for every key your
properties declare under `spring.flutter.theme`, in any theme. The file is a
part of `lib/spring_gen/main.spring.dart`, so import that one in your widgets:

```dart
import 'package:shop/spring_gen/main.spring.dart';
```

The getters:

```dart
context.theme.colors.surfaceContainerLow;      // Color
context.theme.spacing.gutter;                  // double
context.theme.typography.titleLarge;           // TextStyle
context.theme.tokens.brand.accent;             // Color (a #RRGGBB value)
context.theme.tokens.brand.bannerHeight;       // double (a number)
context.theme.tokens.brand.badgeText;          // String (anything else)
selection.select(AppThemes.sepia);             // the ThemeSelection bean
```

The values are read from the theme shown now, when the getter is called, so
a switched or reloaded theme gives its own value and the widget rebuilds.
Rename `brand.accent` in the properties and `context.theme.tokens.brand.accent`
no longer compiles. A token that is a color in one theme and a number in
another fails the build, naming both properties.

- Only what the properties declare is generated; the Material roles computed
  from the seed stay in `Theme.of(context).colorScheme`. `typography` has
  the 15 Material styles and `code` (a group such as `display` configures
  several styles and is not a getter), `tokens` any depth
  (`context.theme.tokens.brand.accent`; see
  [nested tokens](#nested-tokens)).
- Names: `-` and `_` start a new word (`surface-container-low` is
  `surfaceContainerLow`), the first letter is lower case, a leading digit gets
  a `$` in front (`2xl` is `$2xl`), a Dart keyword a `$` behind
  (`default` is `default$`). A name that cannot be made a Dart name, or two
  keys that give one name, fail the build.
- The string API stays for keys added at run time (a theme from a server).
- The Spring theme is read by `context.theme`; Flutter's own
  `Theme.of(context)` is untouched.
- More in [Themes without Dart](#themes-without-dart-references-states-motion-background-images):
  references, `styles.*`, `motion`, `animations.*`, `background` and images
  are typed too.
- Two generated files, both parts of the `.spring.dart` file of your
  `@ComponentScan` library (or `@SpringBootApplication` class):
  `lib/spring_gen/theme.spring.dart` and `lib/spring_gen/messages.spring.dart`. A library such as a
  design-system package gets its own pair, and an app never sees the
  library's `context.theme`. The parent is the `@SpringBootApplication`
  library if there is one, else the outermost `@ComponentScan` (nested scans
  in `lib/src/` are fine); unrelated roots stop the build and are named.
- A `styles.<name>` is the class `AppStyle<Name>` (its values
  `AppStyle<Name>Values`), so a style called `text` or `button` never hides
  Flutter's `TextStyle` or `ButtonStyle`. `background` is nullable
  (`ThemeBackgroundData?`): `null` in a theme without one.

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

### Messages in Flutter: typed access

`context.message('basket.total', args: [total])` finds a misspelt key or a
forgotten argument at run time. The generator reads the same message files
(`lib/resources/messages.properties`, `messages_ja.properties`, ... or the
bases of `spring.messages.basename`) and writes `context.messages` into
`lib/spring_gen/messages.spring.dart` (import `spring_gen/main.spring.dart`):

```properties
# messages.properties
basket.total=Total: {0}
basket.empty=Your basket is empty
order.shipped=Order {0} shipped on {1,date,short}
```

```dart
Text(context.messages.basket.total(sum));       // a method: {0} is a parameter
Text(context.messages.basket.empty);            // a getter: no arguments
Text(context.messages.order.shipped(id, date)); // Object? parameters, one per {n}
```

The text comes from the existing `MessageSource` in the current language, so
`context.messages` rebuilds the widget when the language changes. The dots
nest (`basket.total` is `messages.basket.total`), `-` and `_` start a new
word as for theme keys.

- A key missing in a language file, or only in one, is a build warning naming
  the file.
- The same key with a different number of arguments in two languages, a
  malformed placeholder (`{0`), a key that is both a message and a prefix of
  others (`basket` and `basket.total`) and a key that is no Dart name fail the
  build.
- `context.message('...')` stays for keys built at run time
  (`'theme.${name}'`).

### Themes: every property

> The full theme reference, one page per topic, is in [Flutter themes in YAML](flutter/theme/index.md).

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
        durations:
          medium: 250ms
        curves:
          standard: '0.2, 0, 0, 1'
      components:
        app-bar: { center-title: true, scrolled-under-elevation: level2 }
        button: { shape: full }
        card: { shape: large, color: $colors.surface-container-low }
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
spring.flutter.theme.motion.durations.medium=250ms
spring.flutter.theme.motion.curves.standard=0.2, 0, 0, 1
spring.flutter.theme.components.app-bar.center-title=true
spring.flutter.theme.components.app-bar.scrolled-under-elevation=level2
spring.flutter.theme.components.button.shape=full
spring.flutter.theme.components.card.shape=large
spring.flutter.theme.components.card.color=$colors.surface-container-low
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
| `motion.durations.<name>` | duration | `short` 100ms, `medium` 250ms, `long` 450ms | Durations for the app's animations |
| `motion.curves.<name>` | four numbers | `standard`: Material's | Curves for the app's animations |
| `components.<component>.<property>` | see the next table | Material 3's | Adjusts one component |
| `tokens.<group>.<key>` | any value | — | The app's own values, read with `tokenColor('brand.accent')`, `tokenNumber(...)` or `token(...)` |
| `cupertino.<property>` | see the reference below | iOS's | The `CupertinoThemeData`: `primary-color` (default `colors.primary`, else the seed, else iOS blue), `primary-contrasting-color`, `scaffold-background-color`, `bar-background-color`, `selection-handle-color`, `apply-theme-to-all`, and `text-theme.*` (the text styles) |

**Components.** `components.<component>.<property>` adjusts Flutter's own
component themes (`ThemeData` and its 48 component themes, plus
Cupertino); the app keeps using Flutter's widgets, and nothing is
generated. A property is Flutter's own, in kebab case: `AppBarThemeData`'s
`titleTextStyle` is `components.app-bar.title-text-style`. A key that is
not a component, or not a property of it, fails the start naming the
valid ones, with a "did you mean" for a typo (`components.chek-box`).
The first components also keep their shorter keys (`background`,
`foreground`, `title-style`), for example `app-bar.background`.

The values by type:

| Type | Written as |
|---|---|
| **color** | `#RGB`, `#RRGGBB`, `#AARRGGBB`, a `Colors` name (`grey.shade100`), a reference to a role (`$colors.primary`), or an object `{ color, mix: { with, amount }, alpha }` (`mix` first, then `alpha`; a percent is `12%` or `0.12`) |
| **number** | `12`, `1.5`, `infinity` |
| **elevation** | `level0` … `level5`, or a number |
| **true / false** | `true`, `false` |
| **whole number** | `2` |
| **duration** | `250ms`, `250 ms`, `1.5s`, `2m`, `1h` (the unit in any case), or plain milliseconds |
| **choice** | the name of an enum value, as Flutter spells it or in kebab case: `always-show` is `alwaysShow` |
| **insets** | `8` (all), `16, 8` (horizontal, vertical), `1, 2, 3, 4` (left, top, right, bottom), or a map of `all`, `horizontal`, `vertical`, `left`, `top`, `right`, `bottom` |
| **size** | `48` (a square), `64, 48` (width, height), or a map of `width`, `height` |
| **offset** | `x, y` |
| **constraints** | a map of `min-width`, `max-width`, `min-height`, `max-height` |
| **shape** | a shape token (`small`, `extra-large`, `full`, ...) or a radius, `stadium`, `circle`; or a map: `type` (`rounded`, `continuous`, `beveled`, `stadium`, `circle`), `radius`, and `side` |
| **border side** | a color, `none`, or a map of `color`, `width`, `style` (`solid`, `none`), `stroke-align` (`inside`, `center`, `outside`) |
| **text style** | one of the theme's styles (`display-large` … `label-small`, `code`), or a map of `style` (the base), `color`, `font-family`, `size`, `weight`, `height`, `letter-spacing`, `italic`, `decoration` (`none`, `underline`, `line-through`, `overline`) |
| **icon theme** | a color, or a map of `color`, `size`, `fill`, `weight`, `grade`, `optical-size`, `opacity` |
| **mouse cursor** | `basic`, `click`, `forbidden`, `text`, `grab`, `grabbing`, `move`, `wait`, `progress`, `help`, `precise`, `none`, `alias`, `copy`, `cell`, `no-drop`, `all-scroll`, `zoom-in`, `zoom-out`, `vertical-text`, `context-menu`, `resize-column`, `resize-row` |
| **alignment** | `center`, `top-left`, `top-center`, `top-right`, `center-left`, `center-right`, `bottom-left`, `bottom-center`, `bottom-right`, or `x, y` from -1 to 1 |
| **corner radius** | a shape token or a radius |
| **visual density** | `adaptive`, `standard`, `comfortable`, `compact`, or `horizontal, vertical` |
| **decoration** | a color, or a map of `color`, `radius`, `border` (a border side), `shape` (`rectangle`, `circle`) |
| **input border** | `outline`, `underline`, `none`, or a map of `type`, `radius`, `side` |
| **animation** | a map of `duration`, `reverse-duration` |

**A value per state.** A property marked `*` below is a
`WidgetStateProperty` in Flutter: it takes one value for every state, or a
map with a value per state. A state without a value, and no `default`,
keeps Flutter's own value. The states are `default`, `hovered`, `focused`,
`pressed`, `dragged`, `selected`, `scrolled-under`, `disabled` and `error`.
When a widget is in several at once, the strongest state that has a value
wins, in this order: `disabled` > `error` > `pressed` > `dragged` >
`hovered` > `focused` > `selected` > `scrolled-under` > `default`. A plain
value next to the states is the `default`. A state's value is of the
property's type, so a border side per state is a map of maps.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      components:
        filled-button:
          background-color:
            default: $colors.primary
            hovered: { color: $colors.primary, alpha: 90% }
            pressed: $colors.tertiary
            disabled: { color: $colors.on-surface, alpha: 12% }
          side:
            default: none
            focused: { color: $colors.secondary, width: 2 }
          text-style: { style: label-large, weight: bold }
        checkbox:
          fill-color: { default: $colors.outline, selected: $colors.primary, error: $colors.error }
        card: { shape: { type: continuous, radius: large } }
        bottom-sheet: { constraints: { max-width: 640 } }
      cupertino:
        primary-color: $colors.secondary
        scaffold-background-color: '#F2F2F7'
        text-theme:
          nav-title-text-style: { style: title-large, weight: 600 }
```

</td><td>

```properties
spring.flutter.theme.components.filled-button.background-color.default=$colors.primary
spring.flutter.theme.components.filled-button.background-color.hovered.color=$colors.primary
spring.flutter.theme.components.filled-button.background-color.hovered.alpha=90%
spring.flutter.theme.components.filled-button.background-color.pressed=$colors.tertiary
spring.flutter.theme.components.filled-button.background-color.disabled.color=$colors.on-surface
spring.flutter.theme.components.filled-button.background-color.disabled.alpha=12%
spring.flutter.theme.components.filled-button.side.default=none
spring.flutter.theme.components.filled-button.side.focused.color=$colors.secondary
spring.flutter.theme.components.filled-button.side.focused.width=2
spring.flutter.theme.components.filled-button.text-style.style=label-large
spring.flutter.theme.components.filled-button.text-style.weight=bold
spring.flutter.theme.components.checkbox.fill-color.default=$colors.outline
spring.flutter.theme.components.checkbox.fill-color.selected=$colors.primary
spring.flutter.theme.components.checkbox.fill-color.error=$colors.error
spring.flutter.theme.components.card.shape.type=continuous
spring.flutter.theme.components.card.shape.radius=large
spring.flutter.theme.components.bottom-sheet.constraints.max-width=640
spring.flutter.theme.cupertino.primary-color=$colors.secondary
spring.flutter.theme.cupertino.scaffold-background-color=#F2F2F7
spring.flutter.theme.cupertino.text-theme.nav-title-text-style.style=title-large
spring.flutter.theme.cupertino.text-theme.nav-title-text-style.weight=600
```

</td></tr>
</table>

The buttons (`elevated-button`, `filled-button`, `outlined-button`,
`text-button`) start from `button`, which holds what they share; a value
a button sets itself wins. They take every property of Flutter's
`ButtonStyle`, plus `min-height` and `border-color`. `icon-button`,
`segmented-button` and `menu-button` take the same, and do not start from
`button`. `menu` and `menu-bar` take `MenuStyle`'s. `shape` follows the
theme's shape scale when the scale changes (`shape.medium` reaches `card`).
`date-picker`, `time-picker` and `dropdown-menu` hold nested groups
(`input-decoration`, `cancel-button-style`, `confirm-button-style`,
`menu-style`) with the keys of `input`, a button and `menu`. `cupertino` is
read from its own root, `spring.flutter.theme.cupertino.*`, not below
`components`; its text styles start from iOS's, or from the typography
when the theme has one.

Every component and property of the reference below is generated from the
mapping the starter reads, and a test keeps it in step.

<!-- theme-components:start -->

| Component | Properties, by the type of their value |
|---|---|
| [`app-bar`](flutter/theme/components/app-bar.md) | **color** `background-color`, `foreground-color`, `shadow-color`, `surface-tint-color`<br>**elevation** `elevation`, `scrolled-under-elevation`<br>**shape** `shape`<br>**icon theme** `icon-theme`, `actions-icon-theme`<br>**true / false** `center-title`<br>**number** `title-spacing`, `leading-width`, `toolbar-height`<br>**text style** `toolbar-text-style`, `title-text-style`<br>**choice** `system-overlay-style` (light / dark)<br>**insets** `actions-padding` |
| [`badge`](flutter/theme/components/badge.md) | **color** `background-color`, `text-color`<br>**number** `small-size`, `large-size`<br>**text style** `text-style`<br>**insets** `padding`<br>**alignment** `alignment`<br>**offset** `offset` |
| [`banner`](flutter/theme/components/banner.md) | **color** `background-color`, `surface-tint-color`, `shadow-color`, `divider-color`<br>**text style** `content-text-style`<br>**elevation** `elevation`<br>**insets** `padding`, `leading-padding` |
| [`bottom-app-bar`](flutter/theme/components/bottom-app-bar.md) | **color** `color`, `surface-tint-color`, `shadow-color`<br>**elevation** `elevation`<br>**number** `height`<br>**insets** `padding` |
| [`bottom-navigation-bar`](flutter/theme/components/bottom-navigation-bar.md) | **color** `background-color`, `selected-item-color`, `unselected-item-color`<br>**elevation** `elevation`<br>**icon theme** `selected-icon-theme`, `unselected-icon-theme`<br>**text style** `selected-label-style`, `unselected-label-style`<br>**true / false** `show-selected-labels`, `show-unselected-labels`, `enable-feedback`<br>**choice** `type` (fixed / shifting), `landscape-layout` (spread / centered / linear)<br>**mouse cursor** `mouse-cursor`* |
| [`bottom-sheet`](flutter/theme/components/bottom-sheet.md) | **color** `background-color`, `surface-tint-color`, `modal-background-color`, `modal-barrier-color`, `shadow-color`, `drag-handle-color`<br>**elevation** `elevation`, `modal-elevation`<br>**shape** `shape`<br>**true / false** `show-drag-handle`<br>**size** `drag-handle-size`<br>**choice** `clip-behavior` (none / hard-edge / anti-alias / anti-alias-with-save-layer)<br>**constraints** `constraints` |
| [`button`](flutter/theme/components/button.md) | **number** `min-height`, `icon-size`*<br>**color** `border-color`, `background-color`*, `foreground-color`*, `overlay-color`*, `shadow-color`*, `surface-tint-color`*, `icon-color`*<br>**text style** `text-style`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**choice** `icon-alignment` (start / end), `tap-target-size` (padded / shrink-wrap), `splash-factory` (ripple / sparkle / none)<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**duration** `animation-duration`<br>**true / false** `enable-feedback`<br>**alignment** `alignment` |
| [`elevated-button`](flutter/theme/components/elevated-button.md) | **number** `min-height`, `icon-size`*<br>**color** `border-color`, `background-color`*, `foreground-color`*, `overlay-color`*, `shadow-color`*, `surface-tint-color`*, `icon-color`*<br>**text style** `text-style`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**choice** `icon-alignment` (start / end), `tap-target-size` (padded / shrink-wrap), `splash-factory` (ripple / sparkle / none)<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**duration** `animation-duration`<br>**true / false** `enable-feedback`<br>**alignment** `alignment` |
| [`filled-button`](flutter/theme/components/filled-button.md) | **number** `min-height`, `icon-size`*<br>**color** `border-color`, `background-color`*, `foreground-color`*, `overlay-color`*, `shadow-color`*, `surface-tint-color`*, `icon-color`*<br>**text style** `text-style`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**choice** `icon-alignment` (start / end), `tap-target-size` (padded / shrink-wrap), `splash-factory` (ripple / sparkle / none)<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**duration** `animation-duration`<br>**true / false** `enable-feedback`<br>**alignment** `alignment` |
| [`outlined-button`](flutter/theme/components/outlined-button.md) | **number** `min-height`, `icon-size`*<br>**color** `border-color`, `background-color`*, `foreground-color`*, `overlay-color`*, `shadow-color`*, `surface-tint-color`*, `icon-color`*<br>**text style** `text-style`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**choice** `icon-alignment` (start / end), `tap-target-size` (padded / shrink-wrap), `splash-factory` (ripple / sparkle / none)<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**duration** `animation-duration`<br>**true / false** `enable-feedback`<br>**alignment** `alignment` |
| [`text-button`](flutter/theme/components/text-button.md) | **number** `min-height`, `icon-size`*<br>**color** `border-color`, `background-color`*, `foreground-color`*, `overlay-color`*, `shadow-color`*, `surface-tint-color`*, `icon-color`*<br>**text style** `text-style`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**choice** `icon-alignment` (start / end), `tap-target-size` (padded / shrink-wrap), `splash-factory` (ripple / sparkle / none)<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**duration** `animation-duration`<br>**true / false** `enable-feedback`<br>**alignment** `alignment` |
| [`icon-button`](flutter/theme/components/icon-button.md) | **number** `min-height`, `icon-size`*<br>**color** `border-color`, `background-color`*, `foreground-color`*, `overlay-color`*, `shadow-color`*, `surface-tint-color`*, `icon-color`*<br>**text style** `text-style`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**choice** `icon-alignment` (start / end), `tap-target-size` (padded / shrink-wrap), `splash-factory` (ripple / sparkle / none)<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**duration** `animation-duration`<br>**true / false** `enable-feedback`<br>**alignment** `alignment` |
| [`segmented-button`](flutter/theme/components/segmented-button.md) | **number** `min-height`, `icon-size`*<br>**color** `border-color`, `background-color`*, `foreground-color`*, `overlay-color`*, `shadow-color`*, `surface-tint-color`*, `icon-color`*<br>**text style** `text-style`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**choice** `icon-alignment` (start / end), `tap-target-size` (padded / shrink-wrap), `splash-factory` (ripple / sparkle / none)<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**duration** `animation-duration`<br>**true / false** `enable-feedback`<br>**alignment** `alignment` |
| [`menu-button`](flutter/theme/components/menu-button.md) | **number** `min-height`, `icon-size`*<br>**color** `border-color`, `background-color`*, `foreground-color`*, `overlay-color`*, `shadow-color`*, `surface-tint-color`*, `icon-color`*<br>**text style** `text-style`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**choice** `icon-alignment` (start / end), `tap-target-size` (padded / shrink-wrap), `splash-factory` (ripple / sparkle / none)<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**duration** `animation-duration`<br>**true / false** `enable-feedback`<br>**alignment** `alignment` |
| [`toggle-buttons`](flutter/theme/components/toggle-buttons.md) | **text style** `text-style`<br>**constraints** `constraints`<br>**color** `color`, `selected-color`, `disabled-color`, `fill-color`, `focus-color`, `highlight-color`, `splash-color`, `hover-color`, `border-color`, `selected-border-color`, `disabled-border-color`<br>**number** `border-width`<br>**corner radius** `border-radius` |
| [`floating-action-button`](flutter/theme/components/floating-action-button.md) | **color** `foreground-color`, `background-color`, `focus-color`, `hover-color`, `splash-color`<br>**elevation** `elevation`, `focus-elevation`, `hover-elevation`, `disabled-elevation`, `highlight-elevation`<br>**shape** `shape`<br>**true / false** `enable-feedback`<br>**number** `icon-size`, `extended-icon-label-spacing`<br>**constraints** `size-constraints`, `small-size-constraints`, `large-size-constraints`, `extended-size-constraints`<br>**insets** `extended-padding`<br>**text style** `extended-text-style`<br>**mouse cursor** `mouse-cursor`* |
| [`card`](flutter/theme/components/card.md) | **choice** `clip-behavior` (none / hard-edge / anti-alias / anti-alias-with-save-layer)<br>**color** `color`, `shadow-color`, `surface-tint-color`<br>**elevation** `elevation`<br>**insets** `margin`<br>**shape** `shape` |
| [`carousel-view`](flutter/theme/components/carousel-view.md) | **insets** `padding`<br>**color** `background-color`, `overlay-color`*<br>**elevation** `elevation`<br>**shape** `shape`<br>**choice** `item-clip-behavior` (none / hard-edge / anti-alias / anti-alias-with-save-layer) |
| [`checkbox`](flutter/theme/components/checkbox.md) | **mouse cursor** `mouse-cursor`*<br>**color** `fill-color`*, `check-color`*, `overlay-color`*<br>**number** `splash-radius`<br>**choice** `material-tap-target-size` (padded / shrink-wrap)<br>**visual density** `visual-density`<br>**shape** `shape`<br>**border side** `side` |
| [`chip`](flutter/theme/components/chip.md) | **color** `color`*, `background-color`, `delete-icon-color`, `disabled-color`, `selected-color`, `secondary-selected-color`, `shadow-color`, `surface-tint-color`, `selected-shadow-color`, `checkmark-color`<br>**true / false** `show-checkmark`<br>**insets** `label-padding`, `padding`<br>**border side** `side`<br>**shape** `shape`<br>**text style** `label-style`, `secondary-label-style`<br>**elevation** `elevation`, `press-elevation`<br>**icon theme** `icon-theme`<br>**constraints** `avatar-box-constraints`, `delete-icon-box-constraints` |
| [`data-table`](flutter/theme/components/data-table.md) | **decoration** `decoration`<br>**color** `data-row-color`*, `heading-row-color`*<br>**number** `data-row-min-height`, `data-row-max-height`, `heading-row-height`, `horizontal-margin`, `column-spacing`, `divider-thickness`, `checkbox-horizontal-margin`<br>**text style** `data-text-style`, `heading-text-style`<br>**mouse cursor** `heading-cell-cursor`*, `data-row-cursor`*<br>**choice** `heading-row-alignment` (start / end / center / space-between / space-around / space-evenly) |
| [`date-picker`](flutter/theme/components/date-picker.md) | **color** `background-color`, `shadow-color`, `surface-tint-color`, `header-background-color`, `header-foreground-color`, `day-foreground-color`*, `day-background-color`*, `day-overlay-color`*, `today-foreground-color`*, `today-background-color`*, `year-foreground-color`*, `year-background-color`*, `year-overlay-color`*, `range-picker-background-color`, `range-picker-shadow-color`, `range-picker-surface-tint-color`, `range-picker-header-background-color`, `range-picker-header-foreground-color`, `range-selection-background-color`, `range-selection-overlay-color`*, `divider-color`, `input-decoration.fill-color`, `input-decoration.icon-color`, `input-decoration.prefix-icon-color`, `input-decoration.suffix-icon-color`, `input-decoration.focus-color`, `input-decoration.hover-color`, `cancel-button-style.border-color`, `cancel-button-style.background-color`*, `cancel-button-style.foreground-color`*, `cancel-button-style.overlay-color`*, `cancel-button-style.shadow-color`*, `cancel-button-style.surface-tint-color`*, `cancel-button-style.icon-color`*, `confirm-button-style.border-color`, `confirm-button-style.background-color`*, `confirm-button-style.foreground-color`*, `confirm-button-style.overlay-color`*, `confirm-button-style.shadow-color`*, `confirm-button-style.surface-tint-color`*, `confirm-button-style.icon-color`*, `sub-header-foreground-color`<br>**elevation** `elevation`, `range-picker-elevation`, `cancel-button-style.elevation`*, `confirm-button-style.elevation`*<br>**shape** `shape`, `day-shape`*, `year-shape`*, `range-picker-shape`, `input-decoration.shape`, `cancel-button-style.shape`*, `confirm-button-style.shape`*<br>**text style** `header-headline-style`, `header-help-style`, `weekday-style`, `day-style`, `year-style`, `range-picker-header-headline-style`, `range-picker-header-help-style`, `input-decoration.label-style`, `input-decoration.floating-label-style`, `input-decoration.helper-style`, `input-decoration.hint-style`, `input-decoration.error-style`, `input-decoration.prefix-style`, `input-decoration.suffix-style`, `input-decoration.counter-style`, `cancel-button-style.text-style`*, `confirm-button-style.text-style`*, `toggle-button-text-style`<br>**border side** `today-border`, `input-decoration.outline-border`, `input-decoration.active-indicator-border`, `cancel-button-style.side`*, `confirm-button-style.side`*<br>**choice** `input-decoration.style` (outline / underline / filled), `input-decoration.floating-label-behavior` (never / auto / always), `cancel-button-style.icon-alignment` (start / end), `cancel-button-style.tap-target-size` (padded / shrink-wrap), `cancel-button-style.splash-factory` (ripple / sparkle / none), `confirm-button-style.icon-alignment` (start / end), `confirm-button-style.tap-target-size` (padded / shrink-wrap), `confirm-button-style.splash-factory` (ripple / sparkle / none)<br>**input border** `input-decoration.border`, `input-decoration.error-border`, `input-decoration.focused-border`, `input-decoration.focused-error-border`, `input-decoration.disabled-border`, `input-decoration.enabled-border`<br>**true / false** `input-decoration.filled`, `input-decoration.is-dense`, `input-decoration.is-collapsed`, `input-decoration.align-label-with-hint`, `cancel-button-style.enable-feedback`, `confirm-button-style.enable-feedback`<br>**insets** `input-decoration.content-padding`, `cancel-button-style.padding`*, `confirm-button-style.padding`*<br>**whole number** `input-decoration.helper-max-lines`, `input-decoration.hint-max-lines`, `input-decoration.error-max-lines`<br>**duration** `input-decoration.hint-fade-duration`, `cancel-button-style.animation-duration`, `confirm-button-style.animation-duration`<br>**constraints** `input-decoration.prefix-icon-constraints`, `input-decoration.suffix-icon-constraints`, `input-decoration.constraints`<br>**visual density** `input-decoration.visual-density`, `cancel-button-style.visual-density`, `confirm-button-style.visual-density`<br>**number** `cancel-button-style.min-height`, `cancel-button-style.icon-size`*, `confirm-button-style.min-height`, `confirm-button-style.icon-size`*<br>**size** `cancel-button-style.minimum-size`*, `cancel-button-style.fixed-size`*, `cancel-button-style.maximum-size`*, `confirm-button-style.minimum-size`*, `confirm-button-style.fixed-size`*, `confirm-button-style.maximum-size`*<br>**mouse cursor** `cancel-button-style.mouse-cursor`*, `confirm-button-style.mouse-cursor`*<br>**alignment** `cancel-button-style.alignment`, `confirm-button-style.alignment` |
| [`dialog`](flutter/theme/components/dialog.md) | **color** `background-color`, `shadow-color`, `surface-tint-color`, `icon-color`, `barrier-color`<br>**elevation** `elevation`<br>**shape** `shape`<br>**alignment** `alignment`<br>**text style** `title-text-style`, `content-text-style`<br>**insets** `actions-padding`, `inset-padding`<br>**choice** `clip-behavior` (none / hard-edge / anti-alias / anti-alias-with-save-layer)<br>**constraints** `constraints` |
| [`divider`](flutter/theme/components/divider.md) | **color** `color`<br>**number** `space`, `thickness`, `indent`, `end-indent`<br>**corner radius** `radius` |
| [`drawer`](flutter/theme/components/drawer.md) | **color** `background-color`, `scrim-color`, `shadow-color`, `surface-tint-color`<br>**elevation** `elevation`<br>**shape** `shape`, `end-shape`<br>**number** `width`<br>**choice** `clip-behavior` (none / hard-edge / anti-alias / anti-alias-with-save-layer) |
| [`dropdown-menu`](flutter/theme/components/dropdown-menu.md) | **text style** `text-style`, `input-decoration.label-style`, `input-decoration.floating-label-style`, `input-decoration.helper-style`, `input-decoration.hint-style`, `input-decoration.error-style`, `input-decoration.prefix-style`, `input-decoration.suffix-style`, `input-decoration.counter-style`<br>**choice** `input-decoration.style` (outline / underline / filled), `input-decoration.floating-label-behavior` (never / auto / always)<br>**shape** `input-decoration.shape`, `menu-style.shape`*<br>**input border** `input-decoration.border`, `input-decoration.error-border`, `input-decoration.focused-border`, `input-decoration.focused-error-border`, `input-decoration.disabled-border`, `input-decoration.enabled-border`<br>**true / false** `input-decoration.filled`, `input-decoration.is-dense`, `input-decoration.is-collapsed`, `input-decoration.align-label-with-hint`<br>**color** `input-decoration.fill-color`, `input-decoration.icon-color`, `input-decoration.prefix-icon-color`, `input-decoration.suffix-icon-color`, `input-decoration.focus-color`, `input-decoration.hover-color`, `menu-style.background-color`*, `menu-style.shadow-color`*, `menu-style.surface-tint-color`*, `disabled-color`<br>**insets** `input-decoration.content-padding`, `menu-style.padding`*<br>**whole number** `input-decoration.helper-max-lines`, `input-decoration.hint-max-lines`, `input-decoration.error-max-lines`<br>**duration** `input-decoration.hint-fade-duration`<br>**constraints** `input-decoration.prefix-icon-constraints`, `input-decoration.suffix-icon-constraints`, `input-decoration.constraints`<br>**border side** `input-decoration.outline-border`, `input-decoration.active-indicator-border`, `menu-style.side`*<br>**visual density** `input-decoration.visual-density`, `menu-style.visual-density`<br>**elevation** `menu-style.elevation`*<br>**size** `menu-style.minimum-size`*, `menu-style.fixed-size`*, `menu-style.maximum-size`*<br>**mouse cursor** `menu-style.mouse-cursor`*<br>**alignment** `menu-style.alignment` |
| [`expansion-tile`](flutter/theme/components/expansion-tile.md) | **color** `background-color`, `collapsed-background-color`, `icon-color`, `collapsed-icon-color`, `text-color`, `collapsed-text-color`<br>**insets** `tile-padding`, `children-padding`<br>**alignment** `expanded-alignment`<br>**shape** `shape`, `collapsed-shape`<br>**choice** `clip-behavior` (none / hard-edge / anti-alias / anti-alias-with-save-layer)<br>**animation** `expansion-animation-style` |
| [`icon`](flutter/theme/components/icon.md) | **color** `color`<br>**number** `size`, `fill`, `weight`, `grade`, `optical-size`, `opacity` |
| [`primary-icon`](flutter/theme/components/primary-icon.md) | **color** `color`<br>**number** `size`, `fill`, `weight`, `grade`, `optical-size`, `opacity` |
| [`input`](flutter/theme/components/input.md) | **choice** `style` (outline / underline / filled), `floating-label-behavior` (never / auto / always)<br>**shape** `shape`<br>**input border** `border`, `error-border`, `focused-border`, `focused-error-border`, `disabled-border`, `enabled-border`<br>**true / false** `filled`, `is-dense`, `is-collapsed`, `align-label-with-hint`<br>**color** `fill-color`, `icon-color`, `prefix-icon-color`, `suffix-icon-color`, `focus-color`, `hover-color`<br>**insets** `content-padding`<br>**text style** `label-style`, `floating-label-style`, `helper-style`, `hint-style`, `error-style`, `prefix-style`, `suffix-style`, `counter-style`<br>**whole number** `helper-max-lines`, `hint-max-lines`, `error-max-lines`<br>**duration** `hint-fade-duration`<br>**constraints** `prefix-icon-constraints`, `suffix-icon-constraints`, `constraints`<br>**border side** `outline-border`, `active-indicator-border`<br>**visual density** `visual-density` |
| [`list-tile`](flutter/theme/components/list-tile.md) | **true / false** `dense`, `enable-feedback`, `is-three-line`<br>**shape** `shape`<br>**choice** `style` (list / drawer), `title-alignment` (three-line / title-height / top / center / bottom), `control-affinity` (leading / trailing / platform)<br>**color** `selected-color`, `icon-color`, `text-color`, `tile-color`, `selected-tile-color`<br>**text style** `title-text-style`, `subtitle-text-style`, `leading-and-trailing-text-style`<br>**insets** `content-padding`<br>**number** `horizontal-title-gap`, `min-vertical-padding`, `min-leading-width`, `min-tile-height`<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density` |
| [`menu`](flutter/theme/components/menu.md) | **color** `background-color`*, `shadow-color`*, `surface-tint-color`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**alignment** `alignment` |
| [`menu-bar`](flutter/theme/components/menu-bar.md) | **color** `background-color`*, `shadow-color`*, `surface-tint-color`*<br>**elevation** `elevation`*<br>**insets** `padding`*<br>**size** `minimum-size`*, `fixed-size`*, `maximum-size`*<br>**border side** `side`*<br>**shape** `shape`*<br>**mouse cursor** `mouse-cursor`*<br>**visual density** `visual-density`<br>**alignment** `alignment` |
| [`navigation-bar`](flutter/theme/components/navigation-bar.md) | **number** `height`<br>**color** `background-color`, `shadow-color`, `surface-tint-color`, `indicator-color`, `overlay-color`*<br>**elevation** `elevation`<br>**shape** `indicator-shape`<br>**text style** `label-text-style`*<br>**icon theme** `icon-theme`*<br>**choice** `label-behavior` (always-show / always-hide / only-show-selected)<br>**insets** `label-padding` |
| [`navigation-drawer`](flutter/theme/components/navigation-drawer.md) | **number** `tile-height`<br>**color** `background-color`, `shadow-color`, `surface-tint-color`, `indicator-color`<br>**elevation** `elevation`<br>**shape** `indicator-shape`<br>**size** `indicator-size`<br>**text style** `label-text-style`*<br>**icon theme** `icon-theme`* |
| [`navigation-rail`](flutter/theme/components/navigation-rail.md) | **color** `background-color`, `indicator-color`<br>**elevation** `elevation`<br>**text style** `unselected-label-text-style`, `selected-label-text-style`<br>**icon theme** `unselected-icon-theme`, `selected-icon-theme`<br>**number** `group-alignment`, `min-width`, `min-extended-width`<br>**choice** `label-type` (none / selected / all)<br>**true / false** `use-indicator`<br>**shape** `indicator-shape` |
| [`popup-menu`](flutter/theme/components/popup-menu.md) | **color** `color`, `shadow-color`, `surface-tint-color`, `icon-color`<br>**shape** `shape`<br>**insets** `menu-padding`<br>**elevation** `elevation`<br>**text style** `text-style`, `label-text-style`*<br>**true / false** `enable-feedback`<br>**mouse cursor** `mouse-cursor`*<br>**choice** `position` (over / under)<br>**number** `icon-size` |
| [`progress-indicator`](flutter/theme/components/progress-indicator.md) | **color** `color`, `linear-track-color`, `circular-track-color`, `refresh-background-color`, `stop-indicator-color`<br>**number** `linear-min-height`, `stop-indicator-radius`, `stroke-width`, `stroke-align`, `track-gap`<br>**corner radius** `border-radius`<br>**choice** `stroke-cap` (butt / round / square)<br>**constraints** `constraints`<br>**insets** `circular-track-padding` |
| [`radio`](flutter/theme/components/radio.md) | **mouse cursor** `mouse-cursor`*<br>**color** `fill-color`*, `overlay-color`*, `background-color`*<br>**number** `splash-radius`, `inner-radius`*<br>**choice** `material-tap-target-size` (padded / shrink-wrap)<br>**visual density** `visual-density`<br>**border side** `side` |
| [`scrollbar`](flutter/theme/components/scrollbar.md) | **true / false** `thumb-visibility`*, `track-visibility`*, `interactive`<br>**number** `thickness`*, `cross-axis-margin`, `main-axis-margin`, `min-thumb-length`<br>**corner radius** `radius`<br>**color** `thumb-color`*, `track-color`*, `track-border-color`* |
| [`search-bar`](flutter/theme/components/search-bar.md) | **elevation** `elevation`*<br>**color** `background-color`*, `shadow-color`*, `surface-tint-color`*, `overlay-color`*<br>**border side** `side`*<br>**shape** `shape`*<br>**insets** `padding`*<br>**text style** `text-style`*, `hint-style`*<br>**constraints** `constraints`<br>**choice** `text-capitalization` (words / sentences / characters / none) |
| [`search-view`](flutter/theme/components/search-view.md) | **color** `background-color`, `surface-tint-color`, `divider-color`<br>**elevation** `elevation`<br>**border side** `side`<br>**shape** `shape`<br>**number** `header-height`<br>**text style** `header-text-style`, `header-hint-style`<br>**constraints** `constraints`<br>**insets** `padding`, `bar-padding`<br>**true / false** `shrink-wrap` |
| [`slider`](flutter/theme/components/slider.md) | **number** `track-height`, `min-thumb-separation`, `track-gap`<br>**color** `active-track-color`, `inactive-track-color`, `secondary-active-track-color`, `disabled-active-track-color`, `disabled-secondary-active-track-color`, `disabled-inactive-track-color`, `active-tick-mark-color`, `inactive-tick-mark-color`, `disabled-active-tick-mark-color`, `disabled-inactive-tick-mark-color`, `thumb-color`, `overlapping-shape-stroke-color`, `disabled-thumb-color`, `overlay-color`, `value-indicator-color`, `value-indicator-stroke-color`<br>**choice** `show-value-indicator` (only-for-discrete / only-for-continuous / always / on-drag / always-visible / never), `allowed-interaction` (tap-and-slide / tap-only / slide-only / slide-thumb)<br>**text style** `value-indicator-text-style`<br>**mouse cursor** `mouse-cursor`*<br>**insets** `padding`<br>**size** `thumb-size`* |
| [`snack-bar`](flutter/theme/components/snack-bar.md) | **color** `background-color`, `action-text-color`, `disabled-action-text-color`, `close-icon-color`, `action-background-color`, `disabled-action-background-color`<br>**text style** `content-text-style`<br>**elevation** `elevation`<br>**shape** `shape`<br>**choice** `behavior` (fixed / floating), `dismiss-direction` (vertical / horizontal / end-to-start / start-to-end / up / down / none)<br>**number** `width`, `action-overflow-threshold`<br>**insets** `inset-padding`<br>**true / false** `show-close-icon` |
| [`switch`](flutter/theme/components/switch.md) | **color** `thumb-color`*, `track-color`*, `track-outline-color`*, `overlay-color`*<br>**number** `track-outline-width`*, `splash-radius`<br>**choice** `material-tap-target-size` (padded / shrink-wrap)<br>**mouse cursor** `mouse-cursor`*<br>**insets** `padding` |
| [`tab-bar`](flutter/theme/components/tab-bar.md) | **decoration** `indicator`<br>**color** `indicator-color`, `divider-color`, `label-color`, `unselected-label-color`, `overlay-color`*<br>**choice** `indicator-size` (tab / label), `splash-factory` (ripple / sparkle / none), `tab-alignment` (start / start-offset / fill / center), `indicator-animation` (linear / elastic)<br>**number** `divider-height`<br>**insets** `label-padding`<br>**text style** `label-style`, `unselected-label-style`<br>**mouse cursor** `mouse-cursor`*<br>**corner radius** `splash-border-radius` |
| [`text-selection`](flutter/theme/components/text-selection.md) | **color** `cursor-color`, `selection-color`, `selection-handle-color` |
| [`time-picker`](flutter/theme/components/time-picker.md) | **color** `background-color`, `cancel-button-style.border-color`, `cancel-button-style.background-color`*, `cancel-button-style.foreground-color`*, `cancel-button-style.overlay-color`*, `cancel-button-style.shadow-color`*, `cancel-button-style.surface-tint-color`*, `cancel-button-style.icon-color`*, `confirm-button-style.border-color`, `confirm-button-style.background-color`*, `confirm-button-style.foreground-color`*, `confirm-button-style.overlay-color`*, `confirm-button-style.shadow-color`*, `confirm-button-style.surface-tint-color`*, `confirm-button-style.icon-color`*, `day-period-color`, `day-period-text-color`, `dial-background-color`, `dial-hand-color`, `dial-text-color`, `entry-mode-icon-color`, `hour-minute-color`, `hour-minute-text-color`, `input-decoration.fill-color`, `input-decoration.icon-color`, `input-decoration.prefix-icon-color`, `input-decoration.suffix-icon-color`, `input-decoration.focus-color`, `input-decoration.hover-color`, `time-selector-separator-color`*<br>**number** `cancel-button-style.min-height`, `cancel-button-style.icon-size`*, `confirm-button-style.min-height`, `confirm-button-style.icon-size`*<br>**text style** `cancel-button-style.text-style`*, `confirm-button-style.text-style`*, `day-period-text-style`, `dial-text-style`, `help-text-style`, `hour-minute-text-style`, `input-decoration.label-style`, `input-decoration.floating-label-style`, `input-decoration.helper-style`, `input-decoration.hint-style`, `input-decoration.error-style`, `input-decoration.prefix-style`, `input-decoration.suffix-style`, `input-decoration.counter-style`, `time-selector-separator-text-style`*<br>**elevation** `cancel-button-style.elevation`*, `confirm-button-style.elevation`*, `elevation`<br>**insets** `cancel-button-style.padding`*, `confirm-button-style.padding`*, `input-decoration.content-padding`, `padding`<br>**size** `cancel-button-style.minimum-size`*, `cancel-button-style.fixed-size`*, `cancel-button-style.maximum-size`*, `confirm-button-style.minimum-size`*, `confirm-button-style.fixed-size`*, `confirm-button-style.maximum-size`*<br>**choice** `cancel-button-style.icon-alignment` (start / end), `cancel-button-style.tap-target-size` (padded / shrink-wrap), `cancel-button-style.splash-factory` (ripple / sparkle / none), `confirm-button-style.icon-alignment` (start / end), `confirm-button-style.tap-target-size` (padded / shrink-wrap), `confirm-button-style.splash-factory` (ripple / sparkle / none), `input-decoration.style` (outline / underline / filled), `input-decoration.floating-label-behavior` (never / auto / always)<br>**border side** `cancel-button-style.side`*, `confirm-button-style.side`*, `day-period-border-side`, `input-decoration.outline-border`, `input-decoration.active-indicator-border`<br>**shape** `cancel-button-style.shape`*, `confirm-button-style.shape`*, `day-period-shape`, `hour-minute-shape`, `input-decoration.shape`, `shape`<br>**mouse cursor** `cancel-button-style.mouse-cursor`*, `confirm-button-style.mouse-cursor`*<br>**visual density** `cancel-button-style.visual-density`, `confirm-button-style.visual-density`, `input-decoration.visual-density`<br>**duration** `cancel-button-style.animation-duration`, `confirm-button-style.animation-duration`, `input-decoration.hint-fade-duration`<br>**true / false** `cancel-button-style.enable-feedback`, `confirm-button-style.enable-feedback`, `input-decoration.filled`, `input-decoration.is-dense`, `input-decoration.is-collapsed`, `input-decoration.align-label-with-hint`<br>**alignment** `cancel-button-style.alignment`, `confirm-button-style.alignment`<br>**input border** `input-decoration.border`, `input-decoration.error-border`, `input-decoration.focused-border`, `input-decoration.focused-error-border`, `input-decoration.disabled-border`, `input-decoration.enabled-border`<br>**whole number** `input-decoration.helper-max-lines`, `input-decoration.hint-max-lines`, `input-decoration.error-max-lines`<br>**constraints** `input-decoration.prefix-icon-constraints`, `input-decoration.suffix-icon-constraints`, `input-decoration.constraints` |
| [`tooltip`](flutter/theme/components/tooltip.md) | **shape** `shape`<br>**color** `background`<br>**decoration** `decoration`<br>**constraints** `constraints`<br>**insets** `padding`, `margin`<br>**number** `vertical-offset`<br>**true / false** `prefer-below`, `exclude-from-semantics`, `enable-feedback`<br>**text style** `text-style`<br>**choice** `text-align` (left / right / center / justify / start / end), `trigger-mode` (manual / long-press / tap)<br>**duration** `wait-duration`, `show-duration`, `exit-duration` |
| [`cupertino`](flutter/theme/cupertino.md) (own root) | **color** `primary-color`, `text-theme.primary-color`, `primary-contrasting-color`, `scaffold-background-color`, `bar-background-color`, `selection-handle-color`<br>**text style** `text-theme.text-style`, `text-theme.action-text-style`, `text-theme.tab-label-text-style`, `text-theme.nav-title-text-style`, `text-theme.nav-large-title-text-style`, `text-theme.nav-action-text-style`, `text-theme.picker-text-style`, `text-theme.date-time-picker-text-style`<br>**true / false** `apply-theme-to-all` |

<!-- theme-components:end -->

**Colors** are a name from Flutter's `Colors` (`deepPurple`,
`deepPurple.shade200`, `redAccent.shade100`, `black54`; `deep-purple`
works too) or `#RGB`, `#RRGGBB` or `#AARRGGBB`. In YAML, quote a value
that starts with `#`.

#### A theme in its own file

A custom theme can live in a file of its own, imported from
`application.yml` with `spring.config.import: resources:themes/ocean.yml`:

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

#### A theme from a URL

A custom theme can be downloaded from `https` under a name the app chooses,
whatever the file calls its theme:

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      active: brand
      themes:
        brand:
          source: https://themes.neon.example/ocean.yml
          source-sha256: 3f9a1c5e7b2d4a6f8c0e1b3d5f7a9c2e4b6d8f0a1c3e5b7d9f1a3c5e7b9d1f3a
          refresh: 1h
        brand-dark:
          extends: brand
          brightness: dark
```

</td><td>

```properties
spring.flutter.theme.active=brand
spring.flutter.theme.themes.brand.source=https://themes.neon.example/ocean.yml
spring.flutter.theme.themes.brand.source-sha256=3f9a1c5e7b2d4a6f8c0e1b3d5f7a9c2e4b6d8f0a1c3e5b7d9f1a3c5e7b9d1f3a
spring.flutter.theme.themes.brand.refresh=1h
spring.flutter.theme.themes.brand-dark.extends=brand
spring.flutter.theme.themes.brand-dark.brightness=dark
```

</td></tr>
</table>

| Key (under `spring.flutter.theme.themes.<name>.`) | Default | Meaning |
|---|---|---|
| `source` | none | where the theme comes from: an `https` URL, or `github:owner/repo/path@ref`, which is `https://raw.githubusercontent.com/owner/repo/ref/path` (`HEAD` without `@ref`). `http` and other schemes stop the start, naming the property |
| `source-sha256` | none | 64 hexadecimal digits: content with another digest is refused (not shown, not cached). Part of the cache's identity |
| `refresh` | none (cached for ever) | a duration (`30m`, `1h`, `1.5d`): when the cache is older, the file is read again in the background |

- The file is written like the theme part of `application.yml`: the keys
  under `spring.flutter.theme`, or at the top, or one `themes.<any name>`
  block. Only the theme's look is taken and it becomes `<name>`; any other
  key (`spring.datasource.*`, `active`, `extends`, `system-light`, `source`, ...) is
  ignored with a warning. Keys the theme does not know stop that theme
  (not the app) like in any theme file.
- The theme is always cached in the `support` place through `FileTemplate`,
  in `spring/themes/<sha256 of source and pin>/` (`theme.yml`, and
  `meta.json` with `source`, `sha256`, `fetchedAt`, `etag`,
  `lastModified`), and the cache survives restarts. Without `refresh` it is
  downloaded once (the first start that has the network) and read from the
  cache for ever. With `refresh` the cache is used at once and read again in
  the background when it is older, with `If-None-Match` and
  `If-Modified-Since` (a `304` only renews `fetchedAt`); a new theme is
  shown live, without a restart.
- The cache belongs to the source: another `source` or `source-sha256`
  downloads again, and the cache folders of sources no longer configured
  are removed at start.
- The start never waits on the network when a cache exists. Without one,
  the download may take 10 seconds and 1 MiB at most (redirects only to
  `https`; a theme's request has no custom headers); offline, an error, a timeout or an invalid file leave the theme
  the app's own files describe for `<name>`, and the next start tries again.
- The theme keys the generator typed (`context.theme`) come from the build:
  the file changes values, it does not add keys.

### Themes without Dart: references, states, motion, background, images

> The full theme reference, one page per topic, is in [Flutter themes in YAML](flutter/theme/index.md).

Since 0.6.3 a design system can live in YAML. The examples below sit under
`spring.flutter.theme` (and under `themes.<name>` for one theme); the
`spring:` levels are left out to keep them short.

#### References and color objects

Any value can name another value of the same theme with `$` and its path:

```yaml
seed-color: $colors.primary
colors:
  primary: '#F5E000'
tokens:
  neon:
    yellow: $colors.primary
    badge-fill: { color: $colors.primary, alpha: 12% }
    hover-fill: { color: $colors.primary, mix: { with: white, amount: 14% } }
```

- A path starts at the root of the theme: `$colors.primary`, `$spacing.m`,
  `$motion.durations.fast`, `$tokens.neon.yellow`. A token path may drop
  `tokens.` when its group is not the name of a root section
  (`$neon.yellow`).
- A Material role you did not write down can be referenced too:
  `$colors.outline`, `$colors.surface-container-lowest`. It is the role of
  the palette that the theme's own `seed-color`, `brightness`,
  `scheme-variant` and `contrast` make (other `colors.*` you declare do not
  change it). The same for Material 3's corner radii: `$shape.extra-small`.
  A value you wrote down wins. An unknown name stops the start with the
  closest one.
- Values under `headers` and the image keys `source`, `fallback` and
  `source-sha256` are never resolved: a `$abc` (or `$$`) from a placeholder
  such as `${cdn.token}` stays as it is.
- References are resolved per theme, after `extends`. A dark theme that
  changes `colors.primary` changes everything that refers to it.
- A cycle or an unknown path stops the start. The message shows the chain
  and the closest name.
- `$path` is replaced wherever it stands in a value, as a whole value, in a
  color object or inside a longer text (`120ms ease-out` can be
  `$motion.durations.fast ease-out`).
- `$$` is a literal `$`. A `$` followed by anything but a letter is text
  (`$5`).
- Colors: a color that is changed is an object, `{ color: $colors.primary,
  alpha: 12% }` or `{ color: $colors.primary, mix: { with: white, amount:
  14% } }` (`mix` is applied first, then `alpha`; a percent is `12%` or
  `0.12`). A `color` is a reference, `#RRGGBB`, `#AARRGGBB` or a name
  (`white`, `black`, `transparent`).

Why not `${...}`? That is Spring's placeholder. It reads any property of the
`Environment` (`${cdn.token}`) and it still works in a theme. A theme path
starts at the theme's root, not at a property key, so it has its own, shorter
form.

#### Nested tokens

Tokens can be as deep as you like. They can hold lists and durations. No more
JSON inside a YAML string:

```yaml
tokens:
  neon:
    modal:
      width: 460
      fade: 250ms
      barrier: transparent
      border:
        width: 1
        glow: 8
        colors: [$neon.yellow, $neon.cyan, $neon.pink]
```

```dart
final border = context.theme.tokens.neon.modal.border;
border.width;     // double
border.colors;    // List<Color>
context.theme.tokens.neon.modal.fade;   // Duration
```

A token is typed by its value: a color, a number, a duration (`250ms`), text,
or a list of one type (`List<Color>`, `List<double>`, `List<String>`). Every
group becomes a small class. Tokens with two levels, as in 0.6.2, read as
before.

#### Styles for your own widgets: `styles.*`

Material's components have their states (hovered, pressed, focused...) in
`components.*`. Your own widgets get the same under `styles.<name>`. Give a
property one value, or a map of states:

```yaml
styles:
  neon-chip:
    padding: [12, 6]
    border: { default: $colors.outline, hovered: $colors.primary, selected: $colors.primary }
    fill:   { default: transparent, selected: { color: $colors.primary, alpha: 12% } }
    text:   { default: $colors.on-surface-variant, hovered: $colors.primary }
    transition: 120ms ease-out
```

The states are `default`, `hovered`, `focused`, `pressed`, `dragged`,
`selected`, `scrolled-under`, `disabled` and `error`. When several are true,
the first of this list wins: disabled, error, pressed, dragged, hovered,
focused, selected, scrolled-under, default. A property with states must have
`default`.

Values are typed by what they look like: a color, a number, insets
(`[all]`, `[horizontal, vertical]` or `[left, top, right, bottom]`), text or a
duration. `transition: <duration> [<curve>]` animates the change between
states.

The widget `ThemeStates` tracks the states for you:

```dart
ThemeStates(
  style: context.theme.styles.neonChip,
  selected: selected,
  onPressed: onPressed,           // null: the chip is disabled
  builder: (context, s) => Container(
    padding: s.padding,           // EdgeInsets
    decoration: BoxDecoration(
      color: s.fill,              // Color
      border: Border.all(color: s.border),
    ),
    child: Text(label, style: TextStyle(color: s.text)),
  ),
)
```

It follows the mouse, the focus and the press, handles Enter and Space and the
mouse cursor, and blends the values over `transition`. `selected` and `error`
come from your arguments. Names can be written in any spelling: `neon-chip`,
`neonChip`, `neon_chip`.

#### Motion and animations

```yaml
motion:
  durations: { fast: 120ms, medium: 250ms }
  curves: { emphasized: [0.2, 0, 0, 1], out: ease-out }
  page-transition: fade-upwards
animations:
  border-spin: { duration: 4s, curve: linear, repeat: loop }
  glow-pulse:  { duration: 1.6s, curve: ease-in-out, repeat: reverse }
```

```dart
AnimatedContainer(
  duration: context.theme.motion.fast,                  // a Duration
  curve: context.theme.motion.curves.emphasized,        // a Curve
  ...
)
```

- `motion.durations.<name>` and `motion.curves.<name>` are yours to name. A
  curve is a name (`linear`, `ease`, `ease-in`, `ease-out`, `ease-in-out`,
  `fast-out-slow-in`, `emphasized`, ...) or four numbers for a cubic curve.
- **Reduce motion:** when the device asks for less motion, every duration
  from `context.theme.motion` is `Duration.zero`, an animation with
  `repeat: none` jumps to its end (`t` is 1), and `loop` and `reverse` stand
  still at 0.
- `animations.<name>` has `duration`, `curve` and `repeat`: `none` (once),
  `loop` or `reverse` (back and forth).

`ThemeAnimation` plays one:

```dart
ThemeAnimation(
  context.theme.animations.borderSpin,
  builder: (context, t) => Transform.rotate(angle: t * 2 * pi, child: child),
)
```

`t` goes from 0 to 1. The widget owns the controller, repeats as asked, stands
still (a one-shot goes to its end) when the device asks for less motion, and takes the new duration when the
theme changes.

#### The background: `background`

```yaml
background:
  color: $colors.surface-container-lowest
  image:
    source: https://cdn.example.com/neon/background.jpg
    fit: cover
    alignment: center
    opacity: 0.9
    blur: 0
  overlay:
    gradient: { type: linear, begin: top, end: bottom, colors: [transparent, '#CC0A0C12'] }
  animation: background-drift      # a name from animations.*
  effect: drift                    # drift | zoom | pulse
  transition: 400ms ease-out
  screens:
    login: { image: { source: packages/neon_ui/assets/images/login.jpg } }
```

- With `background` set, `SpringApp` puts it under every screen and makes the
  Material scaffold and the Cupertino page backgrounds **transparent**, so the
  background shows through. A scaffold color you set in the theme is kept.
- The image is loaded at start. A theme switch, or a new image, fades over
  `transition`.
- A gradient has `type` (`linear` or `radial`), `begin`, `end`, `colors` and
  `stops`. For a radial gradient `begin` is the center.
- `ThemeBackground.screen('login', child: ...)` shows `screens.login` over the
  theme's background. `ThemeBackground.none(child: ...)` gives a plain surface
  for a screen that should not have the background. Without a name,
  `ThemeBackground(child: ...)` shows the theme's background (this is what
  `SpringApp` uses).
- Read the values with `context.theme.background`.
- With less motion on the device, the background stands still and changes
  without a fade.

#### Images from the network: `ThemeImage`

The background, the screens' backgrounds and image tokens all take the same
map. `source` is an asset path or a URL:

```yaml
image:
  source: https://cdn.example.com/neon/background.jpg
  refresh: 1d
  source-sha256: 9f2c1a...                 # 64 hexadecimal digits
  headers: { Authorization: 'Bearer ${cdn.token}' }
  timeout: 10s
  fallback: packages/neon_ui/assets/images/neon-background.jpg
  allow-http: false
```

An image token is a token map with `source` and only the keys of this table:

```yaml
tokens:
  neon:
    hero: { source: https://cdn.example.com/hero.png, refresh: 1d }
```

```dart
final hero = context.theme.tokens.neon.hero;      // a ThemeImage
ValueListenableBuilder(
  valueListenable: hero.listenable,
  builder: (context, provider, _) =>
      provider == null ? const SizedBox() : Image(image: provider),
)
```

| Key | Default | Meaning |
|---|---|---|
| `source` | required | an asset path, an `https` URL, or an `http` URL with `allow-http` |
| `refresh` | none | a duration. Without it the file is downloaded once and read from the cache for ever. With it the cache is shown at once and checked again in the background when older |
| `source-sha256` | none | 64 hexadecimal digits. A file with another digest is dropped with a warning |
| `headers` | none | request headers. A map (`{ Authorization: ... }`). `${...}` placeholders work here |
| `timeout` | `10s` | how long a download may take |
| `fallback` | none | an asset shown while there is no cache |
| `allow-http` | `false` | `true` for an `http://` source. Without it the start stops with a hint. Android and iOS refuse clear text anyway |

- It works like [a theme from a URL](#a-theme-from-a-url): the same HTTP
  client, and a cache through `FileTemplate`.
- **The cache** is in the `support` place, in `spring/images/<sha256 of source
  and pin>/` (`image` and `meta.json`). It survives restarts. In a browser it
  is in IndexedDB. Images that are no longer configured are removed at start.
- **The start never waits for the network.** The app shows the cache; with no
  cache the `fallback`; with no `fallback` the `background.color`. When the
  download ends, the image fades in. Offline, a timeout or a bad digest keep
  what is shown, with a warning.
- A redirect to another host drops your custom `headers` (so a token is not
  sent to a stranger).
- **On the web** the server must allow your origin with CORS headers. If a
  download fails, the log says so.

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

### Files of the app

`FileTemplate` has no properties: it is a bean (with a `FileStore` under it,
each only when the app declares none) that writes and reads the app's own
files in three places, the directories `path_provider` finds.

| Place | In code | What it is |
|---|---|---|
| `support` | `files.write(...)` | the app's private data, kept and backed up; the default. The same directory as SQLite's `support` below, except on Android (`files/`, SQLite uses `databases/`); on Windows `%LOCALAPPDATA%\<company>\<product>`, the machine's own, not the roaming directory of `getApplicationSupportDirectory` |
| `cache` | `files.cache.write(...)` | the system may clear it. On Windows the `cache` folder inside the `support` directory (`path_provider`'s cache directory is that `support` directory itself) |
| `documents` | `files.documents.write(...)` | the user sees it |

On the web every place is IndexedDB. Temporary files (`temp`, `tempDir`,
`createTemp`) live in `<system temp>/spring/<run id>/` and are removed after
their block, when the context closes, and (runs that died) at the next
start. See the
[starter's README](https://github.com/farum-azula/spring_core_dart/blob/main/spring_boot_starter_flutter/README.md#files-of-the-app).

### SQLite databases

A Flutter app has no working directory to keep a database in, and
SQLite's calls are synchronous: on the UI isolate a slow query drops
frames. When the app configures a SQL database (`spring.datasource.url`,
or `spring.datasources.<name>.url`), the starter makes the data starter
see two properties, for the primary data source and for each named one:
the app's directory as `base-directory`, so `sqlite:file:books.db` is a
file there, and `isolate=true`, so each connection runs on an isolate of
its own. They have the lowest precedence of all: a property of your own
(a file, `--dart-define`, `defaultProperties`) wins. Without a data
source, nothing is set. The web has no such directory yet: nothing is set
there.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  datasource:
    url: sqlite:file:books.db
    sqlite:
      location: support
```

</td><td>

```properties
spring.datasource.url=sqlite:file:books.db
spring.datasource.sqlite.location=support
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.datasource.sqlite.location` | `support` / `cache` / `documents` | `support` | Which directory of the app holds the databases; any other value stops the start, naming these three |
| `spring.datasource.sqlite.base-directory` | path | the directory of `location` | Set by the starter; the directory is created when it is missing |
| `spring.datasource.sqlite.isolate` | bool | `true` | Set by the starter; `false` keeps the calls on the caller's isolate |

`support` is the app's private data, which the system never deletes and
backs up with the device; `cache` can be deleted when space runs out, so
it is for a database that can be built again; `documents` is the user's
documents folder. `support` is, per platform:

| Platform | `support` directory |
|---|---|
| Android | the app's `databases/` directory (where `Context.getDatabasePath` puts databases), next to the `files/` directory of `getApplicationSupportDirectory()` |
| iOS | `Library/Application Support` (`getApplicationSupportDirectory()`) |
| macOS | the container's `Application Support/<bundle id>` (`getApplicationSupportDirectory()`) |
| Windows | `%LOCALAPPDATA%\<company>\<product>`, the machine's own: the roaming directory that `getApplicationSupportDirectory()` returns would copy the file between machines. `cache` is the `cache` folder inside it, so the two never share a folder; `FileTemplate` uses the same directories |
| Linux | `$XDG_DATA_HOME/<app id>` (`getApplicationSupportDirectory()`) |

The directories come from `path_provider`, read before the application
starts. A widget test has no `path_provider` plugin: the starter then
sets nothing, and the database stays where its URL says. A test that
wants the directories installs a `PathProviderPlatform` of its own.

### The web dev server

`flutter run -d chrome` and `-d web-server` serve the web version on a
random port unless configured. These keys set the dev server instead:
`spring_core_dart_generator` writes them into `web_dev_config.yaml`,
which `flutter run` reads on the web (Flutter 3.38 and later). The
generator runs this step for every package that depends on it, pure Dart
servers included, so it never fails a build, and says nothing, unless the
app evidently uses the file: a config file it can read without loading
the config (any `.properties`, `.yml` or `.yaml` file of
`lib/resources/`, in any document, for any profile, or a file an import
names with a file hint, such as `resources:dev.conf[.yaml]` or
`resources:web.properties[encoding=iso-8859-1]` (a file that is not UTF-8
is read only that way), its placeholders resolved with their defaults or
the files' values) sets a `spring.flutter.web.*` key or
`spring.flutter.security.web.mode`. An import whose name only the running
app knows (`resources:${ENV}.conf[.yaml]`, `ENV` without a default) cannot
be followed there, so keys that only its file sets do not count. Without
such a key, the config is not loaded: nothing is written, a file
generated before is deleted, and imports, placeholders or a file that
does not parse are left to the app's start.
The one exception: while a generated `web_dev_config.yaml` exists, a
config file the app reads that does not parse fails the build and keeps
that file, as it may hold the keys.

With such a key, the config is read at build time, as the app reads it
in a browser: `application.*`, then `application-web.*`, plus the
files of the profiles `spring.profiles.active` names there and the files
that `spring.config.import` names (relative or `resources:` ones, from
`lib/resources/`); environment variables and `--dart-define` values do
not count. A placeholder only they can resolve is unknown at build time,
and never a build error: a profile name with one in
`spring.profiles.active`, `.include`, `.default` or `.group.*` is left
out, whatever else the name holds (`dev,${ENV}-eu` is read as `dev`),
in any form the app reads the key in (`spring.profiles.group[prod]`,
`spring.profiles.group[my.prod]`, `spring.profiles[active]`),
`spring.profiles.validate` or `spring.main.cloud-platform` with one is
read as unset, an import location with one is not read (the other entries
of its `;` group are), and a document whose
`spring.config.activate.on-profile` or `.on-cloud-platform` has one is
skipped, each with a warning that names it (give it a default,
`${APP_PROFILE:dev}`, to have the build use that). Where a key may be is
still checked: `spring.profiles.active` in `application-web.yaml`, or
`spring.profiles.include` in a document limited to a profile, fails the
build whatever its value, as it fails the app's start. A placeholder in
`spring.flutter.security.web.mode`, as in the keys below, must resolve at
build time, or the build fails. A browser has no file system: a
`file:`, `configtree:` or `package:` import (or an absolute path), with a
wildcard or not, is never read from the build machine's disk, and is
skipped, `optional:` or not; when these keys give a file to
write, a warning names the first required one as written (the web version
would fail to start with it, as the app's start reports). An import the
build cannot read (`asset:`, `http:`, `https:`, or a `resources:` file
missing from `lib/resources/`) is skipped silently, even a required one,
as it may exist at run time. An invalid value, or a config file the app
reads that does not parse, fails the build, and the generated file is
left as it is. A `--web-port` or `--web-hostname` flag still wins. The
app itself does not read these keys, and `flutter build web` does not use
them. See
[The web version's port](../spring_boot_starter_flutter/README.md#the-web-versions-port).

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
# application-web.yaml
spring:
  flutter:
    web:
      port: 5050
      headers:
        Cross-Origin-Opener-Policy: same-origin
      proxy:
        - prefix: /api/
          target: http://localhost:8080
```

</td><td>

```properties
# application-web.properties
spring.flutter.web.port=5050
spring.flutter.web.headers.Cross-Origin-Opener-Policy=same-origin
spring.flutter.web.proxy[0].prefix=/api/
spring.flutter.web.proxy[0].target=http://localhost:8080
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.web.host` | string, not empty | any address | The address the dev server listens on: `localhost`, or `0.0.0.0` for other devices on the LAN |
| `spring.flutter.web.port` | integer, 0 to 65535 | a free port | The dev server's port |
| `spring.flutter.web.base-href` | path starting and ending with `/` | `/` | The path the app is served under (`/shop/`) |
| `spring.flutter.web.https.cert-path` | file path | none (HTTP) | The TLS certificate (PEM). With `cert-key-path`, the dev server speaks HTTPS; set both or neither |
| `spring.flutter.web.https.cert-key-path` | file path | none | The certificate's private key (PEM) |
| `spring.flutter.web.headers.<Name>` | string | none | A header added to every response; the map merges across files, the more specific file winning per header |
| `spring.flutter.web.proxy[n].target` | absolute URL | none | Where requests matching rule `n` are forwarded (`http://localhost:8080`). Required in every rule |
| `spring.flutter.web.proxy[n].prefix` | path | none | Rule `n` matches paths starting with it (`/api/`) |
| `spring.flutter.web.proxy[n].regex` | regular expression | none | Or the paths matching it; each rule sets exactly one of `prefix` and `regex` |
| `spring.flutter.web.proxy[n].replace` | string | the path unchanged | The forwarded path: the matched part replaced, `$1` for the first group |
| `spring.flutter.web.content-security-policy` | string, not empty | none; in spa mode a ready policy (below) | The page's Content Security Policy, sent as the `Content-Security-Policy` header. Setting it and `headers.Content-Security-Policy` both fails the build |
| `spring.flutter.web.content-security-policy-report-only` | `true` / `false` | `false` | Send the policy as `Content-Security-Policy-Report-Only`: violations are reported in the console, nothing is blocked (for development) |
| `spring.flutter.web.content-security-policy-connect-src` | list of origins (`https://api.neon.books`, `wss://...`) | none | Origins added to the `connect-src` of spa mode's ready policy (below): the APIs the app calls, a provider's endpoints on other hosts. Setting it with an own policy fails the build; without spa mode it is ignored (a warning) |

The proxy list comes whole from the most specific file that has one, as
lists do in Spring Boot. Forwarding `/api/` to the server is the simplest
way to avoid CORS and third-party cookie trouble in development: the page
and the API share one origin, so a session login works in every browser.

An invalid value fails the build with the key's name; an unknown
`spring.flutter.web.*` key is a warning. Without any of these keys (and
not in spa mode) no file is written, and a hand-written
`web_dev_config.yaml` is never changed or deleted: with the keys set as
well, the build fails and asks to remove one of the two.

### The Content Security Policy

A Content Security Policy tells the browser which scripts, styles and
connections the page may use, so a script injected into it (or loaded
from a place the app never meant) is refused. The generator sends
`spring.flutter.web.content-security-policy` with every answer of
`flutter run`, so development runs under the policy production sends.
An app whose browser logs in by itself
(`spring.flutter.security.web.mode=spa`) and sets no policy gets this
one, with the origins its login fetches from in `connect-src`:

```text
default-src 'self'; script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com;
style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:;
font-src 'self' https://fonts.gstatic.com;
connect-src 'self' https://www.gstatic.com https://fonts.gstatic.com <the providers>;
worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self';
frame-ancestors 'none'
```

What Flutter's web engine needs, and why: `'wasm-unsafe-eval'` compiles
the WebAssembly of CanvasKit and Skwasm (no `eval` of JavaScript);
`https://www.gstatic.com` serves CanvasKit (not needed for builds with
`--no-web-resources-cdn`); `https://fonts.gstatic.com` the fallback
fonts (fetched, so in `connect-src` too); `'unsafe-inline'` styles, as
the engine writes a `<style>` element; `blob:` workers for Skwasm.

`<the providers>` are the origins known at build time: those of the
`spring.security.oauth2.client.provider.*` URIs (issuer, token, user
info, keys); the built-in endpoints of a Google, GitHub, Facebook or
Apple registration that has no provider section of its own (Google's
`https://www.googleapis.com`), except those its provider section
replaces; and, for an `issuer-uri` of Google or Microsoft, the hosts
their discovery documents name besides the issuer
(`https://oauth2.googleapis.com`, `https://openidconnect.googleapis.com`,
`https://www.googleapis.com`; `https://graph.microsoft.com`). The
authorization endpoint is not in the list: the page goes there, it does
not fetch it. Any other issuer's discovery document is read at run time,
so an endpoint it names on another host is not known to the build: list
that host in `spring.flutter.web.content-security-policy-connect-src`,
with the APIs the app calls (`ws:` / `wss:` origins for sockets); they
are added after the providers:

```yaml
# application-web.yaml
spring:
  flutter:
    web:
      content-security-policy-connect-src:
        - https://api.neon.books
        - wss://api.neon.books
```

Or set the whole policy yourself:

```properties
# application-web.properties
spring.flutter.web.content-security-policy=default-src 'self'; \
  script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com; \
  style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; \
  font-src 'self' https://fonts.gstatic.com; \
  connect-src 'self' https://www.gstatic.com https://fonts.gstatic.com \
  https://id.neon.books https://api.neon.books; \
  object-src 'none'; base-uri 'self'; frame-ancestors 'none'
```

The dev server is not production: send the same policy from the web
server or CDN that serves `build/web` (the `Content-Security-Policy`
header of `index.html`), and build with `flutter build web --csp` (no
dynamically generated code). Where the host sets no headers, a
`<meta http-equiv="Content-Security-Policy" content="...">` in
`web/index.html` works as a fallback, except for `frame-ancestors`,
which browsers ignore in a `<meta>`. Hot reload evaluates code in debug
runs, which the policy forbids: use
`content-security-policy-report-only=true` in a development profile when
it gets in the way.

### The web login

`spring_boot_starter_flutter_security` reads the `web.*` keys in a
browser only (the `web` platform profile); the first two keys of the
table are for apps. In `server` mode (the default) the
app's server logs the user in (`oauth2Login()`), the page holds only its
session cookie, and `OAuth2LoginService` sends the page to the server's
login, asks the server who is logged in and posts its logout. See
[The web: the server logs in](../spring_boot_starter_flutter_security/README.md#the-web-the-server-logs-in).
In `spa` mode the browser logs in by itself with the app's own
registrations (`spring.security.oauth2.client.*`, a public client whose
redirect URI is the page, `{baseUrl}/`), the tokens in the tab's memory;
see [The web without a server](../spring_boot_starter_flutter_security/README.md#the-web-without-a-server-the-browser-logs-in-spa-mode).

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
# application-web.yaml
spring:
  flutter:
    security:
      web:
        mode: server
        server-url: https://api.neon.books
        user-endpoint: /api/me
        logout-url: /api/logout
```

</td><td>

```properties
# application-web.properties
spring.flutter.security.web.mode=server
spring.flutter.security.web.server-url=https://api.neon.books
spring.flutter.security.web.user-endpoint=/api/me
spring.flutter.security.web.logout-url=/api/logout
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.security.ephemeral-session` | `true` / `false` | `false` | Apps on iOS and macOS: the login window (`ASWebAuthenticationSession`) keeps no cookies of Safari: no system prompt before the window, but no single sign-on (every login asks for the password). Android ignores it (a Custom Tab always shares the browser's cookies) |
| `spring.flutter.security.application-id` | text | the app's own id | Apps on Windows and Linux: the name the app's secrets are kept under, apart from other apps' (Windows: the folder under `%LOCALAPPDATA%\spring_secret_store`, `\` separates folders; Linux: the Secret Service items' `application` attribute). By default the runner's version resource (`<CompanyName>\<ProductName>`, Windows) or GTK application id (Linux), else the executable's name; a blank value is the default. Other platforms ignore it |
| `spring.flutter.security.web.mode` | `server` / `spa` | `server` | Who logs in: the app's server (backend-for-frontend), or the browser by itself (`spa`: a public client with PKCE, tokens in the tab's memory, DPoP with a non-extractable WebCrypto key; without a registration the app stops at startup) |
| `spring.flutter.security.web.silent-restore` | `true` / `false` | `true` | Spa mode: after a reload or in a new tab, `restore()` sends the page to the provider with `prompt=none` when someone logged in in this browser before, and comes back logged in (or with `login_required`: nobody) |
| `spring.flutter.security.web.server-url` | absolute `http(s)` URL, no query | the page's origin | The app's server, with its context path if any. On another origin than the page, `fetch` is asked to send the cookies there (`FetchCredentials.include`), and the server must allow it (CORS with credentials) |
| `spring.flutter.security.web.user-endpoint` | path or absolute URL | `/user` | `GET` with the session cookie: who is logged in, as `{"name", "authorities", "registrationId", "attributes"}` (only `name` required) |
| `spring.flutter.security.web.logout-url` | path or absolute URL | `/logout` | `POST` with the CSRF token; an answer `{"logoutUrl": "..."}` or a `2xx` with `Location` sends the page to the provider's logout |
| `spring.flutter.security.web.authorization-base-uri` | path or absolute URL | `/oauth2/authorization` | Where the server starts a login; `login('keycloak')` goes to `<server-url><this>/keycloak` |

An invalid value stops the app at startup with the key's name. Outside a
browser the keys are not read.

---

## 18. Reference: web server

`spring_boot_starter_web` runs the application's controllers on a
`dart:io` HTTP server. It reads Spring Boot's `server.*` keys for the
port, TLS and shutdown, the keys of the controllers' server-sent events,
and the upload limits (`spring.web.multipart.*`; see the starter's
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
  context-path: /shop
  max-http-request-body-size: 10MB
  connection-timeout: 60s
  request-timeout: 30s
  compression:
    enabled: true
    mime-types: text/html,application/json
    min-response-size: 2KB
  websocket:
    max-text-message-size: 64KB
    max-binary-message-size: 1MB
    send-buffer-size-limit: 512KB
    send-time-limit: 10s
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
  web:
    multipart:
      enabled: true
      max-file-size: 5MB
      max-request-size: 20MB
      max-part-count: 100
      file-size-threshold: 64KB
      location: /var/tmp/shop-uploads
```

</td><td>

```properties
server.port=8080
server.address=0.0.0.0
server.shutdown=graceful
server.context-path=/shop
server.max-http-request-body-size=10MB
server.connection-timeout=60s
server.request-timeout=30s
server.compression.enabled=true
server.compression.mime-types=text/html,application/json
server.compression.min-response-size=2KB
server.websocket.max-text-message-size=64KB
server.websocket.max-binary-message-size=1MB
server.websocket.send-buffer-size-limit=512KB
server.websocket.send-time-limit=10s
server.ssl.certificate=/etc/shop/cert.pem
server.ssl.certificate-private-key=/etc/shop/key.pem
server.ssl.key-password=s3cret
server.ssl.trust-certificate=/etc/shop/clients.pem
server.ssl.client-auth=want
spring.lifecycle.timeout-per-shutdown-phase=20s
spring.mvc.async.request-timeout=30m
spring.mvc.sse.heartbeat-interval=15s
spring.web.multipart.enabled=true
spring.web.multipart.max-file-size=5MB
spring.web.multipart.max-request-size=20MB
spring.web.multipart.max-part-count=100
spring.web.multipart.file-size-threshold=64KB
spring.web.multipart.location=/var/tmp/shop-uploads
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `server.port` | int | `8080` | The port. `0` picks a free one; the real port is then in `local.server.port` |
| `server.address` | IP address or host name | all interfaces; **`127.0.0.1` in Flutter apps** | The address to listen on. `localhost` is `127.0.0.1`; a host name is looked up. Flutter apps default to `127.0.0.1` so they open no port to the network by accident |
| `server.shutdown` | `graceful` / `immediate` | `graceful` | `graceful` accepts no new connections and lets running requests finish. Open event streams and WebSockets are closed at once (code 1001) |
| `spring.lifecycle.timeout-per-shutdown-phase` | duration | `30s` | How long a graceful shutdown waits for running requests. As in Spring Boot, it is also the timeout per phase of the context's `lifecycleProcessor` (`spring_boot_dart`'s `LifecycleAutoConfiguration`), so the beans are destroyed only after the requests finished |
| `server.context-path` | path | — | A prefix of every mapping, such as `/shop`. A missing leading `/` is added and a trailing one dropped; other paths answer 404. |
| `server.max-http-request-body-size` | data size, or `-1` | `10MB` | A larger request body is answered with 413, whatever its `Content-Type`; `-1` means no limit. This starter's own key. Only the multipart resolver reads uploads with `spring.web.multipart.max-request-size` instead |
| `server.connection-timeout` | duration; `0` or less (`-1`) for none | `60s` | How long a request body may send nothing while it is read: then the answer is 408 and the connection closes. Also how long an idle keep-alive connection stays open. `0` or a negative value means no limit, as in Tomcat. Tomcat's `connectionTimeout` (Spring Boot 2.0 had this key; Boot 4 has `server.tomcat.connection-timeout`) |
| `server.request-timeout` | duration; `0` or less for none | no limit | The longest a request's filters and handler may take to answer. When it passes before the answer starts, the answer is a 503 `ProblemDetail` with a generic detail (`AsyncRequestTimeoutException`, logged as a warning, at most once per 10 seconds), what the handler does afterwards is dropped, and the request's `RequestDeadline` has run out for the code it called (see [Deadlines](#deadlines-one-limit-for-a-request-and-the-calls-it-makes)). Not applied to a response that became a stream (server-sent events, a streamed body: `spring.mvc.async.request-timeout` limits an `SseEmitter`) or to a WebSocket handshake. A response already being sent is left alone. The time the handler spends reading a slow upload counts; `server.connection-timeout` still ends a body that sends nothing. This starter's own key: Spring Boot has none |
| `server.forward-headers-strategy` | `none` / `native` / `framework` | `none` | Behind a reverse proxy: apply its `Forwarded` or `X-Forwarded-Proto`, `-Host`, `-Port`, `-For` headers (the scheme, so cookies get `Secure` behind TLS; the host and port; the client's address), from trusted proxies only. `native` and `framework` do the same here. Another value stops the start |
| `server.forward-headers.trusted-proxies` | list of addresses and CIDR ranges | loopback, `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, `100.64/10`, `::1`, `fc00::/7`, `fe80::/10` | Whose forwarded headers are believed (Tomcat's `internalProxies`); a client reaching the server from elsewhere cannot set them. Not in Spring Boot |
| `server.compression.enabled` | bool (only `true` turns it on) | `false` | gzip of the responses of `mime-types`, from `min-response-size` on (or of unknown length), for clients that send `Accept-Encoding: gzip`; never partial content, nor an answer with a strong `ETag` (as Tomcat). Every answer it would compress gets `Vary: Accept-Encoding`, for clients without gzip too |
| `server.compression.mime-types` | comma-separated media types (`text/*` allowed) | `text/html`, `text/xml`, `text/plain`, `text/css`, `text/javascript`, `application/javascript`, `application/json`, `application/xml` | The media types compressed, as in Spring Boot; add `text/event-stream` to compress event streams |
| `server.compression.min-response-size` | data size | `2KB` | The smallest `Content-Length` compressed |
| `server.websocket.max-text-message-size` | data size, or `-1` | `8KB` | The largest text message a WebSocket session reads, in UTF-8 bytes (Tomcat counts characters); a larger one closes the session with 1009. Tomcat's default in Spring; this starter's own key (Spring sets it on the container) |
| `server.websocket.max-binary-message-size` | data size, or `-1` | `8KB` | The same for binary messages |
| `server.websocket.send-buffer-size-limit` | data size, or `-1` | `512KB` | How much a WebSocket session may keep waiting to be sent to a client that reads slowly or not at all (pongs included); past it the connection is dropped and the session's close status is 4500 (`sessionNotReliable`). Spring's `sendBufferSizeLimit` of `ConcurrentWebSocketSessionDecorator`, set in code there; this starter's own key |
| `server.websocket.send-time-limit` | duration, or `-1` | `10s` | How long what a session sent may take to leave; past it the connection is dropped the same way. Spring's `sendTimeLimit` |
| `server.ssl.enabled` | bool | `true` | `false` ignores the other `server.ssl.*` keys |
| `server.ssl.certificate` | file path (PEM) | — | The certificate chain; TLS is on when it is set |
| `server.ssl.certificate-private-key` | file path (PEM) | — | The private key; required with `certificate` |
| `server.ssl.key-password` | string | — | The password of an encrypted private key |
| `server.ssl.trust-certificate` | file path (PEM) | — | The certificates of trusted clients, for `client-auth` |
| `server.ssl.client-auth` | `none` / `want` / `need` | `none` | Asks clients for a certificate; with `need`, a request without one is answered with 403 |
| `spring.main.web-application-type` | `none`, or anything else | — | `none`: the beans (and `MockMvc`) exist, but no server starts. Other values start it |
| `spring.mvc.async.request-timeout` | duration | no limit | The timeout of an `SseEmitter` created without one; when it passes, the emitter completes after running its `onTimeout` callbacks |
| `spring.mvc.sse.heartbeat-interval` | duration | — (none) | Sends a comment line in every open event stream at this interval, so proxies keep idle streams open. This starter's own key |
| `spring.web.multipart.enabled` | bool | `true` | `false`: `multipart/*` requests are not parsed, and `@RequestPart` parameters answer 400 |
| `spring.web.multipart.max-file-size` | data size, or `-1` | `1MB` | The largest file (or other part) of an upload; above it the answer is 413 (`MaxUploadSizeExceededException`). `-1` means no limit |
| `spring.web.multipart.max-request-size` | data size, or `-1` | `10MB` | The largest multipart request as a whole; above it the answer is 413. `-1` means no limit |
| `spring.web.multipart.max-part-count` | int, or `-1` | `50` | The most parts (files and fields) of a multipart request; above it the answer is 413. This starter's own key: Spring Boot sets the same limit on Tomcat with `server.tomcat.max-part-count` (50) |
| `spring.web.multipart.file-size-threshold` | data size | `0B` | Files above this size are written to a temporary file; smaller ones stay in memory. With `0B` every file goes to a temporary file (in memory where there is no `dart:io`). Temporary files are deleted after the request |
| `spring.web.multipart.location` | directory path | the system's temporary directory | Where the private directory (`0700`) of the uploads' temporary files is made; the files have random names and are deleted when the request ends or fails |
| `spring.test.web-environment` | `mock` / `random-port` / `defined-port` / `none` | not set: a server starts | Set by `springBootTest(webEnvironment:)` (`mock` by default) and by `ApplicationContextRunner` (`mock`). In tests only `random-port` (port `0`) and `defined-port` start a server |
| `local.server.port` | int, **written by the server** | — | The port the server listens on, set once it listens (also in `WebServerInitializedEvent`). Read it; do not set it |

An invalid `server.port`, `server.shutdown` or `server.ssl.client-auth`,
or a certificate without its private key, fails the start naming the key.
The certificate files are paths in the file system, not `resources:`
locations. Mappings are logged at debug level under the logger
`spring.web.mvc` (`logging.level.spring.web.mvc=debug`), and the server
under `spring.web.server`.

### Deadlines: one limit for a request and the calls it makes

`server.request-timeout` is more than a timer: the request runs under a
`RequestDeadline` (`spring_web_dart`) of that length, carried in the
`Zone` like a transaction, so that code the request calls can read it:
`RequestDeadline.current` is the deadline (or `null`), with `remaining`,
`isExpired` and `check()`, which throws a `RequestDeadlineExceededException`.
A deadline started inside another ends at the earlier of the two, never
later, and `RequestDeadline.run(budget, body)` starts one in code of your own.

The Feign starter honours it. A call a controller makes through a Feign
client never outlives the request: the effective limit of the call is the
earlier of its `call-timeout` ([section 15](#15-reference-feign-clients))
and what remains of the request's deadline, and the connect and read
timeouts of each attempt are capped by what remains. When the time is gone,
the call throws `FeignCallTimeoutException`, which is not retried, and the
request is answered with the 503. Nothing else is interrupted: Dart cannot
stop running code, so a handler that never looks at the deadline runs on,
with its late answer dropped.

A response that becomes a stream (server-sent events, a streamed body)
leaves the request's deadline when it starts, so what the stream does later
is not cut at it. The filters (the security starter's filter chain
included) are part of the request, so the time they use is taken from the
handler's.

Spring has no such limit for synchronous requests (Tomcat times out
connections, Spring MVC only asynchronous requests with
`spring.mvc.async.request-timeout`), and no limit follows a request into
the calls it makes. `server.request-timeout`, `call-timeout` and
`RequestDeadline` are extensions of Spring for Dart.

An application that also uses `spring_boot_starter_data` answers its data
errors with the right status instead of a 500, through the bean
`dataAccessExceptionResolver` the generator adds (no property switches
it; declare a bean of that name to replace it, or an `@ExceptionHandler`,
which always comes first):

| Exception | Status | Detail |
|---|---|---|
| `OptimisticLockingFailureException` | 409 | `The resource was changed by someone else` |
| `DuplicateKeyException` | 409 | `The resource already exists` |
| `EmptyResultDataAccessException` | 404 | `Not found` |
| `PropertyReferenceException` (a sort property that does not exist) | 400 | `Invalid sort property` |
| `InvalidPagingRequestException` (a negative page, a size below one, an offset past 2^53 - 1, a direction that is not `asc` or `desc`) | 400 | `Invalid page or sort request` |
| `InvalidDataArgumentException` (a value of the request the database cannot take: a text with a NUL character, a list longer than a statement binds, a `LIKE` pattern ending with its escape character) | 400 | `Invalid request value` |

The answer is a `ProblemDetail` with this fixed detail, never the
exception's message (it may hold SQL or values); the exception is logged
at debug level under `spring.web.mvc`. Other data errors stay a 500. See
[Resolvers](../spring_boot_starter_web/README.md#resolvers-errors-a-library-maps).

### Pageable and Sort parameters

With both starters, a controller parameter of type `Pageable` or `Sort` is
filled from the query (`?page=2&size=10&sort=title,desc&sort=year`) by the
bean `pagingArgumentResolvers` the generator adds (declare a bean of that name
to replace it). The rules are Spring Data Web's; the properties are Spring
Boot's:

| Property | Default |
|---|---|
| `spring.data.web.pageable.default-page-size` | `20` |
| `spring.data.web.pageable.max-page-size` | `2000` (a larger `size` is cut to it) |
| `spring.data.web.pageable.one-indexed-parameters` | `false` |
| `spring.data.web.pageable.page-parameter` | `page` |
| `spring.data.web.pageable.size-parameter` | `size` |
| `spring.data.web.pageable.prefix` | empty |
| `spring.data.web.pageable.qualifier-delimiter` | `_` |
| `spring.data.web.sort.sort-parameter` | `sort` |

`@PageableDefault(size:, page:, sort:, direction:)` and `@SortDefault(sort:,
direction:)` on the parameter give the defaults, `@Qualifier('x')` reads
`x_page`, `x_size` and `x_sort`; a negative or non-numeric page is 0, a size
below one is the default, `sort=a,b,desc` gives both properties one direction
and `ignorecase` may end a part. An unknown sort property is a
`PropertyReferenceException`, answered with a 400. A returned `Page<T>` is
written as `{"content": [...], "page": {"size", "number", "totalElements",
"totalPages"}}`, Spring Data 3.3's stable shape.

Not supported:

- `server.http2.*`: `dart:io` speaks HTTP/1.1;
- `server.forward-headers-strategy` and
  `server.max-http-request-header-size`;
- key stores and SSL bundles (`server.ssl.key-store`, `server.ssl.bundle`);
- `server.error.*` and `spring.mvc.problemdetails.enabled`: errors are
  `ProblemDetail`s (except the plain-text answers Spring gives too: a
  refused CORS request or WebSocket handshake);
- `spring.web.cors.*`;
- `spring.web.resources.*`: there are no static files yet;
- the `server.tomcat.*`, `jetty`, `undertow` and `netty` keys; there is
  no connection limit (Tomcat's `max-connections`).

---

## 19. Reference: OAuth2 clients

`spring_boot_starter_oauth2_client` gets tokens from an OAuth 2.0 or
OpenID Connect provider (Keycloak, Google, GitHub, Auth0, ...), for
calls to other services and for logins. Each **registration** is one
client of one provider: these keys say who the client is (its id and
secret, the scopes it asks for, where the provider sends the browser
back) and where the provider's endpoints are. A server with the security
starter logs browsers in with `oauth2Login()`, which its default chain
turns on as soon as a registration exists; a Flutter app logs in with
`OAuth2LoginService` of `spring_boot_starter_flutter_security`.

`<id>` is the registration's id, as in `/oauth2/authorization/keycloak`.
A registration uses the provider of the same id unless it names another
(`provider`); `google`, `github`, `facebook` and `okta` are known
providers that need no `provider.*` keys.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          keycloak:
            client-id: neon-web
            client-secret: ${KEYCLOAK_SECRET}
            scope: [openid, profile, email]
            client-name: NEON account
          partner:
            provider: keycloak
            client-id: shop
            client-secret: ${PARTNER_SECRET}
            authorization-grant-type: client_credentials
            scope: [orders.read]
          github:
            client-id: ${GITHUB_ID}
            client-secret: ${GITHUB_SECRET}
        provider:
          keycloak:
            issuer-uri: http://localhost:8180/realms/neon
```

</td><td>

```properties
spring.security.oauth2.client.registration.keycloak.client-id=neon-web
spring.security.oauth2.client.registration.keycloak.client-secret=${KEYCLOAK_SECRET}
spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
spring.security.oauth2.client.registration.keycloak.client-name=NEON account
spring.security.oauth2.client.registration.partner.provider=keycloak
spring.security.oauth2.client.registration.partner.client-id=shop
spring.security.oauth2.client.registration.partner.client-secret=${PARTNER_SECRET}
spring.security.oauth2.client.registration.partner.authorization-grant-type=client_credentials
spring.security.oauth2.client.registration.partner.scope=orders.read
spring.security.oauth2.client.registration.github.client-id=${GITHUB_ID}
spring.security.oauth2.client.registration.github.client-secret=${GITHUB_SECRET}
spring.security.oauth2.client.provider.keycloak.issuer-uri=http://localhost:8180/realms/neon
```

</td></tr>
</table>

The keys under `spring.security.oauth2.client.registration.<id>.`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `client-id` | string | required | The client's id at the provider |
| `client-secret` | string | — | The client's secret; none for an app (a public client). Never in an app's configuration |
| `client-authentication-method` | `client_secret_basic` / `client_secret_post` / `none` | `client_secret_basic` with a secret, `none` without one (from the provider's metadata with `issuer-uri`) | How the client proves who it is at the token endpoint |
| `authorization-grant-type` | `authorization_code` / `client_credentials` | `authorization_code` with `issuer-uri` or a known provider; required otherwise | A user's login, or the client's own tokens (server to server) |
| `redirect-uri` | URI template | `{baseUrl}/{action}/oauth2/code/{registrationId}` (`/login/oauth2/code/keycloak` on a server) | Where the provider sends the browser back; the provider must accept it. `{baseUrl}` is the address the request came to (on a server) or `http://127.0.0.1` (an app's loopback); an app with a scheme of its own sets `neonbooks:/oauth2/callback` |
| `scope` | list | none; the provider's defaults for the known providers | The scopes asked for; `openid` makes it an OpenID Connect login (an ID token, checked) |
| `client-name` | string | the issuer, or the known provider's name | The name on the login page |
| `provider` | id | the registration's id | The provider of the `provider.*` keys, or a known one |
| `dpop` | `auto` / `true` / `false` | `auto` | DPoP (RFC 9449): the tokens are bound to the app's `DPoPKey` and every request carries a proof signed by it. `auto` turns it on when the key outlives the program (an app's key) and the provider's metadata lists `ES256` in `dpop_signing_alg_values_supported`, so servers keep `Bearer` unless `true`; `false` keeps `Bearer` tokens. Not in Spring Boot |
| `response-mode` | `query` / `form_post` | `query`; `form_post` for the `apple` provider | How the provider returns the authorization response: in the redirect URI, or posted as a form to it (`response_mode=form_post`; only a server's `oauth2Login()` receives it, over HTTPS only: its authorization request cookie is then `SameSite=None; Secure`). Not in Spring Boot |
| `client-secret-jwt.issuer` | string | — | A client secret that is a JWT signed ES256 by the client's own key (Sign in with Apple's): its `iss` (Apple: the team id). With `key-id` and a key, the `clientSecretResolver` bean makes the JWT per token request. Not in Spring Boot |
| `client-secret-jwt.key-id` | string | — | The JWT's `kid` (Apple: the key id) |
| `client-secret-jwt.private-key-location` | resource location | — | The PKCS #8 private key (Apple's `.p8`), such as `file:/run/secrets/apple.p8`; read at the first token request, never logged |
| `client-secret-jwt.private-key` | string | — | The PEM itself instead (from an environment variable; `\n` escapes allowed) |
| `client-secret-jwt.audience` | string | the provider's `issuer-uri` | The JWT's `aud` |
| `client-secret-jwt.lifetime` | duration | `1h` | How long each JWT is valid (at most `180d`); made again when a tenth is left |
| `native-sign-in` | `none` / `apple` | `apple` for the `apple` provider, else `none` | Apps (`spring_boot_starter_flutter_security`): `apple` signs in with Sign in with Apple's sheet on iOS and macOS instead of the browser; the code then goes to the registration's `token-uri`, the app's server. Not in Spring Boot |

The keys under `spring.security.oauth2.client.provider.<id>.`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `issuer-uri` | URL | — | The provider; the other endpoints come from its OpenID (or OAuth 2.0) metadata, whose `issuer` must equal it. Read at the first use of the registration, not at startup |
| `authorization-uri` | URL | from the metadata | The provider's login page |
| `token-uri` | URL | from the metadata | The token endpoint |
| `user-info-uri` | URL | from the metadata | The user-info endpoint |
| `user-info-authentication-method` | `header` / `form` / `query` | `header` | How the access token is sent to it |
| `user-name-attribute` | string | `sub` with `issuer-uri` | The attribute that names the user |
| `jwk-set-uri` | URL | from the metadata | The provider's public keys; a server checks ID token signatures with them |

Two keys with Spring Cloud OpenFeign's names, read by this starter, add
the token of a registration to every Feign call:
`spring.feign.oauth2.enabled` (`false`) and
`spring.feign.oauth2.client-registration-id` (else the Feign
client's name); [section 15](#15-reference-feign-clients) has the other
Feign keys.

Differences from Spring Boot: providers with `issuer-uri` are discovered
at the first use of their registrations, not at startup, so an app starts
offline and a server starts while the provider is down (its logins fail
until it is up); `dpop` is an addition (Spring Security 7 has no DPoP on
the client's side), `auto` by default. In apps the Flutter security
package's key survives restarts (the Secure Enclave, the Android
Keystore, WebCrypto, the `SecretStore` on desktops); elsewhere the
starter's default key is made for each run and `auto` leaves DPoP off
(`Bearer`, as before). A server that sets `dpop=true` declares a
`DPoPKey` bean that survives restarts and, with several instances
sharing sessions, is shared (the client's README, *DPoP*).

---

## 20. Reference: SQL databases

`spring_boot_starter_data` opens the database of `spring.datasource.url`
with the driver the application lists (`sqlite3` for `sqlite:` URLs,
`postgres` for `postgresql:` ones), runs its migrations at startup, before
any repository or `JdbcTemplate` can use it, and checks the schema against the entities. Without a URL the
repositories keep their data in memory.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  datasource:
    url: sqlite:file:shop.db
    pool:
      max-size: 4
      connection-timeout: 10s
    sqlite:
      busy-timeout: 2000
  datasources:
    stats:
      url: sqlite:file:stats.db
  sql:
    migration:
      enabled: true
  data:
    jdbc:
      schema: validate
      show-sql: true
      slow-query-threshold: 500ms
```

</td><td>

```properties
spring.datasource.url=sqlite:file:shop.db
spring.datasource.pool.max-size=4
spring.datasource.pool.connection-timeout=10s
spring.datasource.sqlite.busy-timeout=2000
spring.datasources.stats.url=sqlite:file:stats.db
spring.sql.migration.enabled=true
spring.data.jdbc.schema=validate
spring.data.jdbc.show-sql=true
spring.data.jdbc.slow-query-threshold=500ms
```

</td></tr>
</table>

| Key | Default | Meaning |
|---|---|---|
| `spring.datasource.url` | | `sqlite:file:books.db`, `sqlite::memory:` (one connection: `pool.max-size=1`), `postgresql://user:password@host:5432/shop?sslmode=require` ([PostgreSQL](#postgresql)); a leading `jdbc:` is dropped; a scheme no listed driver handles stops the start, naming the package to add |
| `spring.datasource.username`, `.password` | | when the URL does not carry them; never logged |
| `spring.datasource.driver` | | the driver's name (`sqlite3`, `postgres`) when two handle the scheme |
| `spring.datasource.pool.max-size` | `10` | most connections at once |
| `spring.datasource.pool.min-idle` | `0` | connections kept open when idle |
| `spring.datasource.pool.connection-timeout` | `30s` | the longest wait for a connection, then `CannotGetJdbcConnectionException` |
| `spring.datasource.pool.idle-timeout` | `10m` | an idle connection above `min-idle` older than this is closed |
| `spring.datasource.pool.max-lifetime` | `30m` | a connection older than this is closed when released |
| `spring.datasource.pool.validation` | `true` | check a connection that waited, before handing it out |
| `spring.datasource.sqlite.busy-timeout` | `5000` | milliseconds a connection waits for SQLite's lock |
| `spring.datasource.sqlite.base-directory` | working directory | where relative `sqlite:file:` names are looked for; in a Flutter app the starter sets it ([SQLite databases](#sqlite-databases)) |
| `spring.datasource.sqlite.isolate` | `false` | `true` opens each connection inside an isolate of its own, so a long query or a busy wait does not hold the caller's isolate (the UI's, the web server's); in a Flutter app the starter sets it to `true` |
| `spring.datasource.sqlite.location` | `support` | read by the Flutter starter only: `support`, `cache` or `documents`, the directory it sets `base-directory` to ([SQLite databases](#sqlite-databases)) |
| `spring.datasource.postgresql.sslmode` | `prefer` | `disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full`; also `spring.datasource.postgres.*` ([PostgreSQL](#postgresql)); every driver key is read through the environment, so it is also an environment variable (`SPRING_DATASOURCE_POSTGRESQL_SSLMODE=verify-full`, `SPRING_DATASOURCES_SHOP_SQLITE_BUSYTIMEOUT=2000`), a command line argument or a file entry, and a name the driver does not know is refused; a driver's keys are read under the URL's scheme and under the driver's name (`spring.datasource.sqlite3.busy-timeout` is `sqlite.busy-timeout`), the driver's name winning |
| `spring.datasource.postgresql.ssl-root-cert` | system roots | PEM file of the certificate authorities a `verify-*` mode checks the server against |
| `spring.datasource.postgresql.connect-timeout` | `15s` | the longest wait for the connection and the TLS handshake (`500ms`, `30s`, `1m`, or milliseconds; this key does not take `PT30S`) |
| `spring.datasource.postgresql.application-name` | | shown in `pg_stat_activity` |
| `spring.datasource.postgresql.search-path` | the server's | the schemas of `search_path`, comma separated (the URL's `currentSchema`) |
| `spring.datasources.<name>.*` | | the same keys for a named database (beans qualified `<name>`, `@UseDataSource('<name>')`), also `sql.init.*`, `sql.migration.*`, `data.jdbc.schema` |
| `spring.sql.init.mode` | `embedded` | `schema.sql` / `data.sql`: `embedded` (in-memory databases only), `always`, `never` |
| `spring.sql.init.schema-locations`, `data-locations`, `platform`, `continue-on-error`, `separator`, `encoding` | `schema.sql` and `data.sql` (and their `-<platform>` variants), `all`, `false`, `;`, `utf-8` | as in Spring Boot |
| `spring.sql.migration.enabled` | `true` | run `lib/resources/db/migration/V<version>__<name>.sql` and `R__<name>.sql` (no files: nothing) |
| `spring.sql.migration.locations` | `resources:db/migration` | `{vendor}` is the database (`sqlite`, `postgresql`) |
| `spring.sql.migration.table` | `schema_history` | the history table |
| `spring.sql.migration.validate-on-migrate` | `true` | an applied file that changed, or went missing, stops the start |
| `spring.sql.migration.baseline-on-migrate`, `baseline-version`, `baseline-description` | `false`, `1`, `<< Baseline >>` | start the history on an existing database |
| `spring.sql.migration.target` | `latest` | migrate up to this version |
| `spring.sql.migration.out-of-order`, `ignore-migration-patterns` | `false`, `*:future` | as Flyway |
| `spring.sql.migration.placeholders.<name>`, `placeholder-replacement`, `placeholder-prefix`, `placeholder-suffix` | `true`, `${`, `}` | `${name}` in the files |
| `spring.sql.migration.group` | `false` | all pending migrations in one transaction |
| `spring.sql.migration.connect-retries`, `connect-retries-interval`, `lock-timeout` | `0`, `10s`, `1m` | wait for the database, and for another instance migrating it |
| `spring.data.jdbc.schema` | `validate` | `none`, `validate` (tables and columns of the entities must exist and fit), `create`, `create-drop` (from the entities; not with migrations or scripts) |
| `spring.jdbc.template.query-timeout` | none | bounds each statement of the `JdbcTemplate` beans |
| `spring.data.jdbc.show-sql`, `format-sql`, `show-parameters` | `false` | statements (and masked values) at info: the value of a name that looks secret (a column or parameter name that contains `password`, `token`, `secret`, `credential`, `apikey` or `privatekey`, or has the word `key`: `sslpassword`, `apiToken`, `clientSecret`; not `keyword`) is `******`, and so is a value bound without a name (a plain list to a `JdbcTemplate`); the values also show at trace, with the same masks |
| `spring.data.jdbc.slow-query-threshold` | none | a slower statement is logged at warn |
| `spring.data.memory.lock-timeout` | `10s` | the in-memory store's wait for a row lock |

Spring Boot's `spring.flyway.*` names are not used (and stop the start,
see [Renamed properties](#renamed-properties)): the migrations are this
project's own runner (Flyway's file naming, `spring.sql.migration.*`).

### PostgreSQL

Add the `postgres` package to the application's dependencies next to
`spring_boot_starter_data`, run the generator again (it writes a thin glue
over the package, as it does for `sqlite3`), and give the URL:

```properties
spring.datasource.url=postgresql://shop:s3cret@db.example.com:5432/shop?sslmode=verify-full
# or, as pasted from Spring Boot:
spring.datasource.url=jdbc:postgresql://db.example.com:5432/shop
spring.datasource.username=shop
spring.datasource.password=s3cret
```

- **The URL.** Host (default `localhost`), port (5432) and database (the
  user's name, else `postgres`) as usual; a user or password with special
  characters is percent-encoded (`%40` for `@`). The parameters after `?` are
  `sslmode`, `sslrootcert`, `connect_timeout` (seconds), `application_name`
  and `currentSchema` (or `search_path`); another one is an error, so that a
  typo such as `sslMod=require` never silently weakens a setting. The
  properties above set the same, and win over the URL.
- **TLS.** `sslmode` is libpq's. The default `prefer` (and `allow`) tries TLS
  first and connects in plain text when the server has none, which an
  attacker who can cut the connection can force: use `require` (encrypted,
  the certificate is not checked) or `verify-full` (also checks the
  certificate and the host name, against the system's roots or
  `ssl-root-cert`) for anything but a development database. `verify-ca` is as
  strict as `verify-full`. When `prefer` falls back to plain text the driver
  logs a warning (once for each database). The setting can come from an
  environment variable: `SPRING_DATASOURCE_POSTGRESQL_SSLMODE=verify-full`.
- **The URL in logs.** The password of the user info is never logged, and
  the value of a query parameter whose name looks secret (`password`,
  `sslpassword`, `token`...) is written `******` in every log line and
  message that shows the URL. Prefer `spring.datasource.username` and
  `password` (or the user info) to secrets in the query.
- **Parameters and values.** The statements keep `?` (the starter turns it
  into `$1`, `$2`; quoted text, comments and `$$` bodies are left alone, and
  `??` is a literal `?`, for the `jsonb` operators), and values always go as
  parameters. `int` is `BIGINT`, `String` and enums `TEXT`, `bool` `BOOLEAN`,
  `double` `DOUBLE PRECISION`, `DateTime` `TIMESTAMPTZ` (always the instant,
  read back in UTC), `Uint8List` `BYTEA`, `BigInt` `NUMERIC`. A generated id
  is `BIGINT GENERATED BY DEFAULT AS IDENTITY`, and comes back with
  `RETURNING`; an id you write yourself does not move the sequence.
- **Transactions.** Every isolation level is offered (`readUncommitted` is
  accepted and runs as read committed, as PostgreSQL documents), read only
  transactions refuse writes, `nested` uses savepoints, a transaction timeout
  or `spring.jdbc.template.query-timeout` cancels the statement on the server
  (a `QueryTimeoutException`; the connection stays usable). DDL is
  transactional, so a failing migration leaves nothing of itself, and the
  migrations of several instances queue on an advisory lock.
- **Compared with Spring.** The propagation × isolation matrix, the locks,
  `@Version` and the timeouts run on PostgreSQL in the starter and in a Spring
  Boot application (`tool/data_reference`, Spring Data JDBC), 304 scenarios
  each, and the outcomes (rows committed, values read, exception kinds) are
  compared by the CI job "Data compared with Spring Data"; the differences
  that remain are deliberate and listed, with the isolation table, in the
  starter's README (section "Compared with Spring").
- **Locks.** `@Lock` is a row lock: `FOR UPDATE` for `pessimisticWrite`, `FOR
  SHARE` for `pessimisticRead`; a zero `timeout` is `NOWAIT`, a longer one is
  `SET LOCAL lock_timeout` before the query, `skipLocked` is `SKIP LOCKED`
  (and wins over a zero timeout: the server refuses both words). Unlike
  SQLite, the `@Lock` query need not be the first statement of its
  transaction.
- **Errors.** By SQL state: `23505` is a `DuplicateKeyException` (with the
  constraint's name), the other `23xxx` and `22xxx` a
  `DataIntegrityViolationException`, `40001` a
  `CannotSerializeTransactionException`, `40P01` a
  `DeadlockLoserDataAccessException`, `55P03` (`NOWAIT`, `lock_timeout`) a
  `CannotAcquireLockException`, `57014` a `QueryTimeoutException`, `42601`,
  `42P01`, `42703` and the other syntax and name errors a
  `BadSqlGrammarException`, `25006` an `InvalidDataAccessResourceUsageException`,
  and `08xxx`, `28xxx` (authentication), `53xxx`, `57P01` and a missing
  database a `DataAccessResourceFailureException`. The messages are the
  server's own, without the `DETAIL` line (a duplicate key's holds the values)
  and without the rejected value of `invalid input syntax for type integer`;
  a password is never in a message.
- **Arguments the database refuses.** A derived `Like`, `Containing`,
  `StartingWith` or `EndingWith` argument is text: `%`, `_` and `\` in it are
  escaped by the starter (a value ending in `\` is a backslash; in `Like`
  itself a lone `\` at the end is a backslash too), on every store. A NUL
  character (`\u0000`) in a text argument of a derived query is an
  `InvalidDataAccessApiUsageException` before anything is sent, on every
  store (PostgreSQL cannot hold one, `22021`; SQLite's `LIKE` stops reading at
  it); a NUL in a `@Query` text or a `save` is refused the same way on
  PostgreSQL. The message never holds the value. The web glue maps only the
  exceptions listed in the web starter's data glue (409, 404, 400 for a sort or
  paging error), so these stay a 500 with the generic body: validate request
  text (`@Pattern`, no NUL) when it reaches a repository. In a `@Query` the
  SQL is yours: `like :p` with a value ending in `\` is PostgreSQL's `22025`
  (an `InvalidDataAccessApiUsageException` saying so; SQLite's `LIKE` has no
  escape character without `ESCAPE` and matches the backslash).
- **Long `In` lists.** A derived `In` / `NotIn` binds the list as one array
  parameter on PostgreSQL (`= any($1)`, `<> all($1)`), so any length works
  (the protocol allows 65 535 parameters per statement; nulls keep their
  meaning: ignored in `In`, nothing matches a `NotIn` that holds one). SQLite
  binds one value per element and has a limit of 32 766 per statement: a
  longer list is an `InvalidDataAccessApiUsageException` that says so (split
  the list, or query another way); the starter does not split it, since the
  limit counts all the values of a statement. A `@Query` `in (:ids)` is
  expanded to one marker per value on both: past the limit PostgreSQL gets a
  clear `InvalidDataAccessApiUsageException` before the statement is sent,
  SQLite the driver's error.
- **Text order.** `ORDER BY` and the range operators on text use the
  database's collation, as in any Spring Data application: a database made
  with `en_US.UTF-8` puts `a_b` before `Cryptonomicon`, where the in-memory
  store and SQLite compare code units. `ignoreCase` is `lower()`, which folds
  the letters the locale knows (`C`: ASCII only); on SQLite it is a `lower` the
  driver registers (Dart's `toLowerCase`), so `findByTitleIgnoreCase('ДЮНА')`
  and `ä`/`Ä` match as in the in-memory store. `ON DELETE RESTRICT` is
  looked at when the statement ends, not row by row as in SQLite, so deleting a
  parent and its child in one statement works.
- **Schema.** `spring.data.jdbc.schema=create` writes the tables above
  (foreign keys come after the tables, so references in a cycle work);
  `validate` reads `information_schema` and `pg_catalog`: any integer width
  fits an `int`, `real` and `numeric` a `double`, `varchar` and `uuid` a
  `String`, `date` and both timestamps a `DateTime`; foreign keys (with their
  `ON DELETE`) and unique keys are compared too.

The tests that need a server run on `SPRING_TEST_POSTGRES_URL` when it is
set, else on a PostgreSQL container they start when Docker is there (see the
data starter's README).

**The build reads the schema too.** The SQL of each `@Query` is checked when
the application is built (see the starter's README): a misspelled table or
column (`books.titel`) is a build error with a `did you mean 'title'?` when
the build knows a close name, from the entities and from the files of
`lib/resources/`: the migrations of `spring.sql.migration.locations` (by
version, then the `R__` files) and the scripts of
`spring.sql.init.schema-locations` (default `schema.sql`, `schema-all.sql`),
`{vendor}` standing for the directory of a database (when several have
files, each is an alternative schema and a column of any is known). The
build reads these settings from `application.properties`, `application.yml`
and `application.yaml` (also in `config/`), and only `resources:` locations:
with a `file:` location, a `${placeholder}` in one, a profile file or a
profile-specific YAML document that sets them, a `spring.config.import`,
`spring.config.location` or `spring.config.additional-location`, or the
settings of a named data source, it cannot see the schema and does not
look for misspelled names. An application that declares its own
`NamingStrategy` bean hides the names derived from the entities.

**The build compiles the SpEL of a `@Query`.** A `:#{...}` value is written
as Dart when the build can (`(arguments, context) => (arguments[0] as
Book).title` for `:#{#book.title}`), so a typo is a build error instead of a
failure at the first call: `BookRepository.sameTitle: the expression
:#{#book.titel} is invalid: No property 'titel' on type 'Book'; did you mean
'title'?` An unknown `#variable`, a wrong number of arguments, a member of a
value that can be null without `?.` and a SpEL syntax error are build errors
too. The variables are `#name` of each parameter, `#p0` and `#a0`, `#root`
(the list of the arguments), `#entityName` and `#methodName`; `@bean` and
`@environment.getProperty(key, default)` work as in the interpreter. What the
build leaves to the interpreter (`T(...)`, `new`, selection and projection,
`matches`, `instanceof`, Java-style names such as `size()`, members of
`Object` or of a bean it does not know) is evaluated at run time, and only
the classes of the arguments of such a method are described for SpEL.

In an application that also uses the web starter, a `DuplicateKeyException`
or an `OptimisticLockingFailureException` is answered with a 409, an
`EmptyResultDataAccessException` with a 404, and a sort property that does
not exist or an invalid page with a 400 ([the table](#18-reference-web-server)),
whatever the database.

A SQL data source sets its schema up on a connection, which Dart cannot wait
for without `await`: start the application with `await runApplicationAsync(args)`
(`SpringApplication.runAsync`); the synchronous `runApplication(args)` fails
at start with a report that says so.

`save` inserts an entity that is new and updates one that is not: with a
`@Version`, new means a `null` version, or `0` for a version that cannot be
null (`int`); a nullable `int?` version is new only when `null`, so a row
stored at version 0 can be updated (Spring Data's rule for `long` and `Long`).

## 21. Tests

`spring_boot_starter_test` starts the application in a test with its own
configuration, so a test can use other values than the application ships
with:

```dart
final app = springBootTest(
  springApplication,
  profiles: ['test'],                                   // spring.profiles.active
  properties: {'shop.max-basket-size': 3},              // above every other source
  propertyFiles: ['resources:extra.properties'],        // just below properties
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

## 22. Code generation options

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
| `aop_prune` | bool | `true` | With `all`, the `@SpringBootApplication` output and the `@ComponentScan` modules of an application package (`publish_to: none`) leave out the proxy classes of beans that no advice can match |

The generator also writes only what the application uses of each class
(there is no option for it). A class that a controller only returns is
described with getters, one that is only a `@RequestBody` or a client's
answer with its constructor and setters, and methods only for the classes
SpEL may call (`@PreAuthorize` and the other security expressions, cache
keys and conditions); `@Introspected()` describes everything. A class used
some other way the build cannot see fails at run time with an error that
says to add `@Introspected()` (see the
[generator's README](../spring_core_dart_generator/README.md#generate-only-what-runs)).

Two limits of SpEL expressions are compile-time defines (`-D` or
`--dart-define`), not properties: `spring.context.expression.maxLength`
(the longest `@Value` expression) and `spring.expression.maxOperations`.

---

## Differences from Spring Boot

### Renamed properties

Spring Boot's names for a few properties carry Java history that means
nothing in Dart: there is no servlet container, no Jackson, no Spring
Cloud, no Logback and no Flyway here. These properties have the names
below instead, and the rest of Spring Boot's names are kept.

| Spring Boot | Here |
|---|---|
| `spring.cloud.openfeign.*` | `spring.feign.*` |
| `spring.jackson.*` | `spring.json.*` |
| `spring.servlet.multipart.*` | `spring.web.multipart.*` |
| `server.servlet.context-path`, `server.servlet.session.*` | `server.context-path`, `server.session.*` |
| `logging.logback.rollingpolicy.*` | `logging.file.rolling-policy.*` |
| `spring.flyway.*` | `spring.sql.migration.*` |

An old name does not work silently: `spring_boot_dart` stops the start
(`APPLICATION FAILED TO START`) when any property source holds a key
under an old name (in a file, on the command line, in `--dart-define`s or
as an environment variable such as `SPRING_JACKSON_TIME_ZONE`) and lists
each key with its new name, for example
`spring.jackson.default-property-inclusion is now
spring.json.default-property-inclusion`. A forgotten
`server.servlet.session.*` ignored in silence would leave the sessions on
their defaults.

There is no `classpath:`: Dart has no class path, and the prefix
points into `lib/resources/` (the files the generator embeds), so every
location is written `resources:` (`resources:config/`, `resources*:i18n/*.properties`
for the search over every root, `optional:resources:extra.yml`, and the
defaults of `spring.sql.migration.locations`, `spring.sql.init.*-locations`,
`spring.messages.basename` and the banner). It works in `spring.config.import`,
`spring.config.location`, `@PropertySource`, `@Value`, `getResource` and the
generator's build-time readers.

- `.properties` files are read as UTF-8; Spring Boot reads ISO-8859-1. For
  Spring Boot's behaviour use
  `PropertiesPropertySourceLoader(encoding: latin1)`, or name the encoding
  of one file where it is named (`x.properties[encoding=iso-8859-1]`). So
  a `.properties` file saved as ISO-8859-1 with a non-ASCII character
  fails the start here (`ConfigDataLoadException`, naming the file and the
  encoding), which Spring Boot reads; a UTF-8 one is read right here and
  as `Ã¼`-style text by Spring Boot. Bytes that are not valid in the
  encoding fail the start (also with `[encoding=utf-8]` or `us-ascii`),
  where Spring Boot reads each as `�`. YAML is UTF-8 in both (Spring Boot
  also reads a UTF-16 file with a byte order mark).
- An encoding hint names UTF-8, ISO-8859-1 or US-ASCII; Spring Boot takes
  any charset of Java (`UTF-16`, `windows-1252`...), which fails the start
  here, also in a YAML location's hint (which Boot ignores).
- XML properties files are not read: Spring Boot reads `application.xml`
  next to `application.properties` and imports `x.xml`
  (`java.util.Properties.loadFromXML`). Here `application.xml` is not
  looked for, `spring.config.import=x.xml` fails the start ("XML
  properties files are not supported") and an `optional:` one is skipped;
  write the file as `.properties` or YAML.
- YAML nesting: Spring Boot (SnakeYAML) refuses a file nested more than
  50 collections deep ("Nesting Depth exceeded max 50"); here such a file
  is read, up to some thousands of levels (3,000 on the Dart VM; the limit
  depends on the platform's stack), and a deeper one fails the start with
  a `ConfigDataLoadException` naming the file ("nested too deeply").
- A `.properties` file with tens of thousands of lines holding only `\`
  is read here; Spring Boot's loader overflows the stack on it
  (`StackOverflowError`).
- Two `.properties` documents stay apart where Spring Boot silently
  changes them. A comment right after a separator (before the document's
  first key, blank lines between or not) makes Spring Boot add the new
  document to the one before it: `#---`, `# the dev part`,
  `spring.config.activate.on-profile=dev` limits the whole file to `dev`
  there. And after spaces behind a separator's hyphens (`#--- `), Spring
  Boot reads the next line wrong: a key with spaces before it is dropped,
  a separator there is a comment. Both are read as written here; write
  such comments below the guard line, and no spaces after `#---`, for a
  file that reads the same in both.
- `spring.main.register-shutdown-hook` is `false` by default, because
  listening for signals keeps a Dart program alive.
- No `env:` imports, no `resources*:` config locations and no classpath
  wildcards.
- In a `;` group of locations (`spring.config.location`,
  `.additional-location`, `spring.config.import`), spaces around an entry
  are trimmed and empty entries are skipped. Spring Boot keeps the spaces
  as part of the location (`a.yml; b.yml` names ` b.yml`, which it then
  does not find) and reads an empty entry as the importing file's
  directory (`b.yml;` also reads that directory's `application.*`), or
  fails on it in `spring.config.location`.
- Each entry of a `;` group is read by its own prefix, so a `configtree:`
  entry is a config tree wherever it stands. Spring Boot picks the
  resolver of the whole group from its first entry:
  `x.yml;configtree:/run/secrets/` reads the tree entry as a plain
  directory (looking for `application.*` in it, so the secrets are not
  read), and `configtree:/run/secrets/;x.yml` fails ("Config tree location
  '/run/secrets/;x.yml' must end with '/'").
- A relative import in a file found through a wildcard location
  (`file:./config/*/`) is relative to that file's directory. Spring Boot
  resolves it against the wildcard pattern instead (`config/*/x.yml`):
  it reads `x.yml` from every subdirectory, not only the importing
  file's, and fails the start on a path with a directory (`sub/x.yml`,
  "must end with '*/'").
- `configtree:` reads directories of the file system only, and its values
  are strings (Boot's can also be bound as a `Resource`). A `configtree:`
  location that is a file, not a directory, counts as missing, so
  `optional:` skips it; Boot fails on it even with `optional:`.
- `spring.profiles.active`, `.default` and `.group.*` in a document
  limited to a profile fail the start when the document applies, and are
  ignored when it does not, as Spring Boot's documentation describes.
  Spring Boot 4.1.2 reads them from such documents (and from documents of
  another cloud platform), applied or not; only `spring.profiles.include`
  fails there (`InactiveConfigDataAccessException`), also in a document
  that does not apply.
- Placeholders in a document's `spring.config.activate.on-profile` and
  `spring.config.import`: Spring Boot resolves them once, when its first
  pass reaches the document, and fails the start
  (`InactiveConfigDataAccessException`) when a key comes from a document
  inactive at that point. Here `on-profile` is resolved once the profiles
  are decided, and again after each document activated; the imports when
  they are read (after the profiles are decided for an `on-profile`
  document); documents not active are ignored. So
  `on-profile=${P:dev}`, with `P=prod` set in a file the same file
  imports and `prod` active, applies here; Spring Boot read `dev` there
  and does not apply it.
- A profile group written as a list is not checked for elements that do
  not bind: `spring.profiles.group.dev[1]=x` without `[0]`, a gap
  (`[0]` and `[2]`) or `[0].a`. Spring Boot fails the start on such a
  list ("were left unbound"), even when the group is not active; here
  the list is read up to the first missing index (`dev[0]=x` and
  `dev[2]=y` add only `x`) and `[0].a` is ignored.
- Profile expressions (`on-profile`, `@Profile`) are stricter than
  Spring 7.0.10's `Profiles.of`: forms it accepts, such as `(dev`, `a)`,
  `a &`, `& a`, `(a)(b)` or `a b`, fail here ("Malformed profile
  expression"). An expression both accept matches the same profiles.
- The profile keys ignored in files read after the profiles are decided
  stay readable with `getProperty`, as in Spring Boot, except in one case:
  `spring.profiles.active` is hidden while no profile is active, and
  `spring.profiles.default` while the default profile is `default`.
  `StandardEnvironment` would read them as profiles then; Spring Boot's
  environment never does.
- These keys are this project's own: `spring.messages.default-locale`,
  `spring.cache.simple.*`, every `spring.websocket.client.*` and
  `spring.flutter.*` key, the Feign `event-stream.*` keys and
  `call-timeout`, `server.max-http-request-body-size`,
  `server.request-timeout`, `server.connection-timeout` (a
  Spring Boot 2.0 key), `server.websocket.*`,
  `spring.web.multipart.max-part-count` and
  `spring.mvc.sse.heartbeat-interval`.
- The web server (`spring_boot_starter_web`) reads only the `server.*` and
  `spring.web.multipart.*` keys of
  [section 18](#18-reference-web-server). They are Spring Boot's names
  without `servlet` (see [Renamed properties](#renamed-properties)), as
  there is no servlet container. There is no HTTP/2, no forwarded
  headers, no key stores, no `server.error.*` and no server-specific keys
  such as `server.tomcat.*`. `server.ssl.*` takes PEM file paths. Errors
  are `ProblemDetail`s, except the plain-text answers Spring gives too
  (a refused CORS request, a refused WebSocket handshake).
- A request can have a deadline: `server.request-timeout` times the
  filters and the handler, and the Feign calls inside it stop at what
  remains of it (`RequestDeadline`; see
  [Deadlines](#deadlines-one-limit-for-a-request-and-the-calls-it-makes)).
  Spring has no timeout for a synchronous request, and none that follows a
  request into the calls it makes; its Feign has only `connect-timeout` and
  `read-timeout` per attempt, where `call-timeout` limits a call with its
  retries.
- `spring.main.web-application-type` knows only `none` (no server).
- Not read: `allow-circular-references`, `keep-alive`,
  `spring.task.execution.*`, `spring.task.scheduling.pool.*`,
  `spring.aop.*`, `management.*`, `info.*`, `logging.config`,
  `logging.structured.*`, `spring.json.*` keys other than those listed
  (they are warned about and ignored), and cache stores other than
  `simple`.
- Jackson time zones and `@Scheduled` zones: only UTC and fixed offsets
  (`@Scheduled`: UTC or local time), as Dart has no time zone database.
- Log dates are UTC.
- There is no `.env` support: configuration lives in property files.
- The `shop.*` keys in the examples are an application's own.
