import 'dart:convert';
import 'dart:typed_data';

/// A readable resource, like Spring's `Resource`.
///
/// Reading is asynchronous because some sources (Flutter assets, network)
/// are async-only. Sources that can also be read synchronously report
/// [supportsSyncRead]; synchronous readers throw [UnsupportedError]
/// otherwise.
///
/// ```dart
/// final resource = DefaultResourceLoader().getResource('file:app.properties');
/// if (resource.exists()) {
///   final text = await resource.readAsString();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// Resource resource = new DefaultResourceLoader()
///     .getResource("file:app.properties");
/// if (resource.exists()) {
///   String text = resource.getContentAsString(StandardCharsets.UTF_8);
/// }
/// ```
///
/// Spring's `getInputStream()` / `getFile()` have no counterpart; read the
/// whole content instead.
abstract interface class Resource {
  /// Whether the resource physically exists.
  bool exists();

  /// Whether the content can be read (usually the same as [exists]).
  bool get isReadable;

  /// File name, if the resource has one.
  String? get filename;

  /// Human-readable description for error messages, e.g.
  /// `file [/app/config/application.properties]`. Also used as the
  /// default property source name and as identity in equality.
  String get description;

  /// URI of the resource, if it has one.
  Uri? get uri;

  /// Whether [readAsBytesSync] and [readAsStringSync] are supported.
  bool get supportsSyncRead;

  /// Reads the whole content asynchronously.
  ///
  /// Like Spring's `getContentAsByteArray()`, but asynchronous.
  Future<Uint8List> readAsBytes();

  /// Reads the whole content asynchronously as text in [encoding].
  ///
  /// ```dart
  /// final text = await resource.readAsString();
  /// ```
  Future<String> readAsString({Encoding encoding = utf8});

  /// Reads the whole content synchronously; throws [UnsupportedError]
  /// unless [supportsSyncRead].
  Uint8List readAsBytesSync();

  /// Reads the whole content synchronously as text in [encoding]; throws
  /// [UnsupportedError] unless [supportsSyncRead].
  String readAsStringSync({Encoding encoding = utf8});

  /// A resource relative to this one (for example a sibling file).
  ///
  /// ```dart
  /// final dev = resource.createRelative('application-dev.properties');
  /// ```
  Resource createRelative(String relativePath);
}

/// Defaults for [Resource] implementations, like Spring's
/// `AbstractResource`.
///
/// Subclasses implement at least [exists], [description] and
/// [readAsBytes]; synchronous reading and [createRelative] are unsupported
/// by default.
///
/// ```dart
/// class HttpResource extends AbstractResource {
///   HttpResource(this.url);
///
///   final Uri url;
///
///   @override
///   bool exists() => true;
///
///   @override
///   String get description => 'URL [$url]';
///
///   @override
///   Future<Uint8List> readAsBytes() => http.readBytes(url);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class HttpResource extends AbstractResource {
///   private final URI url;
///
///   HttpResource(URI url) { this.url = url; }
///
///   @Override
///   public String getDescription() { return "URL [" + url + "]"; }
///
///   @Override
///   public InputStream getInputStream() throws IOException {
///     return url.toURL().openStream();
///   }
/// }
/// ```
abstract class AbstractResource implements Resource {
  /// Constructor for subclasses.
  const AbstractResource();

  @override
  bool get isReadable => exists();

  @override
  String? get filename => null;

  @override
  Uri? get uri => null;

  @override
  bool get supportsSyncRead => false;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());

  @override
  Uint8List readAsBytesSync() => throw UnsupportedError(
    'Synchronous reading is not supported by $description',
  );

  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(readAsBytesSync());

  @override
  Resource createRelative(String relativePath) => throw UnsupportedError(
    'Cannot create a relative resource for $description',
  );

  /// Resources of the same runtime type with the same [description] are
  /// equal, as in Spring.
  @override
  bool operator ==(Object other) =>
      other is Resource &&
      other.runtimeType == runtimeType &&
      other.description == description;

  @override
  int get hashCode => Object.hash(runtimeType, description);

  @override
  String toString() => description;
}

/// In-memory content, like Spring's `ByteArrayResource`.
///
/// Always exists and supports synchronous reading. The bytes are copied on
/// creation and on every read, so the resource is immutable.
///
/// ```dart
/// final resource = ByteArrayResource.fromString(
///   'app.name=demo',
///   description: 'inline config',
/// );
/// final props = PropertiesLoaderUtils.loadPropertiesSync(resource);
/// ```
///
/// Spring (Java):
/// ```java
/// Resource resource = new ByteArrayResource(
///     "app.name=demo".getBytes(StandardCharsets.UTF_8), "inline config");
/// Properties props = PropertiesLoaderUtils.loadProperties(resource);
/// ```
class ByteArrayResource extends AbstractResource {
  /// Creates a resource over a copy of [bytes]; [description] defaults to
  /// `Byte array resource`.
  ByteArrayResource(Uint8List bytes, {String? description})
    : _bytes = Uint8List.fromList(bytes),
      description = description ?? 'Byte array resource';

  /// UTF-8 encoded [text].
  factory ByteArrayResource.fromString(String text, {String? description}) =>
      ByteArrayResource(
        Uint8List.fromList(utf8.encode(text)),
        description: description,
      );

  final Uint8List _bytes;

  @override
  final String description;

  @override
  bool exists() => true;

  @override
  bool get supportsSyncRead => true;

  @override
  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  @override
  Uint8List readAsBytesSync() => Uint8List.fromList(_bytes);

  /// Equal when the description and the content are equal.
  @override
  bool operator ==(Object other) =>
      other is ByteArrayResource &&
      other.description == description &&
      _sameBytes(other._bytes, _bytes);

  @override
  int get hashCode => Object.hash(description, _bytes.length);

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// A placeholder that does not exist, like Spring's `DescriptiveResource`.
///
/// Returned for locations that cannot be resolved, so callers can check
/// [exists] and report [description] instead of handling `null`.
///
/// ```dart
/// const missing = DescriptiveResource('resource [db:config]');
/// missing.exists(); // false
/// ```
///
/// Spring (Java):
/// ```java
/// Resource missing = new DescriptiveResource("resource [db:config]");
/// missing.exists(); // false
/// ```
class DescriptiveResource extends AbstractResource {
  /// Creates a non-existent resource described by [description].
  const DescriptiveResource(this.description);

  @override
  final String description;

  @override
  bool exists() => false;

  /// Always fails with a [StateError].
  @override
  Future<Uint8List> readAsBytes() =>
      Future.error(StateError('$description cannot be opened'));
}
