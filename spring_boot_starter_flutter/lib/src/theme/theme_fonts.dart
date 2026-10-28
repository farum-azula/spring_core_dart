import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Loads the app's font files from its assets, so a theme can name a font
/// family without the files being listed under `flutter: fonts:`.
///
/// Every `.ttf` and `.otf` file that `flutter: assets:` declares, in any
/// directory, is loaded into the family its own `name` table gives
/// (`Inter-SemiBold.ttf` becomes a weight of `Inter`). Then a family the
/// themes name but no file provides is logged as a warning, since Flutter
/// would quietly fall back to its default font. `SpringApplicationWidget`
/// does all this behind the splash screen, before the first frame; apps
/// do not call it.
///
/// ```properties
/// # false: load no font files at all
/// spring.flutter.fonts.auto-load=true
/// # font files kept for other uses, not loaded
/// spring.flutter.fonts.exclude=assets/pdf/**
/// ```
abstract final class ThemeFonts {
  static const _log = SpringLog('spring_boot_starter_flutter.ThemeFonts');

  // Asset keys loaded so far: a restart after a hot reload loads only new
  // files.
  static final _loaded = <String, String>{};

  /// Loads the font files among [assets] (asset keys) from [bundle], except
  /// those matching an [exclude] glob (`*`, `**`) and those of other
  /// packages. Returns the asset keys of each family loaded. A file whose
  /// family cannot be read (a `.ttc` collection, a broken file) is skipped
  /// with a warning. Files loaded before, by an earlier start, are not
  /// loaded again.
  static Future<Map<String, List<String>>> load(
    AssetBundle bundle,
    Iterable<String> assets, {
    List<String> exclude = const [],
  }) async {
    final patterns = [for (final glob in exclude) _glob(glob)];
    final families = <String, List<String>>{};
    final files = <String, List<ByteData>>{};
    for (final key in assets) {
      final lower = key.toLowerCase();
      if (key.startsWith('packages/') ||
          !(lower.endsWith('.ttf') || lower.endsWith('.otf')) ||
          patterns.any((p) => p.hasMatch(key))) {
        continue;
      }
      if (_loaded[key] case final family?) {
        (families[family] ??= []).add(key);
        continue;
      }
      final ByteData data;
      try {
        data = await bundle.load(key);
      } on Object catch (error) {
        _log.warning('Font $key could not be read: $error');
        continue;
      }
      final family = familyName(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      if (family == null) {
        _log.warning(
          'Font $key has no readable family name (a .ttc collection or a '
          'broken file); not loaded.',
        );
        continue;
      }
      (families[family] ??= []).add(key);
      (files[family] ??= []).add(data);
      _loaded[key] = family;
    }
    final loaders = <Future<void>>[];
    for (final MapEntry(key: family, value: data) in files.entries) {
      final loader = FontLoader(family);
      for (final bytes in data) {
        loader.addFont(Future.value(bytes));
      }
      loaders.add(loader.load());
    }
    await Future.wait(loaders);
    if (files.isNotEmpty) {
      _log.debug(
        'Fonts loaded: ${[for (final f in files.keys) '$f (${files[f]!.length})'].join(', ')}',
      );
    }
    return families;
  }

  /// The families declared under `flutter: fonts:` in the pubspec (the
  /// app's `FontManifest.json`); empty when there is none.
  static Future<Set<String>> declaredFamilies(AssetBundle bundle) async {
    try {
      // Not loadString: its cached Future would outlive a widget test's
      // fake-async zone and never complete in the next test.
      final data = await bundle.load('FontManifest.json');
      final manifest = jsonDecode(
        utf8.decode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
      return {
        if (manifest is List)
          for (final entry in manifest)
            if (entry is Map && entry['family'] is String)
              entry['family'] as String,
      };
    } on Object {
      return const {};
    }
  }

  /// The family name of the font file in [bytes], from its `name` table:
  /// the typographic family (name 16, so `Inter-SemiBold.ttf` is `Inter`),
  /// else the family (name 1); `null` when it cannot be read.
  static String? familyName(Uint8List bytes) {
    try {
      final data = ByteData.sublistView(bytes);
      final tag = String.fromCharCodes(bytes.sublist(0, 4));
      if (tag == 'ttcf' || bytes.length < 12) {
        return null;
      }
      final tables = data.getUint16(4);
      for (var i = 0; i < tables; i++) {
        final record = 12 + i * 16;
        if (String.fromCharCodes(bytes.sublist(record, record + 4)) != 'name') {
          continue;
        }
        return _family(data, bytes, data.getUint32(record + 8));
      }
    } on RangeError {
      // A truncated file.
    }
    return null;
  }

  static String? _family(ByteData data, Uint8List bytes, int table) {
    final count = data.getUint16(table + 2);
    final strings = table + data.getUint16(table + 4);
    String? best(int nameId) {
      String? windows;
      String? mac;
      for (var i = 0; i < count; i++) {
        final r = table + 6 + i * 12;
        if (data.getUint16(r + 6) != nameId) {
          continue;
        }
        final platform = data.getUint16(r);
        final encoding = data.getUint16(r + 2);
        final language = data.getUint16(r + 4);
        final length = data.getUint16(r + 8);
        final offset = strings + data.getUint16(r + 10);
        final raw = bytes.sublist(offset, offset + length);
        if ((platform == 3 && (encoding == 1 || encoding == 10)) ||
            platform == 0) {
          final text = String.fromCharCodes([
            for (var j = 0; j + 1 < raw.length; j += 2)
              raw[j] << 8 | raw[j + 1],
          ]);
          if (platform == 3 && language == 0x0409) {
            return text;
          }
          windows ??= text;
        } else if (platform == 1 && encoding == 0) {
          mac ??= latin1.decode(raw);
        }
      }
      return windows ?? mac;
    }

    final family = best(16) ?? best(1);
    return family == null || family.trim().isEmpty ? null : family.trim();
  }

  /// Loads the fonts of [context]'s app from [bundle], among [assets],
  /// with the `spring.flutter.fonts.*` settings; nothing when `auto-load`
  /// is `false`. Then logs a warning for the [themeFamilies] that neither
  /// the assets nor `flutter: fonts:` have (they may still be the
  /// platform's own; names starting with `.` and `monospace` are not
  /// reported).
  static Future<void> loadFor(
    ApplicationContext context,
    AssetBundle bundle,
    Iterable<String> assets, {
    Set<String> themeFamilies = const {},
  }) async {
    final environment = context.environment;
    if (environment
            .getProperty('spring.flutter.fonts.auto-load')
            ?.trim()
            .toLowerCase() ==
        'false') {
      return;
    }
    final exclude = environment is ConfigurableEnvironment
        ? Binder.get(environment)
              .bind(
                'spring.flutter.fonts.exclude',
                const ListType(ClassType<String>()),
              )
              .orElse(const [])
              .cast<String>()
        : const <String>[];
    final loaded = await load(bundle, assets, exclude: exclude);
    final missing = themeFamilies.difference({
      ...loaded.keys,
      ...await declaredFamilies(bundle),
    })..removeWhere((f) => f.startsWith('.') || f == 'monospace');
    if (missing.isNotEmpty) {
      _log.warning(
        'The theme names font families that are neither among the app\'s '
        'assets nor under flutter: fonts: ${missing.join(', ')} (found: '
        '${loaded.keys.join(', ')}). Unless the platform has them, Flutter '
        'shows its default font instead.',
      );
    }
  }

  static RegExp _glob(String glob) {
    final pattern = glob
        .trim()
        .split('**')
        .map((part) => part.split('*').map(RegExp.escape).join('[^/]*'))
        .join('.*');
    return RegExp('^$pattern\$');
  }
}
