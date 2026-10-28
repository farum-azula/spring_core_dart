import 'dart:convert';
import 'dart:typed_data';

/// A piece of content the application reads, wherever it lives: a file of
/// `lib/resources/` (the classpath), a file on disk, a URL, a Flutter
/// asset, bytes in memory.
///
/// It lets code read a template, a data file or a config file without
/// caring where it comes from: the location string (`classpath:mail.txt`,
/// `file:./data.csv`, `https://...`) decides, and the code only reads.
/// Applications receive resources: a `@Value('classpath:...')` parameter
/// of type `Resource`, or `getResource` on the application context (any
/// `ResourceLoader`). They implement it only for a new kind of storage,
/// usually by extending [AbstractResource].
///
/// Reading is asynchronous because some sources (Flutter assets, network)
/// can only be read that way. Resources that can also be read
/// synchronously say so in [supportsSyncRead]; the synchronous readers of
/// the others throw [UnsupportedError].
///
/// ```dart
/// @Component()
/// class OrderMailer {
///   // The template ships in lib/resources/templates/, embedded by the
///   // generator, so it is found on the server, in Flutter and on the web.
///   OrderMailer(
///     @Value('classpath:templates/order-confirmation.txt') this.template,
///   );
///
///   final Resource template;
///
///   Future<String> body() async => (await template.readAsString()).trim();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class OrderMailer {
///   private final Resource template;
///
///   OrderMailer(@Value("classpath:templates/order-confirmation.txt")
///       Resource template) {
///     this.template = template;
///   }
///
///   String body() throws IOException {
///     return template.getContentAsString(StandardCharsets.UTF_8).trim();
///   }
/// }
/// ```
///
/// Spring's `getInputStream()` and `getFile()` have no counterpart; read
/// the whole content instead.
abstract interface class Resource {
  /// Whether the content is there: the file exists, the classpath entry is
  /// embedded. Check it before reading a resource that may be missing.
  /// A `UrlResource` cannot ask the server synchronously and always says
  /// `true`.
  bool exists();

  /// Whether the content can be read; usually the same as [exists], but
  /// `false` for a directory.
  bool get isReadable;

  /// The last part of the path, such as `application.yml`, or `null` when
  /// the resource has no file name (bytes in memory).
  String? get filename;

  /// A text that tells people which resource this is, for error messages,
  /// such as `file [/app/config/application.properties]`. It is also the
  /// default name of a property source read from it, and two resources of
  /// the same type with the same description are equal.
  String get description;

  /// The URI of the resource (`file:`, `https:`, ...), or `null` when it
  /// has none.
  Uri? get uri;

  /// Whether [readAsBytesSync] and [readAsStringSync] work. True for files
  /// and the embedded classpath; false for URLs and Flutter assets.
  bool get supportsSyncRead;

  /// Reads the whole content as bytes. Works for every resource that
  /// exists; fails for one that does not.
  ///
  /// Like Spring's `getContentAsByteArray()`, but asynchronous.
  Future<Uint8List> readAsBytes();

  /// Reads the whole content as text, decoded with [encoding] (UTF-8
  /// unless given).
  ///
  /// ```dart
  /// final text = await resource.readAsString();
  /// ```
  Future<String> readAsString({Encoding encoding = utf8});

  /// Reads the whole content as bytes without waiting, for code that
  /// cannot be asynchronous. Throws [UnsupportedError] unless
  /// [supportsSyncRead].
  Uint8List readAsBytesSync();

  /// Reads the whole content as text without waiting, decoded with
  /// [encoding]. Throws [UnsupportedError] unless [supportsSyncRead].
  String readAsStringSync({Encoding encoding = utf8});

  /// The resource at [relativePath] from this one, such as a sibling file
  /// next to a config file. It is not checked to exist. Throws
  /// [UnsupportedError] for resources without a location (bytes in
  /// memory).
  ///
  /// ```dart
  /// final dev = resource.createRelative('application-dev.properties');
  /// ```
  Resource createRelative(String relativePath);
}

