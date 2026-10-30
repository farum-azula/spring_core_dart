# Fix plan

Open differences from Spring found in reviews: first against Spring
Framework 6.2 / Spring Boot 3, then four times (October 2026) against
Spring Framework 7.0, Spring Boot 4.0, Spring Cloud OpenFeign 5.0 and
Jackson 3 across every package. The items below are from the last of
those (the third pre-0.2.0 review); bugs were confirmed with probe
programs.
Items marked **High** are the ones a Spring developer trips over first.
Before 1.0 renames are made outright, with no deprecated aliases.

**0.2.0** is released only when every item under "Before 0.2.0" is done and a new full
review against Spring Framework 7 / Boot 4 / OpenFeign 5 (every package,
like the October 2026 one) finds nothing left to fix; until then releases
are patches (0.1.x).

Already fixed (with regression tests): Dart default values of
constructor parameters, empty collections for constructors and `@Bean`
methods, `@Bean` products processed like components, `@PropertySource` /
`@Import` gated by the declaring class's conditions, negated `on-profile`
documents, relative import cycles, self-references (composites,
decorators), early events reaching the parent twice, exception-safe and
re-entrant `close()`, violation messages mangled by `MessageFormat`,
`disallowedFields` bypasses, release-safe `@annotation` matching,
package-qualified AOP wildcards, SDK types as beans (`HttpClient`,
`Uint8List`, `List<String>`), proxies for `Future<T>?` members,
`toString` with parameters, members named like `Advised`'s and classes
with the same name in two directories, advice silently skipped for beans
that cannot be proxied, optional fields and setters overwritten with
`null`, `DataBinder.bind` throwing on malformed keys and failing setters,
and the order of `spring.profiles.include`. Fixed after the October 2026
review: the whole validation, binding and messages section; the logging,
cache and test starters; cron day names and lists, `@Scheduled(scheduler:)`;
in AOP `Type+`, `@target`, `this`, `args`, per-aspect named pointcuts,
`bean()` aliases and qualifiers, `Ordered` aspects, plain and ancestor
advisors, the auto proxy creator's order, `AopContext.currentProxy()`,
argument copies, async advice and `Future` methods throwing synchronously.
Second batch: `ObjectProvider` injection points, the container's exception
hierarchy, callbacks, `FactoryBean` names, ancestors in sorted beans,
registration after freezing, superclass-first injection, `ObjectFactory`;
lifecycle (lazy beans, `SmartLifecycle` defaults, `isActive`), payload
listeners, `publishEvent` before refresh, the bundle message source and
`MessageSourceAccessor`, unique context ids; profile names, legacy keys,
`--`, null values, `Duration`, lenient enums, classpath plain paths; Boot's
`@Validated` properties, validation auto-configuration, failure analyzers,
startup logging, `spring.main.*`, dotted basenames; SpEL assignment in
`SimpleEvaluationContext`, enum order, boolean selection, `+` conversion,
map selection; JSON dates with offsets and `spring.jackson.time-zone`,
serializer beans, naming acronyms, raw maps/lists, `NaN`; the HTTP types,
Feign and WebSocket items except optional paths. Third batch: YAML out of
the box, location groups and `config/*/`, relaxed binding in the
environment (camelCase Feign/WebSocket keys), `@ConfigurationProperties`
lists, maps and constructor binding, application events, full-mode
`@Configuration`, conditional beans sharing a name, inferred `@Bean` types.
Fourth batch: every item of the October 2026 review (container, context,
configuration, SpEL, generator, AOP, JSON, HTTP), including async
lifecycle, `BeanRegistrar`, async events, pause/restart, scoped proxies,
Jakarta `Provider` / `@Resource`, `classpath*:`, SpEL numbers on the web,
pointcut validation and constructor selection. Fifth batch: every item of
the pre-0.2.0 review — `@EventListener`
registration after the singletons, cron on the web, SpEL argument
conversion, JSON timestamps in seconds, polymorphism, generic classes and
the Jackson annotations, validation groups and container elements, the new
post-processor kinds, Boot's environment and config-data items, conditions,
`EnvironmentPostProcessor`, per-client Feign configuration, the HTTP types,
proxy pruning across modules, null / function / record / generic beans,
`args` / `within` by runtime and declaring type, `ProxyFactory`, the
remaining pointcut designators and `@Lookup` methods. Sixth batch: every item of the
second pre-0.2.0 review — the validation auto-configuration, `@Bean`
aspects, nested value objects, cloud platforms, self-calls on subclass
proxies, `@DeclareParents`, `execution` type patterns, JSON enums,
`defaultImpl` and mixins, SpEL real numbers on the web (tested on node in
CI), Feign form bodies and raw responses, startup failures in the log file,
class-level cache annotations, `@ConditionalOnBean` without arguments,
ordered initializers, the HTTP types, logging patterns and charsets,
WebSocket retries and the test runner. Seventh batch: every item of the
third review — subclass proxies for classes with private members and a
base class, wildcard parameters, singleton advisors, int `@JsonValue`
enums, Spring 7 safe navigation, `JsonNode` per Jackson 3, SpEL reals on
node, URL resources probed with HEAD, registrars of skipped classes, lazy
listeners, early log lines at the final levels, Feign flags, the test
starter with parents and `@Primary`, WebSocket retries, `max-history=0` and
the smaller ones (an invalid `spring.main.cloud-platform` is ignored, as in
Boot 4). Eighth batch (fourth review): status 0 for browser opaque
redirects, no `max-delay >= delay` check, wildcard parameters in full-mode
`@Bean` methods, interface parameter constraints on subclass proxies and
`BeanWrapper` list growth. Ninth batch (fifth review): zero WebSocket reconnect delays, the list grow limit in `DataBinder.construct`, method annotations not inherited from superclasses for `@annotation`, and parenthesised ternary / Elvis in `toStringAST`; starters (cache, method validation) read annotations over the whole hierarchy like Spring's find semantics. Tenth batch (sixth review): selected imports before the importer's beans under registerBean-phase conditions, and cache defaults and class-level annotations from the declaring class and its superclasses. Eleventh batch (seventh review): import order per configuration class like Spring's parser and reader, and runners registered as singletons. Twelfth batch (eighth review): Boot's bean conditions decided when beans register, like `OnBeanCondition`, and one decision per configuration class for its imports and registrars. Thirteenth batch (ninth review): components and imported classes with bean conditions decided in the reader, in class order.

## Before 0.5.0 (the review of October 2026)

Everything changed since the last review (commit `fb30bf5`): 44 commits,
the web starter, `spring_security_core`, the security starter, the OAuth2
client, the Flutter starter and Flutter security (with their Swift and
Kotlin code) entirely new. Six reviewers, every finding confirmed with a
probe program or test unless marked "read"; plus dependency scans
(OSV, Gradle, Maven), an OWASP ZAP baseline scan of the example server
(dev, logged in, `sso`), and a secrets scan of the history (gitleaks).
No authentication or authorization bypass, no token or secret leak, no
known vulnerability in what is published or shipped. 0.5.0 waits for the
items below. The rule, changed by the owner after the ninth review (each
round found fewer and smaller items, mostly edge cases of Boot parity):
0.5.0 ships when a review finds nothing High or Medium and nothing
security-relevant; its Low items go to "After 0.5.0" below and are fixed
in patch releases.

