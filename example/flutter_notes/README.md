# flutter_notes

A Flutter app with its own REST API: notes added on the screen can be read
over HTTP, and notes sent over HTTP show up on the screen at once. The
server is [`spring_boot_starter_web`](../../spring_boot_starter_web/README.md)
running inside the app (`dart:io`'s `HttpServer`, the main isolate, the same
beans as the widgets).

| File | What it shows |
|---|---|
| `lib/main.dart` | `@SpringBootApplication` on `main`, `SpringApplicationWidget(home: NotesPage())`: listing the web starter in `pubspec.yaml` is enough for the server to start with the app |
| `lib/src/notes/notes.dart` | the notes: one `@ChangeNotifierComponent` bean for the screen and the API, so a change from either side rebuilds the list |
| `lib/src/notes/note.dart` | `Note` (the JSON of the API) and `NewNote`, the request body checked with `@NotBlank` / `@Size` |
| `lib/src/api/note_controller.dart` | the `@RestController`: list, find, add (201 + `Location`), delete (204), server-sent events of new notes, a 404 `ProblemDetail` |
| `lib/src/api/local_api.dart` | where the API listens, for the screen: `@EventListener` on `WebServerInitializedEvent` (the real port) and `ContextStoppedEvent` |
| `lib/src/api/api_banner.dart` | the banner with the address and a button that copies a `curl` command |
| `lib/src/notes/note_input.dart`, `note_list.dart` | the text field (`SpringStatefulWidget`) and the list (`SpringStatelessWidget`; only it rebuilds when a note is added) |
| `lib/resources/application.properties` | `server.port`, the app widget and the theme |
| `test/widget_test.dart` | the screen and the API in one test: `MockMvc` (no socket), then real HTTP to a server on a free port (`WebEnvironment.randomPort`), then the app as `flutter run` starts it |

## Run

```sh
flutter run -d macos          # or linux, windows, android, ios (not the web: no server sockets)
```

The banner shows the address (`http://127.0.0.1:8080/api/notes`). From a
terminal on the same computer:

```sh
curl localhost:8080/api/notes                          # the notes, the newest first
curl -i localhost:8080/api/notes -H 'Content-Type: application/json' \
    -d '{"text": "Buy milk"}'                          # 201; the note appears on the screen
curl localhost:8080/api/notes/1
curl -X DELETE localhost:8080/api/notes/1              # 204; it disappears from the screen
curl -N localhost:8080/api/notes/events                # each new note, as it is added
curl localhost:8080/api/notes -H 'Content-Type: application/json' -d '{"text": ""}'
                                                       # 400 ProblemDetail: "must not be blank"
```

Or with the Zed HTTP client: the ▶ lens above each mapping of
`note_controller.dart` writes the request with this port.

- **Only this computer.** A Flutter app listens on `127.0.0.1` unless
  `server.address` says otherwise. To reach the app on a phone from your
  computer: `server.address=0.0.0.0` and the phone's address (on Android's
  emulator: `adb forward tcp:8080 tcp:8080`, then `localhost:8080`).
- **In the background** the context pauses: the server stops and frees the
  port (the banner says "The API is not running"), and starts again when
  the app comes back. `spring.flutter.lifecycle.pause-in-background=false`
  keeps it running.
- **Permissions:** macOS needs `com.apple.security.network.server`
  (`macos/Runner/*.entitlements`, set here), Android `INTERNET`
  (`android/app/src/main/AndroidManifest.xml`, set here).

After changing beans or annotations, regenerate `lib/main.spring.dart`:

```sh
dart run build_runner build      # or `watch` while developing
```

## Tests

```sh
flutter test
```

Real HTTP requests go to the context of `springBootTest(webEnvironment:
WebEnvironment.randomPort)`: it starts outside the fake clock of
`testWidgets`, so its server answers while the test waits in
`tester.runAsync`. flutter_test answers every `HttpClient` request with a
400 without a network call, so the test takes dart:io's client
(`HttpOverrides.runWithHttpOverrides`).
