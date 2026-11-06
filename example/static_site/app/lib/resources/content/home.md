# A Flutter site on a Spring server

This page is a Flutter web app. The server that sent it is a Spring Boot
application in Dart: it serves the files of `flutter build web` as Spring
Boot serves `src/main/resources/static/`, and its own API on the same
port.

- The pages have real addresses: [the guide](guide.md) is `/guide`. Open it
  directly or reload it: the server answers with `index.html` and the app
  opens the page.
- The [server page](/server) asks `GET /api/info`: same origin, no CORS.
- An address the app does not know shows its not-found page.