**Status: all fixed on branch `review-0.5`, each with a regression test**
(real sockets for the web server's limits, node for the scheduler, the
Android emulator for the destroyed login window, the iOS simulator for a
reinstall, Docker for libsecret, a local Spring 7 / Logback / Spring
`CronExpression` run where Spring's behaviour had to be checked). Kept as
documented differences instead of changes: an `SseEmitter` without a
timeout never ends; dart:io accepts Content-Length with
Transfer-Encoding; class-level `@DirtiesContext` means after each test;
a Feign path variable `.` / `..` is refused (Dart's `Uri` would drop it);
`htu` built from the `Host` header (audiences mitigate); RFC 9207 `iss`
ignored for a registration without `issuer-uri`. Breaking for 0.5.0:
`ResponseCookie` is validated (no longer `const`); a cron time in a
spring-forward gap is skipped, as in Spring (was moved forward). Found and
fixed on the way: the Flutter security plugin's `dartFileName` (APK, iOS
and macOS builds failed), Keychain values surviving an iOS reinstall
(cleared at the first start after one), the issuer metadata lookup
retried on every request. New in CI: the ZAP baseline scan (`.zap/`) and
a Gradle dependency scan.

**The second review (October 2026)** confirmed every fix above with
probes and found 27 new items, mostly at the edges of the fixes: none
High; Medium — a cross-site form could use `?access_token=` to skip CSRF
(with `allowUriQueryParameter`), one account could block every new login
(the session limit), the iOS privacy manifest, the WebSocket outgoing
queue unbounded (both directions), a full disk flooding the console from
the log file's recovery; Low — token `typ` and certificate-bound tokens
accepted (Spring 7.1 refuses them), invalid UTF-8 escapes as 500, bodies
without a Content-Type read as JSON, errors after commit ending a response
cleanly, Host edge cases, `..;` segments (also in the firewall with
`allowSemicolon`), the upload directory removed by the OS, WebSocket
handshake edge cases and sequential session ids, the Android login window
reused after a hot restart, the iOS reinstall marker wiped by a
preferences reset, the Linux locked-keyring check, the 0.4.x store
fallback taking another app's values, the Windows store in the cache
folder, tokens left on two restore paths, a blank application id, the
cache sweep after a burst, nullable and subclass `@TestBean` fields,
`spring.config.import` in the web dev config builder, normalized classpath
patterns, fixed-rate and cron runs under fake timers. **All fixed**, each
with a regression test that fails on the code before it; also a body that
stalls now times out (`server.connection-timeout`, 408) and logout and
login URLs keep their CSRF check even with a token header (stricter than
Spring, documented).

**The third review (October 2026)** confirmed the second round's fixes
and found 18 new items (plus docs), none High. Medium — a WebSocket session whose
output failed while backed up never ended (no close status, never left the
registry, `stop()` waited); two Dart peers sending at once deadlocked (the
input was paused when the output backed up); the `@TestBean(name:)` types
emitted with a `dart:core` prefix that doesn't exist. Low — the WebSocket
client accepted a subprotocol or extension it never offered, followed
redirects and had no incoming message limit; `server.connection-timeout`
of 0 or less; fixed-rate runs twice after the wall clock jumped forward
(the "ahead of the clock" offset) and runs under fake timers in Flutter
tests; LRU eviction in the in-memory cache O(maxSize); one name from two
login sources counted as one user by the session limit; an oauth2Login ID
token of another `typ` (`logout+jwt`, `at+jwt`…) accepted; the Windows
0.4.x move failing when two isolates ran it at once; the Linux store
reporting a locked keyring as a generic error; which `@TestBean(name:)`
fakes get their class's types decided by the field's declared type (now
by the value: a constructor call, also private, prefixed, cascaded or a
dot shorthand); `{var:regex}` classpath patterns normalized as paths; the
web dev config builder reading `file:` and `configtree:` imports from the
build machine's disk (a browser can't); an import with an extension hint
escaping the builder's early check. **All fixed**,
each with a regression test that fails on the code before it. Kept as
documented differences: dart:io keeps no raw request target, so a `\` or
raw non-ASCII in it can't be refused (a proxy in front must). Breaking
for 0.5.0: WebSocket clients refuse messages over 8 KB by default (1009,
Tomcat's default that Spring's `StandardWebSocketClient` uses;
`spring.websocket.client.max-text-message-size` /
`max-binary-message-size`); a connection the peer resets reports 1006
(was 1002); fixed-rate and fixed-delay run on the timers' clock, not the
wall clock (as Spring's executor); a `@TestBean(name:)` fake built with a
constructor gets its class's types whatever the field's declared type; the
web dev config builder skips `asset:` and `http(s):` imports (was a build
error) and fails on a required `file:` one; a config tree wildcard whose
base doesn't exist is no longer a "must be file system locations" error
(a required one fails as "not found", as in Boot — the fourth review).

**The fourth review (October 2026)** confirmed every third-round fix with
probes (real sockets, Keycloak, Docker with a locked GNOME Keyring, Spring
7.0.10 / Boot 4.1.2 / Security 7.1.2 runs) and found 11 new items (plus
docs), none High. Medium — a negative `spring.cache.simple.max-size` hung
the isolate (a regression of the new LRU); a fake or component of a
dart:io type (`HttpClient`, `HttpServer`) lost that interface (also in
0.4.3); the `@TestBean(name:)` fallback dropped the replaced `@Bean`'s
declared interface. Low — a required `configtree:` / `file:` wildcard
matching nothing was silently empty (Boot fails); a YAML syntax error
deleted the generated `web_dev_config.yaml`; classpath patterns cleaned
only up to the first wildcard (Spring cleans the whole pattern); the
first WebSocket messages of a hand-made upgrade never sent; a ping
between the fragments of a message truncated it (dart:io); `isOpen` true
and the wrong exception after a local `close()` (also in 0.4.3); the
app-side ID token decoder accepting any `typ`; Linux `delete()` on a
locked keyring doing nothing; fixed rate slowing down under a fixed
`clock` with real timers. **All fixed**, each with a regression test that fails on the code before
it (Docker with a locked keyring for Linux; a /tmp copy of the workspace
with only the fix reverted for the generator). The dart:io bug is worked
around in our frame filter: it holds the fragments of an unfinished
message and hands them to dart:io whole, while pings, pongs and a close
pass at once (the plain `IoWebSocketSession(io.WebSocket)` constructor
keeps dart:io's behaviour, documented). Also fixed on the way: the
dependency check's false "no longer needed" note (the Flutter guide's
folder is not its package name). Kept as documented differences:
`configtree:` naming a file reads as missing (Boot fails even when
optional); a `\` in a `classpath*:` root is cleaned (Java's class loader
refuses it); a `..` above the classpath roots finds nothing (Spring
escapes them). Breaking for 0.5.0: classpath patterns are cleaned as by
Spring's `cleanPath`, so a `{var:regex}` must not use `\` (reverses the
third round); a required wildcard location that finds nothing fails the
start; a `configtree:` location must end with `/`; generated
`@TestBean(name:)` overrides are wrapped in `_$named(...)` and also
registered under the field's type; the web dev config builder fails on a
required wildcard import and on a YAML syntax error (keeping the file); a
negative cache `max-size` fails the start (0 is now allowed and keeps
nothing); the app-side ID token decoder refuses another `typ`; Linux
`delete()` / `deleteAll()` on a locked keyring throw `libsecret_locked`
(a logout kept the tokens); the Windows 0.4.x move never fails a call (a
file in use moves at the next start); `isOpen` is false right after
`close()` and a send then throws `WebSocketException`.

**The fifth review (October 2026)** confirmed every fourth-round fix (31
config locations and 48 classpath patterns against Boot 4.1.2 / Spring
7.0.10, 22 ID token `typ` values against Spring Security 7.1.2, a
WebSocket frame sequence split at each of its byte boundaries, Docker with
a locked keyring) and found 11 new items (plus docs). High — the Flutter
web dev config builder failed the build of a pure Dart server app with a
required `file:` / `configtree:` / `package:` import (a regression of the
third and fourth rounds; it runs in every package that depends on the
generator). Medium — the new WebSocket frame filter held each empty
fragment as its own buffer, outside the size limit (96 MB of empty
continuation frames held 757 MB; a regression of the fourth round); a
required import in a profile-specific file finding nothing was ignored
(Boot fails; also in 0.4.3). Low — a `@TestBean` field whose nullable
type comes from a typedef; `\\` in a pattern cleaned unlike Spring's
`cleanPath`; a value deleted on Windows came back at the next start when
an old 0.4.x file couldn't be deleted (a logout undone); fixed rate
drifting under fake timers with a clock that stands still, and running
twice with a clock faster than the timers; per-cache sizes of names with a
dot not checked (and Boot's `[a.b]` form ignored); a negative cache
`time-to-live` accepted; the retry pause after a failed discovery measured
on the wall clock (a clock set back blocked logins). **All fixed**, each with a regression test that fails on the code before
it. The web dev config builder now never fails a build over an import a
browser can't read: with nothing to write it writes nothing, with
something to write it writes the file and logs a warning (supersedes the
third and fourth rounds' "fails the build" for required imports; a YAML
syntax error still fails it, keeping the file). The frame filter now holds
one buffer per unfinished message (payload plus at most one 64 KB buffer,
whatever the number of fragments: 96 MB of empty fragments +35 MB, as
dart:io). The scheduler's fake-or-real-timers guess is gone: each
fixed-rate / fixed-delay task keeps its own timeline, moved at each timer
fire by `max(armed, real time waited)` (capped by a clock of its own's
movement), and fixed rate catches up missed runs back to back, as Spring's
`ThreadPoolTaskScheduler` does (checked with Spring 7.0.10: a 300 ms rate
whose first run blocks 1 s starts three runs right after). The Windows
move is recorded after the first try with a list of leftovers (`copy` /
`delete`); a delete through the store cancels a pending copy. Retry
pauses, JWK refetch and cache lifetimes and the DPoP replay cache's purges
are measured on a monotonic clock (token `exp`/`iat` checks stay on the
wall clock). Two older config differences from Boot fixed on the way (checked against
Boot 4.1.2's source and runs): "not found" for pattern, directory and
config-tree wildcard locations is decided after all phases, as Boot's
`checkMandatoryLocations` (a profile variant finding a file counts; a
`;` group is one location); profile keys are checked only in `-{profile}`
variants found by name (in every document; their `group` keys ignored),
and files read after the profiles are decided have their profile keys
ignored. Kept as a documented difference: on-profile documents read before
the profiles are decided fail on `active` / `default` / `group` only when
they apply (Boot 4.1.2 reads them whether they apply or not, against its
own documentation). Breaking for 0.5.0: a required import that
finds nothing in a profile-specific file (or a file it imports) fails the
start (0.4.3 loaded); fixed rate catches up missed runs (was one run after
a long run) and `PeriodicTrigger(fixedRate: true).nextExecution` can be
before the completion; a negative cache `time-to-live` fails the start and
per-cache `[a.b]` keys apply; `\\` in a pattern is one separator; a raw
type now also matches beans of a private type argument (`Repo` →
`Repo<_A>`), so a raw injection point can become ambiguous, as in Spring;
a required `classpath:` directory no longer counts as found from
`lib/resources/` on disk alone; `active` / `default` / `include` in a
profile file's document for another profile fails (as in Boot), while
files imported by a profile file ignore profile keys.

**The sixth review (October 2026)** confirmed every fifth-round fix (the
frame filter by differential fuzzing against dart:io — 3,600 valid,
malformed and size-limit sequences — and lengths up to 2^32; the
scheduler's catch-up against Spring 7.0.10's `ThreadPoolTaskScheduler`;
80 config cases against Boot 4.1.2) and found 10 new items (plus docs).
High — the web dev config builder still failed the build of a pure Dart
server with any `spring.config.import` plus a placeholder only the
runtime resolves (`spring.profiles.active: ${APP_PROFILE}`), the third
of this kind: the builder loaded the config of apps that don't use it.
Low — a DPoP proof replayable at exactly `iat + clockSkew` (the cache
entry counted as gone at that instant); fixed rate's catch-up bursting
after the app was suspended (as in Spring; undocumented, and the doc
example was a UI tick); the cache time-to-live on the wall clock
(Caffeine uses a ticker); `SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE`
ignored (Boot binds it); `;` groups in a file's `spring.config.import`
not split; the extension hint dropped from the not-found location;
`%2A` in a `file:` pattern decoded to a wildcard; relaxed spellings of
profile keys in profile files not refused; the WebSocket reset reason
lost when the write side fails first; origin patterns without Spring's
port lists, optional `[*]`, trailing-slash trim and comma split (the
WebSocket handshake had only `*`). **All fixed**, each with a regression test that fails on the code before
it. The builder's rule is now the principle, not a list of cases: it
loads, warns or fails only when a config file it can read without loading
sets a `spring.flutter.web.*` key or `spring.flutter.security.web.mode`;
otherwise it does nothing (a stale generated file is deleted); with such a
key, a runtime-only placeholder is a warning naming it, never a build
error. A recorded DPoP `jti` is refused until purged and kept until `iat`
+ skew + 5 s. The cache's time-to-live runs on a monotonic stopwatch. One
Spring-compatible origin matcher, `AllowedOrigins` in spring_web_dart
(Spring 7.0.10's `CorsConfiguration` rules; 66 of 73 probe cases exact),
serves CORS and the WebSocket handshake; its `*` in a pattern doesn't
match `/ \ ? # @` or whitespace (stricter than Spring, documented). The
fixed-rate catch-up after a suspended process is kept as in Spring and
documented, with fixed delay recommended for polls and UI ticks. Kept as
documented differences: spaces around `;` entries trimmed (Boot keeps
them); `…_BOOKS_BYISBN_MAX_SIZE` sets cache `books.byisbn` and
`caches.foo.max.size` sets cache `foo` (Boot binds neither); same-origin
compares the host without case. Also on the way: CI's no-op
`--delete-conflicting-outputs` removed. Breaking for 0.5.0: CORS and
WebSocket origin patterns are compared with case (was without) and a
`*` in a comma list with credentials fails the start; `Origin: wss://host`
is not an https server's own origin; DPoP stores get `expiresAt` 5 s later;
`InMemoryCache(clock:)` defaults to none (monotonic), a clock set back
expires entries, and an injected clock no longer holds entries alive (real
time expires them too — tests with short TTLs and a fixed clock change); `x.yaml;y.yaml` inside a file loads both; not-found
errors name the location as written; relaxed spellings of profile keys in
profile files fail the start; `%xx` after the first wildcard of a `file:`
pattern is literal; the web dev config builder never fails or warns in an
app without a web key.

