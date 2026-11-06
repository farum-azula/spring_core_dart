# How it is served

Build the site, then start the server next to it:

```shell
cd app && flutter build web
cd ../server && dart run bin/main.dart
```

The server reads the build from a folder at run time:

```yaml
spring:
  web:
    resources:
      static-locations: file:../app/build/web/
      spa-fallback: true        # /guide gets index.html
      chain:
        compressed: true        # main.dart.js.br when the browser takes it
```

A controller always wins over a file, so `/api/info` is the API's. The
files get an `ETag`, `Last-Modified` and `Cache-Control`; a reload answers
`304 Not Modified` for what did not change.

Back to [the start](home.md).
