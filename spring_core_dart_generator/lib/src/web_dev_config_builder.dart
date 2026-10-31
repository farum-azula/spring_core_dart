import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:build/build.dart' hide Resource;
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';

/// Writes the Flutter web dev server's `web_dev_config.yaml` from the
/// `spring.flutter.web.*` properties in `lib/resources/`.
///
/// `flutter run -d chrome` and `-d web-server` serve the app on a random
/// port unless told otherwise, which breaks whatever needs a fixed origin:
/// a server's CORS list, the redirect back after an SSO login. Since
/// Flutter 3.38 the dev server reads `web_dev_config.yaml` in the project
/// directory (command-line flags still win), and nothing else configures
/// it. This builder writes that file from the application's own config.
///
/// It runs for every package that depends on the generator, pure Dart
/// servers too, so it never fails a build, and says nothing, unless the
/// app evidently uses the dev server's file: a config file it can read
/// without loading the config (any `.properties`, `.yml` or `.yaml` file
/// of `lib/resources/`, in any document, for any profile, and a file an
/// import names with a file hint, such as `classpath:dev.conf[.yaml]` or
/// `classpath:web.properties[encoding=iso-8859-1]` (a file that is not
/// UTF-8 is read only that way), its placeholders resolved with their
/// defaults or the files' values)
/// sets a `spring.flutter.web.*` key or `spring.flutter.security.web.mode`.
/// An import whose name has a placeholder only the running app resolves
/// (`classpath:${ENV}.conf[.yaml]`) cannot be followed there, so keys only
/// that file sets do not count. Without such a key, the config is not
/// loaded at all: nothing is written, a file the builder generated before
/// is deleted, and nothing the config holds (an import, a placeholder, a
/// file that does not parse) is the builder's business; the app's own
/// start reports what is wrong. The one
/// exception is a config file that does not parse while a generated
/// `web_dev_config.yaml` exists: it may be the file with the keys, so the
/// config is loaded, and when the app reads that file the build fails and
/// the generated file is kept.
///
/// An app with such a key has its config read as the app reads it in a
/// browser: `application.*`, then `application-web.*` (the `web` platform
/// profile), the files of the profiles `spring.profiles.active` names
/// there and the files `spring.config.import` names (a `classpath:` one
/// from `lib/resources/`), names matched the relaxed way. Environment
/// variables and `--dart-define` values do not count, so a placeholder
/// only they can resolve is unknown at build time: a profile name with one
/// in `spring.profiles.active`, `.include`, `.default` or `.group.*` is
/// left out, whatever else the name holds (`dev,${ENV}-eu` is read as
/// `dev`), in any form the app reads the key in
/// (`spring.profiles.group[my.prod]`, `spring.profiles[active]`),
/// `spring.profiles.validate` or `spring.main.cloud-platform` with
/// one is read as unset, an import location with one is not read (the
/// other entries of its `;` group are), and a document whose
/// `spring.config.activate.on-profile` or `.on-cloud-platform` has one is
/// skipped; each with a warning that names it, never a build error (a
/// default, `${APP_PROFILE:dev}`, is used). Where a key may be is still
/// checked: `spring.profiles.active` in `application-web.yaml` fails the
/// build whatever its value, as it fails the app's start. A placeholder in
/// `spring.flutter.security.web.mode`, as in a `spring.flutter.web.*`
/// value, must resolve at build time. A browser has no file system:
/// a `file:`, `configtree:` or `package:` import (or a plain absolute
/// path), with a wildcard or not, is not read from the build machine's
/// disk but skipped, `optional:` or not; when the properties give a file
/// to write, a warning names the first required one as written (the web
/// version would fail to start with it, as the app's own start reports).
/// An import the build cannot read (`asset:`, `http:`, `https:`, or a
/// `classpath:` file missing from `lib/resources/`, which another package
/// may provide) is skipped silently, even a required one: it may exist at
/// run time.
///
/// ```yaml
/// # lib/resources/application-web.yaml
/// spring:
///   flutter:
///     web:
///       port: 5050
///       proxy:
///         - prefix: /api/
///           target: http://localhost:8080
/// ```
///
/// gives
///
/// ```yaml
/// # web_dev_config.yaml
/// server:
///   port: 5050
///   proxy:
///     - prefix: "/api/"
///       target: "http://localhost:8080"
/// ```
///
/// `spring.flutter.web.content-security-policy` adds the page's Content
/// Security Policy to the dev server's answers (the
/// `Content-Security-Policy` header, or `Content-Security-Policy-Report-Only`
/// with `content-security-policy-report-only=true`), so development runs
/// under the policy production sends. An app whose browser logs in by
/// itself (`spring.flutter.security.web.mode=spa`) gets a ready policy
/// when it sets none ([WebDevServerSettings.spaContentSecurityPolicy]):
/// its scripts and Flutter's only, no `eval`, connections to its own
/// origin, Flutter's CDN, the endpoints its login fetches that are known
/// at build time and the origins of
/// `spring.flutter.web.content-security-policy-connect-src`, no framing.
///
/// The file is not a declared build output: `build_runner` would overwrite
/// a hand-written file of that name, and delete one it once generated when
/// the builder stops writing it. The builder manages it itself, only ever
/// touching a file that starts with [marker]:
///
/// - properties set, no file or a generated one: the file is (re)written;
/// - properties set and a hand-written file: a build error asks to remove
///   one of them, the file is left alone;
/// - no properties and a generated file: the file is deleted;
/// - no properties and a hand-written file: nothing happens;
/// - invalid properties: a build error names the property, the file is
///   left as it is;
/// - a config file the app reads that does not parse, with a property set
///   in another file or a generated file: a build error, the file is left
///   as it is (without either, nothing happens);
/// - a required import a browser cannot read: as if it were not there
///   (above), with a warning when the file is written.
///
/// build_runner re-runs the step when a file of `lib/resources/` changes,
/// not when `web_dev_config.yaml` does (it is no build source): after
/// deleting the file, run `dart run build_runner clean` or touch a config
/// file to have it written again.
///
/// Spring has no equivalent: a Spring Boot web app's dev server is the
/// app itself (`server.port`).
final class WebDevConfigBuilder implements Builder {
  /// Creates the builder; [files] reads and writes `web_dev_config.yaml`
  /// (on disk in the package directory unless given; tests pass one held
  /// in memory).
  WebDevConfigBuilder({WebDevConfigFiles? files})
    : _files = files ?? const _DiskFiles();

  final WebDevConfigFiles _files;

  /// The file the Flutter tool reads: `web_dev_config.yaml` in the project
  /// directory.
  static const fileName = 'web_dev_config.yaml';

  /// The first line of a generated file; a file starting otherwise is
  /// hand-written and never changed or deleted.
  static const marker = '# GENERATED FILE - DO NOT MODIFY BY HAND.';

  /// The comment at the top of a generated file: [marker], then where the
  /// values come from and what to edit instead.
  static const header =
      '$marker\n'
      '#\n'
      '# Written by spring_core_dart_generator from the spring.flutter.web.*\n'
      '# properties in lib/resources/ (application.yaml, application-web.yaml,\n'
      '# ...). Change those properties instead: this file is rewritten on\n'
      '# every build, and deleted when the properties are removed.\n'
      '# The Flutter tool reads it when it runs the web version\n'
      '# (flutter run -d chrome / -d web-server); --web-port and the other\n'
      '# flags still win over it.';

  /// The prefix of the properties read.
  static const prefix = 'spring.flutter.web';

  // No declared outputs (see the class documentation). `build_to: source`
  // makes build_runner run the step on every build whose inputs changed.
  @override
  Map<String, List<String>> get buildExtensions => const {r'$package$': []};

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    // The main builder warns about a file too large to embed; the app
    // does not read it, nor does this builder.
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final texts = {
      for (final MapEntry(:key, value: (:text, base64: _)) in resources.entries)
        key: ?text,
    };
    // Files that are not UTF-8: read only through an import that names
    // their encoding (`classpath:dev.properties[encoding=iso-8859-1]`).
    final binary = {
      for (final MapEntry(:key, value: (:text, :base64)) in resources.entries)
        if (text == null && base64 != null) key: base64Decode(base64),
    };
    final existing = await _files.read(buildStep, package);
    final generated = existing != null && existing.startsWith(marker);
    final WebDevServerSettings? settings;
    try {
      settings = WebDevServerSettings.read(
        texts,
        generated: generated,
        binary: binary,
      );
    } on WebDevConfigException catch (e) {
      log.severe('$e\n$fileName is left as it is.');
      return;
    }
    if (settings == null) {
      if (generated) {
        await _files.delete(buildStep, package);
        log.info('Deleted $fileName: no $prefix.* property is set any more.');
      }
      return;
    }
    if (existing != null && !generated) {
      log.severe(
        '$fileName exists and was not generated, but $prefix.* properties '
        'are set in lib/resources/. Remove one of them: delete $fileName '
        'to have it generated from the properties (then run '
        '`dart run build_runner clean` or change a file in lib/resources/, '
        'as build_runner does not watch $fileName), or remove the '
        '$prefix.* properties to keep the hand-written file. The file is '
        'left as it is.',
      );
      return;
    }
    final content = '$header\n${settings.toYaml()}';
    if (content != existing) {
      await _files.write(buildStep, package, content);
    }
  }
}

