# A Flutter web site on a Spring server

A Flutter web app served by its own server, as a Spring Boot application
serves a front end from `src/main/resources/static/`: the files of
`flutter build web` and the API on one port, one origin.

| Folder | What |
|---|---|
| [`app/`](app) | The site: a Flutter web app with three pages (`/`, `/guide` from Markdown, `/server` that asks the API) and a not-found page |
| [`server/`](server) | The server: `spring_boot_starter_web` with the app's build as static files and a controller, `GET /api/info` |

## Run

```bash
cd app
flutter pub get
flutter build web                  # writes app/build/web/

cd ../server
dart run bin/main.dart             # http://localhost:8081
```

Open <http://localhost:8081/guide> directly, or reload any page: the server
answers the app's addresses with `index.html` and the app opens the page.
The Server page asks `GET /api/info` of the page's own origin: no CORS, no
server address in the app.

While working on the app, `flutter run -d chrome` serves it on port 5090
and sends `/api/` to the running server (`spring.flutter.web.dev-server.*`
in `app/lib/resources/application.yml`), so the page and the API share an
origin there too.

## Dependencies

The server lists one starter, `spring_boot_starter_web`. The app lists
`spring_boot_starter_flutter_navigation` (it brings the Flutter starter,
`MarkdownView` and `spring_web_dart`'s `HttpTransport`) and, as an app of
`spring.flutter.app.type: material`, `spring_boot_starter_flutter_material`
with `material_ui`, the library of the Material widgets its pages import.
See
[the packages an application lists](../../docs/packages.md).

## The server's configuration

Everything is in `server/lib/resources/application.yml`:

```yaml
spring:
  web:
    resources:
      static-locations: file:../app/build/web/
      spa-fallback: true
      directory-index: true
      chain:
        compressed: true
      cache:
        cachecontrol:
          no-cache: true
```

- **`static-locations: file:...`**: the build is read from a folder at run
  time. It cannot be embedded into the executable like the rest of
  `lib/resources/`: the generator embeds files of up to 1 MB, and Flutter's
  `main.dart.js` and `canvaskit.wasm` are larger.
- **`spa-fallback: true`**: a browser's `GET /guide` (no file there, no
  controller) gets `index.html`, so the app's router opens the page. A
  `fetch()` of a missing path (`Accept` without `text/html`), a missing
  `.js` and anything under `.well-known/` still get a 404.
- **`directory-index: true`**: a path whose folder holds an `index.html`
  gets that file first (`/docs/getting-started` gets
  `docs/getting-started/index.html`). That is where a build with
  `spring.flutter.web.seo.*` puts each page's own HTML for search engines:
  [example/seo_site](../seo_site/README.md) is served by this server
  with `--spring.web.resources.static-locations=file:../../seo_site/build/web/`.
- **Controllers first**: `/api/info` is the controller's, whatever the
  build holds.
- **`chain.compressed`**: `main.dart.js.br` or `.gz` next to `main.dart.js`
  is sent to a browser that takes it. `flutter build web` writes none; a
  build step can. Without them, `server.compression.enabled` compresses
  the answers on the fly (gzip).
- **`cachecontrol.no-cache`**: Flutter's files keep their names from build
  to build, so the browser asks each time and the server answers
  `304 Not Modified` while the `ETag` matches.
- **Types**: `.wasm` is `application/wasm`, `.js` and `.mjs` are
  `text/javascript`; `server.mime-mappings.<extension>` adds or changes
  one.

## Deploy

```bash
(cd app && flutter build web --release)
(cd server && dart compile exe bin/main.dart -o dist/site)
cp -r app/build/web server/dist/web
cd server/dist && ./site --spring.profiles.active=prod   # reads web/ next to it
```

The `prod` profile (`server/lib/resources/application-prod.yml`) reads
the files from `web/` next to the executable.

## Tests

- `app/test/site_test.dart`: the pages, a link between two Markdown pages,
  the Server page with a `MockHttpTransport`, the not-found page.
- `server/test/static_site_test.dart`: the server with a small build of its
  own (`server/test/web/`): `index.html` at `/` and at the app's addresses,
  the API, the types, `304`, the precompressed file, the 404s, nothing
  outside the folder.
- `server/test/built_site_test.dart` (tag `built-site`): the same against
  the real `app/build/web/`. CI builds the site and runs it; locally it is
  skipped without a build.
