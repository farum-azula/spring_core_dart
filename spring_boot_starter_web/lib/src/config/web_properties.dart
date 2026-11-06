import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/forwarded_headers.dart'
    show ForwardHeadersStrategy;
import 'package:spring_boot_starter_web/src/web_server.dart'
    show ClientAuth, Shutdown;

// The settings of the web starter that are properties. Each class below is
// the one place that names its keys, describes them (the editor metadata is
// made from the fields) and gives their defaults; the starter binds them
// with the Binder and builds `ServerProperties`, `HttpSessionProperties` and
// `MultipartProperties` from them.

/// The `SameSite` attribute of the session cookie.
enum SessionSameSite {
  /// `SameSite=Lax`. The default.
  lax,

  /// `SameSite=Strict`.
  strict,

  /// `SameSite=None` (browsers want `Secure` with it).
  none,

  /// No `SameSite` attribute.
  unset,
}

/// The `server.*` properties: the HTTP server.
///
/// Spring Boot (Java): `ServerProperties`.
@ConfigurationProperties('server')
class ServerSettings {
  /// The port. `0` picks a free one; the real port is then in
  /// `local.server.port`.
  int port = 8080;

  /// The address to listen on. `localhost` is `127.0.0.1`; a host name is
  /// looked up. Default: all interfaces; **127.0.0.1 in Flutter apps**.
  String? address;

  /// What happens to running requests when the server stops: `graceful`
  /// accepts no new connections and lets them finish, `immediate` cuts
  /// them.
  Shutdown shutdown = Shutdown.graceful;

  /// A prefix of every mapping, such as `/shop`.
  String? contextPath;

  /// A larger request body is answered with 413, whatever its
  /// `Content-Type`; `-1` means no limit.
  DataSize maxHttpRequestBodySize = DataSize.ofMegabytes(10);

  /// How long a request body may send nothing while it is read: then the
  /// answer is 408 and the connection closes. `-1`, `0` or less: no
  /// timeout. Also how long an idle connection stays open.
  Duration connectionTimeout = const Duration(seconds: 60);

  /// The longest a request's filters and handler may take to answer, else
  /// a 503; also a deadline for the calls the request makes. Default: no
  /// limit (`0` or less: none). Not in Spring Boot.
  Duration? requestTimeout;

  /// Behind a reverse proxy: apply its `Forwarded` or `X-Forwarded-Proto`,
  /// `-Host`, `-Port`, `-For` headers (the scheme, so cookies get `Secure`
  /// behind TLS; the host and port; the client's address), from trusted
  /// proxies only.
  ForwardHeadersStrategy forwardHeadersStrategy = ForwardHeadersStrategy.none;

  /// The forwarded headers' settings (`forward-headers.*`).
  ForwardHeadersSettings forwardHeaders = ForwardHeadersSettings();

  /// TLS (`ssl.*`).
  ServerSslSettings ssl = ServerSslSettings();

  /// Gzip of the responses (`compression.*`).
  ServerCompressionSettings compression = ServerCompressionSettings();

  /// The limits of WebSocket sessions (`websocket.*`).
  ServerWebSocketSettings websocket = ServerWebSocketSettings();

  /// Sessions and their cookie (`session.*`).
  ServerSessionSettings session = ServerSessionSettings();

  /// More media types of the static resources by file extension, on top
  /// of the built-in ones (`server.mime-mappings.wasm=application/wasm`);
  /// an extension listed here wins. The extension is matched in any case.
  Map<String, String> mimeMappings = {};
}

/// The `server.forward-headers.*` properties.
@Introspected()
class ForwardHeadersSettings {
  /// Whose forwarded headers are believed (Tomcat's `internalProxies`): IP
  /// addresses and CIDR ranges, as a comma list or a YAML list. A client
  /// reaching the server from elsewhere cannot set them. Default: loopback
  /// and private networks.
  List<String>? trustedProxies;
}

/// The `server.ssl.*` properties.
@Introspected()
class ServerSslSettings {
  /// `false` ignores the other `server.ssl.*` keys.
  bool enabled = true;

