# spring_boot_starter_restclient: examples

This starter gives a
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
application `RestClient` instances to call other services: a `RestClientBuilder`
bean set up from `spring.http.clients.*`, and the client of each HTTP
service group set by `spring.http.serviceclient.<group>.*`. Every
outgoing address is denied until it is allowed by hand.

[`example.dart`](example.dart) is a small Spring Boot application with an
HTTP service interface, `BookService`, imported into the `catalog` group
by `@ImportHttpServices`: the generator writes the class whose methods
call a local catalog server through the client of that group (its base
URL, `http://127.0.0.1:<port>`, is allowed because it is the group's).
A `Catalog` service reads a book, a missing book (a 404, caught as
`HttpClientErrorException`) and a search (`@RequestParam`, a query
parameter). Then a client of its own, from the `RestClientBuilder`
bean, tries the cloud metadata address and is denied before anything is
sent.

## Run it

```yaml
dependencies:
  spring_boot_starter_restclient: ^0.10.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.10.0   # required: turns annotations into code
```

Adding the dependency and running the generator is all the setup: the
starter is found and switched on automatically. From the package
directory:

```bash
dart run build_runner build
dart run example/example.dart
```

It logs:

```
title: Dune
title: null
search: [978-0]
denied: for good
```
