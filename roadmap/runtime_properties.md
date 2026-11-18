# Properties that change at runtime (the release after the speed release)

The owner, 16 November 2026: the release right after the speed release (the scenes' speed first; [release_optimizations.md](release_optimizations.md)). Not started; the speed and the caches went out together in 0.8.3, so this is the next release, after the generator's split by starter ([generator_by_starter.md](generator_by_starter.md)).

**No code unless the build asks for it** (the owner, 17 November 2026):
changing the context while the app runs may be unsafe, so a flag read at
build time decides whether any of it is generated, as
`spring.flutter.scene.debug.enabled` decides the scenes' tab. Off, the
application has no `RuntimePropertySource`, no rebinding, no store and no
editing in the debug panel: not switched off at run time, not there to
switch on. The key to settle: Spring Cloud's `spring.cloud.refresh.enabled`
(its own default is `true`); ours not set means debug and profile builds
only (the debug window), a release build needs `true` (an app's settings
screen), `false` means none in any build. With it, which keys may change
(a list of prefixes, `spring.flutter.scene.*` for Dota Passport's
graphics), every other key refused even when the code is there; Spring
Cloud's `never-refreshable` is the opposite list.

## Why

Today the `Environment` is read once, at start: every
`@ConfigurationProperties` bean is an immutable instance the generated
binder made then, and the debug panel's *Configuration* section only shows
the values. The owner wants:

- the debug window to change a property while the app runs, the scenes'
  graphics first (`spring.flutter.scene.max-frame-rate`, `render`,
  `pixel-ratio`, `canvas`, `when.*`);
- an app's own settings screen to offer the same keys to its users (a
  "graphics" page: the 3D's frame rate, still or off), through the same
  mechanism, not a store of the app's own;
- the user's choice kept across starts **on every platform**, not only in
  the browser: a data source of its own, chosen by the platform.

## Spring's model

Spring Boot itself has no runtime change; Spring Cloud Context has:
`EnvironmentChangeEvent` (the keys that changed),
`ConfigurationPropertiesRebinder` (rebinds the `@ConfigurationProperties`
beans in place), `@RefreshScope` (beans made anew on a refresh), and the
actuator's `POST /actuator/env` (a property source on top of the others)
and `/actuator/refresh`. We follow it under its names; the docs say that in
Spring it is Spring Cloud's.

## Plan

1. **A property source on top**, `RuntimePropertySource`, before every
   other: the `RuntimeProperties` bean sets a key (`set`), takes it back
   (`reset`, `resetAll`) and lists what it holds. Each change publishes an
   `EnvironmentChangeEvent` with its keys. A key whose name says it is a
   secret (`password`, `secret`, `token`, `key`, `credential`, as the
   *Configuration* section masks them) is refused.
2. **Rebinding.** A change under the prefix of a `@ConfigurationProperties`
   bean has the generated binder make a new instance; a value that does
   not bind or validate is refused, the old one stays, and the error goes
   back to whoever set it. How the beans that hold the old instance get
   the new one is to decide, without reflection: a `@RefreshScope` of our
   own (the bean served through a generated holder, made anew), or the
   properties bean as a listenable (`ObjectProvider` / a typed change
   event) that the starters' beans follow. The starters' own code shows
   which reads best.
3. **Kept across starts**, by a store of its own, `RuntimePropertyStore`,
   chosen by the platform as `SecretStore` and `FileStore` are, and
   replaceable by a bean of the app's:
   - web: `localStorage` (IndexedDB if values grow);
   - iOS, Android, macOS, Windows, Linux: a file in the app's support
     directory, through `FileTemplate`;
   - a server: a file, or nothing;
   - tests: in memory.
   The stored keys win over the configuration's files until they are
   reset, also when a new version of the app changes a default
   (documented). Changes from the debug panel are kept as well, until
   reset there.
4. **The debug panel.** The *Configuration* section edits a property by
   its type from the metadata (`spring_metadata.json`): a number field,
   an enum's values, a switch, a text field. It shows the `runtime` source
   of a changed value, with reset per key and for all. A key read only
   once at start is marked so in the metadata (for example
   `spring.flutter.scene.canvas: engine`, which makes the engine's canvas
   when the engine starts), and the panel says it applies after a
   restart.
5. **Typed keys for the app's settings screen**, generated like the
   theme's keys, so a renamed key fails the build:
   `properties.spring.flutter.scene.maxFrameRate.set(30)` (the shape to
   decide).
6. **The starters say what applies live.** The scenes first:
   `max-frame-rate` (the beat retimes), `render` and `when.*` (the
   availability already notifies), `pixel-ratio` (next frame),
   `pause-off-screen`, `canvas` between `page` and `layer`; `engine` at
   the next start. Then the theme, the frame meter, the log levels (Boot's
   `/actuator/loggers`).
7. **The actuator on servers:** `POST /actuator/env` and
   `/actuator/refresh`, behind security, as Spring Cloud's.
8. **Tests:** a change, its event and the rebound bean; a refused value
   (the old one stays); each store's round trip; a key applied at the next
   start; a `const` default list never written into; a secret refused; a
   key outside the allowed prefixes refused; with the flag off, none of
   the refresh code in the generated module (the generated code compared,
   as the debug panel's absence is).

The first user: Dota Passport's graphics settings (the 3D's frame rate,
still, off) and the scenes' debug tab.
