import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// An [ImageProvider] of a resource by its location, for Flutter's own
/// widgets that take one (`DecorationImage`, `CircleAvatar`,
/// `precacheImage`): an `https:` image is read through the resources'
/// cache, kept on disk across starts, an `asset:` or `resources:` one from
/// the app.
///
/// ```dart
/// CircleAvatar(backgroundImage: ResourceImage(player.avatarUrl))
/// ```
///
/// It reads with the running application's `ResourceLoader`, as
/// `AssetImage` reads with `rootBundle`; [ResourceImage.using] gives one of
/// its own (a test). Two with one location and scale are one image in
/// Flutter's image cache.
@immutable
final class ResourceImage extends ImageProvider<ResourceImage> {
  /// The image at [location], drawn at [scale] device pixels a logical one.
  const ResourceImage(this.location, {this.scale = 1}) : _loader = null;

  /// The image at [location] read by [loader].
  const ResourceImage.using(
    ResourceLoader loader,
    this.location, {
    this.scale = 1,
  }) : _loader = loader;

  /// Where the image is: `https://…`, `asset:assets/…`, `resources:…`.
  final String location;

  /// The device pixels a logical one of the image.
  final double scale;

  final ResourceLoader? _loader;

  /// The running application's loader; set by the starter when the
  /// application starts.
  static ResourceLoader? application;

  @override
  Future<ResourceImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ResourceImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: key.scale,
    debugLabel: key.location,
    informationCollector: () => [
      DiagnosticsProperty<String>('Location', key.location),
    ],
  );

  static Future<ui.Codec> _load(
    ResourceImage key,
    ImageDecoderCallback decode,
  ) async {
    final loader =
        key._loader ??
        application ??
        (throw StateError(
          'ResourceImage(${key.location}): no application runs; '
          'ResourceImage.using(loader, location) reads without one',
        ));
    final bytes = await loader.getResource(key.location).readAsBytes();
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is ResourceImage &&
      other.location == location &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(location, scale);

  @override
  String toString() => 'ResourceImage("$location", scale: $scale)';
}
