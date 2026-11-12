# Docs owed: a Flutter web app in apps' own browsers

A page of the site (farum-azula.org, the Flutter part of the docs) on what
breaks when a Flutter web app is opened inside an app's browser
(Telegram, Instagram, Discord, X) and what fixes it. Found twice, on
farum-azula.org and on dotapassport.com (November 2026).

What the page says, with the fix for each:

| Symptom | Cause | Fix |
|---|---|---|
| A swipe down closes the page instead of scrolling | The app's browser treats it as its own close gesture | `spring.flutter.web.page.swipe-to-close: false` |
| The page loader is small, then jumps to its size | `web/index.html` has no `<meta name="viewport">` (Flutter's template leaves it commented out; the engine adds its own only when it starts), so the phone lays the page out 980 px wide until then | an explicit `<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">` |
| A glyph shows as a box (`→`) | The font subset has no such character and the engine has no fallback for it yet | keep to the subset, or list a fallback in `typography.font-family-fallback` |
| Slow frames on 3x screens | The canvas is drawn at the device's ratio | `spring.flutter.web.page.max-pixel-ratio: 2` |
| A translation offer that cannot work | Flutter draws text on a canvas | `spring.flutter.web.page.translate: false` |
| An old build after a deploy | The zone's Browser Cache TTL overrides `Cache-Control` for `.js` and images on a custom domain | `_headers` with `Cache-Control: no-cache`, and the zone's Browser Cache TTL set to "Respect existing headers" (or a Cache Rule that bypasses the cache) |

The page belongs next to the properties of `spring.flutter.web.page.*`,
linked from the loaders page (the page loader is the first thing a
messenger's user sees).
