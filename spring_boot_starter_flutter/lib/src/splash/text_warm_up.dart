import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_task.dart';

/// Text the app will show, for [TextWarmUp] to lay out while the splash
/// shows. Declare a bean of this type to add text that is not in a file
/// (`spring.flutter.splash.warm-up.text.resources` reads files).
abstract interface class TextWarmUpSource {
  /// The text; only its characters matter, each once.
  Future<Iterable<String>> texts();
}

/// The files of `spring.flutter.splash.warm-up.text.resources`, as a
/// [TextWarmUpSource].
final class ResourceTextWarmUpSource implements TextWarmUpSource {
  /// The files of [locations] (patterns: `resources:messages*.properties`)
  /// in [resources].
  const ResourceTextWarmUpSource(this.resources, this.locations);

  /// Where the files are found.
  final ResourcePatternResolver resources;

  /// The locations, each a pattern.
  final List<String> locations;

  @override
  Future<Iterable<String>> texts() => Future.wait([
    for (final location in locations)
      for (final resource in resources.getResources(location))
        if (resource.exists()) resource.readAsString(),
  ]);
}

/// Lays out the characters of the app's text while the splash shows, so
/// the fonts they need are ready before the app is shown
/// (`spring.flutter.splash.warm-up.text.*`).
///
/// On the web, Flutter downloads a font for the characters the app's fonts
/// do not have (Japanese, Chinese, Arabic, emoji: Noto fonts) the first
/// time it lays them out, then lays out all the text again: a language
/// changed for the first time stutters for a second. This task lays out
/// every character of its [sources] once, [chunk] characters a frame so
/// the splash keeps moving, and waits until the fonts are in. Off by
/// default: `spring.flutter.splash.warm-up.text.enabled: true`.
class TextWarmUp extends SplashTask {
  /// Lays out the characters of [sources] in [fontFamilies]; [fontsChanged]
  /// tells when a font came in (`PaintingBinding.systemFonts`).
  TextWarmUp(
    this.sources, {
    this.fontFamilies = const {},
    this.firstFont = const Duration(milliseconds: 400),
    this.settle = const Duration(milliseconds: 250),
    this.chunk = 200,
    this.fontsChanged,
    this.nextFrame,
  });

  /// The text sources.
  final List<TextWarmUpSource> sources;

  /// The families the app's text is in; the platform's default as well.
  final Set<String> fontFamilies;

  /// How long to wait for the first font: none in that time means the
  /// fonts the app has show all the characters.
  final Duration firstFont;

  /// Once a font came in, how long without another before the task ends.
  final Duration settle;

  /// How many characters are laid out in one frame: a few hundred keep a
  /// phone's frame short.
  final int chunk;

  /// Tells when a font came in; `PaintingBinding.systemFonts` when null.
  final Listenable? fontsChanged;

  /// Waits for the next frame; the scheduler's when null.
  final Future<void> Function()? nextFrame;

  Future<void> _frame() =>
      nextFrame?.call() ?? SchedulerBinding.instance.endOfFrame;

  @override
  String get name => 'text warm-up';

  @override
  Future<void> run(SplashTaskContext task) async {
    final characters = <int>{};
    for (final source in sources) {
      for (final text in await source.texts()) {
        characters.addAll(text.runes);
      }
    }
    characters.removeWhere(_isPlain);
    if (characters.isEmpty) {
      return;
    }
    final fonts = fontsChanged ?? PaintingBinding.instance.systemFonts;
    final quiet = Completer<void>();
    Timer? timer;
    void wait(Duration time) {
      timer?.cancel();
      timer = Timer(time, () {
        if (!quiet.isCompleted) {
          quiet.complete();
        }
      });
    }

    // Laid out once: the engine asks for every font the characters need at
    // their first layout, and a font coming in needs no layout again.
    var fontsIn = 0;
    void changed() {
      task.progress(1 - 1 / (++fontsIn + 1));
      wait(settle);
    }

    fonts.addListener(changed);
    try {
      final all = characters.toList();
      for (var i = 0; i < all.length; i += chunk) {
        layOut(String.fromCharCodes(all.skip(i).take(chunk)));
        await _frame();
      }
      if (fontsIn == 0) {
        wait(firstFont);
      }
      await quiet.future;
    } finally {
      timer?.cancel();
      fonts.removeListener(changed);
    }
  }

  /// Lays [text] out in each of [fontFamilies] and in the default.
  @visibleForTesting
  void layOut(String text) {
    for (final family in <String?>[null, ...fontFamilies]) {
      (ui.ParagraphBuilder(
          ui.ParagraphStyle(fontFamily: family),
        )..addText(text)).build()
        ..layout(const ui.ParagraphConstraints(width: 1024))
        ..dispose();
    }
  }

  // ASCII: every font has it.
  static bool _isPlain(int rune) => rune < 0x80;
}
