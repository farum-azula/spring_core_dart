# A Flutter web site that search engines can read

A Flutter web app draws on a canvas, so its HTML holds no text: a search
engine, a link preview or a language model sees an empty page. This
example turns on `spring.flutter.web.seo.*`, and the build writes a real
HTML page for every address of the site, made from the same routes and
Markdown files the app shows. The reference is
[The site's pages](../../docs/configuration.md#the-sites-pages-springflutterwebseo).

## What it shows

| Where | What |
|---|---|
| `lib/resources/application-web.yml` | the keys: `enabled`, `site-url`, `from-routes`, the `title` pattern, the site's `description` and `image`, a Markdown folder (`content[0]`, with `exclude`), a page by hand (`pages[0]`, a longer title on `/`) |
| `lib/src/pages.dart` | the screens: `/` with `@RouteInfo(description:)`; `/docs/{*path}` and `/blog/{*path}` with `content:` (a page per Markdown file); `/legal/{*path}`, which reads its Markdown itself, so `content[0]` lists its pages; `/books/{id}` with `@RouteInfo(paths:)`; `/about` with `#{key}` from `messages.properties`; `/account` with `@RouteInfo(index: false)` |
| `lib/resources/content/` | the Markdown: front matter (`title`, `description`, `image`), a page without one (its first heading is its title), links between files, a file left out (`_draft.md`) |
| Japanese | `spring.flutter.navigation.languages: [en, ja]` in `application.yml`: English at `/docs`, Japanese at `/ja/docs`; `messages_ja.properties` for `#{key}`; `index.ja.md` and `getting-started.ja.md` next to their English files (`guides/routing.md` has no translation: its `/ja` page keeps the English text, `noindex`); the 日本語 / EN button switches the language at the same page |
| `lib/resources/images/` | the preview pictures (`og:image`), listed under `flutter: assets:` so the build serves them |
| `web/` | what the generator wrote, committed: `<path>/index.html` per page, the root page in `web/index.html`, `sitemap.xml`, `robots.txt`, `llms.txt`, `llms-full.txt`, the `.md` copies, `.spring-seo` (the list of what it wrote) |
| `pubspec.yaml` | `spring_boot_starter_flutter_navigation` for the pages and their addresses; `spring_boot_starter_flutter_material` with `material_ui` for the `MaterialApp` of `spring.flutter.app.type: material` and the Material widgets of `lib/src/pages.dart` |

## Build

```bash
flutter pub get
dart run build_runner build    # writes the pages into web/
flutter build web              # copies them into build/web/
```

`flutter run -d chrome` serves the app on port 5095.

## Look at the result

- `web/docs/getting-started/index.html`: the page's own `<title>`,
  `description`, `canonical` and `og:*` tags, and the Markdown as HTML
  in `<main id="spring-content">`, under the app (never shown).
- `web/account/index.html`: `noindex`.
- `web/sitemap.xml`: every page but `/account`; `web/robots.txt` points
  at it.
- `web/llms.txt` and `web/llms-full.txt`: the Markdown pages for language
  models; `web/docs/getting-started.md`: one of them as written.

### While `flutter run` is running

The pages are for search engines and for people who open an address
directly; the app itself never loads them. So they are not in the
browser's DevTools (Sources shows what the app loaded: its scripts, not
the pages or the Markdown, which is built into the app).

`flutter run`'s dev server answers every address with the root
`index.html`, so `localhost:5095/docs` shows the app with the home page's
`<title>`. Ask for the files themselves and view the source
(Cmd+Option+U, Ctrl+U):

- `localhost:5095/docs/index.html`, `localhost:5095/blog/hello/index.html`:
  the pages, with their own `<title>`, tags and hidden text;
- `localhost:5095/docs/getting-started.md`, `/sitemap.xml`, `/robots.txt`,
  `/llms.txt`.

A real host (below) serves `/docs` from `docs/index.html` itself.

## Host it

The pages are files named `<path>/index.html`
(`spring.flutter.web.seo.page-files: directory`, the default), so the
server must answer `/docs/getting-started` with
`docs/getting-started/index.html`, and the app's other addresses with the
root `index.html`. A static host does that after a redirect to
`/docs/getting-started/`, so the canonical addresses, `og:url` and the
sitemap end with `/`. `page-files: html` writes
`docs/getting-started.html` instead, which Cloudflare Pages, GitHub Pages
and Netlify serve at `/docs/getting-started` with no redirect (the
addresses then have no `/` at the end).

- **A static host** (Cloudflare Pages, GitHub Pages, Netlify, Firebase
  Hosting): upload `build/web/`.
- **`spring_boot_starter_web`**, with `spring.web.resources.directory-index`
  and `spa-fallback`. The server of
  [example/static_site](../static_site/README.md) has both:

  ```bash
  cd ../static_site/server
  dart run bin/main.dart \
    --spring.web.resources.static-locations=file:../../seo_site/build/web/
  curl -s localhost:8081/docs/getting-started | grep '<title>'
  # <title>Getting started · Lumen</title>
  ```

## Tests

- `test/pages_test.dart`: the screens, a link between two Markdown files,
  a book by its id, the messages, the not-found page, `/ja` in Japanese and
  the switch back.
- `test/seo_pages_test.dart`: what `web/` holds: each page's title,
  description and canonical address, the hidden text, the preview
  pictures, the sitemap without the `noindex` page, `robots.txt`, `llms.txt`
  and the Markdown copies; the Japanese pages with `<html lang>`,
  `hreflang` and the sitemap's alternates.
