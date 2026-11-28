# Release 1.0.0

The scope of the first major release, set by the owner on 26 November
2026. Release 0.10 adds nothing more: it gets its full review, its checks
and ships; everything below comes after it, before 1.0.0.

Items 1 and 2 are release 0.10.1 (the owner, 27 November 2026), not
1.0.0.

1. **The new HTTP client**, as Spring Boot 4's `spring-boot-starter-restclient`
   ([rest_client.md](rest_client.md)): `RestClient` on the family's
   `HttpTransport` and `ObjectMapper`, `RestClient.Builder` and
   `RestClientCustomizer`, and HTTP service clients: `@HttpExchange` /
   `@GetExchange` / `@PostExchange` interfaces implemented by the
   generator, registered with
   `@ImportHttpServices` and configured by groups. No `RestTemplate`:
   Spring Framework 7.1 deprecated it for removal.
   - **The family's own calls move onto `RestClient`** (the owner, 27
     November 2026): every place that builds a JSON request, checks the
     status and reads a JSON answer by hand on the `HttpTransport` (some
     10 files: the OAuth2 client's token
     endpoint, user info, discovery and JWK set; the security starter's
     JWT decoder; the Flutter security starter's token revocation and
     server login; the Supabase starter's HTTP). What stays on the
     transport: its decorators, which must see all the traffic (the
     debug network recorder, the CSRF cookie and server credentials
     transports), and the raw bytes and streams (the remote file cache,
     theme images, scene models, server-sent events). Every hot path
     measured before and after. See [rest_client.md](rest_client.md).
2. **The Feign starter discontinued**
   ([spring_boot_starter_feign.md](spring_boot_starter_feign.md), the plan
   in [release_0_10_1.md](release_0_10_1.md)): Spring Cloud OpenFeign is
   feature-complete and Spring points to HTTP service clients, so 0.10.1
   is its last version and everything moves to `RestClient` and
   `@HttpExchange`.
3. **Redis in the data starter**
   ([spring_boot_starter_data.md](spring_boot_starter_data.md)): designed
   first (Spring Data Redis's templates and repositories, caching on
   Redis, the drivers on each platform), then built.
4. **Spring AI** ([spring_ai.md](spring_ai.md), [spring_ai_mcp.md](spring_ai_mcp.md)),
   on the new HTTP client.
5. **A full security check and code review** of the whole family, with
   every document brought up to date.
6. **The site** (farum-azula.org): its performance checked against what
   the docs promise, and moved to the released framework version.
7. **Debug tools for databases**: a small explorer in the Flutter debug
   tools to see what the connected database holds (tables, rows, a query),
   with a build switch as every debug feature.
8. **Flutter tests with annotations**, last (the owner, 28 November
   2026): widget tests as test classes, `@WidgetTest` methods taking a
   `WidgetTester` next to the `@SpringBootTest` classes the Dart test
   starter has, with `pumpSpring` and `@TestBean` fakes in widget tests
   ([spring_boot_starter_flutter_test.md](spring_boot_starter_flutter_test.md),
   the specification in
   [docs/flutter-testing.md](../docs/flutter-testing.md)). Where it lives
   (a package of its own, or a `testing.dart` library of the Flutter
   starter, as the security starter has) is decided when it starts;
   `spring_boot_starter_test` stays free of Flutter.

Maybe in 1.0.0, not decided (the owner, 26 November 2026): recording a
debug session, with the canvas's video
([flutter_debug_recorder.md](flutter_debug_recorder.md)). Later, not in
1.0.0: the Flutter debug tooling moved into a starter of its own.

Left from the review of 0.10 for that move (the owner, 26 November 2026):
the Flutter starter exports some 126 libraries of its debug tools whole
(`DebugGraphViewState`, `DebugGraphPainter`, `DebugConsoleHeader` and
the like): only the extension points should be public (segments, panes,
commands, graph layers, themes, the file export, the log format), by
`show` or a library of their own, before 1.0 freezes the API. And the
largest files of the debug tools mix responsibilities and are split by
them: `debug_graph_view.dart` (some 1350 lines: the layers' lifecycle,
the heat, the legend, the fit and transform, the gestures, the cards),
`widgets_graph_layer.dart` (some 1000), the signals starter's
`signals_section.dart` (some 900) and `spring_auto_configuration.dart`
(some 2000).
