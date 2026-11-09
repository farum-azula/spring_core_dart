import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/asset_resource.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage_event.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_task.dart';

/// Downloads the file of `spring.resources.prefetch` (the files of its
/// locations, written by the build into `lib/resources/spring_gen/
/// prefetch/resources.json`) and keeps its files in memory as embedded
/// resources, so `resources:` finds them at once instead of downloading
/// each when it is read: a site's pages open without a wait.
///
/// With `stage: app` (the default) it starts `delay` after the splash is
/// gone, so the page shown gets its own files first; with `stage: tasks`
/// it is a splash task, and the splash waits for it. On the web only: an
/// app's assets are on its device elsewhere. The file is read a piece at a
/// time, with a pause whenever it has worked a few milliseconds, so the
/// app keeps drawing.
///
/// Spring has no counterpart.
final class ResourcePrefetch extends SplashTask
    implements GenericApplicationListener {
  /// The prefetch of the files of [locations] (empty: none), during the
  /// splash when [duringSplash], else [delay] after the app is shown; the
  /// file read from [bundle] (`rootBundle` by default); [web] says whether
  /// assets are downloaded (`kIsWeb` by default).
  ResourcePrefetch({
    this.locations = const [],
    this.duringSplash = false,
    this.delay = const Duration(seconds: 1),
    AssetBundle? bundle,
    bool? web,
  }) : bundle = bundle ?? rootBundle,
       web = web ?? kIsWeb;

  /// The prefetch `spring.resources.prefetch.*` of [environment] says.
  factory ResourcePrefetch.of(Environment environment) {
    const prefix = 'spring.resources.prefetch';
    return ResourcePrefetch(
      locations: [
        ...?environment
            .getProperty('$prefix.locations')
            ?.split(',')
            .where((l) => l.trim().isNotEmpty),
        for (
          var i = 0;
          environment.getProperty('$prefix.locations[$i]') != null;
          i++
        )
          environment.getProperty('$prefix.locations[$i]')!,
      ],
      duringSplash:
          environment.getProperty('$prefix.stage')?.trim().toLowerCase() ==
          'tasks',
      delay:
          environment.getPropertyAs<Duration>('$prefix.delay') ??
          const Duration(seconds: 1),
    );
  }

  /// The asset key of the file.
  static const file = 'lib/resources/spring_gen/prefetch/resources.json';

  static const _owner = 'spring.resources.prefetch';
  static const _slice = Duration(milliseconds: 8);
  static const _log = SpringLog('spring_boot_starter_flutter.ResourcePrefetch');

  /// The globs of the files in the file (`spring.resources.prefetch
  /// .locations`); the build wrote them, the app only needs to know there
  /// are some.
  final List<String> locations;

  /// Whether the splash waits for the download (`stage: tasks`).
  final bool duringSplash;

  /// How long after the app is shown it starts (`stage: app`).
  final Duration delay;

  /// Where the file is read from.
  final AssetBundle bundle;

  /// Whether the app's assets are downloaded.
  final bool web;

  Future<void>? _loading;
  Timer? _timer;

  /// Completes when the files are in memory (or there was nothing to
  /// download); `null` before it started.
  Future<void>? get loaded => _loading;

  @override
  String get name => 'Prefetch of resources';

  @override
  Future<void> run(SplashTaskContext task) async {
    if (duringSplash) {
      await load();
    }
  }

  @override
  bool supportsEvent(Object event) =>
      event is SplashStageEvent && event.stage == SplashStage.app;

  @override
  void onApplicationEvent(Object event) {
    if (!duringSplash && _loading == null) {
      _timer ??= Timer(delay, () => unawaited(load()));
    }
  }

  /// Downloads the file and keeps its files, once; nothing off the web,
  /// without locations or without the file among the assets.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final manifest = AssetProtocolResolver.rootManifest;
    if (!web ||
        locations.isEmpty ||
        (manifest != null && !manifest.listAssets().contains(file))) {
      return;
    }
    final watch = Stopwatch()..start();
    final String text;
    try {
      text = await bundle.loadString(file, cache: false);
    } on Object catch (error) {
      _log.warning('$file is not read: $error');
      return;
    }
    final lines = const LineSplitter().convert(text);
    var count = 0;
    final slice = Stopwatch()..start();
    for (final (i, line) in lines.indexed.skip(1)) {
      if (slice.elapsed >= _slice) {
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
      final files = (jsonDecode(line) as Map).cast<String, String>();
      Resources.registerAll({
        for (final MapEntry(:key, :value) in files.entries)
          key: EmbeddedResource.text(value),
      }, owner: '$_owner#$i');
      count += files.length;
    }
    _log.debug(
      () =>
          '$count files of $file in memory in ${watch.elapsedMilliseconds} ms',
    );
  }

  /// Stops a download not started yet.
  void stop() => _timer?.cancel();
}