  /// The certificate chain (a PEM file); TLS is on when it is set.
  String? certificate;

  /// The private key (a PEM file); required with `certificate`.
  String? certificatePrivateKey;

  /// The password of an encrypted private key.
  String? keyPassword;

  /// The certificates of trusted clients (a PEM file), for `client-auth`.
  String? trustCertificate;

  /// Asks clients for a certificate; with `need`, a request without one is
  /// answered with 403.
  ClientAuth clientAuth = ClientAuth.none;
}

/// The `server.compression.*` properties.
@Introspected()
class ServerCompressionSettings {
  /// Gzip of the responses of `mime-types`, from `min-response-size` on (or
  /// of unknown length), for clients that send `Accept-Encoding: gzip`;
  /// never partial content, nor an answer with a strong `ETag` (as
  /// Tomcat).
  bool enabled = false;

  /// The media types compressed, as in Spring Boot; add `text/event-stream`
  /// to compress event streams.
  List<String> mimeTypes = [
    'text/html',
    'text/xml',
    'text/plain',
    'text/css',
    'text/javascript',
    'application/javascript',
    'application/json',
    'application/xml',
  ];

  /// The smallest `Content-Length` compressed.
  DataSize minResponseSize = DataSize.ofKilobytes(2);
}

/// The `server.websocket.*` properties.
@Introspected()
class ServerWebSocketSettings {
  /// The largest text message a WebSocket session reads, in UTF-8 bytes
  /// (Tomcat counts characters); a larger one closes the session with 1009.
  /// `-1` for no limit.
  DataSize maxTextMessageSize = DataSize.ofKilobytes(8);

  /// The same for binary messages. `-1` for no limit.
  DataSize maxBinaryMessageSize = DataSize.ofKilobytes(8);

  /// How much a WebSocket session may keep waiting to be sent to a client
  /// that reads slowly or not at all (pongs included); past it the
  /// connection is dropped and the session's close status is 4500
  /// (`sessionNotReliable`). `-1` for no limit.
  DataSize sendBufferSizeLimit = DataSize.ofKilobytes(512);

  /// How long what a session sent may take to leave; past it the connection
  /// is dropped the same way. `-1` for no limit.
  Duration sendTimeLimit = const Duration(seconds: 10);
}

/// The `server.session.*` properties.
@Introspected()
class ServerSessionSettings {
  /// How long a session lives without a request; a number without a unit
  /// is seconds.
  @DurationUnit(ChronoUnit.seconds)
  Duration timeout = const Duration(minutes: 30);

  /// The most sessions kept at once; `-1` for no limit.
  int maxSessions = 10000;

  /// The session cookie (`cookie.*`).
  ServerSessionCookieSettings cookie = ServerSessionCookieSettings();
}

/// The `server.session.cookie.*` properties.
@Introspected()
class ServerSessionCookieSettings {
  /// The name of the session cookie.
  String name = 'JSESSIONID';

  /// The domain of the session cookie. Default: none, so the cookie goes
  /// back only to the host that set it.
  String? domain;

  /// The path of the session cookie. Default: the context path, or `/`.
  String? path;

  /// Whether the session cookie is hidden from scripts.
  bool httpOnly = true;

  /// Whether the session cookie is sent over HTTPS only. Default: not set:
  /// it is secure when the request was.
  bool? secure;

  /// The `SameSite` attribute of the session cookie; `unset` sends none.
  SessionSameSite sameSite = SessionSameSite.lax;
}

/// The `spring.web.multipart.*` properties: uploads.
///
/// Spring Boot (Java): `MultipartProperties`, plus `max-part-count`.
@ConfigurationProperties('spring.web.multipart')
class MultipartSettings {
  /// `false`: `multipart/*` requests are not parsed, and `@RequestPart`
  /// parameters answer 400.
  bool enabled = true;

  /// The largest file (or other part) of an upload; above it the answer is
  /// 413 (`MaxUploadSizeExceededException`). `-1` for no limit.
  DataSize maxFileSize = DataSize.ofMegabytes(1);

  /// The largest multipart request as a whole; above it the answer is 413.
  /// `-1` for no limit.
  DataSize maxRequestSize = DataSize.ofMegabytes(10);