**The seventh review (October 2026)** confirmed every sixth-round fix (79
config cases against Boot 4.1.2, 22 `file:` patterns against Spring
7.0.10, the 73-case origin table plus 50 more incl. IPv6 and IDN, DPoP at
the boundary over 100 real-clock rounds) and found 14 new items (plus
docs). High — a WebSocket session closed during `afterConnectionEstablished`
(or an `@OnOpen` that throws, closing with 1011) crashed the server
process: dart:io drained the message stream nobody listened to yet, and
the later `listen` threw uncaught (also in 0.4.3). Medium — a runtime-only
placeholder inside a profile name (`${ENV}-eu`) failed the build of a
web-configured app (only the placeholder text was cut); one request with
a large `Origin` froze the server when a pattern had two or more `*`
(backtracking regex; 48 KB → 15.7 s, and dart:io accepts 1 MB of
headers). Low — the builder: a raw `ArgumentError` from a malformed
on-profile expression escaped; a placeholder hid a profile key not allowed
there; `spring.flutter.security.web.mode: ${MODE}` silently ignored; a
hinted import with a placeholder not scanned; the large-file warning
repeated in every app. Config: uppercase extensions (`x.YAML`) refused
where Boot reads them; profile group names matched loosely (Boot uses
exact keys); `configtree:` in a `;` group read per entry (Boot picks the
resolver from the first); a non-UTF-8 file failing with a bare
`FormatException`. Web: the reset reason over wss still often lost (TLS
ends the input before the write error); no `Vary` on non-CORS responses
under a CORS configuration (Spring always adds it). **All fixed**, each with a regression test that fails on the code before
it. `IoWebSocketSession` subscribes to its socket when created (paused)
and owns its `messages` stream, so a close before anyone listens can't
break a later `listen`; anything escaping the per-connection code is
logged and closes the session with 1011, `afterConnectionClosed` runs
once, the registry is cleaned. The origin matcher is non-backtracking
(the 73 + 50 origin cases and 65,536 code units unchanged) and refuses an
origin over 1024 characters (1 MB → 0.02 s). `closeStatus` prefers the
status passed to `close` when dart:io reports 1006, and `messages` waits
up to 1 s for the output's result when the input ends without a close
frame (wss 12/12). `Vary` is added for every request to a handler with a
CORS configuration, MVC and security filter paths. The builder drops a
whole profile name holding a runtime-only placeholder (with a warning)
and keeps a rewritten forbidden key so its check still runs. Config:
extensions matched without case (`x.YAML` reads `x.yaml`), group names
exact, a non-UTF-8 file named in a `ConfigDataLoadException`, deep YAML a
`FormatException` instead of a stack overflow; found on the way: a
wildcard file with an extension hint (`file:./conf/*/app[.yml]`) read
nothing. Kept as documented differences: `configtree:` in a `;` group
read per entry; `.properties` read as UTF-8 (Boot: ISO-8859-1); origins
over 1024 characters refused. Breaking for 0.5.0: profile group names
must match exactly; don't listen to a socket wrapped in
`IoWebSocketSession`; messages arriving after `close()` while nobody
listens are dropped; `Vary` on every response of a handler with CORS
rules and the CORS source consulted for every request; a same-origin
"pre-flight" gets a 200 without CORS headers (as Spring);
`security.web.mode: ${X}` is a build error.

