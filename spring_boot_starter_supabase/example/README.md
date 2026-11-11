# spring_boot_starter_supabase: examples

[`example.dart`](example.dart) is a small Spring Boot application on a
Supabase project: the table `todos` behind a Spring Data repository (the
project's REST API), the bucket `avatars` and the Edge Function `hello`
behind declared interfaces. It starts a local server standing in for the
project, so it runs anywhere:

```bash
dart run build_runner build
dart run example/example.dart
```

With a real project, set `spring.supabase.url` and
`spring.supabase.anon-key` instead of the stand-in's address.

The whole of the starter in one project (a Flutter app, a server and an
Edge Function written in Dart, with Auth, Realtime, row-level security
and SQL) is
[`example/supabase`](https://github.com/farum-azula/spring_core_dart/tree/main/example/supabase)
of the repository.
