import 'dart:convert';
import 'dart:io' as io;

import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';

/// Writes the deep links of an app (`spring.flutter.navigation.deep-links.*`
/// of `spring_boot_starter_flutter_navigation`) into its platform files,
/// and the files its domains must serve.
///
/// A link of the app's own scheme (`neonbooks://catalog/books/1`) or of its
/// domain (`https://books.example.com/catalog/books/1`, Universal Links on
/// iOS, App Links on Android) opens the app at that route. The platforms
/// learn it from their own files; this builder writes them from the
/// configuration, read as the app reads it on each platform (the `mobile`
/// then `ios` profiles for iOS, `mobile` then `android` for Android,
/// `desktop` then `macos` for macOS; the later one wins, as in the app):
///
/// - `ios/Runner/Info.plist`: `FlutterDeepLinkingEnabled` and the scheme
///   (`CFBundleURLTypes`); `ios/Runner/Runner.entitlements`: the domains
///   (`applinks:`), when the file exists (Xcode makes it with the
///   Associated Domains capability; the build never edits the Xcode
///   project);
/// - `macos/Runner/Info.plist`: the scheme;
/// - `android/app/src/main/AndroidManifest.xml`: in the main activity,
///   `flutter_deeplinking_enabled` and the intent filters of the scheme and,
///   verified (`autoVerify`), of the domains;
/// - `apple-app-site-association` and `assetlinks.json`, which each domain
///   serves under `/.well-known/`: into `web/.well-known/` for an app with
///   a web version (its build serves them), else into
///   `build/spring/well-known/` to upload.
///
/// Each block sits between `spring:deep-links:start` and
/// `spring:deep-links:end` comments with the hash of what was written; a
/// block changed by hand fails the build (move the change into the
/// properties), and a block whose properties are gone is removed. A key of
/// the block written outside it as well (`CFBundleURLTypes` of the app's
/// own) fails the build too: the platform would read only one.
///
/// The domain takes the whole site (`/*`): routes left out with
/// `deep-links.exclude` are excluded in Apple's file, and the app opens its
/// first screen for them and for screens with `@RouteInfo(link: false)`
/// (Android cannot exclude paths of a verified domain).
final class DeepLinksBuilder implements Builder {
  /// The builder; [files] reads and writes the app's own files (on disk
  /// unless given; tests pass files held in memory).
  DeepLinksBuilder({NativeFiles? files}) : _files = files ?? const _Disk();

  final NativeFiles _files;

  /// The prefix of the properties read.
  static const prefix = 'spring.flutter.navigation.deep-links';

