# The next releases: speed, then caches

The owner, 16 November 2026: this release is the speed the phones
measured (built; its tests and docs to finish), each part its own commit;
the caches and the properties that change at runtime come in the release
right after it. A checklist; the plans are in the files linked.

## Built, not released (to document and test)

What Dota Passport's phones measured and the framework mended
(`spring_boot_starter_flutter_scene`, `spring_boot_starter_flutter`, the
generator; see the changelogs' `Unreleased`):

- [ ] `spring.flutter.scene.canvas: page | layer | engine`: the engine's
  own canvas, every scene drawn on it, nothing handed over or copied;
  behind the page when the first scene fills the screen (`PageUnderlay`
  steps the theme's background aside), else a platform view.
- [ ] One beat for every scene (`SceneFrames`), on the browser's frames
  (`requestAnimationFrame`), a timer elsewhere; `max-frame-rate: 0`, the
  screen's rate.
- [ ] `spring.flutter.scene.light-clustering`; flutter_scene's timeline
  marks off in a web release build.
- [ ] The frame meter's line for frames drawn without Flutter
  (`OutsideFrames`: `3D 60 fps · 0.9 ms`).
- [ ] WebKit's alpha, `when` / `stillOf`, the materials' precision, the
  Telegram swipe (earlier in the cycle).
- [ ] `when: slow` decided while the placeholder shows, by the scenes' own
  frames, never switching off what the user sees (today it does: redo or
  drop before the release).
- [ ] The alpha probe's two lost WebGL contexts quiet in the console.
- [ ] Tests: `engine` (placement, clip, scroll, host change), `layer`,
  `PageUnderlay`, `OutsideFrames`, the screen's rate.
- [ ] README, changelogs, the site's docs (farum-azula.org).

## The release right after it: caches and runtime properties

- [ ] **Properties that change at runtime**
  ([runtime_properties.md](runtime_properties.md)): the debug window and
  an app's settings screen change them, kept across starts by the
  platform's store (`FileTemplate`: a file on iOS, Android and desktops,
  IndexedDB on the web).
- [ ] **The asynchronous cache first**
  ([spring_boot_starter_cache.md](spring_boot_starter_cache.md#an-asynchronous-cache-planned-the-owner-november-2026)):
  `Cache` and `CacheManager` answering `FutureOr`, as Spring's
  `Cache.retrieve`. The stores below answer later (IndexedDB, a file read
  without blocking, Redis), and today's `Cache` is synchronous.
- [ ] **A cache that outlives a restart**: a `CacheManager` whose entries
  are kept in a store, so `@Cacheable` results (API answers, work done)
  survive a restart on every platform. The cache starter is pure Dart: it
  gets the store as an interface (`CacheStore`); the Flutter starter gives
  one on `FileTemplate` (the `cache` place: the system may clear it), a
  server one on a directory. Entries keep their time-to-live; values go
  through the application's `ObjectMapper`, so a cached type needs
  `@Introspected()` or a serializer, as `FileArea.write` does.
- [ ] **`CompositeCacheManager`**, Spring's: one name looked up in several
  managers, the first that has the cache wins.
- [ ] **A layered cache** (not Spring's; the docs say so): a fast cache in
  front of a slower one, a hit in the slower copied into the faster, a put
  and an evict going to both. For example the local store in front of a
  shared one. Redis itself stays postponed (the owner, November 2026); the
  layering is written against `Cache`, so a Redis cache drops in later.
- [ ] **Resources from the network kept on disk, and one widget for any
  resource** (the owner, 16 November 2026: not an image widget, a
  resource; a video tomorrow goes the same way). Spring's `Resource`,
  `ResourceLoader` and `ProtocolResolver` are there already
  (`resources:`, `file:`, `https:`, assets), but `https:` gives a
  `UrlResource` that reads the network every time.
  - The Flutter starter resolves `http:` / `https:` to a cached resource
    (a `ProtocolResolver`): the bytes and a `meta.json` (`source`,
    `sha256`, `fetchedAt`, `etag`, `lastModified`, the content type) in
    the `cache` place of `FileTemplate`, `spring/resources/<sha256 of the
    location>/` (a file on iOS, Android and desktops, IndexedDB on the
    web), as `ThemeImage` keeps its images today (it moves onto this). Read
    from disk at once; past its age read again in the background with
    `If-None-Match` (a `304` only renews `fetchedAt`); a digest that does
    not match is deleted and fetched again; the least recently used go
    first past the size limit. A large one (a video) is streamed to its
    file, not held in memory, and the resource gives that file's path to a
    player that wants a file; ranges later.
  - `asset:` and `resources:` locations are the app's own: never cached
    on disk (in the browser its HTTP cache keeps them, see the headers
    below).
  - The settings under `spring.flutter.resources.cache.*` (the age, the
    size limit, the locations kept or not); per location in code.
  - `ResourceImage`, an `ImageProvider` on the same cache, for Flutter's
    own widgets (`DecorationImage`, `CircleAvatar`, `precacheImage`); it
    takes the running application's `ResourceLoader`, as `AssetImage`
    takes `rootBundle` (`ResourceImage.using(loader, url)` in tests).
  - **One widget**, `ResourceView` (the name to decide), for a location
    or a `Resource`: it resolves through the `ResourceLoader`, and a chain
    of `ResourceRenderer` beans picks the view by the content type (the
    header, else the file's extension): images in the Flutter starter
    (decoded from the cached bytes), an app's own type as one more bean.
  - **A video without a player in the framework** (the owner, 16 November
    2026: no dependency nobody asked for): the cached resource gives
    `playableUri()`, the cached file (`file:` on iOS, Android and
    desktops, a `blob:` URL from IndexedDB on the web), or the network
    URL while the file is still being written in the background; the app
    hands it to the player it chose. The site's docs show it with
    `video_player` as an example. Playing a file still being written (a
    local proxy with ranges) and HLS / DASH are out. The widget does the rest once for all of them: the placeholder,
    the progress, the error, the fade, the size, the semantics.
  - A cached resource as a `@Cacheable` key: today a resource is equal to
    another by its type and address, as in Spring, so a result made from
    a file that changed at the same address stays until its time runs
    out. Behind a flag (hashing the content costs; the owner, 16 November
    2026), the key of a cached resource is its address and its content's
    version (the `sha256` its `meta.json` keeps), so a new file is a new
    key; an explicit key can say it too (`key: "#image.uri + '@' +
    #image.version"`). Results made from the app's own resources
    (`asset:`, `resources:`) kept on disk go with a new version of the
    app.
  - One store under both caches: the place's limit in
    `spring.flutter.files.cache.max-size` (every writer keeps to it),
    `spring.cache.type: files` with its block `spring.cache.files.*` for
    `@Cacheable` (as `type: simple` has `spring.cache.simple.*`; `files`
    is the app's files, IndexedDB on the web), and the resources' share
    and age in `spring.flutter.resources.cache.*`; on disk
    `spring/caches/<name>/<sha256 of the key>.json` and
    `spring/resources/<sha256 of the location>/`. A `@Cacheable` method
    that reads a file through the `ResourceLoader` stacks on the
    resources' cache; a method that returns a `Resource` keeps only its
    address, so one copy of a file serves both.
  - On iOS, Android and the desktops this is what keeps the app's images
    from the network across starts (avatars): `Image.network` keeps them
    in memory only and downloads them again after every start.
- [ ] **The web build's cache headers from the configuration**: the
  generator writes the host's headers (`_headers` for Cloudflare Pages
  and Netlify, later the others) from Spring Boot's keys
  `spring.web.resources.cache.cachecontrol.*`: `no-cache` for what has no
  hash in its name (`index.html`, `main.dart.js`, `main.dart.wasm`, the
  manifests), a long `max-age` for the app's images and fonts, `immutable`
  for hashed files (the scenes' shader bundles). Dota Passport wrote its
  own by hand (`web/_headers`, November 2026): every path was `no-cache`,
  so each open downloaded all 65 images of a match again.

Not cacheable anywhere: decoded images between two opens of a page (the
page's memory goes with it). That is fewer images to decode: an atlas of
small icons (Dota Passport's roadmap, `scenes.md`).
