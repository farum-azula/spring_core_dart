# spring_boot_starter_feign (discontinued)

Discontinued in 0.10.1, its last version (the owner, 27 November 2026).
Spring Cloud OpenFeign is feature-complete and Spring points to its HTTP
service clients; the family follows Spring as closely as it can, so when
Spring stops developing something, the family stops supporting it.

Use `spring_boot_starter_restclient`: `RestClient`, and `@HttpExchange`
interfaces imported with `@ImportHttpServices`, which the generator
implements (see [rest_client.md](rest_client.md)).

The package's code stays in the repository for now, outside CI; no
starter, example or tool depends on it. After 0.10.1 is published it is
marked `discontinued` on pub.dev, and its folder can go (with its entries
in the root `pubspec.yaml` workspace, `tool/version.dart` and
`.github/workflows/publish.yml`, kept only for that last publish).