/// Reads, writes and deletes the `web_dev_config.yaml` of a package for
/// [WebDevConfigBuilder].
abstract interface class WebDevConfigFiles {
  /// The content of the file of [package], or `null` when there is none.
  Future<String?> read(BuildStep buildStep, String package);

  /// Writes [content] to the file of [package].
  Future<void> write(BuildStep buildStep, String package, String content);

  /// Deletes the file of [package].
  Future<void> delete(BuildStep buildStep, String package);
}

// The file in the package's directory on disk (see [PackageDirectories]:
// the package's own directory, also in a workspace build).
final class _DiskFiles implements WebDevConfigFiles {
  const _DiskFiles();

  static io.File? _file(String package) => PackageDirectories.current.file(
    AssetId(package, WebDevConfigBuilder.fileName),
  );

  @override
  Future<String?> read(BuildStep buildStep, String package) async {
    final file = _file(package);
    return file != null && file.existsSync() ? await file.readAsString() : null;
  }

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String content,
  ) async {
    final file = _file(package);
    if (file == null) {
      log.warning(
        'The directory of package $package is not found in '
        '.dart_tool/package_config.json; ${WebDevConfigBuilder.fileName} '
        'is not written.',
      );
      return;
    }
    await file.writeAsString(content);
  }

  @override
  Future<void> delete(BuildStep buildStep, String package) async {
    final file = _file(package);
    if (file != null && file.existsSync()) {
      await file.delete();
    }
  }
}

/// An invalid `spring.flutter.web.*` property; the message names it.
final class WebDevConfigException implements Exception {
  /// Creates the exception with [message].
  WebDevConfigException(this.message);

  /// What is wrong, starting with the property's name.
  final String message;

  @override
  String toString() => message;
}

/// One `spring.flutter.web.proxy[n]` rule: requests whose path starts with
/// `prefix` or matches `regex` go to `target`, the path rewritten by
/// `replace` when set.
typedef WebDevProxyRule = ({
  String target,
  String? prefix,
  String? regex,
  String? replace,
});

/// The dev server settings of the `spring.flutter.web.*` properties, the
/// content of `web_dev_config.yaml`.
final class WebDevServerSettings {
  WebDevServerSettings._({
    this.host,
    this.port,
    this.baseHref,
    this.certPath,
    this.certKeyPath,
    this.headers = const {},
    this.proxy = const [],
  });

  /// The Content Security Policy of an app whose browser logs in by itself
  /// (`spring.flutter.security.web.mode=spa`) and sets no
  /// `spring.flutter.web.content-security-policy`: what Flutter's web
  /// engine needs and nothing more, plus [connectOrigins] for `fetch`.
  ///
  /// The builder passes as [connectOrigins] the origins the login fetches
  /// from that are known at build time: those of the
  /// `spring.security.oauth2.client.provider.*` URIs (issuer, token, user
  /// info, keys), the built-in endpoints of a registration of a common
  /// provider without its own provider section
  /// ([commonProviderEndpoints], Google's `https://www.googleapis.com`),
  /// the endpoints Google's and Microsoft's discovery documents name on
  /// other origins (`https://oauth2.googleapis.com`,
  /// `https://graph.microsoft.com`), and the origins listed in
  /// `spring.flutter.web.content-security-policy-connect-src`. What
  /// another issuer's discovery document names on another origin is only
  /// known at run time: list it in that property, with the APIs the app
  /// calls.
  ///
  /// - scripts: the app's own and CanvasKit from Flutter's CDN
  ///   (`https://www.gstatic.com`; builds with `--no-web-resources-cdn`
  ///   need only `'self'`), WebAssembly allowed (`'wasm-unsafe-eval'`,
  ///   CanvasKit and Skwasm), no `eval` and no inline scripts;
  /// - styles: `'unsafe-inline'`, as Flutter's engine writes a `<style>`
  ///   element (a nonce would need a server that makes one per answer);
  /// - fonts: the fallback fonts of `https://fonts.gstatic.com`;
  /// - connections: the app's origin, the CDN and font host (the engine
  ///   fetches them) and [connectOrigins];
  /// - workers from the origin and `blob:` (Skwasm); images also from
  ///   `data:` and `blob:`;
  /// - no plugins, `<base>` and forms on the origin only, and no framing
  ///   by other sites (`frame-ancestors 'none'`, clickjacking).
  static String spaContentSecurityPolicy(Iterable<String> connectOrigins) {
    final connect = {
      "'self'",
      'https://www.gstatic.com',
      'https://fonts.gstatic.com',
      ...connectOrigins,
    };
    return [
      "default-src 'self'",
      "script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob:",
      "font-src 'self' https://fonts.gstatic.com",
      'connect-src ${connect.join(' ')}',
      "worker-src 'self' blob:",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
    ].join('; ');
  }

  /// The endpoints the browser fetches for the common providers of
  /// `spring_boot_starter_oauth2_client` (its `CommonOAuth2Provider`), by
  /// provider id, each keyed by its provider property in the relaxed form
  /// (`tokenuri` for `token-uri`).
  ///
  /// A registration named after one (or with `provider=<id>`) uses those
  /// its provider section does not set, and none when the section has an
  /// `issuer-uri` (the endpoints are discovered). Token, keys and user
  /// info only: the authorization endpoint is navigated to, never
  /// fetched. Okta has no fixed address (its issuer is configured). A copy
  /// of the client's table, as the generator does not depend on the
  /// client; a test of the client compares the two.
  static const Map<String, Map<String, String>> commonProviderEndpoints = {
    'google': {
      'tokenuri': 'https://www.googleapis.com/oauth2/v4/token',
      'jwkseturi': 'https://www.googleapis.com/oauth2/v3/certs',
      'userinfouri': 'https://www.googleapis.com/oauth2/v3/userinfo',
    },
    'github': {
      'tokenuri': 'https://github.com/login/oauth/access_token',
      'userinfouri': 'https://api.github.com/user',
    },
    'facebook': {
      'tokenuri': 'https://graph.facebook.com/v2.8/oauth/access_token',
      'userinfouri': 'https://graph.facebook.com/me?fields=id,name,email',
    },
    'okta': <String, String>{},
    'apple': {
      'tokenuri': 'https://appleid.apple.com/auth/token',
      'jwkseturi': 'https://appleid.apple.com/auth/keys',
    },
  };

  /// `spring.flutter.web.host`: the address to listen on (`localhost`,
  /// `0.0.0.0`).
  final String? host;

  /// `spring.flutter.web.port`, from 0 to 65535 (0 picks a free port).
  final int? port;

  /// `spring.flutter.web.base-href`: the path the app is served under,
  /// starting and ending with `/`.
  final String? baseHref;

  /// `spring.flutter.web.https.cert-path`: the TLS certificate (PEM).
  final String? certPath;

  /// `spring.flutter.web.https.cert-key-path`: its private key (PEM).
  final String? certKeyPath;

  /// `spring.flutter.web.headers.<Name>=<value>`: headers added to every
  /// response of the dev server, with the Content Security Policy of
  /// `spring.flutter.web.content-security-policy` (or the spa mode's).
  final Map<String, String> headers;

  /// `spring.flutter.web.proxy[n].*`: requests forwarded to other servers.
  final List<WebDevProxyRule> proxy;