  /// The most parts (files and fields) of a multipart request; above it the
  /// answer is 413. `-1` for no limit. Spring Boot sets the same limit with
  /// `server.tomcat.max-part-count`.
  int maxPartCount = 50;

  /// Files above this size are written to a temporary file; smaller ones
  /// stay in memory.
  DataSize fileSizeThreshold = const DataSize.ofBytes(0);

  /// Where the private directory (`0700`) of the uploads' temporary files
  /// is made; the files have random names and are deleted when the request
  /// ends or fails. Default: the system's temporary directory.
  String? location;
}

/// The `spring.mvc.*` properties.
///
/// Spring Boot (Java): `WebMvcProperties`.
@ConfigurationProperties('spring.mvc')
class MvcSettings {
  /// Shows the parameters and headers of requests in the logs (credentials
  /// stay `masked`). Off by default, as they may hold secrets.
  bool logRequestDetails = false;

  /// The path pattern the static resources of
  /// `spring.web.resources.static-locations` are served under: `/**`
  /// serves `static/app.css` as `/app.css`, `/assets/**` as
  /// `/assets/app.css`. The welcome page (`index.html` at `/`) is served
  /// only with `/**`, as in Spring Boot.
  String staticPathPattern = '/**';

  /// Asynchronous responses (`async.*`).
  MvcAsyncSettings async = MvcAsyncSettings();

  /// Server-sent events (`sse.*`).
  MvcSseSettings sse = MvcSseSettings();
}

/// The `spring.mvc.async.*` properties.
@Introspected()
class MvcAsyncSettings {
  /// The timeout of an `SseEmitter` created without one; when it passes,
  /// the emitter completes after running its `onTimeout` callbacks.
  /// Default: no limit.
  Duration? requestTimeout;
}

/// The `spring.mvc.sse.*` properties.
@Introspected()
class MvcSseSettings {
  /// Sends a comment line in every open event stream at this interval, so
  /// proxies keep idle streams open. Default: none.
  Duration? heartbeatInterval;
}

/// The `spring.web.resources.*` properties: the static resources (files
/// and a built web app served as they are).
///
/// Spring Boot (Java): `WebProperties.Resources`.
@ConfigurationProperties('spring.web.resources')
class WebResourcesSettings {
  /// Where the static resources are read from, in order (the first
  /// location with the file wins): `resources:` folders of `lib/resources/`
  /// (embedded by the generator) and `file:` directories read at run time
  /// (`file:web/`, `file:/srv/shop/build/web/`). Spring Boot's defaults
  /// with `classpath:` written `resources:`; `META-INF/resources/` and
  /// `resources/` are left out, as Dart has no jars.
  List<String> staticLocations = ['resources:static/', 'resources:public/'];

  /// `false` turns off the default mapping of `static-locations` under
  /// `spring.mvc.static-path-pattern` and the welcome page; mappings a
  /// `WebMvcConfigurer` adds stay.
  bool addMappings = true;

  /// For a single-page app (a `flutter build web` output, a JavaScript
  /// router): a browser's `GET` or `HEAD` of a path that is no file and no
  /// handler, whose last segment has no extension and that asks for
  /// `text/html` by name, gets the `index.html` of `static-locations`
  /// instead of a 404, so deep links work. Not in Spring Boot: this
  /// starter's own key.
  bool spaFallback = false;

  /// A path with no file, whose folder holds an `index.html`, gets that
  /// `index.html`: `/guide` and `/guide/` are answered with
  /// `guide/index.html`, as static hosts (Cloudflare Pages, Netlify)
  /// answer. The pages the build writes for search engines
  /// (`spring.flutter.web.seo.*`) are such files. Asked before
  /// [spaFallback]; the file is found as any other (inside the location,
  /// the same checks). Not in Spring Boot, whose welcome page covers `/`
  /// only: this starter's own key.
  bool directoryIndex = false;

  /// Caching of the static resources (`cache.*`).
  WebResourcesCacheSettings cache = WebResourcesCacheSettings();

  /// The resource chain (`chain.*`).
  WebResourcesChainSettings chain = WebResourcesChainSettings();
}

