# flutter_spring_rust (planned)

On rinf — an allowed exception to the dependency policy, only in this
starter. Part of the [Flutter plan](spring_boot_starter_flutter.md).

## Rust code as beans

Rust code as beans, for work that should run at native speed off the UI
isolate — image and video processing, compression, cryptography, parsing
large files, search indexes, ML inference — and for Rust crates the Dart
world lacks. Declarative like `@FeignClient`: a Dart interface whose
implementation runs in Rust.

```dart
@RustService('images')
abstract interface class Images {
  Future<Uint8List> thumbnail(Uint8List jpeg, {int width = 256});
  Stream<Progress> encodeVideo(String path); // progress as it comes
}
```

```rust
#[spring::service("images")]
impl Images {
    async fn thumbnail(&self, jpeg: Vec<u8>, width: u32) -> Result<Vec<u8>> { ... }
}
```
Calls are messages (arguments and results through the `ObjectMapper` on
the Dart side and serde on the Rust side) run by the Rust async runtime,
with `Future` and `Stream` results; Rust errors become Dart exceptions,
and the start fails when a Dart method has no Rust implementation. The
other way round, Rust code publishes application events that
`@EventListener`s receive and reads the application's properties; the
Rust runtime starts and stops with the context. Work that does not need
native code can go to a Dart worker isolate through the `TaskExecutor`
([scheduling](spring_boot_starter_scheduling.md)) instead.