  /// The settings of the config [files] of `lib/resources/` (path below
  /// that directory to content; the files that are not UTF-8 as [binary],
  /// read only through an import that names their encoding, such as
  /// `classpath:dev.properties[encoding=iso-8859-1]`), read for the `web`
  /// profile; `null` when
  /// there is nothing to write: no `spring.flutter.web.*` property is set
  /// and the browser does not log in by itself
  /// (`spring.flutter.security.web.mode=spa`).
  ///
  /// The files are only read as the app reads them when the app evidently
  /// uses the dev server's file: a config file read without loading them
  /// (any `.properties`, `.yml` or `.yaml` file of `lib/resources/`, and a
  /// file an import names with a file hint, `[.yaml]` or
  /// `[encoding=iso-8859-1]`) sets one of those keys.
  /// Otherwise the result is `null`, without a word, whatever the files
  /// hold: the builder runs for every package that depends on the
  /// generator, pure Dart servers too. [generated] tells that the package
  /// has a `web_dev_config.yaml` this builder wrote: then a config file
  /// that does not parse may be the one with the keys, so the files are
  /// read to report it, if the app reads it (and only that).
  ///
  /// A placeholder that only the running app can resolve (an environment
  /// variable, a `--dart-define`) in the keys that decide which files are
  /// read is unknown at build time: the files are read without what has
  /// one (a profile name, a `spring.profiles.validate` or
  /// `spring.main.cloud-platform` value, an import location; a document
  /// whose `spring.config.activate.*` guard has one is skipped), with a
  /// warning.
  ///
  /// Throws [WebDevConfigException] for an invalid value and for a config
  /// file that does not parse or cannot be read.
  static WebDevServerSettings? read(
    Map<String, String> files, {
    bool generated = false,
    Map<String, Uint8List> binary = const {},
  }) {
    final config = _StaticConfig(files, binary);
    if (!config.setsWebKeys && !(generated && config.unparsed.isNotEmpty)) {
      return null;
    }
    final reading = _BrowserReading(files, binary, config);
    final StandardEnvironment environment;
    try {
      environment = reading.read();
    } on WebDevConfigException {
      if (config.setsWebKeys || reading.unparsed) {
        rethrow;
      }
      log.fine(
        'The config files of lib/resources/ set no '
        '${WebDevConfigBuilder.prefix}.* property that can be read without '
        'loading them, and cannot be loaded at build time: '
        '${WebDevConfigBuilder.fileName} is not written.',
      );
      return null;
    }
    if (!config.setsWebKeys) {
      // Read only for the file that does not parse, which the app does
      // not read: nothing to write.
      return null;
    }
    reading.warnings.forEach(log.warning);
    final settings = _Reader(environment).read();
    // Only an app with something to write hears of a required import a
    // browser cannot read.
    final unreadable = reading.unreadable;
    if (settings != null && unreadable != null) {
      log.warning(_notInBrowser(unreadable));
    }
    return settings;
  }

  // The warning for a required location of the file system or of a
  // package ([_BrowserResources]), which the app in a browser never
  // finds: the app's own start reports it there, the dev server's file is
  // right without it. [location] is written as in the config file, so
  // `optional:` before it makes it optional.
  static String _notInBrowser(String location) =>
      "spring.config.import: '$location' is read from the file system (or "
      "a package's files), which an app in a browser does not have: the web "
      'version would fail to start with it. Make the import optional '
      "('optional:$location') to read it on the other platforms only, or "
      'put the properties into a file of lib/resources/ and import that '
      'with classpath:. ${WebDevConfigBuilder.fileName} is written without '
      'it.';

  static String _quoted(String value) => jsonEncode(value);

  /// The content of `web_dev_config.yaml` (without the header).
  String toYaml() {
    final out = StringBuffer('server:\n');
    if (host != null) {
      out.writeln('  host: ${_quoted(host!)}');
    }
    if (port != null) {
      out.writeln('  port: $port');
    }
    if (certPath != null) {
      out
        ..writeln('  https:')
        ..writeln('    cert-path: ${_quoted(certPath!)}')
        ..writeln('    cert-key-path: ${_quoted(certKeyPath!)}');
    }
    if (headers.isNotEmpty) {
      out.writeln('  headers:');
      headers.forEach((name, value) {
        out
          ..writeln('    - name: ${_quoted(name)}')
          ..writeln('      value: ${_quoted(value)}');
      });
    }
    if (proxy.isNotEmpty) {
      out.writeln('  proxy:');
      for (final rule in proxy) {
        final (:target, :prefix, :regex, :replace) = rule;
        out
          ..writeln(
            prefix != null
                ? '    - prefix: ${_quoted(prefix)}'
                : '    - regex: ${_quoted(regex!)}',
          )
          ..writeln('      target: ${_quoted(target)}');
        if (replace != null) {
          out.writeln('      replace: ${_quoted(replace)}');
        }
      }
    }
    if (baseHref != null) {
      out.writeln('  base-href: ${_quoted(baseHref!)}');
    }
    return out.toString();
  }
}

// What a location of the config finds when the app runs in a browser, as
// far as the build knows it:
// - `memory:` (the default locations), `classpath:` and plain paths: the
//   build's own files of lib/resources/, as the app reads its embedded
//   ones, not a lib/resources/ on disk below the working directory
//   (another package's in a workspace build);
// - `file:` and `package:` (also a plain absolute path and a
//   `configtree:` directory, which are read through `file:`, wildcards
//   included): nothing, as a browser has no file system and no package
//   files; an optional one is skipped, a required one is not found
//   (_BrowserReading then loads the files again with every location
//   optional, and a warning names it when there is a file to write);
// - a missing file of lib/resources/ and any other location (`asset:`,
//   `http:`): an empty file, so even a required one is skipped. It may
//   exist at run time only, and the build must not depend on what it
//   cannot read.
final class _BrowserResources implements ProtocolResolver {
  _BrowserResources(Map<String, String> files, this._binary)
    : _resolvers = [
        InMemoryProtocolResolver('memory:', files),
        InMemoryProtocolResolver(ClasspathResources.prefix, files),
      ];

  final List<InMemoryProtocolResolver> _resolvers;

  // The files that are not UTF-8, by path below lib/resources/.
  final Map<String, Uint8List> _binary;

  static final _scheme = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]+:');

  @override
  Resource resolve(String location, ResourceLoader resourceLoader) {
    for (final prefix in ['memory:', ClasspathResources.prefix]) {
      if (location.startsWith(prefix)) {
        // InMemoryProtocolResolver's path cleaning.
        final path = FileSystemResource(
          location.substring(prefix.length),
        ).path.replaceFirst(RegExp('^/'), '');
        if (_binary[path] case final bytes?) {
          return ByteArrayResource(
            bytes,
            description: 'resource [$prefix$path]',
          );
        }
      }
    }
    for (final resolver in _resolvers) {
      if (resolver.resolve(location, resourceLoader) case final resource?) {
        return resource.exists() ? resource : _empty(resource.description);
      }
    }
    if (location.startsWith(ResourceLoader.filePrefix) ||
        location.startsWith(DefaultResourceLoader.packagePrefix)) {
      return DescriptiveResource(
        'resource [$location] (not readable in a browser)',
      );
    }
    if (_scheme.hasMatch(location)) {
      return _empty('resource [$location]');
    }
    return resolve('${ClasspathResources.prefix}$location', resourceLoader);
  }

  static Resource _empty(String description) =>
      ByteArrayResource.fromString('', description: description);

  // Whether a location (a `;` group as written) has an entry of the file
  // system or of a package: what a browser can never read. Any other
  // location that is not found (a `classpath:` directory without config
  // files) may be provided at run time and is skipped silently.
  static bool notInBrowser(String location) {
    for (var entry in location.split(';')) {
      entry = entry.trim();
      if (entry.startsWith(ConfigDataEnvironment.optionalPrefix)) {
        entry = entry.substring(ConfigDataEnvironment.optionalPrefix.length);
      }
      if (entry.startsWith(ResourceLoader.filePrefix) ||
          entry.startsWith(DefaultResourceLoader.packagePrefix) ||
          entry.startsWith(ConfigDataEnvironment.configTreePrefix) ||
          entry.startsWith('/') ||
          entry.startsWith(r'\') ||
          RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(entry)) {
        return true;
      }
    }
    return false;
  }
}

// ` (in lib/resources/application-web.yaml)` for the property source of
// a config file of lib/resources/ (named `Config resource
// 'memory:/application-web.yaml'`, or `'classpath:...'` when imported).
String _sourceOrigin(String sourceName) {
  final match = RegExp(
    "'(?:memory|classpath):/?([^']+)'",
  ).firstMatch(sourceName);
  return match == null ? '' : ' (in lib/resources/${match[1]})';
}