  @override
  Map<String, List<String>> get buildExtensions => const {r'$package$': []};

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final texts = {
      for (final MapEntry(:key, value: (:text, base64: _)) in resources.entries)
        key: ?text,
    };
    final binary = {
      for (final MapEntry(:key, value: (:text, :base64)) in resources.entries)
        if (text == null && base64 != null) key: base64Decode(base64),
    };
    // The cheap test first: no file names the deep links.
    final named = texts.values.any(
      (text) => text.contains('deep-links') || text.contains('deepLinks'),
    );
    final targets = <_Target>[];
    final read = <_Platform, DeepLinkSettings?>{};
    for (final platform in _Platform.values) {
      DeepLinkSettings? settings;
      if (named) {
        try {
          settings = DeepLinkSettings.of(
            readPlatformEnvironment(
              texts,
              profiles: platform.profiles,
              binary: binary,
            ),
          );
        } on WebDevConfigException catch (e) {
          log.severe('$e\nThe deep links of ${platform.name} are not written.');
          continue;
        }
      }
      read[platform] = settings;
      targets.addAll(platform.targets(settings));
    }
    _warnLoginScheme(texts, read.values.nonNulls);
    for (final target in targets) {
      final text = await _files.read(buildStep, package, target.path);
      if (text == null) {
        if (target.block != null && target.required) {
          log.warning(target.missing);
        }
        continue;
      }
      final String updated;
      try {
        updated = NativeBlocks.put(
          text,
          target.block,
          anchor: target.anchor,
          keys: target.keys,
        );
      } on StateError catch (e) {
        log.severe('${target.path}: ${e.message}');
        continue;
      }
      if (updated != text) {
        await _files.write(buildStep, package, target.path, updated);
      }
    }
    await _domainFiles(
      buildStep,
      package,
      read[_Platform.ios],
      read[_Platform.android],
    );
  }

  // The login's redirect (an OAuth2 registration's redirect-uri) on the
  // deep links' scheme: the login window's receiver and the app would both
  // claim its links.
  void _warnLoginScheme(
    Map<String, String> texts,
    Iterable<DeepLinkSettings> settings,
  ) {
    final schemes = {for (final s in settings) ?s.scheme};
    if (schemes.isEmpty) {
      return;
    }
    final redirect = RegExp(
      r'''redirect-uri\s*[=:]\s*["']?([a-zA-Z][a-zA-Z0-9+.\-]*):''',
    );
    for (final text in texts.values) {
      for (final match in redirect.allMatches(text)) {
        final scheme = match.group(1)!;
        if (schemes.contains(scheme)) {
          log.warning(
            '$prefix.scheme "$scheme" is also the scheme of a login redirect '
            '(redirect-uri); the login window and the app would both claim '
            'its links. Give the deep links a scheme of their own.',
          );
          return;
        }
      }
    }
  }

  // apple-app-site-association and assetlinks.json for the domains.
  Future<void> _domainFiles(
    BuildStep buildStep,
    String package,
    DeepLinkSettings? ios,
    DeepLinkSettings? android,
  ) async {
    final web = await _files.exists(buildStep, package, 'web/index.html');
    final directory = web ? 'web/.well-known' : 'build/spring/well-known';
    final apple = '$directory/apple-app-site-association';
    final google = '$directory/assetlinks.json';

    final appId = ios?.appId ?? await _appleAppId(buildStep, package);
    if (ios != null && ios.domains.isNotEmpty) {
      if (appId == null) {
        log.warning(
          'The iOS app id (Team ID and bundle ID) is unknown: set '
          '$prefix.app-id in application-ios.yml (ABCDE12345.com.example.app); '
          '$apple is not written.',
        );
      } else {
        await _files.write(
          buildStep,
          package,
          apple,
          DomainFiles.appleAppSiteAssociation(appId, ios.exclude),
        );
      }
    }
    if (android != null && android.domains.isNotEmpty) {
      final name = android.package ?? await _androidPackage(buildStep, package);
      if (name == null || android.fingerprints.isEmpty) {
        log.warning(
          'Android App Links need the package and the SHA-256 fingerprints '
          'of the signing keys ($prefix.package, '
          '$prefix.sha256-cert-fingerprints in application-android.yml); '
          '$google is not written, so Android does not verify the domain.',
        );
      } else {
        await _files.write(
          buildStep,
          package,
          google,
          DomainFiles.assetLinks(name, android.fingerprints),
        );
      }
    }
  }

  // ABCDE12345.com.example.app from the Xcode project: the Runner's team
  // and bundle id, when both are written there.
  Future<String?> _appleAppId(BuildStep buildStep, String package) async {
    final project = await _files.read(
      buildStep,
      package,
      'ios/Runner.xcodeproj/project.pbxproj',
    );
    if (project == null) {
      return null;
    }
    final team = RegExp(
      'DEVELOPMENT_TEAM = ([A-Z0-9]+);',
    ).firstMatch(project)?.group(1);
    final bundle =
        RegExp(
              r'PRODUCT_BUNDLE_IDENTIFIER = ([A-Za-z0-9.\-]+);',
            )
            .allMatches(project)
            .map((m) => m.group(1)!)
            .where(
              (id) => !id.endsWith('Tests'),
            )
            .firstOrNull;
    return team == null || bundle == null ? null : '$team.$bundle';
  }

  // The applicationId of android/app/build.gradle(.kts).
  Future<String?> _androidPackage(BuildStep buildStep, String package) async {
    for (final path in const [
      'android/app/build.gradle.kts',
      'android/app/build.gradle',
    ]) {
      final text = await _files.read(buildStep, package, path);
      final id = text == null
          ? null
          : RegExp(
              r'''applicationId\s*=?\s*["']([^"']+)["']''',
            ).firstMatch(text)?.group(1);
      if (id != null) {
        return id;
      }
    }
    return null;
  }
}

/// The deep links of one platform, `spring.flutter.navigation.deep-links.*`
/// as the app reads them there.
final class DeepLinkSettings {
  DeepLinkSettings._({
    required this.scheme,
    required this.domains,
    required this.exclude,
    this.appId,
    this.package,
    this.fingerprints = const [],
  });

