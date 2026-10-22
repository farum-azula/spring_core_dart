# Spring Boot + Feign against a real API

A small, complete Spring Boot application in Dart that talks to a real
public REST API — [JSONPlaceholder](https://jsonplaceholder.typicode.com),
a free fake API, no key needed — through a Feign client
([`spring_boot_starter_feign`](../../spring_boot_starter_feign/README.md)).

```bash
cd example/spring_boot_feign
dart run build_runner build   # only after changing beans or the client
dart run bin/main.dart
```

```text
Started spring-boot-feign-example in 52 ms (profiles: default)
DEBUG [feign.JsonPlaceholderClient] ---> GET https://jsonplaceholder.typicode.com/users/1
DEBUG [feign.JsonPlaceholderClient] <--- 200 OK (149 ms)
 INFO [blog] user 1: Leanne Graham <Sincere@april.biz>, Gwenborough, works at Romaguera-Crona
DEBUG [feign.JsonPlaceholderClient] ---> GET https://jsonplaceholder.typicode.com/posts?userId=1
DEBUG [feign.JsonPlaceholderClient] <--- 200 OK (40 ms)
 INFO [blog] 10 posts by Bret, first: "sunt aut facere repellat provident occaecati excepturi optio reprehenderit"
DEBUG [feign.JsonPlaceholderClient] ---> GET https://jsonplaceholder.typicode.com/posts/1/comments
DEBUG [feign.JsonPlaceholderClient] <--- 200 OK (36 ms)
 INFO [blog] 5 comments on post 1, by Eliseo@gardner.biz, Jayne_Kuhic@sydney.com, ...
DEBUG [feign.JsonPlaceholderClient] ---> POST https://jsonplaceholder.typicode.com/posts
DEBUG [feign.JsonPlaceholderClient] <--- 201 Created (356 ms)
 INFO [blog] created: 201, id 101, "Spring in Dart"
DEBUG [feign.JsonPlaceholderClient] ---> GET https://jsonplaceholder.typicode.com/posts/9999
DEBUG [feign.JsonPlaceholderClient] <--- 404 Not Found (41 ms)
 INFO [blog] post 9999: 404 Not Found (FeignNotFound)
```

It needs the internet; without it the application starts and logs
`JSONPlaceholder is not reachable: ...` (after 3 attempts).

## What is where

| File | What |
|---|---|
| `bin/main.dart` | `@SpringBootApplication` + `runApplication(args)` — the whole entry point |
| `lib/src/jsonplaceholder_client.dart` | the API as an interface: `@FeignClient`, `@GetMapping`, `@PostMapping`, `@PathVariable`, `@RequestParam`, `@RequestBody`, `ResponseEntity` |
| `lib/src/models.dart` | `User` (with nested `Address`, `Company`), `Post`, `NewPost`, `Comment`: plain immutable classes, no annotations, no `fromJson` / `toJson` |
| `lib/src/feign_config.dart` | a `RequestInterceptor` bean (an `X-Client` header on every request) and a `Retryer` bean |
| `lib/src/blog_runner.dart` | an `ApplicationRunner`: gets the client injected, calls the API, handles `FeignNotFound` |
| `lib/resources/application.properties` | the API URL, Feign timeout and log level, logging levels |
| `bin/main.beans.dart` | generated: the beans, the client implementation, the JSON metadata of the models |

## Things to try

```bash
# Another API base URL (e.g. a local copy of JSONPlaceholder)
dart run bin/main.dart --jsonplaceholder.url=http://localhost:3000

# See the headers of each request (the X-Client header of the interceptor)
dart run bin/main.dart --spring.cloud.openfeign.client.config.jsonplaceholder.logger-level=headers

# No request log
dart run bin/main.dart --logging.level.feign=info
```

Add a method to `JsonPlaceholderClient` (say `@GetMapping('/todos')
Future<List<Todo>> todos(@RequestParam('userId') int userId);` with a
`Todo` class next to the models), run `dart run build_runner build` and call
it from the runner.