// What the config files of lib/resources/ say without being loaded as the
// app loads them: whether any of them sets a spring.flutter.web.* key or
// spring.flutter.security.web.mode (in any document, for any profile),
// which files do not parse, and every key with its first value (the keys
// a placeholder may find at build time). Every .properties, .yml and
// .yaml file counts, as an import may name any of them, and so does a
// file an import names with file hints (`classpath:dev.conf[.yaml]`,
// `classpath:web.properties[encoding=iso-8859-1]`), read in that format
// and encoding (a file that is not UTF-8 only that way). A placeholder in
// such an import is resolved with its default or a value of the files
// (`classpath:${ENV:dev}.conf[.yaml]`); one only the running app knows
// leaves the import unscanned.
final class _StaticConfig {
  _StaticConfig(this._files, this._binary) {
    final pending = <_Hinted>[
      for (final path in _files.keys.toList()..sort())
        if (_loaderOf(_extension(path)) case final loader?)
          (path, loader, null),
    ];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      while (pending.isNotEmpty) {
        final (path, loader, encoding) = pending.removeAt(0);
        if (seen.add(
          '${loader.fileExtensions.first}:${encoding?.name}:$path',
        )) {
          pending.addAll(_scan(path, loader, encoding));
        }
      }
      // The imports with placeholders, once every file found so far has
      // given its values; a file they find may give more.
      final resolver = valuesResolver(values);
      for (final (importing, location) in _withPlaceholders.toList()) {
        final String resolved;
        try {
          resolved = resolver.resolveRequiredPlaceholders(location);
        } on Exception {
          continue; // unknown at build time, for now
        }
        _withPlaceholders.remove((importing, location));
        if (_hinted(importing, resolved) case final file?) {
          pending.add(file);
        }
      }
    }
  }

  // The hinted imports with a placeholder not resolved yet: the importing
  // file and the location.
  final _withPlaceholders = <(String, String)>{};

  // A resolver of placeholders over [values] (key to value), names
  // relaxed.
  static PropertyResolver valuesResolver(Map<String, Object> values) {
    final source = MapPropertySource('lib/resources', values);
    return PropertySourcesPropertyResolver(
      MutablePropertySources([
        ConfigurationPropertySourcesPropertySource(
          ConfigurationPropertySources.attachedPropertySourceName,
          [source],
        ),
        source,
      ]),
    );
  }

  final Map<String, String> _files;

  // The files that are not UTF-8.
  final Map<String, Uint8List> _binary;

  // Whether a file sets a key the builder writes.
  bool setsWebKeys = false;

  // The files that do not parse.
  final unparsed = <String>[];

  // Every key of every file, with the value of the first file that has
  // it.
  final values = <String, Object>{};

  static const List<PropertySourceLoader> _loaders = [
    PropertiesPropertySourceLoader(),
    YamlPropertySourceLoader(),
  ];

  static final _web = ConfigurationPropertyName.of(WebDevConfigBuilder.prefix);
  static final _spaMode = ConfigurationPropertyName.of(
    'spring.flutter.security.web.mode',
  );
  static final _import = ConfigurationPropertyName.of(
    ConfigDataEnvironment.importProperty,
  );

  static PropertySourceLoader? _loaderOf(String extension) => _loaders
      .where((loader) => loader.fileExtensions.contains(extension))
      .firstOrNull;

  // The loader of an extension hint, matched without case as the config
  // loader does (`[.YAML]`).
  static PropertySourceLoader? _loaderOfHint(String extension) =>
      _loaderOf(extension.toLowerCase());

  static String _extension(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1);
  }

  // The text of the file at [path] as [loader] reads it, decoded with the
  // encoding an import names ([encoding], else UTF-8); `null` when there
  // is no such file, or it does not decode (then it is [unparsed], as the
  // app fails on it).
  String? _text(String path, PropertySourceLoader loader, Encoding? encoding) {
    final text = _files[path];
    if (encoding == null) {
      return text;
    }
    final bytes = _binary[path] ?? (text == null ? null : utf8.encode(text));
    if (bytes == null) {
      return null;
    }
    try {
      return loader.encodingFor(encoding).decode(bytes);
    } on FormatException {
      unparsed.add(path);
      return null;
    }
  }

  // Reads the file at [path] with [loader] (decoded with [encoding] when
  // an import names one); returns the files its imports name with a file
  // hint.
  List<_Hinted> _scan(
    String path,
    PropertySourceLoader loader,
    Encoding? encoding,
  ) {
    final text = _text(path, loader, encoding);
    if (text == null) {
      return const [];
    }
    final List<AbstractPropertySource<Object>> sources;
    try {
      sources = loader.load(path, text);
    } on FormatException {
      unparsed.add(path);
      return const [];
    }
    final hinted = <_Hinted>[];
    for (final source in sources) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      final imports = <String>[];
      for (final MapEntry(key: name, value: keys)
          in ConfigurationPropertySources.propertyNames(source).entries) {
        if (_web.isAncestorOf(name) || name == _spaMode) {
          setsWebKeys = true;
        }
        for (final key in keys) {
          if (source.getProperty(key) case final value?) {
            values.putIfAbsent(key, () => value);
            if (name == _import ||
                name.isNumericIndex(name.numberOfElements - 1) &&
                    name.parent == _import) {
              imports.add('$value');
            }
          }
        }
      }
      for (final value in imports) {
        for (final location in value.split(RegExp('[,;]'))) {
          if (location.contains(r'${')) {
            _withPlaceholders.add((path, location));
          } else if (_hinted(path, location) case final file?) {
            hinted.add(file);
          }
        }
      }
    }
    return hinted;
  }

  // The file of lib/resources/ that the import [location] of the file at
  // [importing] names with a file hint (relative, or `classpath:`), as the
  // app reads its file hints (ConfigDataEnvironment.fileHints, on the
  // location joined to the importing file's directory, so brackets in that
  // directory's path are taken out too): with the loader of the extension
  // hint or of the file's extension, and the encoding of an encoding hint;
  // `null` for any other location (its placeholders already resolved),
  // and for a charset the app cannot read (its start reports that).
  static _Hinted? _hinted(String importing, String location) {
    var value = location.trim();
    if (value.startsWith(ConfigDataEnvironment.optionalPrefix)) {
      value = value.substring(ConfigDataEnvironment.optionalPrefix.length);
    }
    if (!value.contains('[') || value.endsWith('/')) {
      return null; // no hint: every config file is read anyway
    }
    final relative =
        !value.startsWith(ClasspathResources.prefix) &&
        !RegExp('^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(value) &&
        !value.startsWith('/') &&
        !value.startsWith(r'\');
    if (!relative && !value.startsWith(ClasspathResources.prefix)) {
      return null;
    }
    final ({String path, String? extension, Encoding? encoding}) hints;
    try {
      hints = ConfigDataEnvironment.fileHints(
        relative
            ? '${importing.substring(0, importing.lastIndexOf('/') + 1)}$value'
            : value,
      );
    } on ConfigDataLoadException {
      return null;
    }
    var file = hints.path;
    final PropertySourceLoader? loader;
    if (hints.extension case final extension?) {
      loader = _loaderOfHint(extension);
    } else {
      // The loader's spelling names the file, as for the app (`x.YAML`
      // reads `x.yaml`).
      final extension = _extension(file);
      loader = _loaderOfHint(extension);
      if (loader != null) {
        final spelling = extension.toLowerCase();
        file = '${file.substring(0, file.length - extension.length)}$spelling';
      }
    }
    if (loader == null) {
      return null;
    }
    if (!relative) {
      file = file.substring(ClasspathResources.prefix.length);
    }
    return switch (ClasspathResources.normalize(file)) {
      final path? when !path.endsWith('/') => (path, loader, hints.encoding),
      _ => null,
    };
  }
}

// A config file to scan: its path below lib/resources/, its loader, the
// encoding an import names.
typedef _Hinted = (String, PropertySourceLoader, Encoding?);

// One reading of the config files as the app in a browser reads them: the
// `web` profile, no environment variables (the build must not depend on
// them), [_BrowserResources] deciding what each location finds, and
// [_BuildTimeLoader] taking out of each document the placeholders only the
// running app can resolve.
final class _BrowserReading {
  _BrowserReading(this._files, this._binary, this._config);

  final Map<String, String> _files;
  final Map<String, Uint8List> _binary;
  final _StaticConfig _config;

  // Placeholders some config file sets, but only in a document that is not
  // read: unknown at build time as well (found when a read fails on
  // them).
  final _unresolvable = <String>{};

  // The resolver of placeholders over every key of every config file,
  // without [_unresolvable].
  late PropertyResolver _known;

  /// Whether a config file that the app reads does not parse.
  bool unparsed = false;

  /// The first required location a browser cannot read
  /// ([_BrowserResources.notInBrowser]), skipped as if optional.
  String? unreadable;

  /// The warnings about placeholders unknown at build time.
  final warnings = <String>{};

  static const _ignoreNotFoundSource = 'webDevConfigIgnoreNotFound';

  /// The environment the config files are read into; throws
  /// [WebDevConfigException] when they cannot be.
  StandardEnvironment read() {
    var ignoreNotFound = false;
    while (true) {
      unparsed = false;
      warnings.clear();
      _known = _resolverWithout(_unresolvable);
      try {
        return _load(ignoreNotFound: ignoreNotFound);
      } on PlaceholderResolutionException catch (e) {
        if (!_unresolvable.add(e.placeholder)) {
          throw _cannotRead(e);
        }
      } on ConfigDataResourceNotFoundException catch (e) {
        if (!_retryWithout(e.location)) {
          ignoreNotFound = _notFound(e, e.location, ignoreNotFound);
        }
      } on ConfigDataLocationNotFoundException catch (e) {
        if (!_retryWithout(e.location)) {
          ignoreNotFound = _notFound(e, e.location, ignoreNotFound);
        }
      } on ConfigDataLoadException catch (e) {
        if (!_retryWithout(e.location)) {
          throw _cannotRead(e);
        }
      } on Exception catch (e) {
        throw _cannotRead(e);
      } on StateError catch (e) {
        // An invalid profile name (Boot's IllegalStateException).
        throw _cannotRead(e);
      } on ArgumentError catch (e) {
        // A malformed profile expression in an on-profile guard
        // (`a & | b`, Boot's IllegalArgumentException), a profile name the
        // environment refuses (`!x` with spring.profiles.validate=false).
        throw _cannotRead(e);
      }
    }
  }

  // A required location that is not found: the app in a browser does not
  // find it either, so every location is read as optional from now on.
  bool _notFound(Object e, String location, bool ignoreNotFound) {
    if (ignoreNotFound) {
      throw _cannotRead(e);
    }
    if (_BrowserResources.notInBrowser(location)) {
      unreadable = location;
    }
    return true;
  }

  static WebDevConfigException _cannotRead(Object e) => WebDevConfigException(
    'The config files of lib/resources/ cannot be read for the '
    '${WebDevConfigBuilder.prefix}.* properties: $e',
  );

  // A location with a placeholder that was not resolved (lenient, as an
  // import's is): its placeholders are unknown at build time; whether
  // that is news, so reading again changes something.
  bool _retryWithout(String location) {
    var added = false;
    for (final (start, end) in _placeholders(location)) {
      final name = _key(location.substring(start + 2, end - 1));
      if (name != null && _unresolvable.add(name)) {
        added = true;
      }
    }
    return added;
  }

  // The config files loaded into a new environment. A required location
  // that is not found throws, unless [ignoreNotFound] makes every
  // location optional (`spring.config.on-not-found=ignore`, a source
  // removed again afterwards).
  StandardEnvironment _load({required bool ignoreNotFound}) {
    final environment = StandardEnvironment(systemEnvironment: const {});
    if (ignoreNotFound) {
      environment.propertySources.addFirst(
        const MapPropertySource(_ignoreNotFoundSource, {
          ConfigDataEnvironment.onNotFoundProperty: 'ignore',
        }),
      );
    }
    ConfigDataEnvironment(
      environment,
      resourceLoader: DefaultResourceLoader(
        protocolResolvers: [_BrowserResources(_files, _binary)],
      ),
      loaders: [
        for (final loader in _StaticConfig._loaders)
          _BuildTimeLoader(loader, this),
      ],
      defaultLocations: const ['optional:memory:/;optional:memory:/config/'],
      additionalProfiles: const ['web'],
    ).processAndApplySync();
    environment.propertySources.remove(_ignoreNotFoundSource);
    ConfigurationPropertySources.attach(environment);
    return environment;
  }

  PropertyResolver _resolverWithout(Set<String> names) {
    final hidden = {
      for (final name in names) ?ConfigurationPropertyName.ofIfValid(name),
    };
    return _StaticConfig.valuesResolver({
      for (final MapEntry(:key, :value) in _config.values.entries)
        if (!hidden.contains(ConfigurationPropertyName.adapt(key, '.')) &&
            !names.contains(key))
          key: value,
    });
  }

  // The keys that decide which files and documents are read, as found in
  // a document: what an unknown placeholder in each makes of it.
  static final _groups = ConfigurationPropertyName.of('spring.profiles.group');
  static final Map<ConfigurationPropertyName, _Decisive> _decisive = {
    for (final name in [
      StandardEnvironment.activeProfilesPropertyName,
      StandardEnvironment.defaultProfilesPropertyName,
      ConfigDataEnvironment.includeProfilesProperty,
    ])
      ConfigurationPropertyName.of(name): _Decisive.profiles,
    for (final name in [
      ConfigDataEnvironment.validateProfilesProperty,
      CloudPlatform.propertyName,
    ])
      ConfigurationPropertyName.of(name): _Decisive.value,
    ConfigurationPropertyName.of(ConfigDataEnvironment.importProperty):
        _Decisive.import,
    ConfigurationPropertyName.of(ConfigDataEnvironment.onProfileProperty):
        _Decisive.guard,
    ConfigurationPropertyName.of(ConfigDataEnvironment.onCloudPlatformProperty):
        _Decisive.guard,
  };

  // What [name] decides, in any form the app reads it in: a group's name
  // dotted or in brackets (`spring.profiles.group.prod`,
  // `spring.profiles.group[my.prod]`), any element in brackets
  // (`spring.profiles[active]` is `spring.profiles.active`, as in Boot),
  // a list item by its index (`spring.profiles.active[0]`).
  static _Decisive? _decisiveOf(ConfigurationPropertyName name) {
    if (name.isEmpty) {
      return null;
    }
    if (_groups.isAncestorOf(name)) {
      return _Decisive.profiles;
    }
    return _decisive[_isListItem(name) ? name.parent : name];
  }

  // Whether the last element of [name] is a list index (`[0]`), not a map
  // key in brackets (`[prod]`).
  static bool _isListItem(ConfigurationPropertyName name) =>
      name.isNumericIndex(name.numberOfElements - 1);

  /// [source], a document as loaded, as far as the build can know it: the
  /// keys that decide which files and documents are read (profiles, cloud
  /// platform, imports) without what has a placeholder only the running
  /// app can resolve, an import with one left out; a document that never
  /// applies (skipped) when its `spring.config.activate.*` guard has one.
  /// Each is warned about.
  ///
  /// A key left without a value stays in the document, and a skipped
  /// document stays loaded, so the checks of where a key may be (a profile
  /// file or an on-profile document may not set the profiles) still see
  /// it, whatever its value.
  AbstractPropertySource<Object> atBuildTime(
    AbstractPropertySource<Object> source,
  ) {
    if (source is! EnumerablePropertySource<Object>) {
      return source;
    }
    Map<String, Object?>? changed;
    for (final MapEntry(key: name, value: keys)
        in ConfigurationPropertySources.propertyNames(source).entries) {
      final decisive = _decisiveOf(name);
      if (decisive == null) {
        continue;
      }
      for (final key in keys) {
        final value = source.getProperty(key);
        if (value is! String || !value.contains(r'${')) {
          continue;
        }
        final unknown = _unknown(value);
        if (unknown.isEmpty) {
          continue;
        }
        // What is left of the value, and what is left out.
        final (String kept, List<String> dropped) = switch (decisive) {
          _Decisive.guard => ('', const []),
          _Decisive.import => _withoutImports(value),
          _Decisive.profiles => _withoutProfiles(value),
          _Decisive.value => ('', [value]),
        };
        warnings.add(
          _warning(key, source.name, value, unknown, decisive, dropped, kept),
        );
        if (decisive == _Decisive.guard) {
          return _neverActive(source);
        }
        // A list item keeps its place (an empty one), so the items after
        // it are still read.
        (changed ??= {})[key] = kept.isEmpty && !_isListItem(name)
            ? null
            : kept;
      }
    }
    return changed == null ? source : _BuildTimeSource(source, changed);
  }

  // [source], whose guard has a placeholder unknown at build time, as a
  // document that never applies: its guards replaced by an on-profile
  // expression no profiles match. Not dropped, so the checks the app makes
  // of every document still see its keys (the legacy `spring.profiles`;
  // `spring.profiles.active` in any document of a profile file).
  static AbstractPropertySource<Object> _neverActive(
    EnumerablePropertySource<Object> source,
  ) {
    final changed = <String, Object?>{
      for (final MapEntry(key: name, value: keys)
          in ConfigurationPropertySources.propertyNames(source).entries)
        if (_decisiveOf(name) == _Decisive.guard)
          for (final key in keys) key: null,
    };
    changed[ConfigDataEnvironment.onProfileProperty] = 'web & !web';
    return _BuildTimeSource(source, changed);
  }

  // The names of the placeholders of [text] (outside nested ones) that do
  // not resolve at build time: each the innermost name that fails.
  List<String> _unknown(String text) => [
    for (final (start, end) in _placeholders(text))
      ?_failing(text.substring(start, end)),
  ];

  String? _failing(String placeholder) {
    try {
      _known.resolveRequiredPlaceholders(placeholder);
      return null;
    } on PlaceholderResolutionException catch (e) {
      return e.placeholder;
    }
  }

  // A comma list of profiles without the names that have a placeholder
  // that does not resolve at build time, whatever else the name holds
  // (`dev,${ENV}-eu` is `dev`); with the names left out.
  (String, List<String>) _withoutProfiles(String value) {
    final kept = <String>[];
    final dropped = <String>[];
    for (final item in _topLevelSplit(value, ',')) {
      if (_unknown(item).isEmpty) {
        kept.add(item);
      } else {
        dropped.add(item.trim());
      }
    }
    return (kept.join(','), dropped);
  }

  // An import value without the locations that have a placeholder that
  // does not resolve at build time (a `;` group keeps its `optional:`);
  // with the locations left out, as written.
  (String, List<String>) _withoutImports(String value) {
    final dropped = <String>[];
    final kept = [
      for (final item in _topLevelSplit(value, ','))
        if (_withoutUnknownEntries(item, dropped) case final group
            when group.isNotEmpty)
          group,
    ];
    return (kept.join(','), dropped);
  }

  String _withoutUnknownEntries(String group, List<String> dropped) {
    final entries = _topLevelSplit(group, ';');
    final optional = entries.first.trim().startsWith(
      ConfigDataEnvironment.optionalPrefix,
    );
    final kept = <String>[];
    for (final entry in entries) {
      if (_unknown(entry).isEmpty) {
        kept.add(entry.trim());
      } else {
        dropped.add(entry.trim());
      }
    }
    if (kept.isEmpty) {
      return '';
    }
    if (optional &&
        !kept.first.startsWith(ConfigDataEnvironment.optionalPrefix)) {
      kept[0] = '${ConfigDataEnvironment.optionalPrefix}${kept.first}';
    }
    return kept.join(';');
  }

  // [text] split at [separator] outside `${...}` placeholders, so a
  // default with a comma (`${A:a,b}`) stays in one part.
  static List<String> _topLevelSplit(String text, String separator) {
    final spans = _placeholders(text);
    final parts = <String>[];
    var last = 0;
    var span = 0;
    for (
      var i = text.indexOf(separator);
      i != -1;
      i = text.indexOf(separator, i + separator.length)
    ) {
      while (span < spans.length && spans[span].$2 <= i) {
        span++;
      }
      if (span < spans.length && spans[span].$1 <= i) {
        continue; // inside a placeholder
      }
      parts.add(text.substring(last, i));
      last = i + separator.length;
    }
    return parts..add(text.substring(last));
  }

  static String _warning(
    String key,
    String sourceName,
    String value,
    List<String> unknown,
    _Decisive decisive,
    List<String> dropped,
    String kept,
  ) {
    final names = unknown.toSet().map((name) => '\${$name}').join(', ');
    final quoted = dropped.map((item) => "'$item'").join(', ');
    final consequence = switch (decisive) {
      _Decisive.guard => 'the document is skipped',
      _Decisive.import when kept.isEmpty =>
        dropped.length == 1
            ? 'the import is not read'
            : 'the imports $quoted are not read',
      _Decisive.import =>
        dropped.length == 1
            ? '$quoted is not read (the rest of the value is)'
            : '$quoted are not read (the rest of the value is)',
      _Decisive.profiles =>
        dropped.length == 1
            ? 'the profile $quoted is left out'
            : 'the profiles $quoted are left out',
      _Decisive.value => 'it is read as if it were not set',
    };
    final origin = _sourceOrigin(sourceName);
    return "$key$origin: '$value' cannot be resolved at build time: only the "
        'running app knows $names (an environment variable or a '
        '--dart-define, which ${WebDevConfigBuilder.fileName} cannot depend '
        'on), so $consequence. Give it a default in the config files '
        "('\${${unknown.first}:...}') to have "
        '${WebDevConfigBuilder.fileName} use that.';
  }

  // The `${...}` placeholders of [text] outside nested ones, as (start,
  // end) offsets; an unclosed one ends the search. An escaped one
  // (`\${X}`, the literal text `${X}`) is none.
  static List<(int, int)> _placeholders(String text) {
    final spans = <(int, int)>[];
    var index = text.indexOf(r'${');
    while (index != -1) {
      if (index > 0 && text[index - 1] == r'\') {
        index = text.indexOf(r'${', index + 2);
        continue;
      }
      var depth = 0;
      var end = -1;
      for (var i = index; i < text.length; i++) {
        if (text.startsWith(r'${', i)) {
          depth++;
          i++;
        } else if (text[i] == '}' && --depth == 0) {
          end = i + 1;
          break;
        }
      }
      if (end == -1) {
        break;
      }
      spans.add((index, end));
      index = text.indexOf(r'${', end);
    }
    return spans;
  }

  // The key of a placeholder's content (before its default), `null` when
  // it is itself made of placeholders.
  static String? _key(String content) {
    final colon = content.indexOf(':');
    final key = (colon == -1 ? content : content.substring(0, colon)).trim();
    return key.isEmpty || key.contains(r'${') ? null : key;
  }
}

// What an unknown placeholder in a key that decides what is read makes of
// it ([_BrowserReading.atBuildTime]).
enum _Decisive {
  // spring.profiles.active, .default, .include, .group.*: each profile
  // name with one is left out (the property without a value when none is
  // left).
  profiles,
  // spring.profiles.validate, spring.main.cloud-platform: the property is
  // read without a value.
  value,
  // spring.config.import: the location is not read.
  import,
  // spring.config.activate.*: the document is skipped.
  guard,
}

// A document with some of its keys changed ([_BrowserReading.atBuildTime]):
// a `null` value leaves the key without a value but still in the document
// (in its names, `containsProperty` true), as a map entry with a `null`
// value is in Spring's MapPropertySource.
final class _BuildTimeSource extends EnumerablePropertySource<Object> {
  _BuildTimeSource(this._source, this._changed)
    : super(_source.name, _source.source);

  final EnumerablePropertySource<Object> _source;
  final Map<String, Object?> _changed;

  @override
  Object? getProperty(String name) =>
      _changed.containsKey(name) ? _changed[name] : _source.getProperty(name);

  @override
  bool containsProperty(String name) => _source.containsProperty(name);

  @override
  List<String> get propertyNames => _source.propertyNames;
}

// A config file format, read for the dev server's file: [_delegate]'s
// documents as far as the build can know them
// ([_BrowserReading.atBuildTime]); a file that does not parse is noted.
final class _BuildTimeLoader extends PropertySourceLoader {
  _BuildTimeLoader(this._delegate, this._reading);

  final PropertySourceLoader _delegate;
  final _BrowserReading _reading;

  @override
  List<String> get fileExtensions => _delegate.fileExtensions;

  @override
  Encoding get encoding => _delegate.encoding;

  @override
  Encoding encodingFor(Encoding hint) => _delegate.encodingFor(hint);

  @override
  List<AbstractPropertySource<Object>> load(String name, String content) {
    final List<AbstractPropertySource<Object>> sources;
    try {
      sources = _delegate.load(name, content);
    } on FormatException {
      _reading.unparsed = true;
      rethrow;
    }
    return [for (final source in sources) _reading.atBuildTime(source)];
  }
}

// Reads the settings from an environment the config files were loaded
// into, sources in precedence order.
final class _Reader {
  _Reader(this._environment);

  final StandardEnvironment _environment;

  static final _web = ConfigurationPropertyName.of(WebDevConfigBuilder.prefix);

  static const _proxyFields = {'target', 'prefix', 'regex', 'replace'};

  // Each config source with its property names below spring.flutter.web.
  late final List<
    (EnumerablePropertySource<Object>, Map<ConfigurationPropertyName, String>)
  >
  _sources = [
    for (final source in _environment.propertySources)
      if (source is EnumerablePropertySource<Object> &&
          source is! ConfigurationPropertySourcesPropertySource)
        (
          source,
          {
            for (final MapEntry(key: name, value: keys)
                in ConfigurationPropertySources.propertyNames(source).entries)
              if (_web.isAncestorOf(name) && keys.isNotEmpty) name: keys.first,
          },
        ),
  ];

  WebDevServerSettings? read() {
    final spa = _spaMode();
    if (!spa && _sources.every((source) => source.$2.isEmpty)) {
      return null;
    }
    _warnUnknown();
    final certPath = _string('https.cert-path');
    final certKeyPath = _string('https.cert-key-path');
    if ((certPath == null) != (certKeyPath == null)) {
      final missing = certPath == null ? 'cert-path' : 'cert-key-path';
      throw WebDevConfigException(
        '${WebDevConfigBuilder.prefix}.https.$missing is not set: HTTPS '
        'needs both https.cert-path and https.cert-key-path.',
      );
    }
    final settings = WebDevServerSettings._(
      host: _host(),
      port: _port(),
      baseHref: _baseHref(),
      certPath: certPath,
      certKeyPath: certKeyPath,
      headers: _withContentSecurityPolicy(_headers(), spa: spa),
      proxy: _proxy(),
    );
    if (settings.host == null &&
        settings.port == null &&
        settings.baseHref == null &&
        certPath == null &&
        settings.headers.isEmpty &&
        settings.proxy.isEmpty) {
      return null;
    }
    return settings;
  }

  // The value of [name] (below spring.flutter.web), placeholders resolved,
  // trimmed; `null` when not set.
  String? _string(String name) {
    final full = ConfigurationPropertyName.of(
      '${WebDevConfigBuilder.prefix}.$name',
    );
    for (final (source, _) in _sources) {
      final value = ConfigurationPropertySources.getProperty(source, full);
      if (value != null) {
        return _resolve(full.toString(), value, source);
      }
    }
    return null;
  }

  String _resolve(
    String name,
    Object value,
    AbstractPropertySource<Object> source,
  ) {
    try {
      return _environment.resolveRequiredPlaceholders('$value').trim();
    } on Exception catch (e) {
      throw WebDevConfigException(
        "$name${_origin(source)}: '$value' cannot be resolved at build "
        'time ($e). The dev server is configured when the app is built, '
        'so only config files count, not --dart-define or environment '
        'variables.',
      );
    }
  }

  // ` (in lib/resources/application-web.yaml)` for a config file source.
  static String _origin(AbstractPropertySource<Object> source) =>
      _sourceOrigin(source.name);

  String? _host() {
    final host = _string('host');
    if (host != null && host.isEmpty) {
      throw WebDevConfigException(
        '${WebDevConfigBuilder.prefix}.host is empty: give the address to '
        'listen on, such as localhost or 0.0.0.0.',
      );
    }
    return host;
  }

  int? _port() {
    final text = _string('port');
    if (text == null) {
      return null;
    }
    final port = int.tryParse(text);
    if (port == null || port < 0 || port > 65535) {
      throw WebDevConfigException(
        "${WebDevConfigBuilder.prefix}.port: '$text' is not a port; use an "
        'integer from 0 to 65535 (0 picks a free port).',
      );
    }
    return port;
  }

  String? _baseHref() {
    final baseHref = _string('base-href');
    if (baseHref != null &&
        !(baseHref.startsWith('/') && baseHref.endsWith('/'))) {
      throw WebDevConfigException(
        "${WebDevConfigBuilder.prefix}.base-href: '$baseHref' must start "
        "and end with '/', such as /app/.",
      );
    }
    return baseHref;
  }

  // Map entries merge across sources, the first source winning per name
  // (header names compared without case, as HTTP does).
  Map<String, String> _headers() {
    final headers = <String, String>{};
    final seen = <String>{};
    for (final (source, names) in _sources) {
      for (final MapEntry(key: name, value: key) in names.entries) {
        if (_field(name) != 'headers' || name.numberOfElements != 5) {
          continue;
        }
        final header = name.getElement(4);
        if (seen.add(header.toLowerCase())) {
          final value = source.getProperty(key);
          if (value != null) {
            headers[header] = _resolve(key, value, source);
          }
        }
      }
    }
    return headers;
  }

  // Whether the browser logs in by itself:
  // spring.flutter.security.web.mode=spa. A placeholder in it is resolved
  // at build time, as in the spring.flutter.web.* values: one only the
  // running app can resolve fails the build.
  bool _spaMode() {
    const property = 'spring.flutter.security.web.mode';
    final name = ConfigurationPropertyName.of(property);
    for (final (source, _) in _sources) {
      if (ConfigurationPropertySources.getProperty(source, name)
          case final value?) {
        return _resolve(property, value, source).toLowerCase() == 'spa';
      }
    }
    return false;
  }

  // [headers] with the Content Security Policy: the property's, else the
  // spa mode's default; a policy in headers.<Name> as well is an error.
  Map<String, String> _withContentSecurityPolicy(
    Map<String, String> headers, {
    required bool spa,
  }) {
    const enforced = 'Content-Security-Policy';
    const reportOnly = 'Content-Security-Policy-Report-Only';
    final policy = _string('content-security-policy');
    final reportOnlyText = _string('content-security-policy-report-only');
    final reportOnlyValue = switch (reportOnlyText?.toLowerCase()) {
      null || 'false' => false,
      'true' => true,
      _ => throw WebDevConfigException(
        '${WebDevConfigBuilder.prefix}.content-security-policy-report-only: '
        "'$reportOnlyText' is not true or false.",
      ),
    };
    final existing = headers.keys.where(
      (name) =>
          name.toLowerCase() == enforced.toLowerCase() ||
          name.toLowerCase() == reportOnly.toLowerCase(),
    );
    if (policy != null && existing.isNotEmpty) {
      throw WebDevConfigException(
        '${WebDevConfigBuilder.prefix}.content-security-policy and '
        '${WebDevConfigBuilder.prefix}.headers.${existing.first} are both '
        'set: keep one of them.',
      );
    }
    if (policy != null && policy.isEmpty) {
      throw WebDevConfigException(
        '${WebDevConfigBuilder.prefix}.content-security-policy is empty: '
        "give the policy, such as default-src 'self'.",
      );
    }
    final connectSrc = _connectSrc();
    if (connectSrc != null && (policy != null || existing.isNotEmpty)) {
      final own = policy != null
          ? 'content-security-policy'
          : 'headers.${existing.first}';
      throw WebDevConfigException(
        '${WebDevConfigBuilder.prefix}.content-security-policy-connect-src '
        'adds origins to the ready policy of spa mode, but the app sets its '
        'own (${WebDevConfigBuilder.prefix}.$own): put the origins into that '
        "policy's connect-src and remove the property.",
      );
    }
    if (connectSrc != null && !spa) {
      log.warning(
        '${WebDevConfigBuilder.prefix}.content-security-policy-connect-src '
        'is ignored: it adds origins to the ready policy of spa mode '
        '(spring.flutter.security.web.mode=spa) only.',
      );
    }
    final value =
        policy ??
        (spa && existing.isEmpty
            ? WebDevServerSettings.spaContentSecurityPolicy({
                ..._providerOrigins(),
                ...?connectSrc,
              })
            : null);
    if (value == null) {
      return headers;
    }
    return {...headers, reportOnlyValue ? reportOnly : enforced: value};
  }

  // spring.flutter.web.content-security-policy-connect-src: a list (YAML,
  // or comma-separated) from the first source that has it, as Spring Boot
  // binds lists; `null` when not set.
  List<String>? _connectSrc() {
    const field = 'contentsecuritypolicyconnectsrc';
    const property =
        '${WebDevConfigBuilder.prefix}.content-security-policy-connect-src';
    for (final (source, names) in _sources) {
      final values = <int, String>{};
      for (final MapEntry(key: name, value: key) in names.entries) {
        if (_field(name) != field) {
          continue;
        }
        final value = source.getProperty(key);
        if (value == null) {
          continue;
        }
        final text = _resolve(key, value, source);
        if (name.numberOfElements == 4) {
          final parts = text.split(',');
          for (var i = 0; i < parts.length; i++) {
            values[i] = parts[i].trim();
          }
        } else if (name.numberOfElements == 5 && name.isNumericIndex(4)) {
          values[int.parse(name.getElement(4))] = text;
        }
      }
      if (values.isEmpty) {
        continue;
      }
      final origins = [
        for (final i in values.keys.toList()..sort())
          if (values[i]!.isNotEmpty) values[i]!,
      ];
      for (final origin in origins) {
        if (!_sourceExpression.hasMatch(origin)) {
          throw WebDevConfigException(
            "$property${_origin(source)}: '$origin' is not an origin to "
            'connect to, such as https://api.example.com or '
            'wss://api.example.com.',
          );
        }
      }
      return origins;
    }
    return null;
  }

  // A host source of a Content Security Policy with its scheme
  // (`https://api.example.com`, `https://*.example.com:8443/v1/`), nothing
  // that could end the directive or add another.
  static final _sourceExpression = RegExp(
    r"^[a-zA-Z][a-zA-Z0-9+.-]*://[^\s;,'\x22]+$",
  );

  // The origins the browser fetches for the OAuth2 client's
  // registrations, sorted: those of every
  // spring.security.oauth2.client.provider.<id> URI it reads (issuer, token,
  // user info, keys), the built-in endpoints of a registration of a common
  // provider (Google, GitHub, Facebook, Apple) that its provider section
  // does not replace, and the endpoints the discovery documents of
  // well-known issuers name on other origins. The authorization endpoint
  // is navigated to, never fetched.
  Set<String> _providerOrigins() {
    final properties = _oauth2ClientProperties();
    final origins = <String>{};
    void add(String? value) {
      final uri = value == null ? null : Uri.tryParse(value.trim());
      if (uri != null &&
          (uri.isScheme('http') || uri.isScheme('https')) &&
          uri.host.isNotEmpty) {
        origins.add(uri.origin);
      }
    }

    // provider id → its URIs (`issueruri`, `tokenuri`, ...).
    final providers = <String, Map<String, String>>{};
    // registration id → its `provider`, or `null`.
    final registrations = <String, String?>{};
    for (final MapEntry(key: name, :value) in properties.entries) {
      if (_providerUri.firstMatch(name) case final match?) {
        (providers[match[1]!] ??= {})[match[2]!] = value;
        add(value);
      } else if (_registrationProperty.firstMatch(name) case final match?) {
        registrations.putIfAbsent(match[1]!, () => null);
        if (match[2] == 'provider') {
          registrations[match[1]!] = value;
        }
      }
    }
    for (final MapEntry(key: id, value: providerId) in registrations.entries) {
      final provider = _relaxed(providerId ?? id);
      final own = providers[provider] ?? const {};
      if (own.containsKey('issueruri')) {
        continue; // discovered: below
      }
      final common =
          WebDevServerSettings.commonProviderEndpoints[provider] ?? const {};
      for (final MapEntry(key: uri, :value) in common.entries) {
        if (!own.containsKey(uri)) {
          add(value);
        }
      }
    }
    for (final provider in providers.values) {
      final issuer = Uri.tryParse(provider['issueruri']?.trim() ?? '');
      if (issuer != null &&
          issuer.isScheme('https') &&
          issuer.host.isNotEmpty) {
        origins.addAll(_discoveredOrigins[issuer.origin] ?? const []);
      }
    }
    return {...origins.toList()..sort()};
  }

  // The spring.security.oauth2.client.* properties of the config files,
  // their names in the relaxed form (lower case, no `-` or `_`), the
  // values resolved; the first source wins. A value that cannot be
  // resolved at build time is left out.
  Map<String, String> _oauth2ClientProperties() {
    final properties = <String, String>{};
    for (final source in _environment.propertySources) {
      if (source is! EnumerablePropertySource<Object> ||
          source is ConfigurationPropertySourcesPropertySource) {
        continue;
      }
      for (final name in source.propertyNames) {
        final relaxed = _relaxed(name);
        if (!relaxed.startsWith(_oauth2Client) ||
            properties.containsKey(relaxed)) {
          continue;
        }
        try {
          if (_environment.getProperty(name) case final value?) {
            properties[relaxed] = value;
          }
        } on Exception {
          continue; // not resolvable at build time
        }
      }
    }
    return properties;
  }

  static String _relaxed(String name) =>
      name.toLowerCase().replaceAll('-', '').replaceAll('_', '');

  static const _oauth2Client = 'spring.security.oauth2.client.';

  static final _providerUri = RegExp(
    r'^spring\.security\.oauth2\.client\.provider\.([^.]+)\.'
    r'(issueruri|tokenuri|userinfouri|jwkseturi)$',
  );

  static final _registrationProperty = RegExp(
    r'^spring\.security\.oauth2\.client\.registration\.([^.]+)\.([^.]+)$',
  );

  // The origins other than the issuer's that the discovery documents of
  // well-known issuers name for the token, keys, user info and revocation
  // endpoints. Any other issuer's are not known at build time:
  // content-security-policy-connect-src adds them.
  static const _discoveredOrigins = {
    'https://accounts.google.com': [
      'https://oauth2.googleapis.com',
      'https://openidconnect.googleapis.com',
      'https://www.googleapis.com',
    ],
    'https://login.microsoftonline.com': ['https://graph.microsoft.com'],
  };

  // A list comes whole from the first source that has it, as Spring Boot
  // binds lists.
  List<WebDevProxyRule> _proxy() {
    for (final (source, names) in _sources) {
      final rules = <int, Map<String, String>>{};
      for (final MapEntry(key: name, value: key) in names.entries) {
        if (_field(name) != 'proxy' ||
            name.numberOfElements != 6 ||
            !name.isNumericIndex(4)) {
          continue;
        }
        final field = name.getElement(
          5,
          form: ConfigurationPropertyNameForm.uniform,
        );
        final value = source.getProperty(key);
        if (_proxyFields.contains(field) && value != null) {
          (rules[int.parse(name.getElement(4))] ??= {})[field] = _resolve(
            key,
            value,
            source,
          );
        }
      }
      if (rules.isNotEmpty) {
        final indexes = rules.keys.toList()..sort();
        return [for (final i in indexes) _rule(i, rules[i]!, source)];
      }
    }
    return const [];
  }

  static WebDevProxyRule _rule(
    int index,
    Map<String, String> fields,
    AbstractPropertySource<Object> source,
  ) {
    final name = '${WebDevConfigBuilder.prefix}.proxy[$index]';
    final origin = _origin(source);
    String? nonEmpty(String field) {
      final value = fields[field];
      return value == null || value.isEmpty ? null : value;
    }

    final target = nonEmpty('target');
    if (target == null) {
      throw WebDevConfigException(
        '$name.target is not set$origin: a proxy rule needs the server to '
        'forward to, such as http://localhost:8080.',
      );
    }
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw WebDevConfigException(
        "$name.target$origin: '$target' is not an absolute URL, such as "
        'http://localhost:8080.',
      );
    }
    final prefix = nonEmpty('prefix');
    final regex = nonEmpty('regex');
    if ((prefix == null) == (regex == null)) {
      throw WebDevConfigException(
        '$name$origin: set exactly one of $name.prefix (a path start, such '
        'as /api/) and $name.regex (a pattern the path must match).',
      );
    }
    if (regex != null) {
      try {
        RegExp(regex);
      } on FormatException catch (e) {
        throw WebDevConfigException(
          "$name.regex$origin: '$regex' is not a valid regular expression: "
          '${e.message}',
        );
      }
    }
    return (
      target: target,
      prefix: prefix,
      regex: regex,
      replace: fields['replace'],
    );
  }

  // The element after spring.flutter.web, uniform (`base-href` gives
  // `basehref`).
  static String _field(ConfigurationPropertyName name) =>
      name.getElement(3, form: ConfigurationPropertyNameForm.uniform);

  // Unknown names are most likely typos (`spring.flutter.web.prot`):
  // warned about, not failed on, as they change nothing.
  void _warnUnknown() {
    for (final (source, names) in _sources) {
      for (final MapEntry(key: name, value: key) in names.entries) {
        if (!_known(name)) {
          log.warning(
            '$key${_origin(source)} is not a known '
            '${WebDevConfigBuilder.prefix}.* property and is ignored; the '
            'properties are host, port, base-href, https.cert-path, '
            'https.cert-key-path, headers.<Name>, '
            'content-security-policy, content-security-policy-report-only, '
            'content-security-policy-connect-src and '
            'proxy[n].target/prefix/regex/replace.',
          );
        }
      }
    }
  }

  static bool _known(ConfigurationPropertyName name) {
    final elements = name.numberOfElements;
    return switch (_field(name)) {
      'host' ||
      'port' ||
      'basehref' ||
      'contentsecuritypolicy' ||
      'contentsecuritypolicyreportonly' => elements == 4,
      'contentsecuritypolicyconnectsrc' =>
        elements == 4 || elements == 5 && name.isNumericIndex(4),
      'https' =>
        elements == 5 &&
            const {'certpath', 'certkeypath'}.contains(
              name.getElement(4, form: ConfigurationPropertyNameForm.uniform),
            ),
      'headers' => elements == 5,
      'proxy' =>
        elements == 6 &&
            name.isNumericIndex(4) &&
            _proxyFields.contains(
              name.getElement(5, form: ConfigurationPropertyNameForm.uniform),
            ),
      _ => false,
    };
  }
}
