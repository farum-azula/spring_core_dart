/// The value of a `Cache-Control` response header, built from its
/// directives.
///
/// Use it to say how long browsers and proxies may keep an answer: the
/// static resources of the web starter take one
/// (`ResourceHandlerRegistration.setCacheControl`), and so can any code
/// that sets the header. Start from one of the factories
/// ([CacheControl.maxAge], [CacheControl.noCache], [CacheControl.noStore],
/// [CacheControl.empty]) and chain the other directives; each call changes
/// this object and returns it. [headerValue] is the text of
/// the header, `null` when no directive is set.
///
/// ```dart
/// // Fingerprinted files (app.3f9a.js) never change: a year, immutable.
/// final forever = CacheControl.maxAge(const Duration(days: 365))
///     .cachePublic()
///     .immutable();
/// forever.headerValue; // max-age=31536000, public, immutable
/// ```
///
/// Spring (Java):
/// ```java
/// CacheControl forever = CacheControl.maxAge(365, TimeUnit.DAYS)
///     .cachePublic()
///     .immutable();
/// ```
final class CacheControl {
  CacheControl._();

  /// No directive yet: [headerValue] is `null` until one is added.
  factory CacheControl.empty() => CacheControl._();

  /// `max-age`: the answer may be reused for [maxAge] (whole seconds)
  /// without asking the server again.
  factory CacheControl.maxAge(Duration maxAge) =>
      CacheControl._().._maxAge = maxAge;

  /// `no-cache`: the answer may be stored, but reused only after the
  /// server confirmed it (a conditional request).
  factory CacheControl.noCache() => CacheControl._().._noCache = true;

  /// `no-store`: the answer must not be stored at all.
  factory CacheControl.noStore() => CacheControl._().._noStore = true;

  Duration? _maxAge;
  var _noCache = false;
  var _noStore = false;
  var _mustRevalidate = false;
  var _noTransform = false;
  var _cachePublic = false;
  var _cachePrivate = false;
  var _proxyRevalidate = false;
  Duration? _sMaxAge;
  Duration? _staleIfError;
  Duration? _staleWhileRevalidate;
  var _immutable = false;

  /// Adds `must-revalidate`: once stale, the answer must not be used
  /// without asking the server. Returns this object.
  CacheControl mustRevalidate() => this.._mustRevalidate = true;

  /// Adds `no-transform`: proxies must not change the content (recompress
  /// images, for one). Returns this object.
  CacheControl noTransform() => this.._noTransform = true;

  /// Adds `public`: any cache, shared ones too, may store the answer.
  /// Returns this object.
  CacheControl cachePublic() => this.._cachePublic = true;

  /// Adds `private`: only the user's own cache may store the answer.
  /// Returns this object.
  CacheControl cachePrivate() => this.._cachePrivate = true;

  /// Adds `proxy-revalidate`: `must-revalidate` for shared caches only.
  /// Returns this object.
  CacheControl proxyRevalidate() => this.._proxyRevalidate = true;

  /// Adds `s-maxage`: how long shared caches may keep the answer (whole
  /// seconds). Returns this object.
  CacheControl sMaxAge(Duration sMaxAge) => this.._sMaxAge = sMaxAge;

  /// Adds `stale-if-error`: how long a stale answer may still be used when
  /// the server fails (whole seconds). Returns this object.
  CacheControl staleIfError(Duration staleIfError) =>
      this.._staleIfError = staleIfError;

  /// Adds `stale-while-revalidate`: how long a stale answer may be used
  /// while a fresh one is fetched in the background (whole seconds).
  /// Returns this object.
  CacheControl staleWhileRevalidate(Duration staleWhileRevalidate) =>
      this.._staleWhileRevalidate = staleWhileRevalidate;

  /// Adds `immutable`: the answer never changes while it is fresh, so a
  /// reload does not ask the server. Returns this object.
  CacheControl immutable() => this.._immutable = true;

  /// The header's text, the directives in Spring's order and separated by
  /// `, ` (`max-age=3600, public`); `null` when there is none.
  String? get headerValue {
    final directives = [
      if (_maxAge case final age?) 'max-age=${age.inSeconds}',
      if (_noCache) 'no-cache',
      if (_noStore) 'no-store',
      if (_mustRevalidate) 'must-revalidate',
      if (_noTransform) 'no-transform',
      if (_cachePublic) 'public',
      if (_cachePrivate) 'private',
      if (_proxyRevalidate) 'proxy-revalidate',
      if (_sMaxAge case final age?) 's-maxage=${age.inSeconds}',
      if (_staleIfError case final age?) 'stale-if-error=${age.inSeconds}',
      if (_staleWhileRevalidate case final age?)
        'stale-while-revalidate=${age.inSeconds}',
      if (_immutable) 'immutable',
    ];
    return directives.isEmpty ? null : directives.join(', ');
  }

  @override
  String toString() => 'CacheControl [${headerValue ?? ''}]';
}
