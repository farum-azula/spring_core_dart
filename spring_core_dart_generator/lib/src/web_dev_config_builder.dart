import 'dart:convert';
import 'dart:io' as io;

import 'package:build/build.dart';
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/dart_define_keys.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';

/// Writes the Flutter web dev server's `web_dev_config.yaml` from the
/// `spring.flutter.web.*` properties in `lib/resources/`.
///
/// `flutter run -d chrome` and `-d web-server` serve the app on a random
/// port unless told otherwise, which breaks whatever needs a fixed origin:
/// a server's CORS list, the redirect back after an SSO login. Since
/// Flutter 3.38 the dev server reads `web_dev_config.yaml` in the project
/// directory (command-line flags still win), and nothing else configures
/// it. This builder writes that file from the application's own config,
/// read as the app reads it in a browser: `application.*`, then
/// `application-web.*` (the `web` platform profile) and the files of the
/// profiles `spring.profiles.active` names there, names matched the
/// relaxed way.
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
/// origin, Flutter's CDN and the providers of its
/// `spring.security.oauth2.client.provider.*` URIs, no framing.
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
///   left as it is.
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
    final resources = await SpringBuilder.resources(buildStep);
    final texts = {
      for (final MapEntry(:key, value: (:text, base64: _)) in resources.entries)
        key: ?text,
    };
    final WebDevServerSettings? settings;
    try {
      settings = WebDevServerSettings.read(texts);
    } on WebDevConfigException catch (e) {
      log.severe('$e\n$fileName is left as it is.');
      return;
    }
    final existing = await _files.read(buildStep, package);
    final generated = existing != null && existing.startsWith(marker);
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

// The file in the package's directory on disk.
final class _DiskFiles implements WebDevConfigFiles {
  const _DiskFiles();

  static final _directories = <String, Uri?>{};

  // build_runner gives builders `asset:` package roots, so the directory
  // comes from the nearest `.dart_tool/package_config.json` above the
  // working directory: the package's own, or its workspace's when the
  // build runs from a pub workspace (`build_runner build --workspace`).
  static Uri? _directory(String package) =>
      _directories.putIfAbsent(package, () {
        var directory = io.Directory.current.absolute;
        while (true) {
          final config = io.File.fromUri(
            directory.uri.resolve('.dart_tool/package_config.json'),
          );
          if (config.existsSync()) {
            try {
              final json = jsonDecode(config.readAsStringSync()) as Map;
              for (final entry in json['packages'] as List) {
                if (entry is Map && entry['name'] == package) {
                  final root = config.uri.resolve(entry['rootUri'] as String);
                  return root.path.endsWith('/') ? root : Uri.parse('$root/');
                }
              }
            } on Object {
              // Unreadable: the package's directory is unknown.
            }
            return null;
          }
          final parent = directory.parent;
          if (parent.path == directory.path) {
            return null;
          }
          directory = parent;
        }
      });

  static io.File? _file(String package) {
    final directory = _directory(package);
    return directory == null || !directory.isScheme('file')
        ? null
        : io.File.fromUri(directory.resolve(WebDevConfigBuilder.fileName));
  }

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
  /// engine needs and nothing more, plus [connectOrigins] (the providers'
  /// origins) for `fetch`.
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
  /// that directory to content), read for the `web` profile; `null` when
  /// no `spring.flutter.web.*` property is set and the browser does not
  /// log in by itself (`spring.flutter.security.web.mode=spa`).
  ///
  /// Throws [WebDevConfigException] for an invalid value.
  static WebDevServerSettings? read(Map<String, String> files) {
    // Reuses the scan behind the --dart-define keys: no config file
    // mentions the properties, so the files need not be loaded at all.
    final keys = DartDefineKeys();
    files.forEach(keys.addConfigFile);
    if (!keys.keys.any(
      (key) =>
          key.startsWith('SPRING_FLUTTER_WEB_') ||
          key == 'SPRING_FLUTTER_SECURITY_WEB_MODE',
    )) {
      return null;
    }
    return _Reader(_environment(files)).read();
  }

  // The environment of the app in a browser: the config files with the
  // `web` profile, no environment variables (the build must not depend on
  // them), missing imports ignored (they may exist at run time only).
  static StandardEnvironment _environment(Map<String, String> files) {
    final environment = StandardEnvironment(systemEnvironment: const {});
    environment.propertySources.addLast(
      const MapPropertySource(
        ConfigDataEnvironment.defaultPropertiesSourceName,
        {ConfigDataEnvironment.onNotFoundProperty: 'ignore'},
      ),
    );
    try {
      ConfigDataEnvironment(
        environment,
        resourceLoader: DefaultResourceLoader(
          protocolResolvers: [InMemoryProtocolResolver('memory:', files)],
        ),
        defaultLocations: const ['optional:memory:/;optional:memory:/config/'],
        additionalProfiles: const ['web'],
      ).processAndApplySync();
    } on Exception catch (e) {
      throw WebDevConfigException(
        'The config files of lib/resources/ cannot be read for the '
        '${WebDevConfigBuilder.prefix}.* properties: $e',
      );
    }
    ConfigurationPropertySources.attach(environment);
    return environment;
  }

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
  static String _origin(AbstractPropertySource<Object> source) {
    final match = RegExp("memory:/([^']+)").firstMatch(source.name);
    return match == null ? '' : ' (in lib/resources/${match[1]})';
  }

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
  // spring.flutter.security.web.mode=spa.
  bool _spaMode() {
    try {
      return _environment
              .getProperty('spring.flutter.security.web.mode')
              ?.trim()
              .toLowerCase() ==
          'spa';
    } on Exception {
      return false;
    }
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
    final value =
        policy ??
        (spa && existing.isEmpty
            ? WebDevServerSettings.spaContentSecurityPolicy(_providerOrigins())
            : null);
    if (value == null) {
      return headers;
    }
    return {...headers, reportOnlyValue ? reportOnly : enforced: value};
  }

  // The origins of the spring.security.oauth2.client.provider.<id> URIs
  // the browser fetches (issuer, token, user info, keys), sorted.
  Set<String> _providerOrigins() {
    final pattern = RegExp(
      r'^spring\.security\.oauth2\.client\.provider\.[^.]+\.'
      r'(issueruri|tokenuri|userinfouri|jwkseturi)$',
    );
    final origins = <String>{};
    for (final source in _environment.propertySources) {
      if (source is! EnumerablePropertySource<Object> ||
          source is ConfigurationPropertySourcesPropertySource) {
        continue;
      }
      for (final name in source.propertyNames) {
        final relaxed = name
            .toLowerCase()
            .replaceAll('-', '')
            .replaceAll(
              '_',
              '',
            );
        if (!pattern.hasMatch(relaxed)) {
          continue;
        }
        final String? value;
        try {
          value = _environment.getProperty(name);
        } on Exception {
          continue; // not resolvable at build time
        }
        final uri = value == null ? null : Uri.tryParse(value.trim());
        if (uri != null &&
            (uri.isScheme('http') || uri.isScheme('https')) &&
            uri.host.isNotEmpty) {
          origins.add(uri.origin);
        }
      }
    }
    return {...origins.toList()..sort()};
  }

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
            'content-security-policy, content-security-policy-report-only '
            'and proxy[n].target/prefix/regex/replace.',
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
