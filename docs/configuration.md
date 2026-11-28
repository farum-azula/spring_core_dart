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
15. [Reference: HTTP clients (RestClient, HTTP service interfaces)](#15-reference-http-clients)
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
setup. The build is a profile too, after the platform's: `release` in a
release build, `profile` in a profile build, `debug` otherwise. A
release that logs only warnings:

```yaml
# lib/resources/application-release.yml
logging:
  level:
    root: warn
```

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
known at compile time. The properties of the starters the application
reaches are listed too, from their `spring_metadata.json`, and so are the
keys of `config/` files. A map key such as `logging.level.<logger>` is
listed only when a config file names it.

```bash
flutter run --dart-define=SPRING_PROFILES_ACTIVE=prod --dart-define=SHOP_URL=https://neon.books
flutter build apk --dart-define-from-file=config/prod.json
```

A define the generated code names is compiled into the app, where anyone
can read it, so a Flutter build leaves out names that look like a secret
(`SHOP_PASSWORD`, `spring.datasource.password`) and warns about the
application's own. The starters' public settings stay. To offer another
name, such as a public key, list its prefix under the builder option
`dart_defines_secrets`; `dart_defines_exclude` leaves out any other names.

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
`run(properties: ...)` (and, in tests, `springBootTest(properties: ...)`
or `@SpringBootTest(properties: ...)` on a test class) gives values that
sit above everything.

---

## 9. Which source wins

When several sources set the same key, the highest one wins. From the
highest:

1. `run(properties: ...)` and `springBootTest(properties: ...)`
   (`@SpringBootTest(properties: ...)` and
   `@TestPropertySource(properties: ...)` on a test class)
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
| `spring.main.startup-checks.enabled` | `true` / `false` | not set | Read by the generator when it writes the application, in `application.yml` or `application.properties` without a profile: whether the starters' startup checks are in the build (the data starter's `transactionValidator` and `dataFailureAnalyzer`, the cache starter's `cacheOperationValidator`, the edge starter's warning list). `true`: in every build. `false`: in none, no code at all. Not set: in debug builds only (a profile build has them only with `true`), so a profile or a release build compiles them away and a mistake they would have found fails at the first call instead of the start. At run time (command line, environment, a profile), `false` turns off the checks the build kept. `dart compile js` and `wasm` define no `dart.vm.product`, so for the build switches they are debug builds; the edge starter's build adds `-Ddart.vm.product=true` |
| `spring.autoconfigure.exclude` | list | — | Auto-configurations not to apply, by class or module name |
| `debug` | any | — | Any value but `false` (for example `--debug`) logs the condition evaluation report: which auto-configured beans were created, and why the others were not |
| `trace` | any | — | Any value but `false` (`--trace`) turns the framework's loggers (`spring_core_dart`, `spring_boot_dart`, `spring.web.server`) to `trace`; `debug` sets them to `debug`. Levels in `logging.level.*` win |
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
| `logging.group.<group>` | list | — | Logger names; `logging.level.<group>` then sets them all. Predefined: `web` (`spring.web`, `spring.websocket`) and `sql` (`spring.jdbc.core.JdbcTemplate`, `spring.jdbc.core.StatementCreatorUtils`); setting one replaces its list |
| `logging.pattern.console` | pattern | Spring Boot's | The console line format; an empty pattern turns the console off |
| `logging.pattern.file` | pattern | Spring Boot's | The file line format; an empty pattern means no file |
| `logging.pattern.dateformat` | date pattern | `yyyy-MM-dd'T'HH:mm:ss.SSSXXX` | The format of `%d` in the default patterns (times are UTC) |
| `logging.pattern.level` | pattern | `%5p` | The level column |
| `logging.pattern.correlation` | pattern | empty | The correlation column |
| `logging.exception-conversion-word` | pattern | `%wEx` | How exceptions are printed |
| `logging.include-application-name` | bool | `true` | Puts `[spring.application.name]` into the default patterns |
| `logging.include-application-group` | bool | `true` | Puts `[spring.application.group]` into the default patterns |
| `logging.console.enabled` | bool | `true` | The console output |
| `logging.console.target` | `stdout` / `stderr` | `stdout` | Where the console lines go |
| `logging.console.record-bar` | bool | `false` | Starts every line of a record (the message's lines, the stack trace, its causes) with `▌` and a space, coloured by level as `%clr` colours the level when `spring.output.ansi.enabled` allows colours, plain otherwise; applied after `logging.pattern.console`. A line the terminal wraps itself is not marked. Only with this starter: core's `printLogHandler` has no bar |
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
| `spring.cache.type` | `generic` / `simple` / `disk` / `none` | `generic` with `Cache` beans, else `simple` | `simple` keeps entries in memory; `generic` uses the application's `Cache` beans; `disk` keeps them on disk, so they survive a restart (`DiskCacheManager`, below; not Spring Boot's); `none` caches nothing, so the methods always run (`NoOpCacheManager`) |
| `spring.cache.cache-names` | list | — (caches are created on demand) | A fixed set of caches; an annotation that names another cache then fails |
| `spring.cache.simple.time-to-live` | duration, `0` or more | none | An entry expires this long after it was written, measured on a monotonic clock as Caffeine's ticker (setting the system clock moves no expiry). `0` keeps nothing; a negative value fails the start (an `ArgumentError` naming the property), as Caffeine's `expireAfterWrite` refuses one |
| `spring.cache.simple.max-size` | int, `0` or more | none | The most entries per cache; when full, the least recently used entry goes. `0` keeps nothing; a negative value fails the start (an `ArgumentError` naming the property) |
| `spring.cache.simple.caches.<name>.time-to-live` | duration, `0` or more | the global one | The same, for one cache; a negative value fails the start too |
| `spring.cache.simple.caches.<name>.max-size` | int, `0` or more | the global one | The same, for one cache; a negative value fails the start too |
| `spring.cache.disk.time-to-live` | duration, `0` or more | none | `type: disk`: an entry expires this long after it was written, by the wall clock (it outlives a restart) |
| `spring.cache.disk.caches.<name>.time-to-live` | duration | the global one | The same, for one cache |
| `spring.cache.disk.max-size` | data size (`50MB`) | none | The most bytes each cache keeps; past it the oldest written go. Only the cache's own folder counts: the resources a Flutter app downloads have a limit of their own, `spring.flutter.resources.cache.max-size` |
| `spring.cache.disk.directory` | folder | `.spring/cache` | Where the entries are where no `CacheStore` bean gives a place (a server; a Flutter app keeps them in its files' `cache` place) |
| `spring.cache.disk.version` | text | none (every entry is read) | The version entries are written by; one of another version is not read, so results made from what a new version changed are made again |
| `spring.cache.resource-version` | `true` / `false` | `false` | Whether a key made of a resource that knows the version of its content (a file the Flutter starter keeps) is its address and that version, so a result made from a file that changed at the same address is made again. Off by default: the version is a digest of the content. Not Spring Boot's |

`type: disk` keeps each entry in one file, `spring/caches/<cache>/<hash
of the key>.json`, with the key it was written under, when it expires,
its version and the value as JSON through the application's
`ObjectMapper`: `String`, numbers, `bool`, `null`, an object the mapper
reads (`@Introspected()` or a JSON serializer), a `List`, `Set` or
`Map<String, …>` of one of those, and a `Resource` with an address (kept as
the address: a file the resources' cache keeps is one copy for both). Another
value is not kept (the method runs again; the cache logs it once), nor is
an empty collection, whose element type is unknown. Its caches answer later
(`AsyncCache`, Spring's `Cache.retrieve`): a method that does not return a
`Future` on one is a start-up error naming it. `CompositeCacheManager`
(Spring's) asks several managers for a cache name; `LayeredCacheManager`
(not Spring's) puts a fast cache in front of slower ones, a hit in a slower
one copied forward, a put and an evict going to every layer.

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

## 15. Reference: HTTP clients

### RestClient and HTTP service interfaces

`spring_boot_starter_restclient` sets up the `RestClientBuilder` bean
and the HTTP service groups from these keys. `spring.http.clients.*`
applies to every client; `spring.http.serviceclient.<group>.*` to the
`RestClient` of one group (the `group` of `@ImportHttpServices`,
`default` without one), whatever it leaves out coming from
`spring.http.clients.*`.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  http:
    clients:
      connect-timeout: 2s
      read-timeout: 10s
      allowed-addresses:
        - api.neon.books
        - 10.20.0.0/16
    serviceclient:
      catalog:
        base-url: https://catalog.neon.books
        default-header:
          X-Tenant: neon
        apiversion:
          default: '2'
          insert:
            header: API-Version
        read-timeout: 5s
```

</td><td>

```properties
spring.http.clients.connect-timeout=2s
spring.http.clients.read-timeout=10s
spring.http.clients.allowed-addresses=api.neon.books,10.20.0.0/16
spring.http.serviceclient.catalog.base-url=https://catalog.neon.books
spring.http.serviceclient.catalog.default-header.X-Tenant=neon
spring.http.serviceclient.catalog.apiversion.default=2
spring.http.serviceclient.catalog.apiversion.insert.header=API-Version
spring.http.serviceclient.catalog.read-timeout=5s
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.http.clients.allowed-addresses` | list | empty | The hosts and addresses the transport may call; **every other one is denied**, private networks and loopback included. An entry is a host (`api.neon.books`), its subdomains (`*.neon.books`), an address (`203.0.113.7`), a CIDR block (`10.20.0.0/16`), a URL whose host is taken, or `*` for any host with a public address. The groups' `base-url` hosts and the OAuth2 providers' configured endpoints are on it by themselves. A name opens only public addresses: list the block of a private network (or `localhost`) too; cloud metadata (`169.254.169.254`) needs its own entry. In a browser only the URL's host is checked. Not in Spring Boot |
| `spring.http.clients.connect-timeout` | duration | `10s` | The longest wait for a connection; `0`: none |
| `spring.http.clients.read-timeout` | duration | `60s` | The longest wait for data (the response, then between two chunks of the body); `0`: none |
| `spring.http.clients.redirects` | `follow-when-possible`, `follow`, `dont-follow` | `follow-when-possible` | Whether redirects are followed |
| `spring.http.serviceclient.<group>.base-url` | URL | none | The base of the group's calls; its host is allowed |
| `spring.http.serviceclient.<group>.default-header.<name>` | list | none | Headers sent with every call of the group |
| `spring.http.serviceclient.<group>.apiversion.default` | string | none | The API version of the group's calls whose exchange annotation gives no `version:`. It needs an inserter (`apiversion.insert.*`, or one a `RestClientCustomizer` sets): without one the start fails |
| `spring.http.serviceclient.<group>.apiversion.insert.header` | string | none | The header that holds the version (`API-Version`) |
| `spring.http.serviceclient.<group>.apiversion.insert.query-parameter` | string | none | The query parameter that holds the version |
| `spring.http.serviceclient.<group>.apiversion.insert.path-segment` | int | none | The index of the path segment the version is inserted as (`0`: `/books` becomes `/2/books`) |
| `spring.http.serviceclient.<group>.apiversion.insert.media-type-parameter` | string | none | The parameter of the `Content-Type` that holds the version. With no `insert.*`, the group keeps its builder's inserter (Spring Boot sets one that inserts nothing) |
| `spring.http.serviceclient.<group>.connect-timeout` | duration | `spring.http.clients`' | The group's connect timeout |
| `spring.http.serviceclient.<group>.read-timeout` | duration | `spring.http.clients`' | The group's read timeout |
| `spring.http.serviceclient.<group>.redirects` | as above | `spring.http.clients`' | The group's redirects |

An `InetAddressFilter` bean narrows the allow list further (every
address must match it too), and an `AllowedAddressesContributor` bean
adds what another starter was given by hand. There is no key to switch
the filter off. As in Spring Boot 4, the API version keys are a group's
only (there is no `spring.http.clients.apiversion`); a `RestClient`
built from the `RestClientBuilder` bean takes `apiVersionInserter(...)`
and `defaultApiVersion(...)` on the builder. The OAuth2 client's keys for `RestClient` calls
(`spring.security.oauth2.client.restclient.*`) are in
[section 19](#19-reference-oauth2-clients).

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
| `max-text-message-size` | data size, or `-1` | `spring.websocket.client.max-text-message-size` | The largest text message this client reads, in UTF-8 bytes; a larger one closes the connection with 1009. What a client leaves out comes from `default`, then from the key for all clients below |
| `max-binary-message-size` | data size, or `-1` | `spring.websocket.client.max-binary-message-size` | The same for binary messages |
| `phoenix.heartbeat-interval` | duration | `30s` | For a `@PhoenixChannel` or a `PhoenixSocket` of that name: the time between two heartbeats; `0` sends none |
| `phoenix.push-timeout` | duration | `10s` | The longest a join, a push or a leave of a Phoenix channel waits for its reply |
| `phoenix.vsn` | `2.0.0`, `1.0.0` | `2.0.0` | The version of the Phoenix wire format, sent as the `vsn` query parameter; `@PhoenixChannel(vsn:)` wins |

An invalid `reconnect.*` value fails the start. Not supported: heartbeats
of a plain `@WebSocketClient` (a Phoenix socket sends its own), STOMP and
SockJS.

```properties
# The feed sends JSON of up to 1 MB; every other client stays at 8 KB.
spring.websocket.client.config.feed.max-text-message-size=1MB
spring.websocket.client.config.chat.phoenix.heartbeat-interval=15s
```

Two keys apply to every client that sets no limit of its own, through
the default `webSocketTransport` bean (on `dart:io`; the browser has no
such limits):

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
(`MaterialApp`, `CupertinoApp` or `WidgetsApp`) from these keys; without
`home` (and `child`) it builds the `.router` form on the application's
`RouterConfig<Object>` bean (the navigation starter's). An app that
passes `child:` instead builds its own app widget, and the keys are not
used.

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
| `spring.flutter.app.type` | `widgets` / `material` / `cupertino`, or the type of an app factory of your own | not set: the one design starter's type (`material`, `cupertino`), else `widgets`; with several, required | The app widget: `WidgetsApp`, `MaterialApp` (needed by `Scaffold` and `AppBar`; `spring_boot_starter_flutter_material`) or `CupertinoApp` (`spring_boot_starter_flutter_cupertino`) |
| `spring.flutter.app.title` | string | empty | The app's name for the OS, shown in the task switcher or the browser tab; the build also writes it into `web/index.html` (`<title>`) and `web/manifest.json` (`name`, `short_name`) |
| `spring.flutter.app.description` | string | none | What the app is, in a sentence: the build writes it into `web/index.html` (`<meta name="description">`) and `web/manifest.json`. With a theme, the build also writes its `primary` (`theme-color`) and `surface` (`background_color`) |
| `spring.flutter.app.debug-banner` | `true` / `false` | `true` | Flutter's DEBUG banner in debug builds |
| `spring.flutter.app.locales` | comma list of locales (`en`, `pt_BR`, `zh_Hant_TW`) | the languages of the messages files | The locales the app supports. By default `messages.properties` counts as English, and each `messages_<locale>.properties` of `spring.messages.basename` adds its locale |

`spring.flutter.app.type` need not be set. As Spring Boot deduces
`spring.main.web-application-type` from the class path, the application's
starters decide: with one design starter
(`spring_boot_starter_flutter_material` → `material`,
`spring_boot_starter_flutter_cupertino` → `cupertino`) or one
`SpringAppFactory` bean of the app's own type, the app is of that type;
with none, `widgets`. With app factories of several types (both design
starters, say) the start fails, naming the property and the types:

```text
Invalid argument(s) (spring.flutter.app.type): not set, and the application has app widgets of several types: cupertino, material. Choose one, for every platform or in a profile of each (spring.flutter.app.type=cupertino in application-ios.properties)
```

Set, the property always wins: `widgets` keeps a `WidgetsApp` although a
design starter came in through another package.

Write `locales`, and in Flutter apps `spring.messages.basename`, as one
comma-separated value, also in YAML. The app widget reads them as single
values, so a YAML list (`[en, ja]`) is not seen.


The start behind the splash (the splash's look is the theme's `splash`; see
[the stages of the start](flutter/theme/loaders.md#the-stages-of-the-start)):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.splash.yield-frames` | `true` / `false` | `true` on the web, `false` elsewhere | Lets Flutter draw a frame between the beans while they are created, so the splash keeps moving. See [yielding frames](flutter/theme/loaders.md#yielding-frames-during-the-start) |
| `spring.flutter.splash.frame-budget` | duration | `8ms` | The work between two frames when `yield-frames` is on |
| `spring.flutter.splash.trace` | `true` / `false` | `false` | Measures the start: each stage and each bean's creation, logged at the end and, on the web, marked in the browser's Performance tab. See [tracing](flutter/theme/loaders.md#tracing-the-start) |
| `spring.flutter.splash.tasks.enabled` | `true` / `false` | `true` | Runs the `SplashTask` beans while the splash shows, before the app. See [tasks during the splash](flutter/theme/loaders.md#tasks-during-the-splash) |
| `spring.flutter.splash.tasks.timeout` | duration | `5s` | How long the splash waits for the tasks; one still running goes on behind the app |
| `spring.flutter.splash.tasks.share` | 0 to 1 | `0.2` | The loader's share the tasks take, when the app has any |
| `spring.flutter.splash.warm-up.text.enabled` | `true` / `false` | `false` | Lays out the characters of the app's text while the splash shows, so the fonts they need are downloaded before the app shows. See [fonts for the app's text](flutter/theme/loaders.md#fonts-for-the-apps-text-web) |
| `spring.flutter.splash.warm-up.text.resources` | list of locations | `resources:messages*.properties` | The files whose characters are laid out (patterns) |
| `spring.flutter.splash.warm-up.text.first-font` | duration | `400ms` | No font downloaded in that time: none is needed |
| `spring.flutter.splash.warm-up.text.settle` | duration | `250ms` | After a font came in, how long without another before the warm-up ends |
| `spring.flutter.splash.warm-up.text.chunk` | number | `200` | How many characters are laid out in one frame, so the splash keeps moving on a phone |

The frame meter: one short line over the app with the frames a second it
really draws, in the theme's primary color, and those a 3D scene draws
beside them (`60 (120 3D)`), over a strip with a bar per frame (within the
budget, up to twice it, over); the debug panel's Frames tab adds the
average time of their build and raster and the worst frame. The times are
Flutter's own (`FrameTiming`), on every platform the web included, so it
shows on a phone what a desktop browser cannot. A frame is late only when
the app was waiting for it (something moves at every frame); an animation
that asks for a frame now and then (a background drifting 15 times a
second) is measured by what each frame cost. The panel is drawn again at most four times a second and its own
frames are not counted: an app that draws nothing shows `idle`. Turn it on
in a profile you test with.

```yaml
spring:
  flutter:
    frame-meter:
      enabled: true
      position: bottom-right
      target-rate: 60
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.frame-meter.enabled` | `true` / `false` | `false` | Shows the frame meter over the app (`FrameMeter`, put there by `SpringApp`) |
| `spring.flutter.frame-meter.position` | `top-left` / `top-right` / `bottom-left` / `bottom-right` | `top-right` | The corner of the screen it shows in, inside the safe area |
| `spring.flutter.frame-meter.target-rate` | number | `60` | The frames a second the screen is meant to show: a frame within `1 / target-rate` is good, up to twice that a warning, more a drop |

Its look is the theme's `frame-meter`; a value left out comes from the
theme's colors and typography:

```yaml
spring:
  flutter:
    theme:
      frame-meter:
        background: { color: $colors.surface, alpha: 85% }
        foreground: $colors.on-surface
        good: $colors.primary
        warning: $colors.tertiary
        bad: $colors.error
        text-style: label-small
```

The resources the `ResourceLoader` downloads (`http:` and `https:`), kept on the disk, and how a `ResourceView` shows them:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.resources.cache.enabled` | `true` / `false` | `true` | Whether an `http:` or `https:` resource of the `ResourceLoader` (a `Resource` of `@Value`, `ResourceView`, `ResourceImage`) is downloaded once and kept in the files' `cache` place (`spring/resources/<sha256 of the address>/`, `data` and `meta.json`) |
| `spring.flutter.resources.cache.max-age` | duration | `7d` | How long a kept resource is used as it is; past it, it is still used and asked again in the background with `If-None-Match` / `If-Modified-Since` (an unchanged one costs no download) |
| `spring.flutter.resources.cache.max-entry-size` | data size | `50MB` | The largest resource kept; a larger one is read from the network every time |
| `spring.flutter.resources.cache.max-size` | data size (`200MB`) | none (the system's) | The most bytes the kept resources take together; past it the least recently used go first. Only their folder counts (`spring/resources/`): the `@Cacheable` caches on disk (`spring.cache.type: disk`, `spring/caches/`) keep to limits of their own |
| `spring.flutter.resources.cache.locations[n].pattern` / `.max-age` / `.enabled` | address pattern (`**` any path, `*` one segment), duration, `true` / `false` | none | Rules by address, the first that matches wins: an age of their own, or `enabled: false` not to keep them |
| `spring.flutter.resources.view.fade` | duration | `200ms` | How long a `ResourceView` fades its resource in over its placeholder; none when the system asks for less motion |

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

`spring_boot_starter_flutter_material` in the dependencies makes the app a
`MaterialApp`, which `Scaffold`, `AppBar` and the other Material widgets
need: as the one design starter, it sets the app's type
(`spring.flutter.app.type: material`, which need not be written).
`seed-color` makes the whole Material 3 palette (primary, secondary,
surfaces, …) from one color.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    theme:
      seed-color: deepPurple
```

</td><td>

```properties
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
`lib/spring_gen/theme.spring.keys.dart`, where `context.theme` has a getter for every key your
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
  `lib/spring_gen/theme.spring.keys.dart` and `lib/spring_gen/messages.spring.keys.dart`. A library such as a
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
  final ThemesApi api;                       // for example an @HttpExchange interface

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
`lib/spring_gen/messages.spring.keys.dart` (import `spring_gen/main.spring.dart`):

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
| `remember` | `true` / `false` | `true` | Keeps the theme the user chooses (`ThemeSelection.select`) between runs: written at each choice by the `ThemeChoiceStore` bean (the app's files by default, IndexedDB in a browser; your own bean keeps it elsewhere) and shown again while the splash shows, so a reload does not flash `active` first. A kept theme that no longer exists is ignored |

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
| `motion.page-transition` | `platform`, `fadeUpwards`, `zoom`, `cupertino`, `fade`, `none`, or a map of `type`, `duration`, `curve` | `platform` | The page transition of every screen, in every app type (the navigation starter's router follows it): the app type's own by default, as in Flutter (Material's per platform in a `MaterialApp`, the iOS slide in a `CupertinoApp`, none without a design library); `none` switches pages at once. See [page transitions](flutter/theme/motion-and-animations.md#page-transitions) |
| `motion.durations.<name>` | duration | `short` 100ms, `medium` 250ms, `long` 450ms | Durations for the app's animations |
| `motion.curves.<name>` | four numbers | `standard`: Material's | Curves for the app's animations |
| `components.<component>.<property>` | see the next table | Material 3's | Adjusts one component |
| `tokens.<group>.<key>` | any value | — | The app's own values, read with `tokenColor('brand.accent')`, `tokenNumber(...)` or `token(...)` |
| `cupertino.<property>` | see the reference below | iOS's | The `CupertinoThemeData`: `primary-color` (default `colors.primary`, else the seed, else iOS blue), `primary-contrasting-color`, `scaffold-background-color`, `bar-background-color`, `selection-handle-color`, `apply-theme-to-all`, and `text-theme.*` (the text styles) |
| `styles.code.<property>` | color, number or insets | the color scheme | The code blocks of `MarkdownView`: the colors `background`, `text`, `keyword`, `string`, `comment`, `number`, `key`, `annotation`, `variable`, `type`, `punctuation`, and the block's `padding`, `radius`, `border`, `border-width`; also `inline-text`, `inline-background`, `header`, `title`, and `copy` (`true`: a copy button on every block). See [Markdown and code](flutter/theme/styles-and-states.md#markdown-and-code-stylescode) |
| `styles.heading.<property>` | color | the text's color | `MarkdownView`'s headings: `color` for every level, `h1` ... `h6` for one |
| `styles.table.<property>` | number, `true` / `false` | `cell-width` 280, `fill` `true` | `MarkdownView`'s tables: `cell-width`, the widest a column grows before its text wraps (a wider table scrolls sideways); `fill`, a narrower table widened to the view |
| `styles.link.color`, `styles.callout.<kind>` | color | `primary`; callouts `primary`, `tertiary`, `secondary`, `error`, `error` | `MarkdownView`'s links, and its callouts `note`, `tip`, `important`, `warning`, `caution` |

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
| `source` | none | where the theme comes from: an `https` URL, or `github:owner/repo/path@ref`, which is `https://raw.githubusercontent.com/owner/repo/ref/path` (`HEAD` without `@ref`). Other schemes stop the start, naming the property; `http` too unless `spring.remote.allow-insecure` (below). `source` on `spring.flutter.theme` itself downloads values every theme shares, under your own files |
| `source-sha256` | none | 64 hexadecimal digits: content with another digest is refused (not shown, not cached). Part of the cache's identity |
| `refresh` | none (cached for ever) | a duration (`30m`, `1h`, `1.5d`): when the cache is older, the file is read again in the background |

- **Insecure connections.** Every address the configuration downloads
  from (theme sources, images, a page loader's `web:`) is read by one
  parser (`RemoteAddress`) and checked at the start by one rule
  (`RemoteAddressPolicy`): an `http://` address stops the start with "the
  connection is not secure", naming the address and its property.
  `spring.remote.allow-insecure=true` allows it, and an `https` address
  whose certificate is expired, self-signed or for another host (not in a
  browser, which checks certificates by itself); a warning then lists
  every insecure address.
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

#### Markdown and code: `styles.code`

`MarkdownView` shows Markdown (a string, or a resource such as
`resources:content/docs/beans.md`) with the theme's text styles; the
navigation's `RouteContentView` shows a route's Markdown with it. Code is
written in the `code` text style, colored by the style `styles.code`:

```yaml
typography:
  code: { font-family: JetBrains Mono, size: 13 }
styles:
  code:
    background: $colors.surface-container-low
    border: $colors.outline-variant
    radius: $shape.small
    padding: 16
    keyword: '#C678DD'
    string: '#98C379'
    comment: '#5C6370'
    number: '#D19A66'
    key: '#E06C75'          # YAML and .properties keys
    annotation: '#61AFEF'
    variable: '#E5C07B'     # $colors.primary, ${PORT}
    punctuation: '#ABB2BF'  # { } [ ] , :
```

`MarkdownView.code(text, language: 'yaml')` shows one block of code the
same way, for the code samples of an app.

Every block has a copy button (`copy: false` for none). Headings take
`styles.heading` (`color`, `h1` ... `h6`); a table's columns grow to
`styles.table.cell-width` (280) and wrap there, a wider table scrolls
sideways and a narrower one fills the view (`styles.table.fill: false`
keeps it as wide as its text). In a `WidgetsApp` or `CupertinoApp` the
text styles are the theme's, with Material's sizes for the script of the
app's language.

Every color is optional and falls back on the color scheme, so code reads
well in every theme without `styles.code`. The full list, with the
defaults: [Markdown and code](flutter/theme/styles-and-states.md#markdown-and-code-stylescode).

What the code of a language is made of comes from the theme's
`syntax.<language>` (rules of regular expressions and kinds, keywords,
types, aliases); the starter has no language of its own. Take Dart, Java,
YAML, properties, shell and JSON for every theme from the themes
repository:

```yaml
spring:
  flutter:
    theme:
      source: github:farum-azula/themes/themes/code.yml@code-v0.2.0
```

See [the languages of code](flutter/theme/styles-and-states.md#the-languages-of-code-syntax).

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
| `source` | required | an asset path, an `https` URL or a `github:owner/repo/path@ref` address (`http` only with `spring.remote.allow-insecure`) |
| `refresh` | none | a duration. Without it the file is downloaded once and read from the cache for ever. With it the cache is shown at once and checked again in the background when older |
| `source-sha256` | none | 64 hexadecimal digits. A file with another digest is dropped with a warning |
| `headers` | none | request headers. A map (`{ Authorization: ... }`). `${...}` placeholders work here |
| `timeout` | `10s` | how long a download may take |
| `fallback` | none | an asset shown while there is no cache |

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
`linux`, `mobile`, `desktop`) and the build's (`release`, `profile`,
`debug`) are always active; see
[Profiles](#profile-files-and-activation).

### The debug panel

A panel over the running app for whoever builds it: the logs, the frame
meter, the configuration, the beans, the themes and the start, each a
section of its menu.
It opens with the action `debug.open`: ⌘⇧D (Ctrl+Shift+D), or four quick
taps and a fifth held three seconds, on every platform. Other keys or taps
are written like any [shortcut](#keyboard-shortcuts):

```yaml
spring:
  flutter:
    debug:
      enabled: true          # true: every build; false: none; not set: debug builds only
    shortcuts:
      debug.open: [primary+shift+d, taps:5+hold:2s]
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.debug.enabled` | `true` / `false` | not set | Read by the generator when it writes `main.spring.dart`. `true`: the panel is in every build. `false`: it is in none; the module is not written, so the app has none of its code. Not set: it is written for debug builds only, and a profile or a release build compiles it away; a profile build has the panel only with `true`. Set to `false` in a profile, it turns off the panel of a running app whose build has it |
| `spring.flutter.debug.frame-meter.enabled` | `true` / `false` | not set | The same, for the frame meter, a module of its own (`springBootStarterFlutterDebugFrameMeterAutoConfiguration`, bean `debugFrameMeter` with `on` and `position`). Its action `debug.frame-meter` has the keys `primary+shift+x` and `taps:5+hold:2s` (`spring.flutter.shortcuts.debug.frame-meter`), and it starts in the corner `spring.flutter.frame-meter.position`. With `debug.enabled: false` and this `true`, a release build has the frame meter and no panel |
| `spring.flutter.debug.motion.enabled` | `true` / `false` | not set | The same, for the motion switch, a module of its own (`springBootStarterFlutterDebugMotionAutoConfiguration`, bean `debugMotion` with `animations`). Its action `debug.motion` has the key `primary+shift+m` (`spring.flutter.shortcuts.debug.motion`) |
| `spring.flutter.debug.flutter-tools.enabled` | `true` / `false` | not set | The same, for the panel's Flutter tab, a module of its own (`springBootStarterFlutterDebugFlutterToolsAutoConfiguration`, bean `debugFlutterTools`) whose beans need the panel: `spring.flutter.debug.enabled` is its parent switch, so a build without the panel has none of its code whatever this key says, and with the panel not set it is in debug builds only (the narrowest of the two). Flutter's own debug tools, switched live and kept while the app runs: the widget inspector (with the selected widget's type, size, position and ancestors), the performance overlay, the semantics debugger, paint size, baselines, layer borders, pointers, the repaint rainbow, inverted oversized images, slow animations (`timeDilation` 1, 2, 5, 10), and `dart devtools <address>` to copy. In profile and release the inspector and the paint flags show as off with the reason; on the web the performance overlay and the DevTools address do |
| `spring.flutter.debug.console.enabled` | `true` / `false` | not set | The debug console, a module of its own (`springBootStarterFlutterDebugConsoleAutoConfiguration`, bean `debugConsole`): only `true` puts it in the build, and then in every build, a release build included (unlike the panel, not set does not mean debug builds); not set or `false`, the app has none of its code, nor of its segments and panes (the scene and signals starters' too), its commands, or the application's `@ConsoleSegment`, `@ConsolePane` and `@ConsoleCommand` classes. Its action `debug.console` has the keys `backquote` and `section` (the key left of `1`, `§` on a Mac's ISO keyboard: as a game's console, on any layout, not while a text field has the focus) and `taps:8+hold:2s` (`spring.flutter.shortcuts.debug.console`). From top to bottom: a header row of segments, then the shown panes, by default the `logs` pane (the newest records colored as the console colors them, the time and `:` faint, the level green, yellow or red, the logger cyan, wrapped, by the Logs tab's filter, the `debugLogFilter` bean, live, or without the panel by `filter.*`); with no pane shown, the header alone ([below](#the-debug-console)); colors and fonts from the [debug theme](#debug-themes) |
| `spring.flutter.debug.console.position` | `top-left`, `top-right`, `bottom-left`, `bottom-right` | `top-left` | Its corner |
| `spring.flutter.debug.console.opacity` | 0 to 1 | `0.9` | How opaque its background is; the text stays opaque. The header's always, the panes' while they interact (unless a pane gives its own `backgroundOpacity`) |
| `spring.flutter.debug.console.interaction` | `pass-through`, `interact` | `interact` | How the panes take the pointer at the start, every pane alike, the application's too ([below](#the-debug-console)): `pass-through`, every tap, scroll, hover and drag over them reaches the app, only the header and the handles take one; `interact`, the panes work (the records scroll and select, a row takes a tap, the graph pans, the input line types). The toggle at the right of the header switches it while the app runs (`debugConsole.interaction`), ⌥ (Alt) held on a desktop interacts while held; starting the records' selection or focusing the input line switches it to `interact`. The debug panel is not affected |
| `spring.flutter.debug.console.pass-through-opacity` | 0 to 1 | `0.7` | How opaque the panes' background is while they pass the pointer through: the app the taps reach seen under it, the panes read; 0, none. A pane's own `backgroundOpacity` counts only while they interact. The header keeps `opacity` |
| `spring.flutter.debug.console.slide-duration` | duration | `220ms` | How long it takes to slide in from its edge when shown and back out when hidden (`150ms`, `0.4s`), as a game's console drops down: from the top in a top corner, from the bottom in a bottom one. Pressed again while it slides out, it comes back from where it is. `0`: it shows and hides at once, with no animation in the tree |
| `spring.flutter.debug.console.max-lines` | 1 to 200 | `12` | How many lines high the `logs` pane starts. The divider under it moves the room between it and the pane below; the lowest pane, the handle on the console's lower edge, by mouse or touch, up to the screen's height; the height dragged to stays while the app runs (not across restarts). Long records wrap; a wheel, a trackpad or a drag over them scrolls back through older ones, as far as `logging.buffer.capacity` keeps them. Scrolled up it keeps the lines read (`paused` in the console's header); at the bottom it follows the newest again |
| `spring.flutter.debug.console.width` | 0.2 to 1 | `1` | How much of a wide screen's width it takes (inside the safe area and the dock's margins), never under 360; a screen narrower than 600, a phone's, all of it |
| `spring.flutter.debug.console.segments` | list of names | `[fps, scene-fps, frames-lost, filter]` | The segments the build has: `fps`, `scene-fps`, `frames-lost`, `filter`, `signals`, `isolates`, `memory`, `timeline`, `net`, an application's own (`@ConsoleSegment`); `*` stands for every one. Read by the build (without a profile): a segment it does not name, without `*`, is not in the build, neither its module nor its code. Their order is the header's when `header` is not set |
| `spring.flutter.debug.console.header` | list of names | all of `segments` | The segments the header shows at the start, in order; `*` stands for the others of `segments`. A name that `segments` does not have fails the start. The debug panel's Console tab shows and hides them (a tap) and moves them (a drag, a long press on touch) while the app runs |
| `spring.flutter.debug.console.panes` | list of names | `[logs]` | The panes the build has: `logs` (the records, their selection and the `export` command), `commands` (the commands and their input line, with the application's `@ConsoleCommand` classes), `network` (with `debug.network.enabled`), `graph` ([the application graph](#the-application-graph), with a layer in the build), a starter's (`signals`: the application graph preset to the signals layer, from `spring_boot_starter_flutter_signals`), an application's own (`@ConsolePane`); `*` stands for every one. Read by the build (without a profile): a pane it does not name, without `*`, is not in the build, neither its module nor its code. Listed, `logs` is in only when named (or `*`); with it out, its view, selection and `export` command are no code in the app, and records still go to the log buffer (the panel's Logs tab and the `filter` segment are not affected). Empty: the header alone |
| `spring.flutter.debug.console.shown-panes` | list of names | `[logs]` when the build has it | The panes shown at the start, under the header by their order; `*` stands for all of `panes`; empty: the header alone. Not set: `logs` when the build has it, else none. A name that `panes` does not have fails the start. The debug panel's Console tab shows and hides them while the app runs |
| `spring.flutter.debug.console.history` | 0 to 1000 | `50` | How many lines typed into the `commands` pane up and down go back through |
| `spring.flutter.debug.console.filter.level` | `trace`, `debug`, `info`, `warning`, `error` | `trace` | The lowest level it shows at the start; the debug panel's Logs tab starts with it too |
| `spring.flutter.debug.console.filter.text` | text | empty | What a record's message or logger must contain, at the start |
| `spring.flutter.debug.isolates.enabled` | `true` / `false` | not set | The same as `debug.enabled`, for the task manager of the isolates and the engine's threads (`springBootStarterFlutterDebugIsolatesAutoConfiguration`): the panel's Isolates tab ([below](#the-isolates-tab)), with the app's memory and, on the web, what the page downloaded, and the console's `isolates` and `memory` segments |
| `spring.flutter.debug.isolates.interval` | duration | `1s` | How often it reads the loads and the memory while its tab or the `isolates` or `memory` segment shows; nothing is read, and the VM service is not connected to, while none does |
| `spring.flutter.debug.timeline.enabled` | `true` / `false` | not set | The same as `debug.enabled`, for the timeline of the start and the observations (`springBootStarterFlutterDebugTimelineAutoConfiguration`): the panel's Timeline tab and the console's `timeline` segment |
| `spring.flutter.debug.network.enabled` | `true` / `false` | not set | The network recorder and the panel's Network tab, a module of its own (`springBootStarterFlutterDebugNetworkAutoConfiguration`; beans `debugNetworkRecorder`, `debugNetworkJournal`, `debugNetworkSection`): only `true` puts it in the build, and only as far as the panel's switch (`spring.flutter.debug.enabled`, its parent) does, so with the panel not set it is in debug builds only and without the panel nowhere, unless the console has its `network` pane or `net` segment (modules `springBootStarterFlutterDebugConsoleNetworkPaneAutoConfiguration`, `springBootStarterFlutterDebugConsoleNetworkSegmentAutoConfiguration`, inside the console's switch instead of the panel's); not set or `false`, the app has none of its code. The recorder, a post-processor, wraps every `HttpTransport` and `WebSocketTransport` bean registered as that type alone (one injected by its own class too, such as a test's `MockHttpTransport`, is left as it is): the requests and frames pass through unchanged, and a copy goes to the journal, the `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `DPoP` and token headers, a `RestClientBuilder`'s `sensitiveHeaders`, the secret query parameters and an address's password masked as `******`. The tab ([below](#the-network-tab)) lists them. Set to `false` in a profile, it turns the recorder off in a running app whose build has it |
| `spring.flutter.debug.network.bodies` | `true` / `false` | `false` | Whether request and response bodies and WebSocket payloads are kept, cut at `body-limit`, the values of JSON keys that look secret (`password`, `access_token`, `apiKey`) and the secret parameters of a form masked. Off: their sizes only |
| `spring.flutter.debug.network.body-limit` | size | `64KB` | The most bytes of a body or a payload kept; a streamed body's first bytes, the rest only counted. At most `1MB`: a larger value is taken as `1MB` |
| `spring.flutter.debug.network.body-budget` | size | `4MB` | The most bytes of bodies and payloads kept in all, with `bodies`: past it, a new one keeps its size only, until old requests leave the journal (`max-entries`, Clear) |
| `spring.flutter.debug.network.max-entries` | 1 to 10000 | `200` | How many requests and WebSocket connections are kept; the oldest goes first |
| `spring.flutter.debug.network.max-frames` | 0 to 10000 | `200` | How many frames of each WebSocket connection are kept; the counts and sizes go on past it |
| `spring.flutter.debug.logs.export.enabled` | `true` / `false` | not set | The log export ([below](#the-log-export)), two modules of their own (`springBootStarterFlutterDebugLogsExportAutoConfiguration` inside the panel's switch, `springBootStarterFlutterDebugConsoleLogsExportAutoConfiguration` inside the console's; beans `debugLogExport`, `debugFileExports`, `plainDebugLogFormat`, `jsonLinesDebugLogFormat`, `browserDebugFileExport`, `downloadsDebugFileExport`): `true` in every build, `false` in none, not set in debug builds only, and in any case only as far as the panel or the console is in the build too; without either, or `false`, the app has none of its code. With the console's `commands` pane, a third module adds the `export` command ([the debug console](#the-debug-console)). Set to `false` in a profile, it turns the export off in a running app whose build has it |
| `spring.flutter.debug.graph.enabled` | `true` / `false` | not set | The panel's **Graph** tab, [the application graph](#the-application-graph): `true` in every build with the panel, `false` in none, not set in debug builds only; inside the panel's switch. Set to `false` in a profile, it turns the tab off in a running app whose build has it. The graph's engine comes only with a layer |
| `spring.flutter.debug.graph.layers` | list of names | `[*]` | The layers of the application graph the build has: `widgets`, `beans` (beans `beansGraphLayer` and `debugBeanGraph`, which follows the beans created and destroyed only while a view shows it), `signals` (from `spring_boot_starter_flutter_signals`), `*` for every one. Read by the build (without a profile): a layer it does not name is not in the build, its module, its bean and its code; with none, the Graph tab, the `graph` pane and the engine are no code in the app |
| `spring.flutter.debug.graph.hot.rebuilds` | 1 to 100000 | `3` | How many rebuilds within `hot.window` make a widget of [the widgets layer](#the-widgets-layer) hot: its node and the branch above it outlined in the debug theme's `graph-hot`, its tooltip telling why (`PageBackdrop: 14 rebuilds in 5 s`) |
| `spring.flutter.debug.graph.hot.window` | duration | `5s` | The window those rebuilds are counted in, and a widget's rebuild count in its card |

The panel lists its sections in a menu. On a screen at least 600 logical
pixels wide (the console's phone width, `DebugLayout.phoneWidth`) the
menu is a side menu on the left, always open, with the section shown in
the debug theme's accent and its content to the right; with the menu
focused (after a tap), the up and down arrows move the selection. On a
narrower screen, a phone's, the menu is closed: the button left of the
title opens it as a drawer over the content, and picking a section, a tap
on the scrim or a swipe to the left closes it (a swipe from the left edge
opens it). The panel opens again on the section last shown, with its
filters. The sections are listed under group headers, the groups in the
order of their first section:

| Group | Sections |
|---|---|
| Logs & state | Logs; Signals (signals starter) |
| Network | Network (with `spring.flutter.debug.network.enabled: true`) |
| Performance | Frames, Motion, Timeline, Isolates |
| App | Configuration, Beans, Graph, Start; Scenes (scene starter) |
| Tools | Theme, Overlays, Console, Flutter |

The sections:

| Section | What it shows |
|---|---|
| Logs | The records of the logging system's buffer (`logBuffer`), oldest first with the newest at the bottom, live, scrolling, each colored as the console colors it (the time and `:` faint, the level green, yellow or red, the logger cyan), by level and text (the `debugLogFilter` bean, kept while the panel is closed and shared with the debug console). The text selects and copies; records are picked whole, copied and [exported](#the-log-export) |
| Frames | The [frame meter](#the-app-widget) live with the times of build and raster, on or off over the app (compact there: one line, `60 (120 3D)`, over the strip of bars), and its corner, without a new build (the `debugFrameMeter` bean; "not in this build" when the module is left out) |
| Motion | Every animation of the app on or off (the `debugMotion` bean; "not in this build" when the module is left out) |
| Configuration | The active profiles and every property with the source that sets it; values of keys that look secret by the family's rule (`SecretNames`: `password`, `pwd`, `passwd`, `passphrase`, `secret`, `token`, `credential` and the like, no longer a plain `key`) show as `******`, and so do the password and the secret query parameters of a URL value |
| Beans | Every bean of the context with its type |
| Graph | [The application graph](#the-application-graph): every layer the build has (the signals starter's), one toolbar row (the layers' switches, the scope, Fit, `Options ▾`, `Groups ▾`, `Legend`), a card beside each node tapped; kept while the app runs; in the build only with a layer |
| Theme | The app's themes and `system`; a tap shows one. Under them, in a row of their own, the [debug themes](#debug-themes); a tap draws the debug tools in another at once |
| Start | When each stage of the start was reached |
| Isolates | The app's memory on top, what the page downloaded on the web, then every isolate and engine thread with its load ([below](#the-isolates-tab)); in the build with `debug.isolates.enabled` |

A section of your own is a `DebugPanelSection` bean, in the order of the
beans. Implement `GroupedDebugPanelSection` instead to list it under a
group, one of the above or one of your own; a section without a group is
listed under `Other`:

```dart
@Component()
@Order(100)
class CartSection implements GroupedDebugPanelSection {
  CartSection(this.cart);
  final Cart cart;

  @override
  String get title => 'Cart';

  @override
  String get group => 'App';

  @override
  Widget build(BuildContext context) => Text('${cart.items.length} items');
}
```

`DebugStyle.of(context)`, `DebugChip` and `DebugFilter` give a section the
panel's look. `debugPanel` (`DebugPanel`) is the panel's state: `toggle()`,
`close()`. The frame meter's state is `debugFrameMeter` (`on`, `position`), the animations' is `debugMotion` (`animations`).

### The debug console

One overlay for what the app does while it runs, instead of one per tool
(`spring.flutter.debug.console.enabled: true`; not set: no code). `true`
puts it in every build, a release build included: set it only in the
configuration of the builds that should have it. From top to bottom:

- **the header**, one line of compact segments, those of `header` at the
  start: numbers in the theme's primary color, states green, amber or red
  (`fps 60  3D 120  lost 0  logs all`);
- **the shown panes**, by their order, from the second on under a
  divider: the built-in `logs` (order 0, the records of the log buffer
  only, by the Logs tab's filter, `max-lines` high at the start; shown by
  default) and `commands` (order 10), a starter's (`signals` 20, `graph`
  25, `network` 30), the application's own;
- **the handle** on the lower edge.

With no pane shown the console is a strip, the header alone, its
background kept and no handle (nothing to stretch); a pane shown later
from the Console tab expands it again. A pane may add to the header's
right while it shows (`DebugConsolePane.buildHeader`: the `logs` pane's
`paused` and `Select`).

A divider moves the room between its two neighbours, the handle stretches
the lowest pane downwards or shrinks it (up to the screen's height), by
mouse or touch, none under its least. Every height stays while the app
runs, a hidden pane's too (`debugConsole.paneHeight(name)`, `resize`). A hidden pane is not built at all, and the next moves up.

**Pass-through and Interact.** The panes either pass the pointer through
to the app or interact, the whole console at once, the built-in panes, a
starter's and the application's alike, with nothing for a pane to do
(`debugConsole.interaction`, `DebugConsoleInteraction`):

- **Pass-through** (`interaction: pass-through`): every tap,
  scroll, hover and drag over a pane reaches the app under the console.
  Only the header (its segments, what the panes add to it: `Select`,
  `Copy`, `Clear`) and the dividers and the lower edge's handle take one.
  The panes' background is `pass-through-opacity` (0.7 by default), the
  app seen under it and the panes read; the header keeps its background
  (`opacity`), so the segments and buttons stay readable.
- **Interact**: each pane works as it does. The `logs` pane scrolls by a
  wheel, a trackpad or a drag (a plain tap on it still reaches the app
  until it selects) and selects; a `network` row takes a tap; the graph
  pans, zooms and selects; the input line types. The backgrounds are of
  `opacity`, or a pane's own `backgroundOpacity`.

The toggle at the right of the header, after what the panes add
(`Pass-through` or `Interact`, in a box of at least 44 by 44 for a
finger), switches it; it shows while a pane does (a strip has nothing to
pass through). On macOS, Windows and Linux ⌥ (Alt) held makes the panes
interact while held (`Interact ⌥`), without switching; a phone has the
toggle alone, no gesture. Starting the records' selection (`Select`, a
long press, a click with ⇧, ⌘ or Ctrl) or focusing the input line
switches it to Interact, so what was started with ⌥ held stays under the
finger after ⌥ is let go. It does not switch back when that ends: the
panes do not change under the pointer, and the toggle is one tap away.
A pane's `backgroundOpacity` counts in Interact only: passing through,
the point is to see the app, and one opacity for every pane says what
shows. The state lives on the `debugConsole` bean while the app runs and
starts as `interaction` says. The debug panel is always interactive.

**Selecting records.** The `logs` pane selects as the Logs tab does, without
taking the app's taps: while the panes interact (or ⌥ is held), a long
press on a record, or a click on one with ⇧, ⌘ or Ctrl, marks it and
starts the selection; `Select` at the right of the header starts it
without a mark, in either mode. Either switches the panes to Interact. While it lasts the records take taps
(a tap marks or unmarks one), their text selects by a mouse drag or a
double tap and copies with ⌘C (Ctrl+C) or its context menu, new records
wait under the ones read, and the header's right shows `N marked · Copy ·
.log · .jsonl · Clear`: Copy puts the marked records on the clipboard as
the console prints them, without colours, `.log` and `.jsonl` (with the
[log export](#the-log-export)) export the marked records, else those the
filter shows, and Clear ends it (`logsPane.selecting`, `marks`).
Before and after, every tap on the pane goes through to the app, and
beside the panes always. The selection follows the pane: in the header
only while it shows, in the build only with it.

With the log export, the `logs` pane and the `commands` pane in the build, the command
`export [log|jsonl]` (`exportCommand`, `log` by default) exports the
marked records, else those the filter shows, and prints where the file
went; `help` lists it. Its module
(`springBootStarterFlutterDebugConsoleExportCommandAutoConfiguration`) is
in the build only when `panes` names `commands` and lets `logs` in
(inside the console's switch) and `spring.flutter.debug.logs.export.enabled`
lets the export in.

The debug panel's **Console** tab (under `Tools`) switches each segment
and each pane the build has on and off, live, `logs` included (every pane
hidden leaves the header alone), and moves a segment left or right in the
header. A switch is selected exactly while its pane (segment) shows,
whatever changed it: the start, another switch, a command calling
`showPane`. The state lives on the `debugConsole` bean while the
app runs (`showSegment`, `moveSegment`, `showPane`); it starts as `header`
and `shown-panes` say. The tab is in the build only with the panel and
the console.

```yaml
spring:
  flutter:
    debug:
      console:
        enabled: true
        segments: [fps, scene-fps, frames-lost, filter, signals]  # built
        header: [fps, signals]          # shown at the start
        panes: [logs, commands]         # built; not set: [logs]
        shown-panes: [logs]             # shown at the start; [] the header alone
        history: 50
        interaction: interact           # or pass-through; the toggle in the header
        pass-through-opacity: 0.7       # the panes' background while passing through
        slide-duration: 220ms           # its slide in and out; 0: at once
```

| Segment | Shows | From | In the build by default |
|---|---|---|---|
| `fps` | The frames a second Flutter draws, `idle` when none | the console | yes |
| `scene-fps` | The frames a second the 3D scenes draw, only while one moves | the scene starter (with `spring.flutter.scene.enabled`) | yes |
| `frames-lost` | How many frames of the last second were over the budget (`spring.flutter.frame-meter.target-rate`): green none, amber, red one over twice | the console | yes |
| `filter` | The level and text the records show by | the console | yes |
| `signals` | Ticks, flushes and effect runs of the last frame (`signals 3 ticks · 1 flush · 2 effects`) | the signals starter | no |
| `isolates` | How many isolates and engine threads, and how busy the busiest is | the console; values with `debug.isolates.enabled` | no |
| `memory` | The process's resident memory natively, the JavaScript heap on the web (`mem`), and Flutter's image cache (`img`): `mem 182 MB · img 34 MB`; read once a second only while the console shows it | the task manager; in the build only with `debug.isolates.enabled` on too (not set: debug builds only) | no |
| `timeline` | How long the start took until the app showed | the console; values with `debug.timeline.enabled` | no |
| `net` | The requests in flight, those that got no response (`failed`: a transport error, a timeout, an abort; red), those answered with a `4xx` or `5xx` (`errors`: a 403 is a response, not a failure; amber), a zero muted, and the last heartbeat round trip of the newest open WebSocket when it has one (`net 2 in flight · 0 failed · 1 error · 45 ms ws`) | the network recorder; in the build only with `debug.network.enabled: true` too | no |

| Pane | Shows | In the build by default |
|---|---|---|
| `logs` (order 0) | The records of the log buffer, newest at the bottom, colored as the console colors them, wrapped, by the Logs tab's filter; scrolls back through the buffer (`paused` in the header), follows the newest at the bottom; its selection and `Select` in the header while it shows | yes (`panes` not set) |
| `commands` (order 10) | What the commands printed, with a scroll of its own: the line typed (dim), what a command printed, an error (red), `help` in two aligned columns (the command and its arguments orange by default, then what it does); at its bottom the input line: while it has the focus it takes every key typed (nothing reaches the app), Enter runs the line, up and down go through the last `history` lines, Escape gives the focus back | no |
| `network` (order 30) | The network recorder's requests, one line each, newest at the bottom (`GET  /api/user  200  120 ms  1.2 KB`): the method in the debug theme's `method-read` or `method-write`, the status `good`, `warning` or `bad`, a time of a second or more in `warning`; a WebSocket on one line with its uptime and last heartbeat round trip. Scrolled up it stops following and keeps the lines read (`paused` under them), back at the bottom it follows again. A tap shows the line in one line under them (the whole address, first byte, total, sizes, error; a WebSocket's handshake, uptime, heartbeat, reconnects, frames), with a hint to the panel's Network tab when the build has it | no; in the build only with `debug.network.enabled: true` too |
| `graph` (order 25) | [The application graph](#the-application-graph) of every layer the build has, compact, on the console's own background (none while passing the pointer through): one toolbar row of short labels (full names in tooltips), the legend behind `Legend`, a card beside each node tapped; kept while the app runs, apart from the Graph tab | no; in the build only with a layer (`debug.graph.layers`) |
| `signals` (order 20) | The application graph preset to the signals layer (from `spring_boot_starter_flutter_signals`), compact | no |

| Command | Does |
|---|---|
| `help [command]` | Lists every command, the application's included, or tells of one |
| `export [log\|jsonl]` | Exports the records marked in the `logs` pane, else those its filter shows (with the `logs` pane and the log export) |

`help` is the one command built in; the application adds its own, and one
of the same word replaces it.

**What is not shown is not built.** Each segment and each pane, the
framework's, a starter's and an application's, is in the build only with
the console and when `segments` (`panes`) names it or holds `*` (`segments`
not set names the four of its default, `panes` not set names `logs`). The
commands, the framework's `help` and the application's `@ConsoleCommand`
classes, come with the `commands` pane. The generator reads `segments`
and `panes` from `application.yml` or `application.properties` without a
profile; what they leave out has no module, no bean and no code in the
app. `header` and `shown-panes` only say what shows at the start, and a
name in them that the build list lacks fails the start with the two keys
named. Each built-in segment and pane is a module of its own whose switch
is `AutoConfigurationBuild.named('spring.flutter.debug.console.segments',
'<name>')` (`panes`) with the console's switch as its parent.

#### Segments, panes and commands of your own

The segments are `DebugConsoleSegment` beans, the panes
`DebugConsolePane` beans, the commands `DebugConsoleCommand` beans. An
application's own is a class with `@ConsoleSegment`, `@ConsolePane` or
`@ConsoleCommand`, injected like any bean. One rule names each: the
annotation's name when there is one, else its `name` getter
(`String? get name`, `null` by default), for one registered as a plain
bean or made by hand. The class need not repeat the annotation's name; a
getter that says another fails the build (one the build cannot read, a
value made at run time, fails the start), and a bean with neither fails
the build. The framework's own carry the annotation in their bean
definitions and have no getter. A command's `usage` is only what follows
its word (`'[command]'`; `help` prints `help [command]`).

The generator registers the class only in the application's debug part
(`main.spring.debug.dart`): a segment when the build has the console and
`segments` names it or holds `*`, a pane when `panes` does, a command when
the build has the `commands` pane. Otherwise nothing refers to the class
and the compiler leaves it out. The build fails for a bean of the app that
injects one, an extension that injects one the build leaves out, and a
getter that disagrees with the annotation.

**A pane** (`DebugConsolePane`) has:

| Member | Default | What |
|---|---|---|
| `String? get name` | `null` | Its name when no `@ConsolePane` gives one |
| `String get title` | (required) | What the Console tab's switch says |
| `double get minHeight` | one line (`DebugConsoleView.lineHeight`) | The least it is high when dragged or squeezed |
| `double get initialHeight` | six lines | How high it starts, until dragged |
| `double? get backgroundOpacity` | `null`: the console's `opacity` | How opaque its background is, 0 to 1, while the panes interact. Passing the pointer through, every pane's is `pass-through-opacity` |
| `void Function() start()` | does nothing | Runs when the pane shows; what it returns runs when it hides or the console does |
| `Widget build(BuildContext, DebugConsole)` | (required) | The pane, given its height and the console's width |
| `Widget? buildHeader(BuildContext, DebugConsole)` | `null` | What it adds at the right of the console's header while it shows (the `logs` pane's `paused` and `Select`) |

`@ConsolePane('name', order: n)` places it among the shown panes, top to
bottom (`logs` is 0, `commands` 10, `signals` 20, `graph` 25, `network` 30). The
console's background is behind every part of it, the header and each
shown pane with its divider and the lower edge's handle, each painting
its own, of the console's `opacity` unless the pane gives its
`backgroundOpacity` (while the panes interact; passing the pointer
through, of `pass-through-opacity`). A pane has nothing to do for
Pass-through: the console keeps every pointer from it then. Keep a hidden pane free: start listening in
`start`, stop in what it returns, and the console builds nothing of it
while hidden. Draw again at most once a frame (a `ListenableBuilder` over
what notifies at most once a frame, or a frame callback), and take the
colors and fonts from the debug theme (`DebugStyle.of(context)`: `code`,
`foreground`, `muted`, `number`, `good`, `warning`, `bad`, `accent`).

```dart
// In the build with panes: [logs, commands, uploads] (or '*').
@ConsolePane('uploads', order: 20)
class UploadsPane extends DebugConsolePane {
  UploadsPane(this.uploads);
  final Uploads uploads;            // a ChangeNotifier

  @override
  String get title => 'Uploads';

  @override
  double get initialHeight => DebugConsoleView.lineHeight * 4;

  @override
  void Function() start() => uploads.watch();   // returns the stop

  @override
  Widget build(BuildContext context, DebugConsole console) {
    final style = DebugStyle.of(context);
    return ListenableBuilder(
      listenable: uploads,
      builder: (context, _) => ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final upload in uploads.waiting)
            Text(
              '${upload.name}  ${upload.percent}%',
              style: style.code.copyWith(color: style.foreground),
            ),
        ],
      ),
    );
  }
}

// In the build with segments: [fps, queue] (or '*').
@ConsoleSegment('queue', order: 50)
class QueueSegment extends SampledDebugConsoleSegment {
  QueueSegment(this.uploads);
  final Uploads uploads;

  @override
  DebugConsoleValue read() =>
      DebugConsoleValue('${uploads.waiting.length}', label: 'queue');
}

// In the build with the commands pane.
@ConsoleCommand('retry')
class RetryCommand extends DebugConsoleCommand {
  RetryCommand(this.uploads);
  final Uploads uploads;

  @override
  String get usage => '';

  @override
  String get help => 'Sends the failed uploads again.';

  @override
  Future<List<String>> run(DebugConsoleCall call) async =>
      ['${await uploads.retry()} sent'];
}
```

A starter's pane is a bean definition in a module of its own, with the
annotation in the definition and the console's switch as its parent:

```dart
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.console.panes',
    'uploads',
    whenMissing: BuildInclusion.never,
    parents: [
      AutoConfigurationBuild(
        'spring.flutter.debug.console.enabled',
        whenMissing: BuildInclusion.never,
      ),
    ],
  ),
)
final BeanModule uploadsConsolePaneAutoConfiguration = BeanModule(
  'uploadsConsolePaneAutoConfiguration',
  [
    BeanDefinition<UploadsPane>(
      name: 'uploadsPane',
      types: const [UploadsPane, DebugConsolePane],
      annotations: const [ConsolePane('uploads', order: 20)],
      create: (r) => UploadsPane(r.dependency<Uploads>()),
    ),
  ],
);
```

A command that lists commands prints rows with
`call.printUsage(word, usage, help)`: the rows line up in columns, as
`help`'s do.

### The log export

The Logs tab selects text across its records, by mouse or touch (a double
tap on a phone), and copies it with ⌘C (Ctrl+C) or the Copy of its context
menu (a right click, or the menu over a selection). A long press on a
record, or a click with ⇧, ⌘ or Ctrl, marks the whole record and starts
the pick mode: a tap marks or unmarks another, the count of marked records
shows over the list, Copy puts them on the clipboard as plain text in the
console's pattern (`logging.pattern.console`) without its colours, and
Clear selection ends the mode.

With the export in the build (`spring.flutter.debug.logs.export.enabled`,
not set: debug builds only, with the panel or the console), the tab
has `Export .log` and `Export .jsonl`. They export the marked records, or
every record the filter shows when none is marked, oldest first:

| Format | Content |
|---|---|
| `.log` | Each record as the console prints it, in its pattern, no ANSI colours; the error and stack trace on the lines after when the pattern prints them |
| `.jsonl` | One JSON object a line: `time` (ISO-8601, UTC), `level` (`INFO`, `WARN`), `logger`, `message`, `error`, `stack` (`null` when there is none) |

The file is named `<app>-logs-<yyyyMMdd-HHmmss>.<ext>`, the app being
`spring.application.name`, else `spring.flutter.app.title`, else `app`.
It is made on the UI isolate in slices of at most 4 ms, each followed by a
turn of the event loop, on every platform alike, the web included, so a
full buffer never holds a frame. Not in an isolate: a record carries its
error and stack trace, any object, which would have to become text before
it could be sent, and that is most of the work.

Where the file goes is the first `DebugFileExport` bean, by `@Order`, that
is `available` (`debugFileExports`); one that throws hands the file to the
next. What it returns shows in the tab for a few seconds. The built-in ones
come last:

| Exporter | Where | What the tab says |
|---|---|---|
| `BrowserDebugFileExport` | the web: a browser download (a `Blob` behind an `<a download>`) | `Downloaded <file>` |
| `DownloadsDebugFileExport` | macOS, Windows, Linux: the Downloads folder (`path_provider`'s `getDownloadsDirectory`; a sandboxed macOS app writes into its container's unless it has the `com.apple.security.files.downloads.read-write` entitlement) | `Saved <path>` |
| none | anywhere else, iOS and Android included: nothing leaves the app, the tab says what to add | `No file export here: add a DebugFileExport bean (a share sheet), or ClipboardDebugFileExport to copy the text to the clipboard` |

`ClipboardDebugFileExport` (the file's text on the clipboard, `<file> copied
to the clipboard`) is not a built-in one: other apps can read the
clipboard, so it is there only when the app registers it as a bean.

On a phone, a share sheet is a bean of the app, with `share_plus` in the
app's own pubspec (the starter does not depend on it):

```dart
@Component()
@Order(0)
class ShareDebugFileExport implements DebugFileExport {
  @override
  bool get available => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Future<String> export(String fileName, Uint8List bytes, String mimeType) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
      fileNameOverrides: [fileName],
    ));
    return 'Shared $fileName';
  }
}
```

A format of your own (a CSV) is a `DebugLogFormat` bean (`extension`,
`mimeType`, `format(record)` ending with a line break): the tab has a
button for it. Any button is a `DebugLogsActions` bean, whose `actions`
get the records the tab would export. `debugLogExport.exportRecords(records,
format)` exports from code (the console's `export` command calls it), and returns what
to tell the user; `debugLogExport.format('jsonl')` finds a format by its
extension.

### The Isolates tab

The task manager's tab (`spring.flutter.debug.isolates.enabled`, under
Performance) scrolls as one: the memory, the size, then every isolate and
engine thread with its load.

**Memory.** A card per number, large in the debug theme's `number`
colour, what it is measured against, a chart of the last three minutes
(scaled so a change of a few megabytes shows) and one muted line of what
the number is:

| Card | Native (debug, profile) | Native release | Web |
|---|---|---|---|
| Process (RSS) | all the memory the system holds for the app | yes | — |
| Dart heap | the UI isolate group's heap, used and capacity, from the VM service | "not available: no VM service" | — |
| JS heap | — | — | used, total and limit (`performance.memory`); "this browser does not tell" outside Chromium. A `--wasm` build keeps its Dart objects here too |
| Image cache | bytes of the maximum, images of the maximum, live and pending (`PaintingBinding.instance.imageCache`) | yes | yes |

The VM service is connected to when the tab (or the `memory` segment)
shows and let go of when neither does, over one WebSocket and one call
(`getMemoryUsage`); no package is added for it. A `MemoryFigureSource`
given to `DebugIsolates(memory: DebugMemoryWatch(sources: ...))` adds a
card of the application's own.

**Size.** On the web, what the page downloaded, from the browser's
Resource Timing: the bytes transferred (`transferSize`, `0` from the
cache) and decoded (`decodedBodySize`) in all, the totals by kind
(`code`: scripts, WebAssembly, CSS, the page; `fonts`; `images`;
`other`; the list is `pageResourceKinds`) and the ten heaviest. A download
from another origin without `Timing-Allow-Origin` reports `0`: it is
marked `hidden`, and their number is said above the lists. The browser
keeps 250 entries unless raised; the block raises the buffer when it first
shows, and says so when entries were dropped before (a debug build loads
more scripts than that before the app starts). Read when the tab opens and
on Refresh. Natively the block says: build size on the web only; use
`flutter build <platform> --analyze-size`.

**Cost.** Nothing is read while neither the tab nor the `memory` segment
shows: no timer, no connection. With `debug.isolates.enabled: false`, or
in a profile or a release build without it set, none of this is in the app.

### The network tab

With `spring.flutter.debug.network.enabled: true` (in a build with the
panel), the debug panel has a Network group with one tab. It lists the
requests of the app's `HttpTransport` beans and the connections of its
`WebSocketTransport` beans, newest first: `RestClient` and the HTTP
service clients, the OAuth2 client, Supabase, the WebSocket starter's clients and Phoenix channels,
the themes and resources downloaded from a URL, and the app's own calls
through those beans. No client is changed: a post-processor puts a
recording decorator around each transport bean.

```yaml
spring:
  flutter:
    debug:
      network:
        enabled: true      # read by the build: no code without it
        bodies: true       # off by default: sizes only
        body-limit: 16KB
        max-entries: 500
```

- **A row**: the method (`WS` for a WebSocket), colored as a method that
  reads or one that writes (the debug theme's `method-read` and
  `method-write`); the path and query; the status in the theme's `good`
  (`1xx` to `3xx`, a WebSocket open or closed normally), `warning`
  (`4xx`) or `bad` (`5xx`, no answer); the time (a WebSocket's uptime);
  the bytes received. Under it, its bar in a waterfall: one time scale
  for the rows shown, from the first request's start to the last one's
  end, so overlapping requests overlap and a slow one stands out. The
  wait for the first byte is muted, the rest in the accent, `warning` from
  one second, `bad` when it failed, lighter while in flight (it grows to
  now). A WebSocket does not stretch the scale (its bar runs past the
  end); its row adds a line: the handshake time, the uptime, the last
  heartbeat round trip and the reconnects. While anything is in flight
  the tab refreshes once a second.
- **Filters**: a chip per method (`GET`, `POST`, `PUT`, `PATCH`,
  `DELETE`, `WS`), a chip per status class (`2xx`, `3xx`, `4xx`, `5xx`,
  `Failed`, `Pending`), a line over the address. Pause stops recording
  new requests (those in flight still complete), Clear empties the
  list. The filter stays while the panel is closed.
- **A request opened**: the whole address, the status, when it started,
  the time to the first byte, the total, the bytes sent and received,
  the error, a phase breakdown (each phase's length and its bar), the
  request's and the response's headers, and with `bodies` the bodies,
  JSON indented when it was kept whole. A WebSocket shows when it
  started, the handshake time, when it connected, its uptime (to now, or
  to the close), its reconnects (which connection to that address it is
  since the start or the last Clear, a failed attempt counted), when it
  closed, its close code and reason and which side closed it, the frames
  and bytes each way, the channels joined, its heartbeat round trips (the
  last 60 as bars, with the last, least, mean and most), and its last
  `max-frames` frames: the direction, the time from the start and by the
  clock, the size, a label (a Phoenix `join room:lobby`, `leave`,
  `close`, `error`, `heartbeat`, `heartbeat reply 23.4 ms`) and with
  `bodies` the payload.

The timings of a request, and where they come from:

| Timing | Streamed (`stream`) | Whole (`send`) |
|---|---|---|
| Total | measured | measured |
| First byte (status and headers) | measured | the browser's, if available; else none |
| Waiting, then body | measured | the browser's, if available |
| Redirect, queued, DNS, TCP, TLS, waiting, download | the browser's, if available | the browser's, if available |

`send` gives the response whole, and no transport says when its headers
came. The recorder does not send it through `stream` to find out: their
timeouts differ (`timeout` and `readTimeout` cover the whole exchange of
`send`, the headers only of `stream`), and so do their errors, so the
caller would get another result. Name lookup, connection and TLS times
come from neither `dart:io` nor `fetch`. On the web the recorder reads the
browser's Resource Timing entry of the request's address once the response
is done (a `PerformanceObserver`, which sees every entry; the browser's
own list stops at 250, which a debug build fills with its scripts before
the app starts). "If available": a response from another origin shows its
phases only when it sends `Timing-Allow-Origin` (else the detail says the
browser hides them); two requests to one address at the same moment may
get each other's. On mobile and desktop there is none.

A WebSocket's heartbeat round trip is the time from a heartbeat sent to
its reply, matched by its `ref`: Phoenix's `heartbeat` on the `phoenix`
topic and its `phx_reply` (the WebSocket starter's channels, Supabase
Realtime). A `WebSocketPingMatcher` in a `WebSocketTransportDecorator`
bean finds another protocol's.

What is masked before anything is kept: the headers by
`HttpSecrets.isSensitiveHeader` (`Authorization`, `Proxy-Authorization`,
`Cookie`, `Set-Cookie`, `DPoP`, `X-Amz-Security-Token`, a name with
`session`, a name `SecretNames` finds secret such as `X-Api-Token` or
`apikey`) and the request's own `sensitiveHeaders` (a `RestClientBuilder`'s
`sensitiveHeaders`); an address's password and its query parameters by
`HttpSecrets.isSensitiveParameter` (`code`, `state`, `access_token`,
`apikey`, `signature`...); in a body kept, the values of JSON keys that
look secret and the secret parameters of a form. A `NetworkBodyMasker`
bean masks a format of the app's own, before the built-in ones.

A streamed response (`HttpTransport.stream`: server-sent events, a
download) is never gathered: its body goes to the caller chunk by chunk
as the caller reads it, paused and cancelled with it; each chunk is
counted, and with `bodies` its first `body-limit` bytes copied. The
request is done when the caller has read to the end, stopped reading or
seen the body fail.

The journal (`debugNetworkJournal`, a `ChangeNotifier`) tells its
listeners at most once a frame, and only while something listens: with
the panel closed, recording is a few fields per request.

The [debug console](#the-debug-console) has a view of it too: the
`network` pane and the `net` header segment, each in the build only when
the console's `panes` (`segments`) names it or holds `*`, and with
`spring.flutter.debug.network.enabled: true` (the recorder's switch, the
panel not needed). Either makes the recorder and the journal when the
panel's tab has not; with both, they share one. Hidden, neither listens
nor draws.

```yaml
spring:
  flutter:
    debug:
      network:
        enabled: true
      console:
        enabled: true
        segments: [fps, net]
        panes: [network]
        shown-panes: [network]
```

A compact view of its own
reads its `entries`, its `summary` (in flight, the requests in flight,
failed, bytes, open WebSockets, the last heartbeat round trip of the
newest open one) and a `DebugNetworkFilter` of its own. A
`WebSocketFrameLabeler` bean names the frames of a protocol of the app's
own, a `NetworkTransportDecorator` bean records a transport of another
kind; both are asked before the built-in ones.

A transport bean is wrapped only when it is registered as the transport
type alone (`BeanDefinition<HttpTransport>`, a `@Bean` method returning
`HttpTransport`, the starters' own). One registered under its own class
too (a `@Component` transport, a test's `MockHttpTransport` bean) is left
as it is, so what asks for that class still gets it; the recorder says
so at `debug` level.

### The application graph

The app as one graph, in the debug panel's **Graph** tab (under `App`) and
the console's `graph` pane: each **layer** a bean that gives nodes and
edges of one colour, each kind of node of a layer in a shape of its own.
The starter gives the `widgets` layer ([below](#the-widgets-layer): the
application's widgets as a tree, their rebuilds) and the `beans` layer
([below](#the-beans-layer): the application's beans by module and what
injects what), and the signals
starter the `signals` layer (its `@Signal` fields, `@Computed` values and
`@Effect` methods, a lane per bean, and the widgets that read them); the
next layers draw on the same engine.

```yaml
spring:
  flutter:
    debug:
      graph:
        enabled: true          # the Graph tab; not set: debug builds only
        layers: [beans, signals]  # the layers built in; not set: every one
      console:
        enabled: true
        panes: [logs, graph]   # the graph pane (or signals: the signals layer alone)
        shown-panes: [graph]
```

Above the graph, one toolbar row (it wraps in the panel; in the console
the labels are short and the pointer over a button tells its full name):

- the switches of the layers, each with a square of its colour (filled
  while the layer shows), the scope (**On screen**, **All**) and **Fit**;
- **Options ▾**, a menu of checkboxes for what is changed rarely: **Live
  only**, `Close all cards`, and under each layer's title its own options
  (the beans layer's `framework` and `skipped`, the widgets layer's
  `framework widgets`, `DebugGraphLayer.options`) and single choices, a
  radio row per value (`DebugGraphLayer.choices`, as a `Group by`);
- **Groups ▾** (with lanes), the lanes to show, each with what touches
  it: a search field (a part of the title, any case), `all` first, the
  groups chosen last next, then the others, each a checkbox, built row by
  row so hundreds scroll smoothly; the button tells the state
  (`Groups: all`, `Groups: 3`);
- **Legend**, which opens the legend over the graph: each layer in its
  colour with an entry for each kind of node in its shape, its pulse
  (what a flash means: `a signal ticked or an effect ran`, `a widget
  built`, `an instance was created or destroyed`) and the widgets layer's
  hot outline (`rebuilt 3+ in 5 s`; the branch above a hot widget is
  outlined too). The entries stand in two columns where the legend has
  room, an entry too long for half the width on a row of its own. An
  entry is **selectable**: a tap highlights its nodes (a border and a
  glow in the theme's accent) and dims the others, several may be
  selected, a second tap unselects one, `Clear` all; the pointer over an
  entry (a long press on a touch screen) tells how many of its nodes the
  graph shows and what it is, in a line of two rows' fixed height under
  the entries, so they never move while the pointer passes. The wheel
  over the legend scrolls only the legend, never the graph under it.

A tap on a node selects it and lights its chain; a **double tap** (a
double click) opens its **card** beside it, open with its labelled rows,
and closes it again; a double tap on another node opens another card
(several may be open). A card's rows tell what its layer knows (`Basket ·
coupon  'FIVE' · 2 s ago · 3 changes · 1 write`), wrapped, and a row may
list nodes under it (`DebugGraphDetail.links`): a row whose node is on the
graph selects it. `×` closes a card, `Close all cards` (Options) closes
them all. A card follows its node as the graph pans and zooms. A lane
folds by a tap on its title (`[-]` / `[+]`).

**What a view keeps.** Its layers, scope, "Live only", the groups chosen,
the lanes, branches and repeats folded or opened, where the graph is (pan
and zoom), the legend's selection and the cards open are kept while the
app runs on a bean (`DebugGraphMemory`), so a view opens again as it was
left: the panel's Graph tab on `debugGraphSection.memory`, each console
pane on its own (`debugGraphPane.memory`, `signalsPane.memory`), the
Signals tab on `signalsGraphLayer.viewMemory`. A layer's options are on
the layer's bean, shared by every view.

- **Layout.** Left to right in columns by the longest path, the nodes
  that only read last, ordered to cross few edges; a layer may ask for
  another layout (`DebugGraphLayer.layout`; `TreeDebugGraphLayout` draws a
  tree top to bottom). A group is a **lane**: a band across every column
  with its title at the left; a tap on the title collapses the lane into
  one node (`Basket (6)`) and back. **Repeats** (nodes of one lane with one
  repeat key, as the widgets of one type) fold into one node,
  `PlayerReviews ×10`, until it is tapped open; the card's chip folds
  them back. Arrows on the edges; a tap on a node highlights everything
  before and after it, the rest dimmed.
- **Auto** (on by default): the graph fits its room whenever it or the
  room changes: the first time a view opens, a pane's height (a divider,
  the console's handle, a pane shown or hidden beside it), a window
  resized, the "On screen" nodes changing as the app scrolls. A pan or a
  zoom by the user turns Auto off; from then on nothing moves or zooms
  the graph by itself (not a tap, a selection, a card, a fold, a filter,
  layers switched, a refresh, a flash, the panel or the console opened
  again: the view opens where it was left), until Auto is turned on
  again. **Fit** (and ⌘⇧Z, the action `debug.graph.fit`) fits once. In
  the panel's Graph tab and in a console pane (`graph`, `signals`) the
  graph is as wide as its room, centred across and at the top; a small
  graph keeps its size (`DebugGraphView.fit`: `DebugGraphFit.width`,
  `DebugGraphFit.whole`). With Auto off, when the layout changes, the graph is shifted so that
  the node tapped (else one with a card, else the one nearest the middle)
  stays where it was on the screen. When a smaller room would leave the
  graph wholly out of sight, its edge is pulled back into view, the zoom
  kept; this changes only what is shown, not the place kept, so in a room
  big enough again the graph is where it was. A wheel or a drag pans, ⌘
  or Ctrl with the wheel and a pinch zoom; the wheel is the graph's
  alone, nothing around it scrolls (the graph never sits in a scroll
  view).
- **Scope.** *On screen* (the default): the nodes of the widgets whose
  box is in the app's window (not offstage, not transparent, not scrolled
  out of a list; the debug panel over the app does not hide them), every
  node they read up the graph, and the nodes that listen to the same
  sources without feeding a widget (an effect). *All*: every node. **Live
  only** (off by default) hides the nodes that did not change, run or
  build in the last five seconds. **Groups** keeps the lanes chosen and
  what touches them. "On screen" and "Live only" are read again three
  times a second while the graph shows.
- **Light.** A node that changes or runs flashes: a brighter border, a
  glow and at most a quarter of the debug theme's `graph-flash` in its
  fill, never a solid fill; a pulse runs along its edges to its readers,
  fading in a second. A **hot** branch (a widget that rebuilt
  `spring.flutter.debug.graph.hot.rebuilds` times or more within
  `….hot.window`, 3 in 5 s by default, and the branch above it) is
  outlined in `graph-hot`, the links between too. The pointer over a node
  shows its tooltip, a hot one's first line telling why
  (`PageBackdrop: 14 rebuilds in 5 s`, `above PageBackdrop: …` for the
  branch above it).

**Colours.** Each layer's nodes are in a key of the debug theme
([below](#debug-themes)), so a node's layer reads at a glance:

| Key | Default | What |
|---|---|---|
| `graph-beans` | `good`'s green | The beans layer's nodes |
| `graph-widgets` | `logger`'s cyan blue | The widgets layer's nodes |
| `graph-signals` | `command`'s orange | The signals layer's nodes |
| `graph-hot` | terminal magenta | The outline of a hot branch; a hue no layer has, so a hot node reads apart from an orange signal and from a warning |
| `graph-flash` | terminal yellow | What lights a node that changed or ran, and the pulse along its edges |
| `graph-<layer id>` | a colour of the theme's palette, picked by the id | A layer of the app's (`graph-routes`); the palette keeps apart from the colours above |

**What it costs.** The graph is laid out only when what it shows changes
(a node, an edge, a filter, a fold), never for a value or a flash: 300
signal nodes in about 4 ms and a tree of 2000 widgets in about 1 ms in a
JIT benchmark (`spring_boot_starter_flutter/benchmark/debug_graph_benchmark_test.dart`).
The still picture is recorded once per layout, and while something glows
only the lit nodes and pulses are painted over it, at most once a frame.
The layers collect only while a view shows (`start`); hidden, there is no
timer, listener or probe. **What is not shown is not built:** the engine
has no module of its own; each layer's module brings the Graph tab
(`debugGraphSection`) and, with the console, the `graph` pane
(`debugGraphPane`), so with no layer in the build none of the engine's
code is in the app. A layer is in the build by its own switch
(`AutoConfigurationBuild.named('spring.flutter.debug.graph.layers',
'<id>')`), the tab inside `spring.flutter.debug.graph.enabled` and the
panel's switch, the pane inside the console's.

#### Lanes by route or by module

`Group by` in the graph's `Options` picks what the lanes are: **Route**
(the default) or **Module**. With *Route* the lanes are the navigator
stack, top to bottom:

1. **the current screen** (`/m/9102782543 · MatchScreen`, the page's name
   and its first widget of the application): its widgets, the beans of its
   route scope (`@Scope(NavigationScopes.route)`) and their signals;
2. **the dialogs and sheets** over it, one lane each, while open;
3. **the screens under it**, the nearest first, shown in *All* and hidden
   in *On screen*;
4. **App**: the singletons and their signals, and the widgets above the
   navigator (a shell's, a layout's, a header).

A widget is in the lane of its route, `App` above every navigator; a
route that holds a navigator of its own (a `@RouteShell`) is no lane, its
widgets are `App`'s and its navigator's screens take its place. A bean of
a route scope is in the lane of the route it lives in (the topmost, when
it lives in several), a singleton in `App`, with its edges to the widgets
of the screens that inject it; a bean of a route scope that lives in no
route has no lane. Signals go with their bean, a widget that read them
with its route. The group filter lists the lanes by role,
`Current · Dialog · Below (n) · App`. On a navigation the lanes are read
again: the beans of the screen that closed flash in its lane as they are
destroyed, then leave it; those of the new screen flash as they are
created. With *Module* the lanes are the layers' own: the beans by module,
the signals by bean, the widgets one tree.

The stack is read from Flutter's own tree, so any navigator counts (the
navigation starter's, a `MaterialApp`'s, a nested one): each entry of a
navigator's overlay is a route's, the routes under an opaque one are
offstage; the top page shown is the current screen (without pages, the
lowest route shown), the routes over it dialogs, those under it below. A
route is named through `ModalRoute.settingsOf`, a dependency that never
rebuilds the widget. Which route a bean lives in comes from the
`DebugGraphRouteBeans` beans: the navigation starter's
`routeScopesGraphBeans` is one, a bean of its debug modules (no code
without the graph), answering from the route scopes at each call.

For a layer of your own, the engine's part is general: a node whose group
has an order (`DebugGraphNode.groupOrder`) is in a lane of the graph's
own, shared by every layer that names the group and placed by that order
before the layers' lanes, with a role (`groupRole`:
`DebugGraphGroupRole.current`, `dialog`, `below`, `app`) that the group
filter reads and that hides `below` in *On screen*; `repeatScope` narrows
its repeats inside the lane (the widgets of one type under one parent).
`debugGraphRoutes` (`DebugGraphRoutes`) holds the choice and gives the
lanes: `stack.routes`, `laneOf(element)`, `beanLanes()`;
`TreeDebugGraphLayout(banded: true)` draws a tree in each lane.

**What it costs.** Only while a view shows a layer that groups by route:
the stack is read in one walk of the tree after the frames that may have
changed it, at most every 250 ms, and the routes' beans read from their
scopes at each collect. With *Module*, or with no view showing, nothing
is read or kept; the route scopes keep nothing for it.

#### A layer of your own

A layer is a `DebugGraphLayer` bean:

| Member | Default | What |
|---|---|---|
| `String get id` | (required) | Its name, what its nodes' ids start with |
| `String get title` | (required) | What its switch and the legend say |
| `int get order` | `0` | Its place among the layers (switches, lanes) |
| `Color colorOf(DebugStyle)` | the theme's `graph-<id>`, else a palette colour | The colour of its nodes, from the debug theme (`style.graphLayer(id)`; a layer with a colour of its own passes it, `style.graphLayer(id, orElse: style.good)` for the beans layer, `style.logger` for the widgets layer, `style.command` for the signals layer) |
| `List<DebugGraphKind> get kinds` | (required) | Its kinds of node: `DebugGraphKind(id, label, shape, description:)`, `DebugGraphShape.rounded`, `pill`, `rectangle`, `octagon`, `hexagon`, `parallelogram`, `tagged`; the `description` is what the pointer over its legend entry tells |
| `DebugGraphLayout? get layout` | `null` (left to right) | The layout while it is the first layer shown |
| `List<DebugGraphOption> get options` | none | Its own switches, checkboxes under its title in the graph's `Options ▾`: `DebugGraphOption(label:, value:, onChanged:)`; a tap calls `onChanged` and the graph collects again |
| `List<DebugGraphChoice> get choices` | none | Its own single choices in the graph's `Options ▾`, a heading and a radio row per value: `DebugGraphChoice(label:, choices:, value:, onChanged:)`; a tap on another value calls `onChanged` with it and the graph collects again (the built-in layers give `Group by: Route \| Module` once, from `debugGraphRoutes.choicesOf`) |
| `String? get flashMeaning` | `null` | What a flash of its nodes means, the label of its legend entry after a pulse (`a signal ticked or an effect ran`); `null`: no entry |
| `String? get heatMeaning` | `null` | What its hot outline means, the label of its legend entry after an outline (`rebuilt 3+ in 5 s`); `null`: no entry |
| `String? hotNoteOf(node)` | `null` | Why a hot node is hot, the first line of its tooltip in `graph-hot` (`PageBackdrop: 14 rebuilds in 5 s`) |
| `void Function() start()` | does nothing | Runs while a view shows; what it returns runs when the last hides |
| `Listenable get changes` | (required) | Notifies when its nodes or edges change (not their values), while started |
| `DebugGraphPart collect(DebugGraphScope)` | (required) | Its nodes and edges: `DebugGraphNode` (`id`, `layer`, `kind`, `label`, `group`, `groupTitle`, `groupOrder` and `groupRole` for a lane of the graph's own ([above](#lanes-by-route-or-by-module)), `details`, `repeatKey`, `repeatScope`, `widget` for "On screen", `source`, `sink`, `dimmed` for a grey node of what is not there) and `DebugGraphEdge` (`from`, `to`, `kind`, `dashed`) |
| `List<DebugGraphDetail> detailsOf(node)` | the node's `details` | What its tooltip and card tell, read when they show (the card's closed line: the first three values) |
| `double heatOf(node)` | `0` | How hot a node is, 0 to 1: outlined in `graph-hot` |
| `double glowOf(node)` | `0` | How lit a node is now, 1 to 0 over a second |
| `bool isLive(node, window)` | `true` | Whether it changed within `window`, for "Live only" |
| `void Function() onActivity(wake)` | does nothing | Calls `wake` when something lights up, so the view draws frames |

An edge may name another layer's node by its id: it is drawn when both
ends show, so the layer that knows a tie across layers gives it. The node
of a widget has the id `DebugGraphWidgets.idOf(element)`
(`widget:<identity of the element>`) in every layer that ties to it, and
`DebugGraphWidgets.springWidgets()` lists the Spring widgets in the tree
with their `beansType`, walking it only when called. The view's
steps are chains too: `DebugGraphAssembler(filters: [...], folds: [...])`
takes `DebugGraphFilter` instances (the built-in scope, group and live filters) and
`DebugGraphFold` instances (a collapsed lane, repeats).

```dart
// The routes of the app as a layer: each page a node, an edge from a page
// to the pages it opens.
class RoutesGraphLayer extends DebugGraphLayer {
  RoutesGraphLayer(this.routes);
  final AppRoutes routes;                       // a ChangeNotifier

  @override
  String get id => 'routes';

  @override
  String get title => 'Routes';

  // Its colour: the debug theme's `graph-routes`, else a palette colour.

  @override
  List<DebugGraphKind> get kinds => const [
    DebugGraphKind(
      'page',
      'page',
      DebugGraphShape.rounded,
      description: 'A page of the app',
    ),
    DebugGraphKind('dialog', 'dialog', DebugGraphShape.pill),
  ];

  @override
  Listenable get changes => routes;

  @override
  DebugGraphPart collect(DebugGraphScope scope) => DebugGraphPart(
    [
      for (final route in routes.all)
        DebugGraphNode(
          id: 'routes:${route.path}',
          layer: id,
          kind: route.dialog ? 'dialog' : 'page',
          label: route.path,
          group: route.section,
        ),
    ],
    [
      for (final route in routes.all)
        for (final target in route.opens)
          DebugGraphEdge('routes:${route.path}', 'routes:$target'),
    ],
  );
}
```

Registered as a plain bean it is in every build that has its class. To
leave it out as the built-in layers are, register it in a module of its
own with the Graph tab's and the pane's definitions:

```dart
@AutoConfigurationModule(
  build: AutoConfigurationBuild.named(
    'spring.flutter.debug.graph.layers',
    'routes',
    whenMissing: BuildInclusion.always,
    parents: [
      AutoConfigurationBuild('spring.flutter.debug.graph.enabled'),
      AutoConfigurationBuild('spring.flutter.debug.enabled'),
    ],
  ),
)
final BeanModule routesGraphAutoConfiguration = BeanModule(
  'routesGraphAutoConfiguration',
  [
    BeanDefinition<RoutesGraphLayer>(
      name: 'routesGraphLayer',
      types: const [RoutesGraphLayer, DebugGraphLayer],
      create: (r) => RoutesGraphLayer(r.dependency<AppRoutes>()),
    ),
    ...debugGraphSectionDefinitions,   // the Graph tab, made once
  ],
);
```

#### The widgets layer

The `widgets` layer (`widgetsGraphLayer`, from the starter) draws the
application's widgets as a tree from top to bottom
(`TreeDebugGraphLayout`).

- **Only the application's** by default: a widget is the application's
  when what its `build` makes is created in the application's files
  (Flutter's creation locations, there in a debug run; the files are those
  of the package of the widget given to `runApp`, not its dependencies'),
  and Flutter's builders (`Builder`, `LayoutBuilder`, the `…Builder` classes,
  `KeyedSubtree`, `Visibility`, the signals starter's `Watch`) never are.
  Flutter's wrappers (`Padding`, `Align`, `Container`, `Text`) fold into
  the application's widget above them. A Spring widget always counts.
  Without creation locations (a build without the tracking) only the
  Spring widgets do. `framework widgets` (Options) shows every element.
- **Kinds**: a route's first widget of the application's is a screen (cut
  corners), a Spring widget (its beans injected) a pill, a stateful widget
  rounded, a stateless one a rectangle, an element of Flutter's (with the
  option) slanted.
- **Folds**: widgets of one type under one parent fold into one node,
  `ReviewTile ×10`, until it is tapped; the card's `collapse branch`
  folds a widget and everything under it into one node (`SiteHeader ▸ 12`,
  `DebugGraphBranchFold`), a tap opens it.
- **Live**: a widget that builds flashes. In a debug build every rebuild
  is heard (Flutter's `debugOnRebuildDirtyWidget`, chained after
  DevTools'), counted once a frame for the node it is folded into, with
  the time the widget's own `build` took; elsewhere what changed between
  two walks of the tree. The branches built most often (three times or
  more in five seconds by default, `spring.flutter.debug.graph.hot.*`) are
  outlined in the theme's `graph-hot`, from the hot widget up to the root;
  the pointer over one tells why (`PageBackdrop: 14 rebuilds in 5 s`).
- **On screen** (the default): the widgets whose box is in the window and
  the branch above them, worked out in one pass over the render tree; not
  a widget scrolled out of a list, offstage, or under a `TickerMode` that
  is off (a route under an opaque one). A widget under a `PaintedElsewhere`
  key, as a 3D scene's widgets are (built under an `Offstage`, drawn on the
  engine's canvas), counts by the place of the marked widget. **All**: the
  whole mounted tree, lower routes in the navigator's stack included.
- **Detail of a widget**: type, key, size and place on the screen, its
  `State` class, its route (`route 2 of 2 (top)`), the beans of a Spring
  widget by name, its rebuilds in five seconds and its build time (last,
  mean), where it was created; and, merged in, what other layers know of it
  (the signals it read, from the signals layer). A tap also outlines the
  widget over the app (an entry of the app's overlay, under the debug
  panel, so it shows with the console's pane), the outline following it
  as it moves (read again after each frame while it shows, gone when the
  widget leaves the tree), and selects it in Flutter's inspector (the
  Flutter tab shows it).
- **Properties of a widget**: after those lines the card has a
  `properties` block, the widget's values, and a `state properties`
  block, its `State`'s, as name and value rows. They come from sources
  asked in turn (`WidgetProperties`, `WidgetsGraphLayer.properties`; the
  application's own `WidgetProperties` beans first): Flutter's
  diagnostics (`toDiagnosticsNode().getProperties()`, what
  `debugFillProperties` adds, those not at their default value; in a
  debug build only), then the public fields the generator reads
  (`DebugWidgetFields`, bean `debugWidgetFields`). For each public,
  non-generic widget class of the application's scan that does not
  override `debugFillProperties`, and its public `State` class, the
  generator writes into the debug part (`<library>.spring.debug.dart`) a
  reader of each public instance field the class and its superclasses of
  the application's package declare. **Private fields are not shown**:
  generated code cannot read them from another library (`_count`, a
  private `_PageState`); make the field public, or override
  `debugFillProperties`. Getters are not read, as a getter may compute,
  allocate or change something, nor a `late` field with an initializer,
  which reading would run; a `late` field not set yet says `not set`. A
  value is short: a string quoted and cut at 60 characters, a list, set
  or map by its length (`List(6)`, `Map(2)`), another iterable as
  `Iterable` (counting it would run it), a function as `Function`, an
  object by its type (`PassportPlayer`, never `Instance of …`); a row
  marked `▸` opens on a tap into the whole value (a list's first 20
  items, the whole string, an object's `toString()`, called only then).
  A name that looks secret (`SecretNames.looksSecret`: `password`,
  `apiKey`, `token`) shows `******`. The values are read when a card
  opens and again at most once per walk of the tree. The readers are a
  lazy bean the application registers only in debug builds, and
  only when the build has the widgets layer (its module's switches,
  above): a profile or a release build, or one without the layer, has
  none of them.

**Widget node ids.** A widget's node is `DebugGraphWidgets.idOf(element)`
(`widget:<identity of its element>`, stable while the element is mounted),
the one id every layer uses for a widget: the beans layer draws its edges
to it, the signals layer gives each widget that read state
`DebugGraphNode.sameAs` that id, and with the widgets layer shown the
reader is merged into the widget's node (its edges moved to it, its
details told with it, no second node); without it the reader shows as
its own. `widgetsGraphLayer.nodeIdOf(holder)` gives the node of any
element, `State` or widget the layer walked past: its own, or the node it
is folded into.

**What it costs.** It walks the tree when a view starts showing it, then
at most every 250 ms after a frame (an idle app is not walked), and hears
rebuilds, only while a view shows it; it skips the debug tools' own
widgets (`DebugToolSubtree`). Over a tree of 2000 elements a walk takes
about 1 ms and "On screen" 0.5 ms (JIT benchmark). Hidden, it has no timer,
no hook and keeps nothing. In the build when
`spring.flutter.debug.graph.layers` names `widgets`, holds `*` or is not
set, inside `spring.flutter.debug.graph.enabled` and the panel's switch
(the pane: inside the console's).

#### The beans layer

The `beans` layer (`beansGraphLayer`, from the starter) draws the beans
the application defined: its `@Service`, `@Repository`, `@Component`,
`@Configuration` classes, `@Bean` methods and controllers. Each module is
a lane: a folder of the application under `lib/src` (`shop/basket`), an
auto-configuration for the framework's beans. Each role has its shape:
`@Service` rounded, `@Repository` a rectangle, `@Component` a pill,
`@Configuration` cut corners, `@Bean` a hexagon, `@Controller` a
parallelogram, the framework's infrastructure tagged.

- **Edges** run from a bean to each bean that injects it (so what a
  widget needs is to its left): solid for a constructor or field, dashed
  for a `@Lazy` point, an `ObjectProvider` and a `@DependsOn`. They come
  from the injection points the generator lists and from what the
  container saw a bean take (a hand-written definition's).
- **Options** (`Options ▾`): `framework` adds the framework's and the auto-configurations'
  beans; `skipped` (in *All*) adds, grey, the beans a condition left out
  (a profile not active, a property not set, a bean already there).
- **On screen**: the beans the Spring widgets on the screen inject
  (`SpringStatelessWidget`, `SpringStatefulWidget`) and everything those
  depend on. Each such bean has an edge to the widget's node of the
  widgets layer, drawn when that layer shows.
- **Detail of a bean**: type, role, module, scope, whether it is created
  (a lazy one waiting for its first use, the live instances of a route's
  bean), the advisors around it and the annotated members of its proxy
  (`@Transactional`, `@Cacheable`, `@PreAuthorize`, `@SignalBuffer`,
  `@Observed`), the conditions it was registered under, its creation
  order and time (with the start's trace or the timeline), what it
  depends on and what uses it, its `@EventListener` methods. A bean left
  out tells the condition that did not match.
- **Light**: a bean flashes when an instance of it is created or
  destroyed (a route's beans open and close with their screen, a lazy
  bean on first use). Method calls do not flash.

It follows the beans only while a view shows it: then a post-processor
(`DebugBeanLifecycleRecorder`) hears of each bean created and destroyed;
hidden, the container has none. Its data is the `debugBeanGraph` bean
(`DebugBeanGraph`: `snapshot` with `DebugBean`, `DebugBeanModule`,
`DebugBeanEdge`, `DebugSkippedBean`, `closureOf`, `widgetOf`; `start`,
`stop`, `events`). Node ids: `beans:<bean name>`, `beans:skipped:<source>`.

### Debug themes

Every color and font of the debug tools (the panel, the console, the
frame meter over the app) comes from a debug theme. The built-in one,
`default`, is the look the tools always had: the app theme's colors and
its `code` font, the logs and the console's states in a terminal's palette
for a dark background, or for a light one by the background's luminance
(so the default stays readable on a light app theme), and the commands
orange. The frame meter keeps the app theme's `frame-meter` look but for
what a theme sets.

A theme of your own is declared under `spring.flutter.debug.themes.<name>`
and selected by `spring.flutter.debug.theme`; what it does not set is the
built-in theme's, worked out on its own background (a light one gets the
light palette). The debug panel's Theme tab switches them live, in a row
under the app's themes; the choice lasts while the app runs.

```yaml
spring:
  flutter:
    debug:
      theme: night
      themes:
        night:
          background: '#101820'
          text: '#F2AA4C'
          dim: '#7A6A50'
          command: '#FF8C42'
          level-info: '#4EC9B0'
          font-family: JetBrains Mono
          font-size: 12
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.debug.theme` | name | `default` | The debug theme the tools start with: `default`, one of `themes`, or a `DebugTheme` bean's name. A name no theme has fails the start, naming the property |
| `spring.flutter.debug.themes.<name>.background` | color | the app theme's surface | The fill of the panel, the console and the frame meter (85% opaque there; the console's own `opacity` applies to it) |
| `….text` | color | the app theme's on-surface | The text |
| `….dim` | color | the app theme's on-surface-variant | Labels, hints, the echo of a command typed |
| `….accent` | color | the app theme's primary | What is selected or on: a chip, the input's `>` |
| `….number` | color | `accent` | The numbers of the console's header, the frame meter's rate |
| `….good`, `….warning`, `….bad` | color | terminal green, amber, red | The states of the console's header, the loads of the Isolates tab, the frame meter's bars |
| `….error` | color | terminal red | What a command reports as gone wrong |
| `….line` | color | the app theme's outline-variant | Lines between rows, borders, the divider |
| `….level-error`, `….level-warning`, `….level-info`, `….level-debug` | color | terminal red, yellow, green, green | A record's level (`level-debug` for debug and trace) |
| `….time` | color | `text`, faint | A record's time and the `:` after its logger |
| `….logger` | color | terminal cyan | A record's logger |
| `….command` | color | orange | A command's word, in the commands pane |
| `….argument` | color | `command`, faint | How a command's arguments are written, in `help` |
| `….graph-flash` | color | terminal yellow | What lights a node of the [application graph](#the-application-graph) that just changed or ran: its border, its glow, at most a quarter of its fill, the pulse along its edges |
| `….graph-beans`, `….graph-widgets`, `….graph-signals` (the `graph-<layer id>` of the built-in layers) | color | `good`'s green, `logger`'s cyan blue, `command`'s orange | The nodes of the graph's beans, widgets and signals layers, and their squares in the toolbar and the legend |
| `….graph-hot` | color | terminal magenta | The outline of a hot branch of the graph (a widget that rebuilds often and the branch above it); a hue no layer has |
| `….graph-<layer id>` | color | a palette colour, picked by the id | The nodes of a graph layer of the app's (`graph-routes`); any key of this form is a theme's |
| `….method-read`, `….method-write` | color | terminal cyan, `command`'s orange | The methods in the Network tab: those that read (`GET`, `HEAD`, `OPTIONS`, `TRACE`) and those that write (`POST`, `PUT`, `PATCH`, `DELETE`); its statuses are `good`, `warning` and `bad` |
| `….font-family` | family | the app theme's | The font of every debug tool's text |
| `….font-size` | number | `11` | The size of the logs and the console's text |

A color is `#RRGGBB`, `#AARRGGBB` or a `Colors` name. A key a theme does
not have, or a value that is not a color, fails the start with the
property's name.

A theme built in code is a `DebugTheme` bean: a `name` and a
`styleOf(context)` returning a `DebugStyle`, usually the built-in look with
some values of its own (`DebugStyle.fromApp(context, background: ...)`).
A theme declared in the configuration replaces a bean of its name; either
replaces `default`.

```dart
@Component()
class SolarizedDebugTheme implements DebugTheme {
  @override
  String get name => 'solarized';

  @override
  DebugStyle styleOf(BuildContext context) => DebugStyle.fromApp(
    context,
    background: const Color(0xFF002B36),
    foreground: const Color(0xFF93A1A1),
    command: const Color(0xFFCB4B16),
  );
}
```

Debug themes are part of the debug build: their beans (`debugThemes`,
`defaultDebugTheme`, `debugThemeCustomizer`) come with the panel's module
and with the console's, the first making them, so a build with neither
has none of their code, and does not read these keys. `DebugStyle.of`
then gives the built-in look.

### Keyboard shortcuts

An action's keys are configuration, its handler is a bean method. Change the
keys per platform or per profile without touching the code.

```yaml
spring:
  flutter:
    shortcuts:
      search.open: primary+k                  # ⌘K on macOS and iOS, Ctrl+K elsewhere
      navigation.back: [alt+left, primary+bracket-left]
      help.show: char:?                       # the character, whatever keys type it
```

```dart
@Component()
class SearchActions {
  @Shortcut('search.open', keys: ['primary+k']) // keys when the configuration has none
  void open(BuildContext context) => SearchDialog.show(context);
}
```

Writing keys:

| Form | Meaning |
|---|---|
| `primary+shift+k` | Modifiers and one key, joined by `+`. Modifiers: `primary` (⌘ on Apple's platforms, Ctrl elsewhere), `shift`, `alt` (`option`), `control` (`ctrl`), `meta` (`cmd`). Keys: letters, digits, `f1`–`f12`, `enter`, `escape`, `space`, `tab`, `backspace`, `delete`, `home`, `end`, `page-up`, `page-down`, `up`, `down`, `left`, `right`, `slash`, `backslash`, `comma`, `period`, `semicolon`, `quote`, `minus`, `equal`, `bracket-left`, `bracket-right`, `backquote` |
| `char:?` | The character typed, on any keyboard layout |
| `taps:4+hold:3s` | Taps on the screen, not keys: quick taps anywhere (1 to 10), then, with `hold`, one press held that long (`ms`, `s`). Every platform: a finger, a pen or a mouse. Without `hold` the last tap is the shortcut (`taps:3`). It only listens: every touch still reaches the app. A tap lasts at most 300 ms, two taps are at most 400 ms apart, a finger that moves more than 18 points is a scroll and starts again |
| a list | Any of them: `[primary+k, slash, taps:3]` |

A value no notation reads stops the start, naming the property
(`spring.flutter.shortcuts.search.open: 'moon' is no key ...`). The same
keys given to two actions log a warning.

Handlers:

- A `@Shortcut` method takes nothing, a `BuildContext` (the focused
  widget's, below the navigator, so it can show a dialog) or a
  `ShortcutInvocation`. It returns nothing (handled) or a `bool`: `false`
  passes the press on. Another signature stops the start.
- A bean that implements `ShortcutHandler` handles its `action`; with
  `Ordered` it takes its place among the others. One that implements
  `KeyedShortcutHandler` names its action's keys when the configuration
  does not, as `@Shortcut(keys:)` does.
- An action's handlers are asked by `@Shortcut(order:)` / `Ordered`, lower
  first, until one handles the press.
- A screen's own handlers sit in the widget tree and are asked first while
  the focus is below them. An action they do not have, or a handler that
  returns `false`, goes on to the handlers above and then the beans:

```dart
ShortcutHandlers(
  handlers: {
    'editor.save': (_) => draft.save(),
    'search.open': (_) => searchInThisBook(),   // instead of the app's
  },
  child: EditorPage(draft),
)
```

- Plain keys (`slash`, `char:?`) are ignored while a text field has the
  focus, so they still type. Keys with Ctrl, ⌘ or Alt work there too.

Showing the keys: `ShortcutLabel('search.open')` writes the action's first
keys the platform's way (`⌘K`, `Ctrl+K`), from the same configuration;
`ShortcutLabel.of(context, action)` gives the text.

The starter installs the shortcuts around the app's navigator
(`KeyboardShortcutsScope`, through a `FlutterAppCustomizer`). An app with
its own `MaterialApp` puts `KeyboardShortcutsScope(shortcuts:
context.bean<KeyboardShortcuts>(), child: child)` in its `builder`.

To read keys written another way (`numpad:5`, a chord), declare a
`ShortcutNotation` bean. The notations form a chain of responsibility: the
app's own are asked first (by `@Order`), then `CharacterNotation`,
`TouchPatternNotation` and `KeyCombinationNotation`.

```dart
@Component()
class NumpadNotation implements ShortcutNotation {
  @override
  bool supports(String text) => text.startsWith('numpad:');

  @override
  ShortcutKeys parse(String text, TargetPlatform platform) => ...;
}
```

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
the files' values) sets a `spring.flutter.web.dev-server.*` key or
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
      dev-server:
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
spring.flutter.web.dev-server.port=5050
spring.flutter.web.dev-server.headers.Cross-Origin-Opener-Policy=same-origin
spring.flutter.web.dev-server.proxy[0].prefix=/api/
spring.flutter.web.dev-server.proxy[0].target=http://localhost:8080
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.web.dev-server.host` | string, not empty | any address | The address the dev server listens on: `localhost`, or `0.0.0.0` for other devices on the LAN |
| `spring.flutter.web.dev-server.port` | integer, 0 to 65535 | a free port | The dev server's port |
| `spring.flutter.web.dev-server.base-href` | path starting and ending with `/` | `/` | The path the app is served under (`/shop/`) |
| `spring.flutter.web.dev-server.https.cert-path` | file path | none (HTTP) | The TLS certificate (PEM). With `cert-key-path`, the dev server speaks HTTPS; set both or neither |
| `spring.flutter.web.dev-server.https.cert-key-path` | file path | none | The certificate's private key (PEM) |
| `spring.flutter.web.dev-server.headers.<Name>` | string | none | A header added to every response; the map merges across files, the more specific file winning per header |
| `spring.flutter.web.dev-server.proxy[n].target` | absolute URL | none | Where requests matching rule `n` are forwarded (`http://localhost:8080`). Required in every rule |
| `spring.flutter.web.dev-server.proxy[n].prefix` | path | none | Rule `n` matches paths starting with it (`/api/`) |
| `spring.flutter.web.dev-server.proxy[n].regex` | regular expression | none | Or the paths matching it; each rule sets exactly one of `prefix` and `regex` |
| `spring.flutter.web.dev-server.proxy[n].replace` | string | the path unchanged | The forwarded path: the matched part replaced, `$1` for the first group |
| `spring.flutter.web.dev-server.content-security-policy` | string, not empty | none; in spa mode a ready policy (below) | The page's Content Security Policy, sent as the `Content-Security-Policy` header. Setting it and `headers.Content-Security-Policy` both fails the build |
| `spring.flutter.web.dev-server.content-security-policy-report-only` | `true` / `false` | `false` | Send the policy as `Content-Security-Policy-Report-Only`: violations are reported in the console, nothing is blocked (for development). Any other value fails the build; `FlutterWebProperties` declares the field as text (`String?`), so an editor accepts anything there, but only `true` or `false` works |
| `spring.flutter.web.dev-server.content-security-policy-connect-src` | list of origins (`https://api.neon.books`, `wss://...`) | none | Origins added to the `connect-src` of spa mode's ready policy (below): the APIs the app calls, a provider's endpoints on other hosts. Setting it with an own policy fails the build; without spa mode it is ignored (a warning) |

The proxy list comes whole from the most specific file that has one, as
lists do in Spring Boot. Forwarding `/api/` to the server is the simplest
way to avoid CORS and third-party cookie trouble in development: the page
and the API share one origin, so a session login works in every browser.

An invalid value fails the build with the key's name; an unknown
`spring.flutter.web.dev-server.*` key is a warning. Without any of these keys (and
not in spa mode) no file is written, and a hand-written
`web_dev_config.yaml` is never changed or deleted: with the keys set as
well, the build fails and asks to remove one of the two.

### The Content Security Policy

A Content Security Policy tells the browser which scripts, styles and
connections the page may use, so a script injected into it (or loaded
from a place the app never meant) is refused. The generator sends
`spring.flutter.web.dev-server.content-security-policy` with every answer of
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
that host in `spring.flutter.web.dev-server.content-security-policy-connect-src`,
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
spring.flutter.web.dev-server.content-security-policy=default-src 'self'; \
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

### The page in apps' own browsers

A link opened in a messenger or a social app shows in the app's own
browser, which closes the page on a swipe down when the page is at its
top. A Flutter page always is (it scrolls inside its canvas), so every
swipe down closes it instead of scrolling.

```yaml
# lib/resources/application-web.yml
spring:
  flutter:
    web:
      page:
        swipe-to-close: false
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.web.page.swipe-to-close` | `true` / `false` | `true` | `false`: the generator writes a block into `web/index.html` that keeps the page open. On a touch screen it makes the page a thousand screens tall, scrolls it to its end with Flutter's view fixed on the screen, and stops the browser's own scrolling of the page, so the page is never at its top and a swipe down is Flutter's. It names no app and calls no app's API |
| `spring.flutter.web.page.max-pixel-ratio` | number, 1 or more | the screen's own | The most pixels for each point Flutter draws at. A phone's screen has 3, so every frame is 9 times the pixels of the page and its graphics chip drops frames on a full-screen scroll; `2` draws 2.25 times fewer and the text stays sharp. The generator writes a script into `web/index.html` that runs before the engine starts; a screen at or under the value is left as it is |
| `spring.flutter.web.page.translate` | `true`, `false` | `true` | Whether browsers and Google may offer to translate the page. Flutter draws its text on a canvas, so a translator finds none to translate; `false` writes `translate="no"` on `<html>` and `<meta name="google" content="notranslate">` into `web/index.html` (and so into the SEO pages), and the offer is gone |

### The page loader

While the browser downloads Flutter it shows what the generator writes into
`web/index.html` from the `splash` of the active theme (`active`; with
`system` the light theme, and the dark one under `prefers-color-scheme:
dark`): the background, logo and title of the splash, and its loader. The
block lies between `<!-- spring:loader:start -->` and
`<!-- spring:loader:end -->`; the generator adds the markers after `<body>`
when they are missing, rewrites the block on every build, and removes it when
the theme has no splash. The rest of the page is yours, and a page that does
not exist is not created.

```yaml
spring.flutter.theme:
  splash:
    background: { color: $colors.surface-container-lowest }
    logo: { source: assets/images/logo.png, size: 96 }
    title: NEON
    loader: neon-gate
  loaders:
    neon-gate:
      kind: neon-gate                     # @ThemeLoaderKind('neon-gate')
      bar: { color: $colors.error, glow: 22 }
      edge: { color: $colors.primary, width: 2 }
      web: loaders/neon-gate.html         # lib/resources/loaders/neon-gate.html
```

- The built-in kinds (`spinner`, `dots`, `pulse`, `bar`, `skeleton`) have a
  CSS form made from their keys. A kind of the app's own gives a `web:` HTML
  file: a path below `lib/resources/`, the app's own or a package's it
  uses (`loaders/neon-gate.html`), or below the app's directory; or an
  address the build downloads, `https://...` or
  `github:owner/repo/path@ref`, to share a loader without a package. The
  build keeps a copy in `.dart_tool/spring/loaders/` and uses it offline;
  `web-sha256` pins the file (another one is refused). The HTML goes into
  the page as it is: take it from an address you trust, at a tag. The keys of the loader are CSS variables on the loader, named after
  the key path in kebab case: `bar.color` is `--bar-color`,
  `edge.width` is `--edge-width`. Colors are resolved (references, color
  objects, the Material roles of the seed) to `#rrggbb` or `rgba()`; numbers
  are unitless (`calc(var(--box-width) * 1px)`); durations are `500ms`;
  texts are quoted CSS strings. The page also has `--spring-progress` (0 to
  1, from Flutter's loading stages) and `data-stage` (`load`, `app`,
  `engine`, `run`, `done`) on `#spring-loader`.
- Nothing in a theme can leave its place in the page: texts are escaped for
  HTML and CSS, and a logo must be an asset, an `http(s)` URL or a
  `data:image/` URL (an asset path `assets/x.png` is served as
  `assets/assets/x.png`, as Flutter does).
- The loader shows at once, follows `_flutter.loader` as its progress,
  stops its animations under `prefers-reduced-motion`, and is removed when
  the Flutter splash has painted and calls `window.springLoaderHandOff`, or
  after 60 seconds (3 seconds after the first Flutter frame). The script is
  the same in every app; the generated content-security policy of spa mode
  allows it by its hash. If you set your own policy
  (`content-security-policy`), add `WebPageLoader.scriptHash` (the
  `'sha256-...'` of the block's script) to its `script-src`.

### WebAssembly in Safari and Firefox

A `flutter build web --wasm` build has both a WebAssembly and a JavaScript
form of the app; Flutter's loader picks the WebAssembly one only on Blink
(Chrome, Edge) unless told otherwise. `wasm-allow-list` tells it which
engines may run it:

```yaml
# lib/resources/application-web.yml
spring:
  flutter:
    web:
      page:
        wasm-allow-list:
          gecko: true     # Firefox 147 and newer
          webkit: true    # Safari 26.2 and newer
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.web.page.wasm-allow-list.<engine>` | `true` / `false` per engine: `blink`, `gecko`, `webkit` | not set: Flutter's own, Blink only | The generator writes the map into the block between the loader's markers, and the page passes it to `_flutter.loader.load` as `config.wasmAllowList`. An engine the app's own `flutter_bootstrap.js` names in its `wasmAllowList` keeps the app's value. With a splash, the page loader's script passes it; without one, the block has only that script. Another engine name, or a value that is not `true` or `false`, fails the build |

- It needs a `--wasm` build; a JavaScript-only build loads as before.
- A browser older than the versions above, or one without the WebAssembly
  features dart2wasm needs, gets the JavaScript form: Flutter's loader
  checks them before it uses the list. `false` keeps an engine on
  JavaScript, Blink too.
- When it is not set, nothing is written and Flutter's default (Blink only)
  applies; the page loader's script is the one of `WebPageLoader.scriptHash`.
- With it, the script differs: the policy of spa mode allows it by its hash;
  an own `content-security-policy` adds the `'sha256-...'` of the script
  between the block's `<script>` tags.

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

### Navigation

`spring_boot_starter_flutter_navigation` (brought by
`spring_boot_starter_flutter_security` too) puts the screens of
`@ScreenRoute` and `ScreenRoutes` beans on the SDK's `Router`: the
browser's address bar, deep links and Android's back button. How to write
screens, shells, guards and tests is in the
[starter's README](../spring_boot_starter_flutter_navigation/README.md);
these are its properties.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    navigation:
      initial: /catalog
      login: /login
      redirects:
        "[/home]": /catalog
      languages: [en, ja]
      web:
        url-strategy: path
      deep-links:
        scheme: neonbooks
        domains: [books.example.com]
        exclude: [/checkout, /admin/**]
```

</td><td>

```properties
spring.flutter.navigation.initial=/catalog
spring.flutter.navigation.login=/login
spring.flutter.navigation.redirects[/home]=/catalog
spring.flutter.navigation.languages=en,ja
spring.flutter.navigation.web.url-strategy=path
spring.flutter.navigation.deep-links.scheme=neonbooks
spring.flutter.navigation.deep-links.domains[0]=books.example.com
spring.flutter.navigation.deep-links.exclude[0]=/checkout
spring.flutter.navigation.deep-links.exclude[1]=/admin/**
```

</td></tr>
</table>

A key of `redirects` is a path, so it is written in brackets: `[/home]`
(in YAML in quotes too).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.navigation.initial` | path | none | Where the app starts when the platform gives `/` (no deep link, the site's root) |
| `spring.flutter.navigation.login` | path | none | Where a guarded screen (`@PreAuthorize`, `RouteSecurity.preAuthorize`) sends nobody logged in; the app comes back after the login. Without it, such a navigation shows the route's error screen |
| `spring.flutter.navigation.redirects.<from>` | path | none | An address that leads to another (`"[/]": /catalog`); a route's own redirect of the same path wins |
| `spring.flutter.navigation.languages` | list of language tags | none (one language, no prefix) | The languages with their own addresses: the first is the default, without a prefix; the others under `/<language>` (`/ja/catalog`). An address of a language sets the app's locale (`context.message`, Flutter's widgets); the app's own paths are written without a prefix and keep the current language; `RouteTemplate.switchLanguage('ja')` changes it. The build writes the pages for search engines in each language ([The site's pages](#the-sites-pages-springflutterwebseo)) |
| `spring.flutter.navigation.web.url-strategy` | `path` / `hash` | `path` | How a browser's address bar shows the route: `/catalog/books/1` (a static host answers every path with `index.html`, or the build writes a page per path) or Flutter's `/#/catalog/books/1` |
| `spring.flutter.navigation.deep-links.enabled` | `true` / `false` | `true` | Whether the deep links are written; `false` in a platform's profile file turns them off there |
| `spring.flutter.navigation.deep-links.scheme` | URL scheme | none | The app's own scheme (`neonbooks://catalog/books/1`); not verified, another app may claim it. The generator writes it into `Info.plist` (iOS, macOS) and the Android manifest |
| `spring.flutter.navigation.deep-links.domains` | list of host names | none | The domains whose `https` links open the app (Universal Links, App Links): `applinks:` in `ios/Runner/Runner.entitlements` (when the file exists), a verified intent filter on Android, and `apple-app-site-association` / `assetlinks.json` for the domain to serve under `/.well-known/` |
| `spring.flutter.navigation.deep-links.exclude` | list of path patterns | none | Addresses a link does not open (the app's first screen opens instead), as `@RouteInfo(link: false)`; excluded in Apple's file too |
| `spring.flutter.navigation.deep-links.app-id` | `TEAMID.bundle.id` | from the Xcode project | The iOS app id of `apple-app-site-association` (set it in `application-ios.yml`) |
| `spring.flutter.navigation.deep-links.package` | Android package | the Gradle file's `applicationId` | The package of `assetlinks.json` |
| `spring.flutter.navigation.deep-links.sha256-cert-fingerprints` | list | none | The SHA-256 fingerprints of the Android signing keys; without them `assetlinks.json` is not written and Android does not verify the domain |

What the build writes for the deep links, per platform:

| Platform | File | What |
|---|---|---|
| iOS | `ios/Runner/Info.plist` | `FlutterDeepLinkingEnabled` and the scheme (`CFBundleURLTypes`) |
| iOS | `ios/Runner/Runner.entitlements` | `applinks:<domain>` for each domain, when the file exists (create it in Xcode with the Associated Domains capability; the build only warns when it is missing) |
| macOS | `macos/Runner/Info.plist` | The scheme |
| Android | `android/app/src/main/AndroidManifest.xml` | In the main activity: `flutter_deeplinking_enabled`, an intent filter for the scheme and a verified (`autoVerify`) one for the domains |
| Each domain | `web/.well-known/` (a web app), else `build/spring/well-known/` | `apple-app-site-association` and `assetlinks.json`, which the domain serves under `https://<domain>/.well-known/`; the excluded paths are left out of Apple's file |

Windows and Linux get no deep links yet. Every link that opens the app
goes through its routes: a screen with `@RouteInfo(link: false)` or under
`deep-links.exclude` opens the first screen instead, and a guarded screen
asks for the login first.

The generator writes the platforms' blocks between
`spring:deep-links:start` and `spring:deep-links:end` comments with their
hash: a block changed by hand, or a key of the block the file declares
outside it (`CFBundleURLTypes`), fails the build. It never edits the Xcode
project.

### Scenes

`spring_boot_starter_flutter_scene` puts 3D scenes among the app's
widgets, on `flutter_scene`. How to write a scene, the models, the
application's scene, the start's events and the debug tab are in the
[starter's README](../spring_boot_starter_flutter_scene/README.md); these
are its properties.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    scene:
      render: animated
      max-frame-rate: 30
      pixel-ratio: 1.5
      canvas: engine
      preload: eager
      models:
        hero:
          source: asset:assets/models/hero.glb
          preload: lazy
      materials:
        glass:
          source: assets/materials/glass.fmat
          preload: eager
      app:
        enabled: true
        placement: background
        camera:
          position: 0, 1.5, -4
          target: 0, 1, 0
          fov: 45
```

</td><td>

```properties
spring.flutter.scene.render=animated
spring.flutter.scene.max-frame-rate=30
spring.flutter.scene.pixel-ratio=1.5
spring.flutter.scene.canvas=engine
spring.flutter.scene.preload=eager
spring.flutter.scene.models.hero.source=asset:assets/models/hero.glb
spring.flutter.scene.models.hero.preload=lazy
spring.flutter.scene.materials.glass.source=assets/materials/glass.fmat
spring.flutter.scene.materials.glass.preload=eager
spring.flutter.scene.app.enabled=true
spring.flutter.scene.app.placement=background
spring.flutter.scene.app.camera.position=0,1.5,-4
spring.flutter.scene.app.camera.target=0,1,0
spring.flutter.scene.app.camera.fov=45
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.scene.enabled` | `true` / `false` | `true` | Whether the app has scenes. `false`: no scene bean exists, the engine never starts, every scene widget shows its placeholder; set in the application's own configuration (not a profile's), the build leaves the starter's module out (the engine's code stays while the app has scene widgets) |
| `spring.flutter.scene.render` | `animated` / `still` / `off` | `animated` | How scenes draw: up to `max-frame-rate` frames a second; one frame that stands, drawn again when what it shows changes; or placeholders only |
| `spring.flutter.scene.max-frame-rate` | number | `30` | The most frames a second any scene draws; a widget may ask for fewer. `0`: as many as the screen shows (in a browser each of its frames, 60, 120 or 144; elsewhere the display's refresh rate) |
| `spring.flutter.scene.pixel-ratio` | number | the device's | The scenes' own pixel ratio |
| `spring.flutter.scene.when.<condition>` | `still` / `off` | none | The mode every scene takes while the condition holds; the least of `render` and the conditions that hold wins. The starter's conditions: `touch` (the main pointer is a finger) and `slow` (below); an app's own is a `SceneCondition` bean. A condition not named here changes nothing |
| `spring.flutter.scene.slow.frame-time` | duration | `16ms` | For `when.slow`: a beat of the scenes (drawing every moving scene once, on the page's thread) taking more than half of it is slow. Decided by the first scenes' own frames while their placeholders show (the first few left out, on which the engine builds its programs), so they show in the mode they keep; never by switching a scene off in front of the user |
| `spring.flutter.scene.slow.probe` | number | `24` | How many frames of the first scenes are measured before they show |
| `spring.flutter.scene.slow.after` | duration | `3s` | How long beats are slow, on end, after the scenes showed, before `slow` holds: at the next moment no scene moves, then for the rest of the run. Measured where the scenes draw apart from Flutter's frames (`canvas: engine` or `layer` in a browser); with `page` and on the native platforms only the frames before they show decide |
| `spring.flutter.scene.canvas` | `page` / `layer` / `engine` | `page` | Where a frame of a scene goes in a browser: Flutter draws it into the page (and the page again around it); a canvas of the scene's own under the page, each frame handed over by the browser (copied in Firefox and WebKit); or the engine's own canvas, every scene drawn on it where it stands, nothing handed over (behind the page when the first scene fills the screen). `engine` is the whole app's, set when the engine starts |
| `spring.flutter.scene.light-clustering` | `true` / `false` | `true` | Whether the scenes' lamps are shaded through the engine's clustering (`Scene.punctualLightClustering`). `false`: each mesh shades the lamps that reach it, cheaper with a few lamps; the clustering makes its lamp textures anew when a lamp comes into the view or leaves it |
| `spring.flutter.scene.pause-off-screen` | `true` / `false` | `true` | Whether a scene scrolled off the screen stops drawing |
| `spring.flutter.scene.preload` | `eager` / `lazy` | `lazy` | When the engine starts: with the splash, or when the first scene shows. The default of a model's own `preload` |
| `spring.flutter.scene.engine-log` | `true` / `false` | `true` | Whether the engine's own messages (it writes them with `debugPrint`) are records of the application's log, under the logger `flutter_scene` (`logging.level.flutter_scene`) |
| `spring.flutter.scene.models.<name>.source` | asset or address | none (required) | The model's `.glb` file: an asset (`asset:assets/models/hero.glb`) or an `https` address (`http` with `spring.remote.allow-insecure`; in a browser its server must allow the page's origin). Not a file of `lib/resources/`, which is embedded into the code |
| `spring.flutter.scene.models.<name>.preload` | `eager` / `lazy` | as `spring.flutter.scene.preload` | When the model is loaded: with the splash, or when a scene first shows it |
| `spring.flutter.scene.materials.<name>.source` | path | none (required) | The material's `.fmat` file by its path from the app's root (`assets/materials/glass.fmat`, no `asset:`). The app's build hook (`buildSceneAssets`) compiles it and fails when a material named here is not there; at run time the compiled material is loaded, not this file. `SpringSceneMesh(material: 'glass')` and `SceneMaterials` take it by its name |
| `spring.flutter.scene.materials.<name>.preload` | `eager` / `lazy` | as `spring.flutter.scene.preload` | When its programs are loaded: with the splash, or when a scene first shows it (the first frame of that scene waits for it) |
| `spring.flutter.scene.app.enabled` | `true` / `false` | `false` | Whether the app has one scene of its own (the `applicationScene` bean), made with the splash |
| `spring.flutter.scene.app.placement` | `background` / `none` | `background` | Where it shows: under every screen, or only in the app's `SpringSceneView` widgets |
| `spring.flutter.scene.app.camera.position` | three numbers | `0, 0, -5` | Where the camera of the application's scene is |
| `spring.flutter.scene.app.camera.target` | three numbers | `0, 0, 0` | What it looks at |
| `spring.flutter.scene.app.camera.fov` | degrees | `45` | Its vertical field of view |
| `spring.flutter.scene.debug.enabled` | `true` / `false` | not set: debug builds only | The "Scenes" tab of [the debug panel](#the-debug-panel): `true` in every build, `false` in none (no code) |

A model without a `source` stops the app at startup with the key's name.
A value for one platform goes into its profile file: `render: still` in
`application-android.yml`, say.

### Signals

`spring_boot_starter_flutter_signals` follows state in beans (`@Signal`,
`@Computed`, `@Effect`): see the
[starter's README](../spring_boot_starter_flutter_signals/README.md). Its
properties (`SignalsProperties`):

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.signals.debug.enabled` | `true` / `false` | not set: debug builds only | The "Signals" tab of [the debug panel](#the-debug-panel), with every bean and member by name (sub-tabs Fields, Graph with the signals layer of [the application graph](#the-application-graph) when the build has it, List): `true` in every build, `false` in none (no code) |
| `spring.flutter.signals.debug.reads` | `true` / `false` | `true` | Whether the reads are counted while a debug tool shows (they are the most frequent event) |
| `spring.flutter.signals.debug.read-window` | duration | `5s` | The window of the read counts the Signals tab shows (`reads/5s`) |
| `spring.flutter.signals.debug.log.enabled` | `true` / `false` | `false` | The DEBUG log of signal activity, under the logger `spring.flutter.signals.activity`; only in a build with the Signals tab |
| `spring.flutter.signals.debug.log.reads` | `true` / `false` | `false` | That log names every read too (very many lines) |
| `spring.flutter.signals.queue.flush` | `immediate` / `microtask` / `frame` / `interval` | not set: `microtask` | The built-in schedule on which the default queue tells the readers of what was written. A `SignalFlushSchedule` bean with the queue's `@Qualifier` is the other way; both for one queue fail the start |
| `spring.flutter.signals.queue.interval` | duration | `100ms` | How often, for `flush: interval` |
| `spring.flutter.signals.queue.capacity` | int | `1024` | How many fields may wait in the queue |
| `spring.flutter.signals.queue.on-overflow` | `flush` / `drop-oldest` / `drop-newest` | `flush` | What one more field does when the queue holds `capacity`: `flush` tells what it holds and takes the write (while it is telling already, it refuses the write as `drop-newest`); `drop-oldest` drops the oldest write it holds, `drop-newest` refuses this one, each with a warning |
| `spring.flutter.signals.queues.<name>.*` | the keys of `queue` | — | More queues, by name, for `@Signal(queue: '<name>')`: `flush`, `interval`, `capacity`, `on-overflow` |
| `spring.flutter.signals.buffer.async-methods` | `true` / `false` | `false` | Whether every async method of a bean on signals runs in a `SignalBuffer` (`@SignalBuffer(false)` takes one out). Read by the build too |
| `spring.flutter.signals.buffer.on-error` | `discard` / `publish` | `discard` | What happens to the writes of a buffered method that failed: dropped, or told as if it had succeeded |
| `spring.flutter.signals.on-scope-end` | `discard` / `flush` / `defer` | `discard` | What happens to the writes not told yet when a bean's scope ends: dropped with a warning naming the bean and the fields, told at once, or kept until their queue tells them (at most `defer-timeout`) |
| `spring.flutter.signals.defer-timeout` | duration | `5s` | How long `on-scope-end: defer` waits |
| `spring.flutter.signals.eager` | `true` / `false` | `false` | Whether every signal is made with its bean rather than on first use |
| `spring.flutter.signals.caller-bound` | `true` / `false` | `true` | Whether a value computed through method security or from the current user is kept for that user only. `false` lets one user's value reach another |
| `spring.flutter.signals.allow-advice` | `true` / `false` | `false` | Whether a bean with followed state may carry advice; read by the build too: without it, such advice is a build error |
| `spring.flutter.signals.transaction.mode` | `buffered` / `direct` | `buffered` | How a `@Signal` write in a transaction is told: held until the commit and dropped by a rollback, or written at once whatever the transaction does later |

Every assignment and every run of an effect is logged at `debug` by the
logger `spring.flutter.signals` (`logging.level.spring.flutter.signals`).

### The site's pages: `spring.flutter.web.seo.*`

A Flutter web app draws on a canvas: its HTML holds no text, so a search
engine, a link preview or a language model sees an empty page. With
`spring.flutter.web.seo.enabled`, the generator gives every page of the
site real HTML, made from the same sources the app shows, without a
second version of the site to keep up:

- **A page per address.** For each route and each Markdown file, a copy
  of `web/index.html` with the page's own `<head>`: `<title>`,
  `description`, `canonical`, the `og:*` tags of link previews, and
  `robots` (`noindex` where asked). The site's root page is
  `web/index.html` itself.
- **The page's text, hidden.** The text goes into the page as plain HTML
  (`<main id="spring-content">`) under the page loader, and then under
  Flutter's view: a visitor never sees it, it is never removed, and a
  crawler reads it. It is the page's Markdown as HTML; a screen without
  Markdown has its `<head>` only (title, description, preview).
- **Files for crawlers and models.** `sitemap.xml` and `robots.txt`;
  `llms.txt` (a map of the Markdown pages) and `llms-full.txt` (all their
  text); `<path>.md`, the Markdown as written, next to each Markdown
  page.

#### Turning it on

Put the keys in the web profile's file, since only the web build reads
them. `site-url` is required: it makes the absolute addresses of
`canonical`, `og:url` and the sitemap.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
# lib/resources/application-web.yml
spring:
  flutter:
    web:
      seo:
        enabled: true
        site-url: https://spring-dart.dev
        from-routes: true
        title: '{title} · Spring Dart'
        description: Spring Boot for Dart servers and Flutter apps.
        image: resources:images/preview.png
        content:
          - location: resources:content/blog/
            path: /blog
            exclude: ['_*.md']
        pages:
          - path: /
            title: Spring Dart
```

</td><td>

```properties
# lib/resources/application-web.properties
spring.flutter.web.seo.enabled=true
spring.flutter.web.seo.site-url=https://spring-dart.dev
spring.flutter.web.seo.from-routes=true
spring.flutter.web.seo.title={title} · Spring Dart
spring.flutter.web.seo.description=Spring Boot for Dart servers and Flutter apps.
spring.flutter.web.seo.image=resources:images/preview.png
spring.flutter.web.seo.content[0].location=resources:content/blog/
spring.flutter.web.seo.content[0].path=/blog
spring.flutter.web.seo.content[0].exclude[0]=_*.md
spring.flutter.web.seo.pages[0].path=/
spring.flutter.web.seo.pages[0].title=Spring Dart
```

</td></tr>
</table>

Then build as usual: `dart run build_runner build` writes the pages into
`web/`, and `flutter build web` copies them into `build/web/`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.flutter.web.seo.enabled` | `true` / `false` | `false` | Whether the pages are written |
| `spring.flutter.web.seo.site-url` | absolute URL | none (required) | The site's address: `canonical`, `og:url` and the sitemap. Its path is where the app is served (`https://example.com/docs/` for an app under `/docs/`) |
| `spring.flutter.web.seo.from-routes` | `true` / `false` | `false` | Every screen of the navigation is a page (see below) |
| `spring.flutter.web.seo.exclude` | globs | none | Files of every Markdown folder, the routes' and `content[n]`'s, that make no page: `['**/contents*.md']` for a table of contents the site reads for its menu. `*` matches within a folder, `**` across folders, and `**/` no folder too |
| `spring.flutter.web.seo.title` | text with `{title}` | `{title}` | The `<title>` of every page; `{title}` is the page's own title |
| `spring.flutter.web.seo.description` | string | none | The description of a page that has none of its own |
| `spring.flutter.web.seo.image` | `resources:` location or URL | none | The preview image (`og:image`, `twitter:image`) of a page that has none of its own; with one, link previews (messengers, X, Slack) show a large card (`twitter:card: summary_large_image`). About 1200×630 |
| `spring.flutter.web.seo.site-name` | text | none | The site's name in link previews (`og:site_name`) |
| `spring.flutter.web.seo.content[n].location` | `resources:` folder | none | A folder of Markdown files, a page per file |
| `spring.flutter.web.seo.content[n].path` | path | `/` | The folder's address: `first.md` is `<path>/first`, `index.md` is `<path>` itself |
| `spring.flutter.web.seo.content[n].exclude` | list of globs | none | Files of the folder left out (`_*.md`) |
| `spring.flutter.web.seo.pages[n].path` | path | none | A page by hand, or the page of a route whose values below override the route's |
| `spring.flutter.web.seo.pages[n].title` | string | the route's title | The page's title |
| `spring.flutter.web.seo.pages[n].description` | string | the route's | The page's description |
| `spring.flutter.web.seo.pages[n].image` | `resources:` location or URL | the route's | The page's preview image |
| `spring.flutter.web.seo.pages[n].index` | `true` / `false` | the route's | `false`: `noindex`, and not in the sitemap |
| `spring.flutter.web.seo.sitemap` | `true` / `false` | `true` | Whether `sitemap.xml` and `robots.txt` are written |
| `spring.flutter.web.seo.llms` | `true` / `false` | `true` | Whether `llms.txt` and `llms-full.txt` are written |
| `spring.flutter.web.seo.markdown` | `true` / `false` | `true` | Whether `<path>.md` is written next to a Markdown page |
| `spring.flutter.web.seo.page-files` | `directory` / `html` | `directory` | How a page's file is named. `directory`: `<path>/index.html`; a static host serves it only after a redirect from `<path>` to `<path>/`, so the canonical address, `og:url`, the languages' links and the sitemap end with `/`. `html`: `<path>.html`; Cloudflare Pages, GitHub Pages and Netlify serve it at `<path>` itself with no redirect, and the addresses have no `/` at the end. A canonical address that redirects keeps a page out of search engines, so it always matches what the host serves |

#### Where the pages come from

Three sources, which can be combined:

1. **The routes** (`from-routes: true`, with
   `spring_boot_starter_flutter_navigation`). Every screen whose path has
   no variables is a page (`/about`). A screen that shows a folder of
   Markdown (`@ScreenRoute('/docs/{*path}', content:
   'resources:content/docs/')`) gives a page per file:
   `content/docs/core/beans.md` is `/docs/core/beans`. A screen with
   other path variables has no page unless `@RouteInfo(paths: [...])`
   lists its addresses. A guarded screen (`@PreAuthorize`) gets
   `noindex` and stays out of the sitemap.
2. **Markdown folders** (`content[n]`), for pages that are no screen of
   their own.
3. **Pages by hand** (`pages[n]`), for anything else, or to change what a
   route says about itself (a longer title on `/`).

`@RouteInfo` next to `@ScreenRoute` says what a screen's page needs
beyond navigation:

```dart
@ScreenRoute('/', title: 'Spring Dart')
@RouteInfo(description: 'Spring Boot for Dart servers and Flutter apps.')
class HomePage extends StatelessWidget { ... }

@ScreenRoute('/catalog/books/{isbn}', title: 'Book')
@RouteInfo(paths: ['/catalog/books/978-0441013593'])
class BookPage extends StatelessWidget { ... }

@ScreenRoute('/checkout')
@RouteInfo(index: false, link: false)
class CheckoutPage extends StatelessWidget { ... }
```

| `@RouteInfo` | Default | Meaning |
|---|---|---|
| `description` | none | The text under the title in a search result and a link preview; `#{key}` is a message key |
| `image` | none | The preview picture (`resources:images/book.png`, or a URL) |
| `index` | `true` | `false`: the page gets `noindex` and stays out of the sitemap |
| `paths` | none | The addresses of a screen with path variables, which the build cannot know |
| `link` | `true` | `false`: a deep link from outside the app does not open the screen (see [Navigation](#navigation)) |

A screen's `title:` is the page's title; `#{key}` in a title or a
description is read from the default messages (`messages.properties`).

A Markdown page may start with a front matter; without a `title`, its
first `#` heading is the title:

```markdown
---
title: Beans
description: How the container creates, wires and scopes beans.
image: resources:images/beans.png
index: true
---

# Beans
...
```

Links between the Markdown files become the site's addresses
(`beans.md#scopes` from `/docs/core/configuration` is
`/docs/core/beans#scopes`). The build fails on a link to a Markdown file
that is no page, on two files with one address, and without `site-url`.
HTML written in the Markdown is kept as text, in the page and in the app.

#### What is written, and what to commit

The generator writes into `web/`: `<path>/index.html` per page, the
root page into `web/index.html` between `spring:seo` markers, and
`sitemap.xml`, `robots.txt`, `llms.txt`, `llms-full.txt` and the `.md`
files. It lists them in `web/.spring-seo`, and deletes a page that is
gone at the next build. The files are generated: commit them if the site
is built elsewhere from the repository without `build_runner`, or add
them to `.gitignore` (the folders of the pages, the `.txt`, `.xml` and
`.md` files, and `web/.spring-seo`).

A preview image given as `resources:images/preview.png` is written as
`<site-url>/assets/lib/resources/images/preview.png`: the address
`flutter build web` gives a Flutter asset. List the image's folder under
`flutter: assets:` in `pubspec.yaml`, or give an absolute URL.

#### Serving the site

The pages are files named `<path>/index.html`, so the server must answer
`/docs/core/beans` with `docs/core/beans/index.html`:

- **Static hosts** (Cloudflare Pages, GitHub Pages, Netlify, Firebase
  Hosting) do that, and answer other addresses of the app with the root
  `index.html` when told to.
- **`spring_boot_starter_web`** does with
  `spring.web.resources.directory-index: true`: `/docs/core/beans` gets
  `docs/core/beans/index.html`, before `spa-fallback` answers the other
  addresses with the root `index.html`. Without it, only `/` gets its
  page and a crawler reads the root page's text and `<head>` everywhere.
  [`example/seo_site`](../example/seo_site/README.md) is served this way.

Keep `spring.flutter.navigation.web.url-strategy` at `path`, its default:
the pages have the app's addresses (`/docs/core/beans`), while the `hash`
strategy puts the route after a `#` (`/#/docs/core/beans`), which a
crawler does not follow and these pages do not match.

#### Languages

With `spring.flutter.navigation.languages` (`[en, ja]`), the build writes
every page in each language: the default one at its address, the others
under `/<language>` (`/ja/docs/getting-started`), the addresses the app
itself opens.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  flutter:
    navigation:
      languages: [en, ja]
```

</td><td>

```properties
spring.flutter.navigation.languages=en,ja
```

</td></tr>
</table>

- **Titles and descriptions:** `#{key}` from that language's messages
  (`messages_ja.properties`), else the default ones.
- **Markdown:** the translation sits next to the file, with the language
  before `.md`: `getting-started.ja.md` next to `getting-started.md`. Its
  front matter gives the page's title and description; a link in it may
  name `routing.md` or `routing.ja.md`, both lead to `/ja/...`. A
  translation file makes no page of its own. The app's Markdown screens
  (`RouteContentView`) show the same translation under `/ja`.
- **No translation:** the page is written anyway (the address works), with
  the default language's text, its `canonical` the default language's
  page, `noindex`, out of the sitemap and of the alternates.
- **Every page** gets `<html lang="...">`; a translated page gets
  `<link rel="alternate" hreflang="...">` for each language that has its
  text, and `x-default` for the default one; the sitemap lists each
  translated page with its `xhtml:link` alternates. `llms.txt` and
  `llms-full.txt` stay in the default language; the `.md` copy of a
  translation is at `/ja/<path>.md`.

### The browser cache of the web build: `web/_headers`

The generator reads Spring Boot's keys
`spring.web.resources.cache.cachecontrol.*` (the same as the web server's,
section 18) at build time and writes the app's `web/_headers`, the headers
file of Cloudflare Pages, which `flutter build web` copies into the build.

```yaml
# lib/resources/application-web.yml
spring:
  web:
    resources:
      cache:
        cachecontrol:
          max-age: 30d
          cache-public: true
```

A Flutter web build names its files without a hash (`index.html`,
`main.dart.js`, `main.dart.wasm`, `flutter_bootstrap.js`), so the block
the build writes between `# spring:cache:start` and `# spring:cache:end`
gives every path `no-cache`, the keys' `Cache-Control` to `/assets/*`
(the app's images and fonts; `max-age=2592000, public` above), and
`no-cache` again to the assets that change with every build:
`/assets/AssetManifest*`, `/assets/FontManifest.json`, `/assets/NOTICES`,
`/assets/*/manifest.json`, `/assets/shaders/*`, the icon fonts Flutter
cuts to the icons the app uses (`/assets/fonts/MaterialIcons-Regular.otf`,
`/assets/packages/cupertino_icons/*`) and the app's resources read at run
time (`/assets/lib/resources/*`: Markdown pages, messages, a search
index). Each rule first takes off the earlier rules' header
(`! Cache-Control`, Cloudflare's syntax), so the last rule that matches
wins. The app's own rules before and after the
block stay as they are; the file is made when missing. Without the keys
the block is removed (the file too when nothing else is in it); a value
that cannot be read fails the build and leaves the file as it is.
`spring.web.resources.cache.period` and `use-last-modified` are the
server's alone.

On a domain of its own the site is behind the zone's cache settings,
which come after the file: with Caching → Configuration → Browser Cache
TTL set to a time (4 hours, the default of older zones), Cloudflare puts
that time in place of `no-cache` on the files it counts as static
(scripts, images, fonts). `flutter_bootstrap.js`, `main.dart.js` (the
build every browser but Chromium's runs, Flutter's default: Safari,
Firefox and every browser on iOS) and the icon fonts are then kept up to
that long after a deploy, and a phone shows the build before it. Set
Browser Cache TTL to *Respect Existing Headers* (or a Cache Rule's
browser TTL to the origin's), so the file decides;
`curl -sI https://<site>/main.dart.js` then says `cache-control: no-cache`.

---

## 18. Reference: web server

`spring_boot_starter_web` runs the application's controllers on a
`dart:io` HTTP server. It reads Spring Boot's `server.*` keys for the
port, TLS and shutdown, the keys of the controllers' server-sent events,
the static resources (`spring.web.resources.*`,
`spring.mvc.static-path-pattern`), and the upload limits
(`spring.web.multipart.*`; see the starter's
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
    static-path-pattern: /**
    async:
      request-timeout: 30m
    sse:
      heartbeat-interval: 15s
  web:
    resources:
      static-locations: file:build/web/
      spa-fallback: true
      directory-index: true
      cache:
        period: 1h
      chain:
        compressed: true
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
spring.mvc.static-path-pattern=/**
spring.mvc.async.request-timeout=30m
spring.mvc.sse.heartbeat-interval=15s
spring.web.resources.static-locations=file:build/web/
spring.web.resources.spa-fallback=true
spring.web.resources.directory-index=true
spring.web.resources.cache.period=1h
spring.web.resources.chain.compressed=true
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
| `server.request-timeout` | duration; `0` or less for none | `60s` | The longest a request's filters and handler may take to answer. The default ends a request whose body trickles in without ever being idle; raise it for handlers or uploads that rightly take longer. When it passes before the answer starts, the answer is a 503 `ProblemDetail` with a generic detail (`AsyncRequestTimeoutException`, logged as a warning, at most once per 10 seconds), what the handler does afterwards is dropped, and the request's `RequestDeadline` has run out for the code it called (see [Deadlines](#deadlines-one-limit-for-a-request-and-the-calls-it-makes)). Not applied to a response that became a stream (server-sent events, a streamed body: `spring.mvc.async.request-timeout` limits an `SseEmitter`) or to a WebSocket handshake. A response already being sent is left alone. The time the handler spends reading a slow upload counts; `server.connection-timeout` still ends a body that sends nothing. This starter's own key: Spring Boot has none |
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
| `spring.mvc.static-path-pattern` | path pattern | `/**` | The path pattern the static resources of `spring.web.resources.static-locations` are served under (`/assets/**` serves `static/app.css` as `/assets/app.css`). The welcome page only with `/**`, as in Spring Boot |
| `spring.web.resources.static-locations` | list of locations | `resources:static/`, `resources:public/` | Where the static resources are read from, in order: folders of `lib/resources/` (`resources:`, embedded by the generator) and directories read at run time (`file:build/web/`). Spring Boot's defaults with `classpath:` written `resources:`, without `META-INF/resources/` and `resources/`. The root of `lib/resources/` (`resources:`) and other prefixes stop the start |
| `spring.web.resources.add-mappings` | bool | `true` | `false` turns off the default mapping and the welcome page; mappings of `WebMvcConfigurer.addResourceHandlers` stay |
| `spring.web.resources.spa-fallback` | bool | `false` | For a single-page app: a `GET` or `HEAD` of a path that is no file and no handler, whose last segment has no extension and whose `Accept` names `text/html`, gets the `index.html` of the locations instead of a 404 (never under `.well-known/`). This starter's own key: Spring Boot has none |
| `spring.web.resources.directory-index` | bool | `false` | A path with no file whose folder holds an `index.html` gets that file: `/guide` and `/guide/` get `guide/index.html`, as static hosts answer (the pages `spring.flutter.web.seo.*` writes are such files). Asked before `spa-fallback`; found as any file, inside the locations, with the same checks. This starter's own key: Spring Boot's welcome page covers `/` only |
| `spring.web.resources.cache.period` | duration (seconds without a unit) | — (no `Cache-Control`) | `Cache-Control: max-age` of the static resources; `0` sends `no-store`. The `cachecontrol.*` keys win over it |
| `spring.web.resources.cache.use-last-modified` | bool | `true` | Whether `Last-Modified` is sent and `If-Modified-Since` checked |
| `spring.web.resources.cache.cachecontrol.max-age` | duration (seconds without a unit) | — | `max-age` |
| `spring.web.resources.cache.cachecontrol.no-cache` / `no-store` | bool | — | `no-cache` / `no-store` (which wins over `no-cache` and `max-age`) |
| `spring.web.resources.cache.cachecontrol.must-revalidate` / `no-transform` / `cache-public` / `cache-private` / `proxy-revalidate` | bool | — | The directive of the same name (`public`, `private` for the `cache-` ones) |
| `spring.web.resources.cache.cachecontrol.s-max-age` / `stale-while-revalidate` / `stale-if-error` | duration (seconds without a unit) | — | `s-maxage`, `stale-while-revalidate`, `stale-if-error` |
| `spring.web.resources.chain.compressed` | bool | `false` | Serves `app.js.br` (first) or `app.js.gz` next to `app.js` to a client whose `Accept-Encoding` takes it, with `Content-Encoding` and `Vary: Accept-Encoding`. `chain.enabled`, `chain.cache` and the version strategies are not supported |
| `server.mime-mappings.<extension>` | media type | — | More media types of the static resources by extension, on top of the built-in ones (`server.mime-mappings.wasm=application/wasm`) |
| `spring.web.multipart.enabled` | bool | `true` | `false`: `multipart/*` requests are not parsed, and `@RequestPart` parameters answer 400 |
| `spring.web.multipart.max-file-size` | data size, or `-1` | `1MB` | The largest file (or other part) of an upload; above it the answer is 413 (`MaxUploadSizeExceededException`). `-1` means no limit |
| `spring.web.multipart.max-request-size` | data size, or `-1` | `10MB` | The largest multipart request as a whole; above it the answer is 413. `-1` means no limit |
| `spring.web.multipart.max-part-count` | int, or `-1` | `50` | The most parts (files and fields) of a multipart request; above it the answer is 413. This starter's own key: Spring Boot sets the same limit on Tomcat with `server.tomcat.max-part-count` (50) |
| `spring.web.multipart.file-size-threshold` | data size | `0B` | Files above this size are written to a temporary file; smaller ones stay in memory. With `0B` every file goes to a temporary file (in memory where there is no `dart:io`). Temporary files are deleted after the request |
| `spring.web.multipart.location` | directory path | the system's temporary directory | Where the private directory (`0700`) of the uploads' temporary files is made; the files have random names and are deleted when the request ends or fails |
| `spring.web.rate-limit.enabled` | bool | not set: on when `rules` has a rule | Whether requests are rate limited. An application that only uses `@RateLimiter` sets it to `true` (the start fails when a controller has the annotation and nothing turned the limiter on); `false` turns the rules and the annotations off. This starter's own keys: Spring Boot has no rate limiter (see [Rate limiting](#rate-limiting)) |
| `spring.web.rate-limit.store` | `memory` / `primary-isolate` / `jdbc` / `procedure`, or the name of another library's store | not set: the most specific the application has | Where the buckets are kept: `procedure` (a database function through the REST API; Supabase starter, the default on its REST path), `jdbc` (a table of the primary `DataSource`; data starter, the default with one), `primary-isolate` (the first isolate, for all of a pool; the default with `server.isolates.*`), `memory` (this isolate). A `RateLimitStore` bean of the application wins over all. A store the application does not have fails the start |
| `spring.web.rate-limit.on-store-failure` | `deny` / `allow` | `deny` | When the store cannot be reached: `deny` answers 503 with `Retry-After`, `allow` lets the request through, not counted. One WARN line on `spring.web.ratelimit` (at most every 10 s) names the rule, never the key |
| `spring.web.rate-limit.verify-store` | bool | `true` | Whether the store is asked at startup that its table, database function or binding is there: without it the application does not start, and says what to run. A store that cannot be reached then is a WARN. `false` skips the check and its one call |
| `spring.web.rate-limit.store-failure-retry-after` | duration | `5s` | The `Retry-After` of that 503 |
| `spring.web.rate-limit.trusted-proxies` | list of addresses and CIDR ranges (IPv4, IPv6) | empty | The reverse proxies in front of the server. Only a connection from one of them has `client-address-header` read; the client is the entry the first trusted proxy added, counting from the right, and everything to the left of it is ignored. Empty: no header is ever read, the client is the connection's own address |
| `spring.web.rate-limit.client-address-header` | header name | `X-Forwarded-For` | The header a trusted proxy puts the client's address in: a list read from the right, or one address (`CF-Connecting-IP`) |
| `spring.web.rate-limit.ipv6-prefix-length` | int, 1 to 128 | `64` | How many bits of an IPv6 address say who a client is: the client is counted by that prefix, the rest zeroed, so every address of one /64 (the network a provider gives one client, who may change the other 64 bits at every request) shares a bucket. `128` counts every address by itself. IPv4 addresses, also mapped into IPv6 (`::ffff:a.b.c.d`), are counted whole; the trusted proxies are compared by their whole address. Outside 1..128 fails the start |
| `spring.web.rate-limit.hash-addresses` | bool | `false` | Stores the keys made of an address as their HMAC-SHA-256 under `hash-secret`, so the store holds no address in clear |
| `spring.web.rate-limit.hash-secret` | string | — | The secret of `hash-addresses` (required with it; the same on every server that shares a store) |
| `spring.web.rate-limit.headers` | bool | `true` | Whether the answers carry `RateLimit-Limit`, `RateLimit-Remaining` and `RateLimit-Reset` (seconds) of the rule that leaves the least |
| `spring.web.rate-limit.memory.max-entries` | int | `100000` | The most keys the stores in memory (`memory`, `primary-isolate`) keep; past it the buckets that are full again go, then the keys not used for the longest |
| `spring.web.rate-limit.rules[n].name` | string | `rule-<n+1>` | The rule's name: the first part of its keys in the store (`<name>:ip:<address>`, `<name>:user:<name>`) and what the logs call it |
| `spring.web.rate-limit.rules[n].path` | path pattern | `/**` | The paths the rule is for, inside the context path |
| `spring.web.rate-limit.rules[n].methods` | list of HTTP methods | empty: all | The methods the rule is for |
| `spring.web.rate-limit.rules[n].key` | `user` / `ip` / `#{...}` / a key of a `RateLimitKeyResolver` bean | `user` | Who a bucket belongs to: `user` is the authenticated user, else the client's address (decided right after the security filter chain); `ip` is the client's address (decided before any authentication); `#{...}` is a SpEL expression over `request`, `headers` (also `request.headers`; a name is found in any case: `#{request.headers['X-Api-Key']}`), `principal`, `authentication`, `address`, `method`, `path`, which counts by address when it gives nothing (a header the request does not have, no user). An expression that cannot be parsed fails the start naming the rule; one that reads what does not exist (`request.header`) counts by address and logs one WARN line for the rule on `spring.web.ratelimit`, once |
| `spring.web.rate-limit.rules[n].limit` | `<count>/<duration>` | — (required) | The limit: `5/1m`, `120/1m`, `10/s`. A token bucket: `count` requests at once, refilled evenly over the duration |
| `spring.web.rate-limit.rules[n].burst` | int | the count of `limit` | The most requests at once, when it is not the count |
| `spring.web.rate-limit.rules[n].on-store-failure` | `deny` / `allow` | `spring.web.rate-limit.on-store-failure` | The same for this rule |
| `spring.test.web-environment` | `mock` / `random-port` / `defined-port` / `none` | not set: a server starts | Set by `springBootTest(webEnvironment:)` and `@SpringBootTest(webEnvironment:)` (`mock` by default) and by `ApplicationContextRunner` (`mock`). In tests only `random-port` (port `0`) and `defined-port` start a server |
| `local.server.port` | int, **written by the server** | — | The port the server listens on, set once it listens (also in `WebServerInitializedEvent`). Read it; do not set it |

The static resources (the starter's
[Static resources](../spring_boot_starter_web/README.md#static-resources)
section) answer with `Content-Type` by extension and
`X-Content-Type-Options: nosniff`, a weak `ETag`, `Last-Modified`,
`Range` and `HEAD`; they never serve a dot file (except under
`.well-known/`) or anything outside their location.

An invalid `server.port`, `server.shutdown` or `server.ssl.client-auth`,
or a certificate without its private key, fails the start naming the key.
The certificate files are paths in the file system, not `resources:`
locations. Mappings are logged at debug level under the logger
`spring.web.mvc` (`logging.level.spring.web.mvc=debug`), and the server
under `spring.web.server`.

### Rate limiting

```yaml
spring:
  web:
    rate-limit:
      trusted-proxies: [173.245.48.0/20]   # the proxies in front
      rules:
        - path: /api/auth/**               # logins: by address, before
          methods: [POST]                  # any authentication work
          key: ip
          limit: 5/1m
        - path: /api/**                    # the API: by user
          limit: 120/1m
```

```properties
spring.web.rate-limit.trusted-proxies=173.245.48.0/20
spring.web.rate-limit.rules[0].path=/api/auth/**
spring.web.rate-limit.rules[0].methods=POST
spring.web.rate-limit.rules[0].key=ip
spring.web.rate-limit.rules[0].limit=5/1m
spring.web.rate-limit.rules[1].path=/api/**
spring.web.rate-limit.rules[1].limit=120/1m
```

A request past a limit is answered with a 429 `ProblemDetail` and
`Retry-After`, before its body is read. Every rule that matches a request
applies; it passes only when all of them allow it. Rules keyed by `ip`
run in a filter before the sessions and the security filter chain; rules
keyed by `user` or an expression run right after the chain (a request the
chain answered itself, such as a 401, does not reach them: limit those by
`ip`). On a controller, `@RateLimiter('10/1m', key: '#{authentication.name}')`
does the same for a method or a class. The buckets are kept in the
store of `spring.web.rate-limit.store`; the SQL of the stores in a
database is in their packages (`spring.data.jdbc.rate-limit.*` in
[section 20](#20-reference-sql-databases), `spring.supabase.rate-limit.function`
under [Supabase](#supabase-springsupabase)). The whole of it is in the
web starter's
[Rate limiting](../spring_boot_starter_web/README.md#rate-limiting)
section.

### Deadlines: one limit for a request and the calls it makes

`server.request-timeout` (a minute unless set; `0` for none) is more than
a timer: the request runs under a
`RequestDeadline` (`spring_web_dart`) of that length, carried in the
`Zone` like a transaction, so that code the request calls can read it:
`RequestDeadline.current` is the deadline (or `null`), with `remaining`,
`isExpired` and `check()`, which throws a `RequestDeadlineExceededException`.
A deadline started inside another ends at the earlier of the two, never
later, and `RequestDeadline.run(budget, body)` starts one in code of your own.

`RestClient` honours it, and so do the HTTP service clients
([section 15](#15-reference-http-clients)). A call a controller makes
never outlives the request: it is not sent when the deadline has passed,
its connect and read timeouts are capped by what remains, and it is given
up when the time is gone (a `ResourceAccessException`); a `@Retryable`
pause that would end past the deadline is not made, and the request is
answered with the 503. Nothing else is interrupted: Dart cannot
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
- `server.max-http-request-header-size`;
- key stores and SSL bundles (`server.ssl.key-store`, `server.ssl.bundle`);
- `server.error.*` and `spring.mvc.problemdetails.enabled`: errors are
  `ProblemDetail` instances (except the plain-text answers Spring gives too: a
  refused CORS request or WebSocket handshake);
- `spring.web.cors.*`;
- the `server.tomcat.*`, `jetty`, `undertow` and `netty` keys; there is
  no connection limit (Tomcat's `max-connections`).

### Actuator: `management.*`

`spring_boot_starter_actuator` answers Spring Boot Actuator's endpoints
under `/actuator` (its
[README](../spring_boot_starter_actuator/README.md)). The keys are Spring
Boot's; `access` (Spring Boot 3.4+) and `enabled` (Spring Boot 2–3) are
both read, `access` first.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
management:
  endpoints:
    web:
      base-path: /actuator
      exposure:
        include: health,info
  endpoint:
    health:
      show-details: when-authorized
      roles: ADMIN
      probes:
        enabled: true
      group:
        core:
          include: ping,db
  info:
    git:
      mode: full
```

</td><td>

```properties
management.endpoints.web.base-path=/actuator
management.endpoints.web.exposure.include=health,info
management.endpoint.health.show-details=when-authorized
management.endpoint.health.roles=ADMIN
management.endpoint.health.probes.enabled=true
management.endpoint.health.group.core.include=ping,db
management.info.git.mode=full
```

</td></tr>
</table>

**Endpoints and their exposure**

| Key | Type | Default | Meaning |
|---|---|---|---|
| `management.endpoints.web.base-path` | path | `/actuator` | Where the endpoints are; `/` puts them at the root, without the discovery page |
| `management.endpoints.web.exposure.include` | comma list | `health` | The ids exposed over HTTP; `*` for all |
| `management.endpoints.web.exposure.exclude` | comma list | — | The ids not exposed; wins over `include` |
| `management.endpoints.web.path-mapping.<id>` | path | the id | Another path of an endpoint (`path-mapping.health=healthcheck`) |
| `management.endpoints.web.discovery.enabled` | bool | `true` | The base path answers the `_links` of the exposed endpoints |
| `management.endpoint.<id>.enabled` | bool | `true` | Whether the endpoint exists (`health`, `info`, `mappings`, your own) |
| `management.endpoint.<id>.access` | `none` / `read-only` / `unrestricted` | — | Spring Boot 3.4's switch; `none` disables the endpoint |
| `management.endpoints.enabled-by-default` | bool | — | The default of every `management.endpoint.<id>.enabled` |
| `management.endpoints.access.default` | `none` / `read-only` / `unrestricted` | — | The default of every `management.endpoint.<id>.access` |

**Health**

| Key | Type | Default | Meaning |
|---|---|---|---|
| `management.endpoint.health.show-details` | `never` / `when-authorized` / `always` | `never` | Who sees the details of the indicators; `when-authorized` is a logged-in user (with the security starter) |
| `management.endpoint.health.show-components` | same | as `show-details` | Who sees the components by name |
| `management.endpoint.health.roles` | comma list | — | The roles `when-authorized` asks for (any one); `ADMIN` matches the authority `ROLE_ADMIN` |
| `management.endpoint.health.status.order` | comma list | `down,out-of-service,up,unknown` | The statuses from the most severe; the first one of the parts is the aggregate |
| `management.endpoint.health.status.http-mapping.<status>` | int | `down` and `out-of-service`: 503 | The HTTP status of a health status; setting one replaces the defaults |
| `management.endpoint.health.group.<name>.include` / `.exclude` | comma list | all / — | The members of a group at `/actuator/health/<name>` (`db/primary` for a part of a composite) |
| `management.endpoint.health.group.<name>.show-details` / `.show-components` / `.roles` / `.status.*` | as above | the endpoint's | The rules of the group |
| `management.endpoint.health.group.<name>.additional-path` | `server:/path` | — | The group at another path of the server too |
| `management.endpoint.health.probes.enabled` | bool | on Kubernetes and Cloud Foundry | The `liveness` and `readiness` groups (and their indicators) |
| `management.endpoint.health.probes.add-additional-paths` | bool | `false` | The probes at `/livez` and `/readyz` too |
| `management.endpoint.health.validate-group-membership` | bool | `true` | A group naming a contributor that does not exist stops the start |
| `management.endpoint.health.logging.slow-indicator-threshold` | duration | `10s` | An indicator slower than this is logged as a warning |
| `management.health.defaults.enabled` | bool | `true` | The default of every indicator's `enabled` |
| `management.health.<name>.enabled` | bool | `defaults.enabled` | Whether the indicator `ping`, `diskspace` or `db` exists |
| `management.health.livenessstate.enabled` / `readinessstate.enabled` | bool | `false` | The availability indicators without the probes |
| `management.health.securityContext.enabled` | bool | `false` | The security starter's `securityContext` indicator: whether an authentication is set outside every request now (`programWideAuthentication`) and how many times one was (`setOutsideRequests`); always `UP`. Not in Spring Boot |
| `management.health.diskspace.path` | path | `.` | The path whose file system is checked |
| `management.health.diskspace.threshold` | data size | `10MB` | The least free space that is `UP` |

**Info**

| Key | Type | Default | Meaning |
|---|---|---|---|
| `management.info.defaults.enabled` | bool | `true` | The default of `build` and `git` |
| `management.info.build.enabled` / `git.enabled` | bool | `defaults.enabled` | The build and git details, when their files exist |
| `management.info.git.mode` | `simple` / `full` | `simple` | The branch, short commit id and time, or every key |
| `management.info.env.enabled` | bool | `false` | The `info.*` properties, without the prefix |
| `management.info.os.enabled` / `dart.enabled` | bool | `false` | The operating system; the Dart version (Spring Boot's `java`) |
| `spring.info.build.location` / `.encoding` | location / charset | `resources:build-info.properties` / `UTF-8` | The build's `build.*` keys (Spring Boot: `classpath:META-INF/build-info.properties`) |
| `spring.info.git.location` / `.encoding` | location / charset | `resources:git.properties` / `UTF-8` | The `git.*` keys |
| `info.*` | any | — | Free details shown with `management.info.env.enabled=true` |

Not supported yet: `management.server.*` (a port of the endpoints' own),
`management.endpoints.web.cors.*`, `management.endpoints.jmx.*`, and the
endpoints other than `health`, `info` and `mappings`.

### Security: `spring.security.*`

The keys of `spring_boot_starter_security` and of `spring_security_core`, which it brings (the OAuth2 clients' are in
[section 19](#19-reference-oauth2-clients)). The rules themselves are
code: a `SecurityFilterChain` bean (see the starter's README).

```properties
spring.security.user.name=admin
spring.security.user.password=change-me
spring.security.user.roles=ADMIN
spring.security.cookie.secret=${COOKIE_SECRET}
spring.security.session.maximum-sessions=3
spring.security.oauth2.resourceserver.jwt.issuer-uri=https://login.example.com
spring.security.oauth2.resourceserver.jwt.audiences=my-api
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.security.user.name` | string | `user` | The default user, while the application has no users of its own |
| `spring.security.user.password` | string | random, logged at startup | Its password (`{noop}` unless it starts with an `{id}`) |
| `spring.security.user.roles` | list | none | Its roles |
| `spring.security.filter.order` | int | `-100` | The place of the security filter among the web filters |
| `spring.security.cookie.secret` | string, 32 characters or more | a random key per process | Signs the cookies kept before a login (the page to come back to, the OAuth 2.0 authorization request); the same value on every instance behind a proxy. Not in Spring Boot |
| `spring.security.session.maximum-sessions` | int | `10` | The most sessions per user in every chain with sessions; `-1` for none (Spring's default). Not in Spring Boot |
| `spring.security.session.max-sessions-prevents-login` | bool | `false` | At the limit, refuse the new login instead of ending the user's least recently used session. Not in Spring Boot |
| `spring.security.password-checks.max-concurrent` | int | half the processors | Password hashes computed at once. Not in Spring Boot |
| `spring.security.password-checks.max-queued` | int | eight times `max-concurrent` | Logins waiting for a hash; beyond that a `503` with `Retry-After: 1`. Not in Spring Boot |
| `spring.security.oauth2.resourceserver.jwt.issuer-uri` | URL | none | The provider; its keys come from its metadata |
| `spring.security.oauth2.resourceserver.jwt.jwk-set-uri` | URL | none | The provider's public keys |
| `spring.security.oauth2.resourceserver.jwt.secret-key` | string, 32 bytes or more | none | The secret shared with a provider that signs with HS256, HS384 or HS512, as its UTF-8 bytes; not with `jwk-set-uri`; `issuer-uri` beside it is only compared with `iss`. On a server only: never in a client application. Not in Spring Boot |
| `spring.security.oauth2.resourceserver.jwt.jws-algorithms` | list | `RS256`; `HS256` with `secret-key` | With `jwk-set-uri`, or the one HMAC algorithm (`HS256`, `HS384`, `HS512`) of `secret-key` |
| `spring.security.oauth2.resourceserver.jwt.audiences` | list | none | The audiences a token must name; none: no check |
| `spring.security.oauth2.resourceserver.jwt.required-claims.<claim>` | string | none | The value a top-level claim of every token must have (a number or a boolean as its text); else a `401`. Not in Spring Boot |
| `spring.security.oauth2.resourceserver.jwt.require-expiry` | bool | `false` | Whether a token without an `exp` claim is refused (else such a token never expires, as in Spring Security); set it for an issuer whose tokens always expire |
| `spring.security.oauth2.resourceserver.jwt.authority-prefix` | string | `SCOPE_` | The prefix of the authorities read from the token |
| `spring.security.oauth2.resourceserver.jwt.authorities-claim-name` | string | `scope`, else `scp` | The claim of the authorities; without a claim of that name, a name with dots is a path into nested objects (`realm_access.roles`) |
| `spring.security.oauth2.resourceserver.jwt.authorities-claim-delimiter` | string | a space | Between authorities in that claim |
| `spring.security.oauth2.resourceserver.jwt.principal-claim-name` | string | `sub` | The claim that names the user |

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

Two keys put the token of a registration on `RestClient` calls and HTTP
service interfaces:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.security.oauth2.client.restclient.enabled` | bool | `true` | Whether every `RestClientBuilder` of the RestClient starter gets the `OAuth2ClientHttpRequestInterceptor`; it sends a token only on the calls that name a registration (`@ClientRegistrationId`, the request attribute). Not in Spring Boot |
| `spring.security.oauth2.client.restclient.client-registration-id` | string | none | The registration of the calls that name none: every such call, to any host, then carries its token. Not in Spring Boot |

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
| `spring.data.jdbc.show-sql`, `format-sql`, `show-parameters` | `false` | statements (and masked values) at info: the value of a name that looks secret (a column or parameter name that contains `password`, `token`, `secret`, `credential`, `apikey` or `privatekey`, or has the word `key`: `sslpassword`, `apiToken`, `clientSecret`; not `keyword`) is `******`, and so is a value bound without a name (a plain list to a `JdbcTemplate`); the values also show at trace, with the same masks. The generator reads `show-sql` too, without a profile: `true` keeps the three switches in every build, `false` in none, not set in debug builds only (where a profile's `show-sql: true` turns them on; the build warns that a profile-mode or a release build has no code for it) |
| `spring.data.jdbc.slow-query-threshold` | none | a slower statement is logged at warn, in every build |
| `spring.data.jdbc.rate-limit.table` | `rate_limit` | the table of the rate limiter's SQL store (`spring.web.rate-limit.store: jdbc`, the default with a primary data source): a name, or `schema.name` |
| `spring.data.jdbc.rate-limit.create-table` | only when `spring.data.jdbc.schema` is `create` or `create-drop` | whether the store creates that table when it is not there; else it comes from a migration (the SQL is in the package: `sql/rate_limit/postgresql.sql`, `sql/rate_limit/sqlite.sql`) |
| `spring.data.memory.lock-timeout` | `10s` | the in-memory store's wait for a row lock |
| `spring.data.store` | `jdbc` with a primary data source, else `memory` | the store of the repositories without `@UseStore` and `@UseDataSource`: `memory`, `jdbc`, or the name of another package's store (`supabase`); a name no store has fails the repositories when they are created, with the stores there are |

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

### Supabase: `spring.supabase.*`

The keys of `spring_boot_starter_supabase`: the
project, how the repositories reach its database, Auth, Realtime,
Storage, Edge Functions and the caches. They are this starter's own:
Spring has no Supabase support.

<table>
<tr><th>YAML</th><th>.properties</th></tr>
<tr><td>

```yaml
spring:
  supabase:
    url: https://abcd.supabase.co
    anon-key: ${SUPABASE_ANON_KEY}
    service-role-key: ${SUPABASE_SERVICE_ROLE_KEY}
    db:
      url: ${SUPABASE_DB_URL}
      rls: user
    auth:
      redirect-urls:
        - com.example.app://login
    cache:
      shared: [catalog]
```

</td><td>

```properties
spring.supabase.url=https://abcd.supabase.co
spring.supabase.anon-key=${SUPABASE_ANON_KEY}
spring.supabase.service-role-key=${SUPABASE_SERVICE_ROLE_KEY}
spring.supabase.db.url=${SUPABASE_DB_URL}
spring.supabase.db.rls=user
spring.supabase.auth.redirect-urls[0]=com.example.app://login
spring.supabase.cache.shared=catalog
```

</td></tr>
</table>

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.supabase.url` | `http://` or `https://` URL | none | The project's address (`https://<ref>.supabase.co`), without a trailing slash, user, query or fragment (else the start fails). Every service is called under it; a key or a token is only ever sent to it |
| `spring.supabase.anon-key` | string | none | The anon (publishable) key: `apikey` of every call, and the bearer token while nobody is signed in |
| `spring.supabase.service-role-key` | string | none | The service role (secret) key, used only inside `SupabaseCredentials.asServiceRole`; it passes row-level security. Server only: in a Flutter app it is warned about at startup |
| `spring.supabase.connect-timeout` | duration | `10s` | The longest the Realtime connection may take to open, unless the WebSocket client `supabase-realtime` (or `default`) sets `connect-timeout` |
| `spring.supabase.timeout` | duration | `30s` | The longest a call may take, the answer's body included; the bodies of Storage downloads are not limited |
| `spring.supabase.db.url` | `postgresql://` URL | none | The PostgreSQL address of the project or of a pooler. Set: the repositories use SQL over it (it becomes the default of `spring.datasource.url`). Not set: they use the REST API (`spring.data.store` defaults to `supabase`). In a Flutter app it is warned about at startup |
| `spring.supabase.db.rls` | `off`, `user` | `off` | As whom SQL runs: the user of `db.url`, or (`user`) the current user, with the role `authenticated` or `anon` and the token's claims in every transaction and statement. `user` through the transaction pooler (port 6543) fails the start |
| `spring.supabase.db.schema` | string | the API's (`public`) | The schema the REST API reads and writes |
| `spring.supabase.db.max-rows` | int | `1000` | The most rows the REST API returns in one answer (the project's "Max rows"); an answer that long is read on in further calls |
| `spring.supabase.auth.enabled` | bool | `true` | Whether Supabase Auth is plugged into Spring Security: the resource server's defaults on a server, the `supabaseAuth` bean, and on a server (`ModulePlatform.server`: never in a Flutter app or a browser build) the `supabaseAuthAdmin` bean |
| `spring.supabase.auth.redirect-urls` | list | empty | Where a login through a provider, a magic link or a password reset may come back to; the first is the default, any other address is refused |
| `spring.supabase.auth.issuer` | string | `<url>/auth/v1` | The issuer of the project's tokens |
| `spring.supabase.auth.jwt-secret` | string | none | The legacy JWT secret of a project that signs with HS256; it becomes the default of `…resourceserver.jwt.secret-key`. Server only: in a Flutter app it is warned about at startup |
| `spring.supabase.auth.persist-session` | bool | `true` | Keeps the session across restarts, in the application's `SecretStore` |
| `spring.supabase.auth.auto-refresh` | bool | `true` | Refreshes the access token by a timer before it expires; without it, when the next call needs it |
| `spring.supabase.auth.refresh-margin` | duration | `30s` | How long before its expiry an access token counts as expired |
| `spring.supabase.realtime.heartbeat-interval` | duration | `25s` | How often the Realtime connection says it is alive; `spring.websocket.client.config.supabase-realtime.phoenix.heartbeat-interval` wins |
| `spring.supabase.realtime.timeout` | duration | `10s` | How long a join or a message waits for its answer; `…supabase-realtime.phoenix.push-timeout` wins |
| `spring.supabase.realtime.max-message-size` | data size | `4MB` | The largest message read from Realtime; a larger one closes the connection; `…supabase-realtime.max-text-message-size` wins |
| `spring.supabase.storage.signed-url-expiry` | duration | `1h` | How long a signed URL is valid when the call does not say |
| `spring.supabase.functions.region` | string | none | The region the Edge Functions run in (the `x-region` header) |
| `spring.supabase.functions.timeout` | duration | `spring.supabase.timeout` | How long a function may take |
| `spring.supabase.cache.shared` | list | empty | The caches whose entries are the same for every user; every other cache keeps the entries of each caller (the anon key, each user, the service role) apart |
| `spring.supabase.rate-limit.function` | name of a database function | `rate_limit_acquire` | The function the rate limiter's store calls for an acquisition (`spring.web.rate-limit.store: procedure`, the default of an application on the REST path with the rate limiter on), as the service role. The table and the function come from a migration: the package's `sql/rate_limit.sql` |

On a server, with `spring.supabase.url` set and `auth.enabled` not
`false`, the starter gives the resource server of
`spring_boot_starter_security` these defaults, of the lowest precedence
(the application's own values win):

| Key under `spring.security.oauth2.resourceserver.jwt.` | Default with this starter |
|---|---|
| `jwk-set-uri` | `${spring.supabase.url}/auth/v1/.well-known/jwks.json` (without `auth.jwt-secret`) |
| `secret-key` | `${spring.supabase.auth.jwt-secret}` (with it) |
| `jws-algorithms` | `ES256,RS256`; `HS256` with `auth.jwt-secret` |
| `issuer-uri` | `${spring.supabase.auth.issuer:${spring.supabase.url}/auth/v1}` |
| `audiences` | `authenticated` |
| `required-claims.role` | `authenticated` |
| `require-expiry` | `true`: a token without `exp` is refused |
| `authorities-claim-name` | `app_metadata.roles` |
| `authority-prefix` | `ROLE_` |

The Realtime connection is the WebSocket client `supabase-realtime`
([section 16](#16-reference-websocket-clients); its `url` is not read,
the address is always the project's), and the Edge Functions are the HTTP
service group `supabase-functions`
([section 15](#15-reference-http-clients); its base URL is the
project's, and it never follows a redirect).

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

The same configuration, declared with annotations on a test class:

```dart
@SpringBootTest(properties: {'shop.max-basket-size': 3})         // above every other source
@ActiveProfiles(['test'])                                        // spring.profiles.active
@TestPropertySource(locations: ['resources:extra.properties'])  // just below properties
class ShopTest {
  @DynamicPropertySource()
  static void shopUrl(DynamicPropertyRegistry registry) =>
      registry.add('shop.url', () => server.url);                // read on every access
}
```

- `profiles` (`@ActiveProfiles`) replaces the config files'
  `spring.profiles.active`.
- `properties` (`@SpringBootTest(properties:)` and
  `@TestPropertySource(properties:)`) wins over every other source, the
  command line and `propertyFiles` included. `dynamicProperties`
  (`@DynamicPropertySource` methods) wins even over `properties`: use it
  for values known only once the tests run, such as the port of a server
  started in `setUpAll` (`@BeforeAll`).
- `propertyFiles` (`@TestPropertySource(locations:)`) are resource
  locations of `.properties` files; a later file wins. A plain path is a
  classpath location, and `test/resources/` is on the classpath. A
  missing file fails the start.
- `test/resources/` comes first on the classpath, so
  `test/resources/application-test.yml` is the `test` profile's file, and
  a file there replaces a packaged file with the same path.
- The OS environment is not visible (`systemEnvironment: {}` by default,
  `@TestEnvironment` to set it), so tests do not depend on the machine
  they run on.
- Log levels set by a test's configuration are restored afterwards.
- `const ApplicationContextRunner().withPropertyValues(['shop.beta=true'])`
  is for auto-configuration tests. It reads no config files.
- With `spring_boot_starter_web`, a test starts no server unless it asks
  for one: `springBootTest(webEnvironment: WebEnvironment.randomPort)` or
  `@SpringBootTest(webEnvironment: WebEnvironment.randomPort)`
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
| `aop_defer` | bool | `false` | In a library package without `lib/spring_auto_configuration.dart` whose modules a starter's auto-configuration imports: its `lib/` modules leave to the application the proxy classes only the application's aspects can match, as a starter's do |

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
nothing in Dart: there is no servlet container, no Jackson, no Logback
and no Flyway here. These properties have the names
below instead, and the rest of Spring Boot's names are kept.

| Spring Boot | Here |
|---|---|
| `spring.jackson.*` | `spring.json.*` |
| `spring.servlet.multipart.*` | `spring.web.multipart.*` |
| `server.servlet.context-path`, `server.servlet.session.*` | `server.context-path`, `server.session.*` |
| `logging.logback.rollingpolicy.*` | `logging.file.rolling-policy.*` |
| `spring.flyway.*` | `spring.sql.migration.*` |

An old name does not work silently: `spring_boot_dart` stops the start
(`APPLICATION FAILED TO START`) when any property source holds a key
under an old name (in a file, on the command line, in `--dart-define` flags or
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
  `spring.flutter.*` key, `spring.http.clients.allowed-addresses`,
  `server.max-http-request-body-size`,
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
  are `ProblemDetail` instances, except the plain-text answers Spring gives too
  (a refused CORS request, a refused WebSocket handshake).
- A request can have a deadline: `server.request-timeout` times the
  filters and the handler, and the `RestClient` calls inside it stop at
  what remains of it (`RequestDeadline`; see
  [Deadlines](#deadlines-one-limit-for-a-request-and-the-calls-it-makes)).
  Spring has no timeout for a synchronous request, and none that follows a
  request into the calls it makes.
- `spring.main.web-application-type` knows only `none` (no server).
- Not read: `allow-circular-references`, `keep-alive`,
  `spring.task.execution.*`, `spring.task.scheduling.pool.*`,
  `spring.aop.*`, `logging.config`,
  `logging.structured.*`, `spring.json.*` keys other than those listed
  (they are warned about and ignored), and cache stores other than
  `simple`. `management.*` and `info.*` are read by
  `spring_boot_starter_actuator` (see
  [Actuator](#actuator-management)); without it they mean nothing.
- Jackson time zones and `@Scheduled` zones: only UTC and fixed offsets
  (`@Scheduled`: UTC or local time), as Dart has no time zone database.
- Log dates are UTC.
- There is no `.env` support: configuration lives in property files.
- The `shop.*` keys in the examples are an application's own.
