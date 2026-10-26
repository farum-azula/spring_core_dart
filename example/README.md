# Examples

Separate projects; each one runs on its own from its folder.

| Folder | What | Run |
|---|---|---|
| [`spring_core_tour/`](spring_core_tour/README.md) | NEON Books: a tour where every feature of `spring_core_dart` and `spring_boot_dart` is used and prints what it did, with end-to-end tests over the generated code | `dart run bin/main.dart` |
| [`spring_boot_feign/`](spring_boot_feign/README.md) | A small Spring Boot app against real public servers: a Feign client (REST), server-sent events, a WebSocket client | `dart run bin/main.dart` |
| [`flutter_themes/`](flutter_themes/README.md) | Themes from properties: light, dark, system and custom themes (one YAML file each), every Material component, fonts from the assets, switching at run time and a theme loaded from a "server"; golden screenshots of each theme | `flutter run` |
| [`flutter_notes/`](flutter_notes/README.md) | Notes in a Flutter app with its own REST API (`spring_boot_starter_web` inside the app): add a note on the screen and read it with `curl`, or POST one and see it appear | `flutter run -d macos` |
| [`flutter_counter/`](flutter_counter/README.md) | The `flutter create` counter on `spring_boot_starter_flutter`: the count in a bean, properties per platform, texts in English and Japanese | `flutter run` |