/// The `spring.web.resources.cache.*` properties.
@Introspected()
class WebResourcesCacheSettings {
  /// How long browsers may keep a static resource (`Cache-Control:
  /// max-age=` and the seconds); `0` sends `no-store`. A number without a
  /// unit is seconds. Default: no `Cache-Control`. The `cachecontrol.*`
  /// keys win over it.
  @DurationUnit(ChronoUnit.seconds)
  Duration? period;

  /// Whether the files' modification time is sent as `Last-Modified` and
  /// checked against `If-Modified-Since` (`304`).
  bool useLastModified = true;

  /// The `Cache-Control` header of the static resources, directive by
  /// directive (`cachecontrol.*`).
  WebResourcesCacheControlSettings cachecontrol =
      WebResourcesCacheControlSettings();
}

/// The `spring.web.resources.cache.cachecontrol.*` properties: the
/// `Cache-Control` header of the static resources. When any of them is
/// set, they replace `spring.web.resources.cache.period`.
@Introspected()
class WebResourcesCacheControlSettings {
  /// `max-age`: how long the answer may be reused without asking the
  /// server. A number without a unit is seconds.
  @DurationUnit(ChronoUnit.seconds)
  Duration? maxAge;

  /// `no-cache`: reused only after the server confirmed it.
  bool? noCache;

  /// `no-store`: never stored. Wins over `no-cache` and `max-age`.
  bool? noStore;

  /// `must-revalidate`: once stale, not used without asking the server.
  bool? mustRevalidate;

  /// `no-transform`: proxies must not change the content.
  bool? noTransform;

  /// `public`: shared caches may store the answer too.
  bool? cachePublic;

  /// `private`: only the user's own cache may store the answer.
  bool? cachePrivate;

  /// `proxy-revalidate`: `must-revalidate` for shared caches only.
  bool? proxyRevalidate;

  /// `stale-while-revalidate`: how long a stale answer may be used while a
  /// fresh one is fetched. A number without a unit is seconds.
  @DurationUnit(ChronoUnit.seconds)
  Duration? staleWhileRevalidate;

  /// `stale-if-error`: how long a stale answer may be used when the server
  /// fails. A number without a unit is seconds.
  @DurationUnit(ChronoUnit.seconds)
  Duration? staleIfError;

  /// `s-maxage`: how long shared caches may keep the answer. A number
  /// without a unit is seconds.
  @DurationUnit(ChronoUnit.seconds)
  Duration? sMaxAge;
}

/// The `spring.web.resources.chain.*` properties.
@Introspected()
class WebResourcesChainSettings {
  /// Serves a precompressed file next to the one asked for
  /// (`app.js.br`, `app.js.gz`) to a client whose `Accept-Encoding`
  /// takes it (Brotli first), with `Content-Encoding` and `Vary:
  /// Accept-Encoding`.
  bool compressed = false;
}

/// The `spring.main.*` properties of the web starter.
@ConfigurationProperties('spring.main')
class WebMainSettings {
  /// `none`: the beans (and `MockMvc`) exist, but no server starts. Any
  /// other value starts the server.
  @PropertyValues(['none'])
  String? webApplicationType;
}

/// The `spring.test.*` properties of the web starter.
@ConfigurationProperties('spring.test')
class WebTestSettings {
  /// Set by `springBootTest(webEnvironment:)` (`mock` by default) and by
  /// `ApplicationContextRunner` (`mock`): `mock` has no server (`MockMvc`
  /// calls the dispatcher in memory), `random-port` a real server on a free
  /// port, `defined-port` one on `server.port`, `none` no server. Default:
  /// not set: a server starts. Another value starts no server either.
  @PropertyValues(['mock', 'random-port', 'defined-port', 'none'])
  String? webEnvironment;
}

/// The `local.server.*` properties, which the server sets.
@ConfigurationProperties('local.server')
class LocalServerSettings {
  /// The port the server listens on, set once it listens (also in
  /// `WebServerInitializedEvent`). Nothing reads it from configuration: it
  /// is put there for the application to read.
  int? port;
}
