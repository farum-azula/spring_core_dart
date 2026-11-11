# spring_boot_starter_edge: examples

[`main.dart`](main.dart) and [`books.dart`](books.dart) are a small Spring
Boot application that runs as a function: a controller, bearer tokens
checked by Spring Security, work after the answer (`EdgeRuntime.waitUntil`)
and work by the platform's schedule (`EdgeScheduledHandler`). Everything
in it works in a function.

```bash
dart run build_runner build
dart run example/main.dart      # an ordinary server on port 8080
dart run spring_boot_starter_edge:build --platform supabase \
  --name books --entry example/main.dart
```

A whole project is
[`example/supabase/function`](https://github.com/farum-azula/spring_core_dart/tree/main/example/supabase/function)
of the repository: an Edge Function of a Supabase project.