/// A base class for new kinds of [Resource]: it fills in everything that
/// can be derived from a few members.
///
/// Extend it to read content from a place the framework does not know,
/// for example a database or an HTTP client of your own, then hand it out
/// from a `ProtocolResolver`. A subclass implements [exists],
/// [description] and [readAsBytes]; text reading is derived from them.
/// Synchronous reading and [createRelative] throw [UnsupportedError]
/// until overridden. Two resources of the same type with the same
/// [description] are equal.
///
/// ```dart
/// // Content behind an HTTP client the application already has.
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
  /// Lets subclasses be `const`.
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

  /// Whether [other] is a resource of the same run-time type with the same
  /// [description], as in Spring.
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

/// A resource over bytes held in memory.
///
/// Use it where an API wants a [Resource] but the content is already in
/// hand: in tests, for text built at run time, or for a download kept in
/// memory. It always exists and can be read synchronously. The bytes are
/// copied on creation and on every read, so the content cannot change.
///
/// ```dart
/// // Properties built in code, read like a file.
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
  /// Creates a resource over a copy of [bytes], described by
  /// [description] (`Byte array resource` unless given).
  ByteArrayResource(Uint8List bytes, {String? description})
    : _bytes = Uint8List.fromList(bytes),
      description = description ?? 'Byte array resource';

  /// Creates a resource whose content is [text], encoded as UTF-8.
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

  /// Whether [other] is a byte array resource with the same description
  /// and the same bytes.
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

/// A resource that never exists, standing for a location that cannot be
/// resolved.
///
/// Loaders return it instead of `null`, so callers keep one code path:
/// they check [exists] and put [description] in their error message.
/// Applications meet it as the result of a lookup that found nothing;
/// reading it fails.
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
  /// Creates a missing resource described by [description].
  const DescriptiveResource(this.description);

  @override
  final String description;

  @override
  bool exists() => false;

  /// Always fails with a [StateError]: there is nothing to read.
  @override
  Future<Uint8List> readAsBytes() =>
      Future.error(StateError('$description cannot be opened'));
}

/// A [resource] paired with the character [encoding] to read it in;
/// `null` means UTF-8.
///
/// It carries `@PropertySource(encoding: ...)` to the
/// `PropertySourceFactory`, which is where applications meet it: a custom
/// factory reads the file through it, so the declared encoding is used.
///
/// ```dart
/// // A legacy file in ISO-8859-1.
/// final resource = EncodedResource(
///   FileSystemResource('config/legacy.properties'),
///   encoding: latin1,
/// );
/// resource.readAsStringSync();
/// ```
///
/// Spring (Java):
/// ```java
/// var resource = new EncodedResource(
///     new FileSystemResource("config/legacy.properties"),
///     StandardCharsets.ISO_8859_1);
/// ```
final class EncodedResource {
  /// Pairs [resource] with the [encoding] to read it in (UTF-8 when
  /// `null`).
  const EncodedResource(this.resource, {this.encoding});

  /// The resource to read.
  final Resource resource;

  /// The declared encoding, or `null` for UTF-8.
  final Encoding? encoding;

  /// Reads the whole content as text without waiting, decoded with
  /// [encoding]. Throws [UnsupportedError] when the resource cannot be
  /// read synchronously.
  String readAsStringSync() =>
      resource.readAsStringSync(encoding: encoding ?? utf8);

  /// Reads the whole content as text, decoded with [encoding].
  Future<String> readAsString() =>
      resource.readAsString(encoding: encoding ?? utf8);

  @override
  bool operator ==(Object other) =>
      other is EncodedResource &&
      other.resource == resource &&
      other.encoding?.name == encoding?.name;

  @override
  int get hashCode => Object.hash(resource, encoding?.name);

  @override
  String toString() => resource.toString();
}