  /// The settings in [environment]; `null` when deep links are off or
  /// neither a scheme nor a domain is set. Throws [WebDevConfigException]
  /// for a scheme or domain that is not one.
  static DeepLinkSettings? of(PropertyResolver environment) {
    String? string(String name) {
      final value = environment
          .getProperty('${DeepLinksBuilder.prefix}.$name')
          ?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    List<String> list(String name) {
      final whole = string(name);
      final values = <String>[
        if (whole != null)
          for (final part in whole.split(','))
            if (part.trim().isNotEmpty) part.trim(),
      ];
      for (var i = 0; ; i++) {
        final value = string('$name[$i]');
        if (value == null) {
          break;
        }
        values.add(value);
      }
      return values;
    }

    if (string('enabled') == 'false') {
      return null;
    }
    final scheme = string('scheme');
    final domains = list('domains');
    if (scheme == null && domains.isEmpty) {
      return null;
    }
    if (scheme != null &&
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*$').hasMatch(scheme)) {
      throw WebDevConfigException(
        '${DeepLinksBuilder.prefix}.scheme "$scheme" is no URL scheme '
        '(letters, digits, +, - and ., a letter first).',
      );
    }
    if (scheme == 'http' || scheme == 'https') {
      throw WebDevConfigException(
        '${DeepLinksBuilder.prefix}.scheme cannot be $scheme: put the site in '
        '${DeepLinksBuilder.prefix}.domains instead.',
      );
    }
    for (final domain in domains) {
      if (!RegExp(
        r'^(\*\.)?[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)+$',
      ).hasMatch(domain)) {
        throw WebDevConfigException(
          '${DeepLinksBuilder.prefix}.domains: "$domain" is no host name (no '
          'scheme, no path: books.example.com).',
        );
      }
    }
    return DeepLinkSettings._(
      scheme: scheme,
      domains: domains,
      exclude: list('exclude'),
      appId: string('app-id'),
      package: string('package'),
      fingerprints: list('sha256-cert-fingerprints'),
    );
  }

  /// The app's own scheme, or `null`.
  final String? scheme;

  /// The domains whose links open the app.
  final List<String> domains;

  /// The path patterns whose links do not open the app.
  final List<String> exclude;

  /// The iOS app id (`TEAMID.bundle.id`), or `null` (from the project).
  final String? appId;

  /// The Android package, or `null` (from the Gradle file).
  final String? package;

  /// The SHA-256 fingerprints of the Android signing keys.
  final List<String> fingerprints;
}

/// The files each domain serves under `/.well-known/`.
abstract final class DomainFiles {
  /// Apple's `apple-app-site-association` for [appId]: the whole site
  /// opens the app except the paths of [exclude] (Spring patterns: a
  /// variable or `**` becomes `*`).
  static String appleAppSiteAssociation(String appId, List<String> exclude) {
    final components = [
      for (final pattern in exclude)
        {'/': appleComponent(pattern), 'exclude': true},
      {'/': '*'},
    ];
    final json = const JsonEncoder.withIndent('  ').convert({
      'applinks': {
        'details': [
          {
            'appIDs': [appId],
            'components': components,
          },
        ],
      },
    });
    return '$json\n';
  }

  /// A Spring path pattern as a path of Apple's components: `/admin/**`
  /// is `/admin/*`, `/books/{isbn}` is `/books/*`.
  static String appleComponent(String pattern) => pattern
      .replaceAll(RegExp(r'\{[^}]*\}'), '*')
      .replaceAll('**', '*')
      .replaceAll(RegExp(r'\*+'), '*');

  /// Google's `assetlinks.json`: [package] signed by [fingerprints] handles
  /// the domain's links.
  static String assetLinks(String package, List<String> fingerprints) =>
      '${const JsonEncoder.withIndent('  ').convert([
        {
          'relation': ['delegate_permission/common.handle_all_urls'],
          'target': {
            'namespace': 'android_app',
            'package_name': package,
            'sha256_cert_fingerprints': fingerprints,
          },
        },
      ])}\n';
}

/// Puts a generated block into an XML platform file (a plist, the Android
/// manifest) between marker comments.
abstract final class NativeBlocks {
  static const _start = '<!-- spring:deep-links:start';
  static const _end = '<!-- spring:deep-links:end -->';
  static const _properties = 'spring.flutter.navigation.deep-links.*';

