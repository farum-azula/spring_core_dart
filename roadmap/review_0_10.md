# The review after 0.9.0 (November 2026)

A full review of everything since the review of 0.6 to 0.8 (`11dc4ca4`):
bugs and differences from Spring 7 / Boot 4, security, and every annotation
of the framework where it does not belong
([fix_plan.md](fix_plan.md#for-the-next-full-review-annotations-where-they-do-not-belong)).
Each finding was confirmed by a probe.

## What was found and fixed

- **Bugs and Spring parity** (33: 4 High, 17 Medium, 12 Low): the disk cache
  (expiry, key collisions, classes of the same name, `sync`, quadratic puts),
  the hot-reload fingerprint of nested modules, build keys and profile files,
  `--dart-define` of the starters' properties, a synchronous `@Transactional`
  in a release build, `@Computed` and `@Effect` through the proxy, a bare
  `@ConditionalOnMissingBean()` on the declared return type, rename in the
  language server.
- **Security** (no Critical or High): files of `lib/resources/` embedded in
  every build, secret-looking `--dart-define` keys in client builds,
  `@PreAuthorize` on a member the proxy cannot override, credentials sent
  along a cross-origin redirect by Feign, a `Like` pattern that froze an
  isolate, JSON number length and nesting limits, `?sort=` limits, masking in
  `toString`, logs and the debug panel, the SEO builder's paths, the disk
  cache's file modes, the language server's symlinks, YAML bombs and framing,
  the checksum of the server the Zed extension downloads.
- **Annotations** (247 classes, 1656 placements; 959 did nothing or did the
  wrong thing): each now fails the build with what to change, or is covered
  as valid. An annotation composes by extending another
  (`class Dev extends Profile`); `@Primary` on an annotation class is a build
  error.

- **After the review**: two `Host` headers are a 400 (the server reads the
  request heads in the bytes of each connection, about 2% of requests per
  second on a minimal handler); the build warns about a handler's `Pageable`
  or `Sort` without `@AllowedSortProperties`, since a DTO does not hide what
  the order of the rows shows. That annotation and the limit of 16 sort
  properties are the framework's own additions.

## Left as it is, on purpose

- **`Profiles.of` stays strict**: Spring accepts `(dev` or `a &` without a
  word; here a typo is an error.
- **A deferred call on `this`** (`scheduleMicrotask(() => this.m())`) is still
  advised, since a subclass proxy is the target. Only proxies that are a
  separate object would change it.
- **The Zed extension reads `.zed/settings.json`** of the project for the
  server's path (its API has no user-only setting): open only projects you
  trust.
- **`LayeredCacheManager`** gives a hit copied into a faster layer that
  layer's full TTL again (documented).
- **Constraints and JSON annotations on a plain DTO**: the build cannot tell
  whether another package or a test reads the class, so three such placements
  are not errors.