**The eighth review (October 2026)** confirmed every seventh-round fix
(the origin matcher by 2.6 M fuzz cases against a regex built as Spring
builds it plus all 65,536 code units; WebSocket back pressure and the
16 MB both-ways case through the handler mapping; 200 connections ending
at once; Boot 4.1.2 through its real `ApplicationEnvironment`, env-var
groups and a case-sensitive disk) and found 9 new items (plus docs), none
High. Medium — the builder failed the build on the bracket form of a
profile group (`spring.profiles.group[prod]: "dev,${X}"`) and on
`spring.profiles[active]`. Low — a `ResponseEntity`'s own `Vary` replaced
the CORS `Vary` (Spring merges); a non-ASCII `Origin` or
`Access-Control-Request-*` value gave a 500 with a stack trace (Tomcat:
403 / 200); the sixth round's stricter `*` in origin patterns broke
Spring patterns spanning the scheme (`*.example.com`, `*localhost*`) for
no security gain (browsers send the real origin, other clients can send
any); a pre-flight to a mapped path without CORS rules got a 403 (Spring:
200 without CORS headers); `ServerWebSocketSession.messages` documented
as usable though the mapping consumes it; a `\` continuation into `#---`
in `.properties` split the document (Boot continues); Boot 4.1's
`[encoding=…]` location hints unsupported. Docs: `.xml` properties files
and YAML deeper than 50 levels (Boot refuses) undocumented. **All fixed**, each with a regression test that fails on the code before
it. The builder matches groups by their full name and recognises the
bracketed forms of every profile key. Config `.properties` files are read
by a character-level port of Boot's `OriginTrackedPropertiesLoader`
(3,000 random files: a Boot-exact variant matches Boot on all; the shipped
reader differs only by the two documented choices below). Boot 4.1's
`FileHint` is ported: several brackets in any order, `[encoding=…]` for
UTF-8, ISO-8859-1 and US-ASCII (Java's alias list), brackets removed from
file paths; an unsupported charset fails naming it. An `.xml` import says
XML properties aren't supported. `Vary` from a handler is merged with the
CORS names (and compression adds `Accept-Encoding` once, nothing after
`*`); a non-visible-ASCII `Origin` or requested method/headers is a 403;
an origin pattern's `*` is Spring's `.*` again (≈194,000 fuzz cases
against Spring's own `OriginPattern` and `checkOrigin`: 0 differences); a
pre-flight to a path without CORS rules is a 200 without CORS headers in
the router and the security `CorsFilter` (as Spring; checked with the
differential tests against Spring Security). The examples' `.properties`
files had a comment right after `#---`, which Boot's documented rule
forbids (Boot then joins the documents): the comments now follow the
guard line. Kept as documented differences: a comment after `#---` keeps
the documents apart (Boot joins them); after `#---` with trailing spaces
a following indented line is read (Boot drops it); YAML ignores an
encoding hint (as Boot) and UTF-16 / cp1252 aren't decoded; `.xml`
properties files; YAML deeper than 50 levels is read (Boot refuses);
requested methods/headers with non-ASCII refused (Spring echoes them).
Breaking for 0.5.0: in `.properties`, `#---` right after a `#` comment
line is a comment, a `\`-continued line runs into a following `#---`,
`key[]=a,b` expands to `key[0]`/`key[1]`, empty keys are skipped;
brackets in a file location are removed from the path; an unsupported
charset hint fails even when `optional:`; a pre-flight to a mapped path
without CORS rules is a 200 (was 403); non-ASCII CORS values are a 403
(was a 500).

**The ninth review (October 2026)** confirmed every eighth-round fix
(2,300 random `.properties` files through Boot, the shipped reader and a
Boot-exact copy; the examples' effective config identical for all 1,040
profile sets; 45 file-hint cases; 193,935 origin fuzz cases against
Spring; the 12 pre-flight cases and 31 more against the Spring Security
reference) and found 10 new items (plus docs), none High. Medium — a
location listed twice counted at its first position (Boot: the last, so
`--spring.config.additional-location=file:./config/` didn't win; also in
0.4.3). Low — a real (non-pre-flight) CORS request never checked against
the allowed methods (Spring refuses it with 403; an allowed origin could
read a `DELETE` answer); with the security starter the CORS rules were
picked by path and method only, ignoring consumes/produces (another
handler's rules applied); a `ResponseEntity`'s ETag / Last-Modified never
answered 304; no `Vary: Accept-Encoding` when the client didn't accept
gzip (Tomcat adds it); `PropertiesParser` (for `@PropertySource` and
message bundles) unlike `java.util.Properties` on Unicode spaces and a
lone `\` line; `fileHints` unlike its doc; the builder missing a hinted
import from a bracketed directory; odd indexed forms
(`on-cloud-platform[0]`, `import[x]`, `active[x]`) unlike Boot; the
websocket test app's generated file stale (CI's "generated" job). Docs:
with a `CorsConfigurationSource` bean Spring ignores `@CrossOrigin` for
real requests too; an ambiguous pre-flight; `allowPrivateNetwork`
missing. **All fixed**, each with a regression test that fails on the code before
it. The config processing core is now a port of Boot's contributor tree
(a list resolved, then read from its last location; strongest first,
depth first, Boot's post-order; `moveProfileSpecific` ported): the
earlier Boot case sets match 338 of 383 (the rest documented), 1,199 of
1,200 random configs with nested and duplicate imports, `;` groups,
profile files and on-profile documents match Boot (was 808).
`PropertiesParser` is a port of `java.util.Properties`' `LineReader` /
`load0` / `loadConvert` (2,384 files: 0 differences given the same text).
List keys go through Boot's unbound-element check (`import[x]` fails);
scalar settings ignore list forms. The CORS processor ports Spring's
`handleInternal` (a real request's own method checked; `@CrossOrigin`
without `methods` allows the mapped method, as Spring's
`initCorsConfiguration`); the security `CorsFilter` resolves the handler
the router would call (all conditions); a `CorsConfigurationSource` bean
decides alone where it has rules (router and filter); `allowPrivateNetwork`
added; a `ResponseEntity`'s ETag / Last-Modified answer 304 / 412 as
Spring's `checkNotModified`; `Vary: Accept-Encoding` and compression
follow Tomcat (also without gzip, not with a strong ETag, not for 205).
Spring MVC 7.0.10 probe: 54 cases, 23 differences before, 0 after. Kept
as documented differences: a relative import inside a file found through
a wildcard location resolves against the file's directory (Boot: against
the pattern); a directory location must end with `/` (Boot also accepts
`\` on Windows); a leading BOM is dropped (Java keeps it); an ambiguous
pre-flight answers from the first handler's rules (Spring allows any
origin with credentials); a pre-flight refused if any requested header
isn't allowed (Spring answers the allowed subset). Breaking for 0.5.0: a
file listed twice counts at its later, stronger place and profile
variants follow Boot's order (`x-dev` beats `application-dev`);
malformed list elements fail the start; `PropertiesParser` follows
`java.util.Properties` exactly; cross-origin requests whose own method
isn't allowed are a 403 (HEAD under GET-only rules included);
`@CrossOrigin()` without `methods` allows only the mapped method; a
`CorsConfigurationSource` bean is no longer combined with `@CrossOrigin`
or `addCorsMappings`; a `ResponseEntity` with an ETag / Last-Modified
answers 304 / 412; a mapping with `*` plus credentials or private network
makes its requests a 500 (as Spring).

**The tenth review (October 2026)**, the last under the new rule,
confirmed every ninth-round fix: the rewritten config core matched Boot
4.1.2 on 1,797 of 1,800 new random configs (the 3 are the deferred
placeholder timing), sync and async alike, dart2js on node too, a chain
of 1,000 imports in 0.9 s (Boot 15–33 s); `PropertiesParser` 0
differences from `java.util.Properties` on 3,195 files; about 160 new
web cases against Spring MVC 7.0.10 / Security 7.1.2. It found three
Medium items, all fixed with regression tests: a file listed twice was
still decoded at the weaker place (a latin1 hint where it counts failed
the start as "not valid UTF-8"); with the security starter a WebSocket
handshake was checked against the `WebMvcConfigurer` CORS mappings (403
where Spring answers 101 — the filter now asks the dispatcher's mappings
in order, as `HandlerMappingIntrospector`); bodiless answers carried
dart:io's `Content-Type: text/plain` and 304/204 a `Content-Length: 0`
(a shared cache revalidating a CSS file got text/plain, refused with
`nosniff`). Also fixed, since a valid Spring setup failed to start: two
`CorsConfigurationSource` beans — only the bean named
`corsConfigurationSource` is used now, as in Spring Security. Its Low
items are under "After 0.5.0". By the review rule nothing is left, but the owner blocked the release on the sessions and the Docker security run ("Blocking the 0.5.0 release").

### High

- **Multipart: an upload failing inside a part hangs forever and leaks its
  files** (web): the parser never ends the part's stream on a body error
  (`spring_web_dart/lib/src/multipart/multipart.dart`), the resolver only
  cleans up for its own exceptions (`multipart_resolver.dart`). A request
  over the 10 MB limit inside a file part, or a client that aborts: no
  answer, temp files left behind, shutdown blocked 10 s. Spring answers
  413 and cleans up.
- **A `multipart/*` Content-Type switches off
  `server.max-http-request-body-size`** (web, DoS): the whole body is read
  before the media type is checked (`io_web_server.dart`,
  `request_mapping.dart`); 400 MB to a JSON endpoint got a 415 after
  +873 MB of memory. Limit every body reader; check the media type first.
- **Scheduling in browsers and JavaScript: delays over 24.8 days fire at
  once, the task repeats** (`task_scheduler.dart`): `setTimeout` takes no
  more than 2^31-1 ms and `_run` does not check that the time has come; a
  yearly cron ran 238 times in 300 ms. Cap each timer and re-arm when it
  fires early (also for the edge starter).

### Medium

- **Anonymous requests can log every user out** (web + security): at
  `server.servlet.session.max-sessions` (10 000) the least recently used
  session is dropped, and the request cache, CSRF and `oauth2Login()`
  create sessions for anonymous clients: 10 000 cheap GETs evict all
  logins. Spring has no cap by default (Tomcat refuses new sessions
  instead). Evict expired, then never-returned sessions first, or refuse
  new anonymous sessions when full; the threat model to mention it.
- **POST / PUT / DELETE with a bearer or DPoP token get 403** (security):
  the resource server does not exempt token requests from CSRF
  (`http_security.dart`), as Spring's `registerDefaultCsrfOverride` does;
  the default JWT chain refuses every state-changing API call (fails
  closed).
- **A handler `@CrossOrigin` widens the global CORS origins to `*`**
  (web): the annotation's default `*` is merged with explicit global
  origins (`cors.dart`); with `allowCredentials` it fails with a 500.
  Spring's default markers never override explicit values. The README
  advises exactly that annotation for PUT / DELETE.
- **Encoded `/`, `\` and NUL decoded into path variables, nothing refuses
  them without the security starter** (web): `..%2F..%2Fsecret` becomes
  `../../secret`; the README's `FileSystemResource('/var/shop/covers/$isbn.png')`
  example reaches any `.png`. Tomcat and Spring Security's firewall answer
  400; do so by default and fix the example.
- **No back pressure for SSE / NDJSON** (web): a client that reads
  nothing makes the server buffer without bound (+263 MB for 200 000
  events). Pause the source while a write is pending.
- **WebSocket server endpoints: no message size limit, permessage-deflate
  on, no back pressure** (web + websocket): a 64 MB message is accepted;
  a slow handler queues messages without bound. Tomcat: 8 KiB, close with
  1009. Add `max-text/binary-message-size`, compression off by default,
  pause reading while a message is handled.
- **No limit on the number of multipart parts** (web, DoS, the class of
  CVE-2023-24998): 20 000 parts in 1.5 MB, 20 000 temp files.
- **Graceful shutdown cut off at 10 s** (Boot): only the web server reads
  `spring.lifecycle.timeout-per-shutdown-phase`; the lifecycle processor
  keeps its 10 s, so beans are destroyed under running requests. Boot
  applies the property to the lifecycle processor.
- **A port in use is reported after a successful start, exit code 0**
  (web): `ApplicationReadyEvent` and the runners run first. Spring fails
  the refresh with exit code 1.
- **`ResponseEntity<SseEmitter>` and `ResponseEntity<EventStream>` do not
  work** (web): answered as JSON, or a 500. Spring supports both.
- **Log file errors escape the appender and break it** (logging): an IO
  error in `flush` / roll-over is an uncaught async error; the file stays
  closed, later flushes and `close()` throw, the old handler is never
  given back. Logback reports and goes on. An unwritable
  `logging.file.name` also fails the start.
- **Web server mode sends cookies with every request, to every origin**
  (Flutter security): the shared transport uses `credentials: include`
  for all calls when the server is cross-origin; third-party APIs with
  `Access-Control-Allow-Origin: *` then fail. Decide per request (only
  the server's origin), as the CSRF header already does.
- **Android: a login whose window is destroyed never answers** (Flutter
  security, read): a `singleTask` main activity or a `CLEAR_TOP` intent
  destroys the management activity without `onResume`; the login service
  stays busy (`in_progress`) until the app restarts; process death and hot
  restart leave the same state. Cancel in `onDestroy` when finishing
  without an answer, clear `pending` when the engine detaches.
- **`restore()` loses the authorities of the app's own user service**
  (Flutter security): restore rebuilds `OIDC_USER` + `SCOPE_*` only; roles
  the service added are gone after a restart. Store the service's
  authorities in the login record.
- **`SpringApplicationWidget` leaves the context running when the start
  fails after it** (Flutter): runners and scheduled tasks keep going
  behind the failure screen; each hot reload starts another. Close it in
  the catch.
- **A failed build can write another package's generated file**
  (generator): with `--workspace`, the "keep the existing output" path
  reads from the current directory, not the package built.
- **The spa CSP misses provider origins** (generator): built-in providers
  without a provider section (Google's `www.googleapis.com`) and
  discovered endpoints on other origins (`oauth2.googleapis.com`) are not
  in `connect-src`; the browser blocks the token request.
- **Two `@Log` classes with the same name break the build** (generator):
  two `extension $CheckoutLog` in one file.

### Low

- Security: the DPoP replay cache filled before the key binding is checked
  (any valid token signs proofs with fresh keys; check `cnf.jkt` before
  `markUsed`); no backoff when discovery or the JWK Set endpoint fails
  (each request makes new outbound requests); success events published for
  requests then refused (bound token as Bearer, before the proof check);
  the client's ID token decoder accepts an RSA exponent of 1 (refuse
  e <= 1 as the starter's own check does).
- Web: compression applies only to byte streams; advice beans chosen by
  the most specific handler across all beans, not by `@Order` first; a
  non-ASCII header value gives an empty 200; `ResponseCookie` not
  validated (attribute injection through the value); a bad `Host` header
  gives a 500 with a stack trace in the log; a disallowed pre-flight gets
  405 (Spring 403); matrix parameters not stripped; upload temp files in
  the shared temp directory, 0644, predictable names; hot reload stops
  restarting after one failed restart; `SseEmitter` without a timeout
  never ends (Tomcat's 30 s default in Spring; not in Differences);
  `@ControllerAdvice` cannot be scoped (not in Differences); dart:io
  accepts both Content-Length and Transfer-Encoding (document, SDK).
- Feign: the `headers` log shows `Cookie`, `Set-Cookie`,
  `Proxy-Authorization`, API-key headers; `Retry-After` negative or huge
  gives a zero delay; `FeignException.toString()` carries the whole body;
  a path variable `..` / `.` changes the target URL.
- WebSocket: the client logs `?token=` in URLs and exception texts;
  `@PathVariable() int` on an endpoint passes the startup check and fails
  every connection.
- Test starter: `BeanOverride.named` keeps interfaces the fake does not
  implement; class-level `@DirtiesContext` is after each method (Spring:
  after the class), not documented.
- Cache: TTL-only caches keep expired entries until read (documented;
  sweep on `put`). Scheduling: cron across a DST fall-back skips the
  repeated hour (Spring likely fires in it; document).
- Core: `classpath:../..` escapes `lib/resources/`; the default log
  handler always prints colours (Boot detects a terminal); user strings
  (`@Log` topic, bean names) unescaped in generated doc comments.
- Flutter security: logout fails open when the store cannot delete
  (clear the context in `finally`); stored-token keys of two registrations
  can collide (`a.b`+`c` vs `a`+`b.c`); the Android redirect matcher
  accepts opaque redirects that can never match and any link when the
  authority is no valid host; a forged redirect with the exact path ends a
  running login (DoS; give the window the expected `state`); the browser
  key vault does not re-check a stored key's extractability; Windows /
  Linux stores keyed by the executable's name (two apps with the same name
  share secrets; DPAPI temp file name fixed; long keys); the loopback
  window turns an explicit `localhost` into `127.0.0.1`; tokens left when
  a registration is removed; `SecretTemplate` throws synchronously; the
  web condition differs between modules; a dismissed libsecret unlock
  prompt reads as no value.
- Example server (ZAP): CSP without `form-action` / `base-uri`;
  `XSRF-TOKEN` and `neon-recent` without SameSite, `neon-recent` without
  HttpOnly; `Server-Timing` names handlers; anonymous GETs create
  sessions (request cache).
- Build tooling: the Android Gradle and Kotlin Gradle plugins pull
  BouncyCastle 1.79, Guava 33.3.1, jose4j 0.9.5, jdom2 2.0.6,
  commons-lang3 3.16.0 with advisories (build machine only, not in the
  APK); Kotlin 2.4.0 itself (build-cache deserialization, fixed in
  2.4.20). Move Kotlin to 2.4.21, force the rest with buildscript
  constraints; CI scans only pub lock files, not Gradle / Maven.

### Docs that state false things

- Graceful shutdown "waits up to `timeout-per-shutdown-phase`" (10 s in
  effect); "gzip for clients that accept it"; CORS "combined as in
  Spring"; advice beans "tried in @Order"; the multipart resolver
  "deletes what it stored" on a limit; multipart bodies "have the
  multipart limits instead"; "a port in use stops the application";
  "every error is answered with a problem" (CORS rejections, 501, 403 for
  a missing client certificate are plain text); `@ResponseStatus` "read on
  methods only".
- `PlatformSecretStore` "other apps and users cannot read it" (on Windows
  and Linux any process of the user can; DPAPI and the Secret Service
  separate users, not apps); the software Keychain DPoP key "never reaches
  the app's memory" (it does where there is no Secure Enclave); WebCrypto
  "never the key's bytes" (scripts cannot export them, but the browser
  writes them to its profile on disk); a reinstalled app "has none" /
  "never in a backup" (Keychain items survive the app's deletion and are
  in encrypted backups of the same device); `restore()` "as at the end of
  their last login"; server mode sends credentials "only to the server";
  "any other link is dropped".
- Generator: "an error never changes an existing output" (workspace
  builds); the spa CSP covers "the providers"; `printLogHandler` "in
  colour like Spring Boot's console"; `BeanMethod.returnTypeInfo`.

### Proposed with it

- A ZAP baseline job in CI (a draft exists: dev and `sso` legs, a rules
  file, a seeding hook), once the three example fixes above are in.
- Dependency scans of the Gradle and Maven graphs in CI.

## Blocking the 0.5.0 release

The owner's decision: 0.5.0 doesn't ship before these are done.

Sessions (decided by the owner): The eviction
scheme (expired → never returned → without a login → the least recently
used login of the user holding the most sessions, with
`principalNameAttribute` / `principalKeyAttribute`) is this project's
own, grown over the review; nothing in Spring works like it, and a
refusing limit alone would let a flood of new sessions lock new
visitors out. So:
- no session before a login: the CSRF token in a cookie
  (`CookieCsrfTokenRepository`) where a session isn't needed anyway, the
  request cache only for browser navigation, `oauth2Login()`'s
  authorization request (`state`, `nonce`, PKCE) in a signed short-lived
  cookie instead of the session; a session is created at a successful
  login only;
- at the limit: remove expired sessions, then refuse the new one with a
  503; never push out a live session; the eviction order and the
  principal attributes removed;
- SSO keeps working in all three ways (native apps and `spa` without
  sessions, `server` / BFF with a session after the login);
- then the hard security run on a Docker network
  (`roadmap/security_verification.md`, section 7).

## After 0.5.0

Low items of the reviews before 0.5.0, left for patch releases by the
release rule (nothing High, Medium or security-relevant):

- Web: an empty body with a compressible type is gzipped (a 412 or an
  empty `ResponseEntity` with `application/json` becomes a 20-byte gzip
  stream; Tomcat sends `Content-Length: 0`, no encoding) — in `close()`,
  set the length 0 when nothing was written before commit.
- Security: cache headers unlike Spring's lazy `CacheControlHeadersWriter`
  — a 304 gets `Cache-Control: no-cache, no-store…`, `Pragma`, `Expires`
  (Spring writes none on a 304), and an app that sets only `Expires` or
  `Pragma` keeps the no-store `Cache-Control` (Spring writes none of the
  three when any one is present).
- Config: placeholders in a document's `on-profile` and
  `spring.config.import` are resolved once profiles are decided and again
  after each activation; Boot resolves them once, when the first pass
  reaches the document, and fails with
  `InactiveConfigDataAccessException` on a key from a document inactive
  then (3 of 1,800 random configs differ, all this) — port Boot's
  bind-once-and-fail-on-inactive.
- Config: profile group lists (`group.dev[1]` without `[0]`, `[0].a`,
  gaps) aren't checked for unbound elements (Boot fails the start).
- `Profiles` expressions stricter than Spring's `Profiles.of` (`(dev`,
  `a)`, `a &`, `(a)(b)`, `a b` refused here) — port Spring's leniency.
- Config: a flat list of ~1,000+ imports whose files have guarded
  documents slows down cubically (1,000: 2.2 s, 2,000: 15 s; Boot ~2 s):
  each guard check builds `_resolver(document)` over all sources — build
  it only when the guard has `${`, or cache it per activation.

## How close to Spring (tenth pre-0.2.0 review, October 2026)

Per area: **API** — public names and signatures that match Spring
(a change forced by Dart counts half); **behaviour** — 15–50 behaviours
per area a Spring developer relies on, checked in the code and with probe
programs; **coverage** — share of the commonly used features of the Spring
counterpart. Estimates, ±5–10 points; the third review's numbers in
brackets.

| Area | API | Behaviour | Coverage |
|---|---|---|---|
| Container (`beans`) | 88% (88) | 88% (88) | 73% (73) |
| Context, events, lifecycle | 89% (88) | 86% (84) | 71% (70) |
| Configuration, resources (`core`) | 92% (92) | 87% (87) | 73% (73) |
| SpEL | 73% (73) | 85% (84) | 82% (82) |
| Validation, binding | 86% (86) | 84% (84) | 62% (62) |
| JSON (vs Jackson 3) | 74% (74) | 80% (80) | 50% (50) |
| AOP | 82% (82) | 74% (71) | 72% (72) |
| Annotations, generator | 92% (92) | 83% (80) | 77% (77) |
| `spring_boot_dart` | 74% (73) | 87% (86) | 64% (63) |
| `spring_web_dart` | 79% (79) | 80% (80) | 51% (51) |
| Feign starter | 80% (80) | 80% (79) | 57% (57) |
| WebSocket starter (declarative by design) | 64% (64) | 80% (79) | 59% (59) |
| Logging starter | 78% (78) | 81% (81) | 58% (58) |
| Scheduling starter | 76% (76) | 87% (86) | 62% (62) |
| Cache starter | 91% (91) | 89% (89) | 67% (67) |
| Test starter | 77% (77) | 79% (78) | 62% (62) |
| **All, weighted by code size** | **86%** (86) | **84%** (83) | **69%** (69) |

## Before 0.2.0

Nothing open. The tenth review found nothing blocking except one outdated
doc comment (`ConfigurationCondition`), fixed right after it.

## After 0.2.0

Found while writing the guides (`example/server_guide`,
`example/flutter_guide`, October 2026); each is worked around there:

- `@ConditionalOnMissingBean()` without arguments on a `@Bean` method
  checks the type of the returned value (`SystemClock`), not the declared
  return type (`Clock`) as Spring does: a user `Clock` does not make it back
  off.
- `@EventListener(condition:)` takes a function, not a SpEL string like
  Spring's.
- ~~`FetchHttpTransport` (the web) sends no credentials~~ Fixed:
  `FetchCredentials` (October 2026).
- Flutter starter: no routes in `spring.flutter.app.*` (`routes`,
  `onGenerateRoute`, `routerConfig`), no locale property, and
  `SpringApplicationWidget` takes no `BeanOverride`s for tests.
- `MockMvc` cannot send a target starting with `//` (parsed as a host).
- The name of a `@Valid @RequestBody` object for message codes is the
  parameter's name, not Spring's type-derived one (`newBook`).
- `@ConfigurationProperties` validation messages ignore the
  `MessageSource`.
- The scheduling starter logs "Bean 'taskScheduler' ... not eligible for
  getting processed by all BeanPostProcessors" at every start (its
  post-processor depends on the scheduler eagerly; the cache starter had
  the same and is fixed).
- A model class named `Order` clashes with the `@Order` annotation, and
  the generator reports only "cannot be forwarded by a proxy".

Found while rewriting the documentation comments (October 2026); the
comments now describe what the code does:

- Web: `@CrossOrigin()` without `methods` allows GET/HEAD/POST only
  (Spring: the mapping's own methods), so a PUT/DELETE pre-flight gets 403;
  `${...}` in a mapping's `headers` is resolved by clients, not the server;
  a `HEAD` on a multi-chunk `StreamingResponseBody` reports the first
  chunk's length; after `MultipartFile.transferTo` the file can no longer
  be read or moved again; the session error suggests a non-existent
  `spring.web.session.enabled`; the "(https)" start line looks at
  `server.ssl.certificate`, not the real settings; `afterCompletion` gets
  the exception even when an `@ExceptionHandler` answered it; a second
  `Validator` bean without `@Primary` turns `@Valid()` bodies off silently.
- HTTP types: `MediaType` parameters in single quotes split on `,`/`;`;
  a duplicated cookie name keeps the last value; a bad `%xx` in
  `filename*` throws `FormatException`; SSE: the last event id does not
  carry over and an empty `id:` sends an empty `Last-Event-ID`;
  `EventStream.fromEvents`/`of` fail a second listener on a
  single-subscription source; `CloseStatus` range checked by an `assert`
  only; the browser WebSocket session drops errors after opening;
  `closeStatus` may stay null after a drop.
- WebSocket starter: a `@SendMessage` value that is not JSON throws
  synchronously from a `Future` method; a handler error is ignored by
  `AbstractWebSocketHandler` (Spring closes with 1011);
  `setAllowedOrigins`/`setAllowedOriginPatterns`/`setSupportedProtocols`
  add instead of replace; a bad `reconnect.multiplier`/`max-retries` fails
  with a `FormatException` that does not name the property.
- Security: `{pbkdf2}` uses the v5_8 settings while Spring 6 maps it to
  v5_5, so Java `{pbkdf2}` hashes may not verify; `offload_io.dart` catches
  `ArgumentError` from the work itself and checks the password twice;
  hash upgrades at login run on the main isolate; the global strategy's
  `runWithContext` restores at the first `await`; with only `issuer-uri`,
  `jws-algorithms` is ignored; `headers().defaultsDisabled()` ignores later
  header calls; users from `HttpSecurity.userDetailsService(...)` never get
  hash upgrades; form login reads at most 64 KB, but when the CSRF token
  comes as a form field the CSRF filter has already read the form with the
  1 MiB limit and the login filter reuses it, so its own limit never
  applies.
- Boot: a `spring.jackson.*` boolean typo silently means false;
  auto-configuration `before`/`after` match short names only, exclusion by
  `Type` matches the simple name; `@ConfigurationProperties` validation
  builds its own `BeanValidator`; `defaultValidator` has no
  `validationMessageSource`, so `{key}` in constraint messages stays as is.
- Context and container: `addBeanFactoryPostProcessor` after refresh is
  ignored silently (`register` throws); the `parent` setter is not guarded
  after refresh; `startupDate` is public and mutable; an `@EventListener`
  whose id ends in `.onApplicationEvent` is taken for an
  `ApplicationListener`; `ReloadableResourceBundleMessageSource` is not
  `ResourceLoaderAware`; `ObjectProvider.isEmpty`/`length` count null beans
  that iteration skips; `NullValueInNestedPathException` from
  `_readSegment` names the whole path.
- Configuration: an invalid profile name throws a plain `StateError`;
  `urlExists` is true on the web, so an `optional:` URL import fails there;
  `validateRequiredProperties` throws on an unresolvable placeholder
  instead of listing the key; random ranges over 2^32 are slightly biased;
  `ConfigurationPropertyName` accepts a leading digit its message forbids.
- SpEL: `SpelType.constructors` entries other than `''` are ignored;
  `MapAccessor.canWrite` is true for every map; `keys`/`keySet` give a
  `List` as properties, a `Set` as methods; `.5` reports EL1044E (Spring
  EL1047E). AOP: advice of one kind is sorted with the unstable
  `List.sort`; the README says named pointcuts are shared as `name()`, the
  code needs `Type.name()` for another aspect's.
- Starters: cache `invalidate()` returns true for an empty or only-expired
  cache; two `sync: true` methods on the same cache and key share one
  pending result; `LogQuery.copyWith` cannot clear `fields` with null;
  Flutter `ThemeConfig` is public API but not exported; widgets sharing a
  beans record share one binding. Test starter: a misspelt
  `BeanOverride(name:)` adds a second bean; without a name and a bean of
  `T` it may replace an unrelated bean named `defaultBeanName(T)`; the
  replacement keeps only type `T`; `andExpect(json:)` on a non-JSON body
  throws `FormatException`; the runner ignores initializers' `order`.


Found while rewriting the READMEs and `docs/` (October 2026):

- Objects made by hand without an introspector (`StandardEvaluationContext()`,
  `DataBinder`, `BeanValidator`, `ObjectMapper`) read only
  `BeanIntrospector.shared`, while the generated `@Introspected`
  descriptions go to each context's introspector: they do not see
  generated classes unless given the context's `BeanIntrospector` bean.
- Configuration read before any `BeanModule` is created misses the
  embedded `lib/resources/` files outside `dart run` (an AOT executable
  started from another directory).
- Flutter starter: `spring.flutter.app.locales` and `spring.messages.basename`
  are read as single values (a YAML list is ignored), and a basename with
  dots (`i18n.messages`) finds no locale files, while Boot's
  `MessagesBundleCondition` reads both; after a hot-reload restart missing
  font families are not logged again.
- A non-numeric Feign `event-stream.max-attempts` fails with a
  `FormatException` that does not name the property.
- Test classes: an `@Autowired() Map<String, T>` field ignores
  `@Qualifier` (`test_builder.dart`).
- Not verified: `@Log` in a Boot app without `@ComponentScan` generates the
  `log` getter into the scan's file (`bin/main.spring.dart`), which a
  `lib/` library cannot import.

Found by the reviews, not blocking:

- Tenth review: unconditional `@Bean` methods are registered while parsing, not in the reader in class order (earlier bean conditions see them; registration order `[h2, h1]` vs Spring's `[h1, h2]` affects unordered `List<T>` injection) — document or defer; plain (non-`ConfigurationCondition`) conditions on `@Bean` methods evaluated while parsing; a component's `@ConditionalOnMissingBean` of its own type; `@ConditionalOnBean(B)` on a component when B is a later conditional component; `@ConditionalOnMissingBean()` without arguments on a class should fail like Boot; `UrlResource.existsAsync()` status rules (204, 500 with a body); `@Bean` products with private members get interface-only proxies (`BeanNotOfRequiredTypeException` when injected by class; README should say subclass proxies are for component classes); operators (`[]`) on subclass proxies aren't advised; a `*String` delay resolving to whitespace.

- Ninth review: excluding an auto-configuration doesn't exclude the configuration classes it `@Import`s (inlined under their own source); a registrar / selector `@Import`ed by two generated classes uses only the first importer's conditions; a user `DeferredImportSelector`'s beans make auto-configurations back off (Boot runs it after `AutoConfigurationImportSelector`); `SpringLogHold.release()` of a non-innermost hold; blank per-client Feign flags vs `config.default`; the condition report shows a whole auto-configuration as not matched for one backed-off bean; `max-history=0` with `total-size-cap`.

- Eighth review: several `TaskScheduler` beans without a primary or `taskScheduler` fail the start (Spring falls back to a local scheduler); the example tour closes with sync `close()` (use `closeAsync()`); SpEL on the web `{{2.0}}.toString()` and `'' + {2.0}`; JSON `intValue()` of `1e20`; README row for list-gap padding; a private default value leaves a subclass-proxy method unadvised.

- Seventh review: `@CacheConfig` on an implemented interface; `initialDelay` with a blank `initialDelayString`; `reconnect.delay=0` with jitter; `DataBinder` / `BeanWrapper` writing into a `const []` default (copy to a growable list or record a field error); 64-bit overflowing indexes; `@Configuration` classes are never AOP proxy candidates (Spring advises them; at least document); `mergedAnnotations` order (interfaces before superclasses); enum names accepted next to `@JsonValue`; `DataBinder.construct` shifting elements after a failed conversion; `#x = 2.0` not `instanceof T(Double)` on the web (document).

- Sixth review: `DataBinder.bind` drops a write into a gap of a `List<int>` silently (document); `BeanWrapper` appending at the grow limit; concurrent `runAsync` holds interleave; held lines of a failed start filtered at WARN; superclass and interface `@Cacheable` together; `@Scheduled` on an overridden superclass method; `default.reconnect.*` errors reported under the client key; empty client-level Feign flags; Feign example README "Dart 3.9.0"; SpEL `{-1, 2}` unmodifiable and quote escaping in AST text; `BeanWrapper` gap exception types.

- Fifth review: `@Scheduled(initialDelay:)` with a blank `initialDelayString`; Feign query spaces as `+` (OpenFeign `%20`); held early lines reach the console in the default format; `DataBinder.construct` gaps in `List<String>` should be `''` like `BeanWrapper`; parameter constraints added on an override should be rejected (`ConstraintDeclarationException`); SpEL real literal `toString` on the web, `Assign` spacing; `StringNode(" 3").asInt()`; `on-profile` inside a profile-specific file should fail; `BeanWrapper` index above the grow limit should raise `InvalidPropertyException` out of `bind()`.

- Fourth review: the lazy-listener stand-in ignores `Ordered.order` and doesn't retry a failed creation; empty comma-list elements (`1,,2`) should bind null; `ignoreInvalidFields` on indexed lists stops at the bad index in Boot; `UrlResource.existsAsync()` and `Content-Length`; document that `SpringLog.hold()` is isolate-wide and that the `--debug` report is INFO; blank resolved `cron` should count as unset; `clean-history-on-start` with `max-history=0`; a connect in flight when the last WebSocket listener cancels; sync `close()` with an open WebSocket logs a not-awaited warning; Feign example README omits timestamps; `JoinPoint` declaring type for interface methods under subclass proxies (CGLIB reports the class); the `@Lazy` through-proxy flag after an unadvised inherited member.

- Context / Boot: `@EventListener` results by runtime class; YAML hex integers beyond 64 bits; nested generic conversion (`Map<String, List<String>>`), `Encoding` aliases (`UTF8`), `canConvert(map, List<int>)`; `AbstractFailureAnalyzer` over the cause chain; `ResourceBanner` `${AnsiColor.*}` / `${application.*}`; `ApplicationAvailability` / `LivenessState`; `methodValidationPostProcessor` with `search: current`; log a throwing exit code generator; async `common-messages`; a class `@Import`ed by two generated classes skipped only when both are (selected modules are); `supportsAsyncExecution()`, `Scope.resolveContextualObject`, `BeanRegistry` spec options.
- SpEL: regex `replaceAll` / `replaceFirst`; `char` arithmetic; 32-bit int literals and overflow; `T(Arrays)`, `Collections`, `UUID`, `LocalDate`, `Duration`, `BigDecimal`; `.class`; conversion on writes to typed map / list elements.
- JSON: `1.0` written as `1` on the web (document); timestamp fraction digits; Dart enum names next to `@JsonValue` values; JSON Pointer `01`; `JsonNode.from(nan)`; `findValue(s)`, `findParent`, `required`, `withObject` / `withArray`, `setAll`; constructor properties first when sorting is off; `1` → `true`.
- Validation: message EL beyond `${validatedValue}`; default message only for `{0}`; canonical `requiredFields`.
- AOP / generator: `(A || B).*`, `@Ann *` in `execution`; `@Pointcut` holder classes turning pruning off; error wording.
- Web / Feign: custom `HttpMethod`s; body-less `ResponseEntity.ok()` builder, `allow` / `cacheControl` / `varyBy`; multipart, `@SpringQueryMap`, `FallbackFactory`, streamed downloads, placeholders in client names, `default.url` per client only; empty `id:` SSE events.
- WebSocket: STOMP client, ping / keep-alive, send-time / buffer / message-size limits, session details, handshake failure status.
- Cache: `Cache.get(key, valueLoader)`, async `retrieve()`; interface vs implementation cache annotations. Scheduling: `SchedulingConfigurer` / `ScheduledTaskRegistrar`, README on ignored `pool.size` / `thread-name-prefix`. Test starter: `prepare()`, `withBean` customizers, output capture. Logging: `logging.structured.*`, time-based rolling and `.gz`, `web` / `sql` groups.