  static final _existing = RegExp(
    r'[ \t]*<!-- spring:deep-links:start(?: sha=([0-9a-f]{12}))?[^\n]*\n'
    r'([\s\S]*?)[ \t]*<!-- spring:deep-links:end -->\n?',
  );

  /// [text] with [block] between the markers: replacing the block written
  /// before, else inserted before the last match of [anchor], one level
  /// deeper than the anchor's line. A `null` [block] removes the old one.
  /// Throws a [StateError] when the old block was changed by hand (its
  /// hash does not match), when [anchor] is missing, or when one of [keys]
  /// (which the block writes) is written outside it too.
  static String put(
    String text,
    String? block, {
    required Pattern anchor,
    List<String> keys = const [],
  }) {
    final existing = _existing.firstMatch(text);
    var rest = text;
    if (existing != null) {
      final written = existing.group(1);
      if (written != null && written != _hash(existing.group(2)!)) {
        throw StateError(
          'the block between "$_start" and "$_end" was changed by hand. Make '
          'the change in the $_properties properties instead and delete the '
          'block (it is written again), or remove the properties.',
        );
      }
      rest = text.replaceRange(existing.start, existing.end, '');
    }
    for (final key in keys) {
      if (rest.contains(key)) {
        throw StateError(
          '$key is written outside the generated block too; the platform '
          'reads one. Remove it from the file (the deep links of '
          '$_properties write it) or turn the deep links off.',
        );
      }
    }
    if (block == null) {
      return rest;
    }
    final matches = anchor.allMatches(rest).toList();
    if (matches.isEmpty) {
      throw StateError('no place for the deep links ($anchor not found).');
    }
    final at = matches.last.start;
    final lineStart = rest.lastIndexOf('\n', at - 1) + 1;
    final indent = RegExp(
      r'^[ \t]*',
    ).firstMatch(rest.substring(lineStart))!.group(0)!;
    final unit = rest.contains('\n\t<') ? '\t' : '    ';
    final inner = '$indent$unit';
    final body = [
      for (final line in block.trimRight().split('\n'))
        if (line.isEmpty) '' else '$inner$line',
    ].join('\n');
    final written =
        '$inner$_start sha=${_hash('$body\n')} (generated from '
        '$_properties; do not edit) -->\n'
        '$body\n'
        '$inner$_end\n';
    return rest.replaceRange(lineStart, lineStart, written);
  }

  static String _hash(String body) =>
      sha256.convert(utf8.encode(body)).toString().substring(0, 12);
}

/// Reads and writes the app's own files (below the package directory).
abstract interface class NativeFiles {
  /// The text of [path] below [package]'s directory, or `null`.
  Future<String?> read(BuildStep buildStep, String package, String path);

  /// Whether [path] exists below [package]'s directory.
  Future<bool> exists(BuildStep buildStep, String package, String path);

  /// Writes [content] to [path], making its directory.
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  );
}

final class _Disk implements NativeFiles {
  const _Disk();

  @override
  Future<String?> read(BuildStep buildStep, String package, String path) async {
    final file = PackageDirectories.current.file(AssetId(package, path));
    return file != null && file.existsSync() ? await file.readAsString() : null;
  }

  @override
  Future<bool> exists(BuildStep buildStep, String package, String path) async =>
      PackageDirectories.current.file(AssetId(package, path))?.existsSync() ??
      false;

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  ) async {
    final file = PackageDirectories.current.file(AssetId(package, path));
    if (file == null) {
      log.warning(
        'The directory of $package is not found; $path is not '
        'written.',
      );
      return;
    }
    if (file.existsSync() && file.readAsStringSync() == content) {
      return;
    }
    await io.Directory(file.parent.path).create(recursive: true);
    await file.writeAsString(content);
  }
}

// One file to change: its path, the block (null: remove), where it goes.
final class _Target {
  _Target(
    this.path,
    this.block, {
    required this.anchor,
    this.keys = const [],
    this.required = false,
    this.missing = '',
  });

  final String path;
  final String? block;
  final Pattern anchor;
  final List<String> keys;
  final bool required;
  final String missing;
}

enum _Platform {
  ios(['mobile', 'ios']),
  android(['mobile', 'android']),
  macos(['desktop', 'macos']);

  _Platform(this.profiles);

  final List<String> profiles;

