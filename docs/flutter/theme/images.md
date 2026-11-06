---
title: "Theme images — Spring for Dart"
description: "Images in a Flutter theme from assets or the network: cache, refresh, SHA-256 pin, headers, timeout, fallback, redirects, web CORS and image tokens."
slug: /docs/flutter/theme/images
section: Flutter / Theme
order: 10
keywords: [flutter, theme, yaml, images, network image, cache, refresh, sha256, headers, fallback, cors, ThemeImage]
---

# Theme images

A theme can name images: the [background](background.md) image, the images of
single screens, and **image tokens** you read in Dart. All use the same map.
An image is either an **asset** of the app or a file from the **network**.
Network images are downloaded in the background, kept in a cache that
survives restarts, checked against a SHA-256 digest if you give one, and
refreshed when you ask.

```yaml
spring:
  flutter:
    theme:
      background:
        image:
          source: https://cdn.example.com/neon/background.jpg
          refresh: 1d
          source-sha256: 9f2c1a5e7b2d4a6f8c0e1b3d5f7a9c2e4b6d8f0a1c3e5b7d9f1a3c5e7b9d1f3a
          headers:
            Authorization: Bearer ${cdn.token}
          timeout: 10s
          fallback: assets/images/background.jpg
      tokens:
        brand:
          hero:
            source: https://cdn.example.com/hero.png
            refresh: 1d
```

## Properties

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `source` | text | an asset path, an `https://` URL, a `github:owner/repo/path@ref` address | required | Where the image is. A path with no scheme (and a Windows drive such as `C:`) is an asset; an address is downloaded. `http://` stops the start unless `spring.remote.allow-insecure` is `true` (see [insecure connections](properties.md#insecure-connections)). Any other scheme stops the start |
| `refresh` | duration | `30m`, `12h`, `1.5d` | none | How old the cache may get before the file is looked at again in the background. Without it the first download is kept for ever and there is never another request |
| `source-sha256` | text | 64 hexadecimal digits | none | The file must have exactly this digest. Any other file is refused |
| `headers` | map | header name to value | none | Request headers, such as `Authorization`. `${...}` placeholders are resolved by the application's configuration. Header names keep their spelling |
| `timeout` | duration | `10s`, `1m` | `10s` | The longest a download may take |
| `fallback` | text | an asset path | none | An asset shown while a network image is not there yet |

Durations here are the same as everywhere in a theme: a number (decimals
allowed) with a unit (`ms`, `s`, `m`, `h`, `d`), like `1.5s` or `0.5d`. A
plain number is milliseconds. ISO-8601 (`PT1H30M`) is not accepted.

In a [background image](background.md#the-image) these keys sit next to
`fit`, `alignment`, `opacity` and `blur`. Any other key stops the start and
lists the valid ones.

References (`$colors.primary`) are not resolved in `source`, `fallback`,
`source-sha256` or `headers`, so a `$` in a secret that came from a placeholder
stays exactly as it is. See [tokens and references](tokens-and-references.md).

## What is shown, and when

The start never waits for the network.

| Situation | What the app shows |
|---|---|
| An asset | The asset, at once |
| A network image with a cache | The cached image, at once |
| A network image without a cache, with a `fallback` | The fallback; the download runs in the background and the image replaces it when it arrives |
| A network image without a cache and without a fallback | Nothing; for a background, its `color` |

When a download ends, the new image fades in (for a background, over its
[`transition`](background.md#the-transition)).

## Downloads and the cache

- **Where.** The cache is in the app's `support` files place, in
  `spring/images/<sha256 of source and digest>/` (`image` and `meta.json`).
  It survives restarts. In a browser it is in IndexedDB. The folder belongs
  to the source and the digest, so a changed `source` or `source-sha256`
  downloads again. Images that are no longer in any theme are removed at
  start. Two themes that name the same image share one download.
- **First start.** No cache means a download in the background, once. The
  request asks for `image/*`.
- **Refresh.** With `refresh`, a cache that is older than that is read again
  in the background, with `If-None-Match` and `If-Modified-Since`. A `304`
  only renews the age. A new file is swapped in as soon as it arrives. If a
  download fails, it is tried again after the refresh time, but not later than
  five minutes.
- **Digest.** A downloaded file with a different SHA-256 is refused and the
  image on screen stays. A cached file that does not match is dropped with a
  warning.
- **Limits.** A file may be 20 MiB at most; an empty answer is an error.
- **Failures.** Offline, a timeout, a wrong digest or a file that is too big
  keep what is shown, and write a warning to the log.
- **Redirects.** A redirect to another host drops your custom `headers`, so a
  token is not sent to a stranger.
- **On the web** the server must allow your origin with CORS headers
  (`Access-Control-Allow-Origin`). If a download fails there, the log says so.

## Image tokens

A token that is a map with a `source` and **only** the keys of the table above
is an image. A map with another key next to `source` is a group of tokens.
The image sits at least at `tokens.<group>.<key>`.

```yaml
spring:
  flutter:
    theme:
      tokens:
        neon:
          hero: { source: https://cdn.example.com/hero.png, refresh: 1d }
          logo: { source: assets/images/logo.png }
```

```dart
final hero = context.theme.tokens.neon.hero;      // a ThemeImage
ValueListenableBuilder(
  valueListenable: hero.listenable,
  builder: (context, provider, _) =>
      provider == null ? const SizedBox() : Image(image: provider),
);
```

`ThemeImage.provider` is the image to paint now (`null` while a network image
has neither a cache nor a fallback), and `listenable` notifies when a download
arrives or is refreshed. `theme.tokenImage('neon.hero')` reads the same image
without the generator.

## Errors

A wrong value stops the start and names the property, for example
`tokens.neon.hero.source-sha256` with "must be 64 hexadecimal digits". An
`http://` source stops the start with "the connection is not secure", naming
the address and its property, unless `spring.remote.allow-insecure` is
`true`. A missing `source` is an error too: every image needs one.

## See also

- [Background](background.md)
- [Tokens and references](tokens-and-references.md)
- [Properties](properties.md#a-theme-from-a-url): a whole theme from a URL