  List<_Target> targets(DeepLinkSettings? settings) => switch (this) {
    ios => [
      _Target(
        'ios/Runner/Info.plist',
        settings == null
            ? null
            : _plistBlock(settings.scheme, deepLinking: true),
        anchor: RegExp(r'</dict>\s*</plist>'),
        keys: [
          if (settings?.scheme != null) '<key>CFBundleURLTypes</key>',
          if (settings != null) '<key>FlutterDeepLinkingEnabled</key>',
        ],
      ),
      _Target(
        'ios/Runner/Runner.entitlements',
        settings == null || settings.domains.isEmpty
            ? null
            : _entitlementsBlock(settings.domains),
        anchor: RegExp(r'</dict>\s*</plist>'),
        keys: [
          if (settings != null && settings.domains.isNotEmpty)
            '<key>com.apple.developer.associated-domains</key>',
        ],
        required: true,
        missing:
            'ios/Runner/Runner.entitlements is missing, so iOS does not open '
            'the links of ${settings?.domains.join(', ')}: add the Associated '
            'Domains capability to the Runner target in Xcode (it makes the '
            'file); the build then writes the domains into it.',
      ),
    ],
    macos => [
      _Target(
        'macos/Runner/Info.plist',
        settings?.scheme == null
            ? null
            : _plistBlock(settings!.scheme, deepLinking: false),
        anchor: RegExp(r'</dict>\s*</plist>'),
        keys: [if (settings?.scheme != null) '<key>CFBundleURLTypes</key>'],
      ),
    ],
    android => [
      _Target(
        'android/app/src/main/AndroidManifest.xml',
        settings == null ? null : _manifestBlock(settings),
        anchor: _mainActivityEnd,
        keys: [if (settings != null) 'flutter_deeplinking_enabled'],
      ),
    ],
  };

  // The end of the main activity (the one with the launcher's intent).
  static final _mainActivityEnd = _MainActivityEnd();

  static String _plistBlock(String? scheme, {required bool deepLinking}) => [
    if (deepLinking) ...['<key>FlutterDeepLinkingEnabled</key>', '<true/>'],
    if (scheme != null) ...[
      '<key>CFBundleURLTypes</key>',
      '<array>',
      '\t<dict>',
      '\t\t<key>CFBundleURLName</key>',
      r'		<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>',
      '\t\t<key>CFBundleURLSchemes</key>',
      '\t\t<array>',
      '\t\t\t<string>$scheme</string>',
      '\t\t</array>',
      '\t</dict>',
      '</array>',
    ],
  ].join('\n');

  static String _entitlementsBlock(List<String> domains) => [
    '<key>com.apple.developer.associated-domains</key>',
    '<array>',
    for (final domain in domains) '\t<string>applinks:$domain</string>',
    '</array>',
  ].join('\n');

  static String _manifestBlock(DeepLinkSettings settings) => [
    '<meta-data android:name="flutter_deeplinking_enabled" android:value="true" />',
    if (settings.scheme case final scheme?) ...[
      '<intent-filter>',
      '    <action android:name="android.intent.action.VIEW" />',
      '    <category android:name="android.intent.category.DEFAULT" />',
      '    <category android:name="android.intent.category.BROWSABLE" />',
      '    <data android:scheme="$scheme" />',
      '</intent-filter>',
    ],
    if (settings.domains.isNotEmpty) ...[
      '<intent-filter android:autoVerify="true">',
      '    <action android:name="android.intent.action.VIEW" />',
      '    <category android:name="android.intent.category.DEFAULT" />',
      '    <category android:name="android.intent.category.BROWSABLE" />',
      '    <data android:scheme="https" />',
      for (final domain in settings.domains)
        '    <data android:host="$domain" />',
      '</intent-filter>',
    ],
  ].join('\n');
}

// Matches the `</activity>` that closes the activity with the launcher's
// intent filter (Flutter's MainActivity).
final class _MainActivityEnd implements Pattern {
  @override
  Iterable<Match> allMatches(String string, [int start = 0]) {
    final launcher = string.indexOf('android.intent.category.LAUNCHER', start);
    if (launcher < 0) {
      return const [];
    }
    return RegExp('</activity>').allMatches(string, launcher).take(1);
  }

  @override
  Match? matchAsPrefix(String string, [int start = 0]) =>
      RegExp('</activity>').matchAsPrefix(string, start);

  @override
  String toString() => 'the end of the main activity';
}
