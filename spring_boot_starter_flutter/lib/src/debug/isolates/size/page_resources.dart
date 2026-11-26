import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_masking.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/size/page_resources_stub.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_flutter/src/debug/isolates/size/page_resources_web.dart'
    as browser;

/// One download of the page, from the browser's Resource Timing
/// (`PerformanceResourceTiming`, the page itself
/// `PerformanceNavigationTiming`).
@immutable
final class PageResource {
  /// The download of [name].
  const PageResource({
    required this.name,
    required this.initiator,
    required this.transferSize,
    required this.decodedBodySize,
    required this.crossOrigin,
  });

  /// Its address, as the browser tells it; shown only [masked].
  final String name;

  /// [address] with its credentials masked as the network recorder masks
  /// an address: the user-info password and the secret query parameters
  /// (`?token=******`, a signed address's `signature`).
  static String masked(String address) => const NetworkMasking().text(address);

  /// What fetched it (`navigation`, `script`, `fetch`, `img`).
  final String initiator;

  /// The bytes that came over the network, headers included; `0` from
  /// the cache, or from another origin without `Timing-Allow-Origin`.
  final int transferSize;

  /// The body's bytes once decoded (unzipped).
  final int decodedBodySize;

  /// Whether it came from another origin than the page's.
  final bool crossOrigin;

  /// Whether the browser hides its sizes: from another origin without
  /// `Timing-Allow-Origin`, it tells `0` for both.
  bool get hidden => crossOrigin && transferSize == 0 && decodedBodySize == 0;

  /// Whether it came from the browser's cache: nothing transferred, a
  /// body all the same.
  bool get cached => transferSize == 0 && decodedBodySize > 0;

  /// The bigger of its two sizes, what it is ranked by.
  int get weight =>
      transferSize > decodedBodySize ? transferSize : decodedBodySize;
}

/// A kind of download the size block totals apart: its [name] and the
/// endings of the addresses ([extensions]) or the initiators that are of
/// it.
@immutable
final class PageResourceKind {
  /// The kind [name] of [extensions] and [initiators].
  const PageResourceKind(
    this.name, {
    this.extensions = const [],
    this.initiators = const [],
  });

  /// Its name (`code`, `fonts`).
  final String name;

  /// The endings of the addresses of it (`.js`).
  final List<String> extensions;

  /// The initiators of it (`script`, `navigation`).
  final List<String> initiators;

  /// Whether [resource] is of it.
  bool matches(PageResource resource) {
    final path = Uri.tryParse(resource.name)?.path.toLowerCase() ?? '';
    return initiators.contains(resource.initiator) ||
        extensions.any(path.endsWith);
  }
}

/// The kinds of downloads, asked in order: the first that matches a
/// download is its kind, `other` when none does.
const pageResourceKinds = <PageResourceKind>[
  PageResourceKind(
    'code',
    extensions: ['.js', '.mjs', '.wasm', '.css', '.html'],
    initiators: ['navigation', 'script'],
  ),
  PageResourceKind('fonts', extensions: ['.woff2', '.woff', '.ttf', '.otf']),
  PageResourceKind(
    'images',
    extensions: [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.avif',
      '.svg',
      '.ico',
      '.bmp',
    ],
    initiators: ['img', 'image'],
  ),
];

/// The name of [resource]'s kind among [kinds]; `other` when none
/// matches.
String pageResourceKindOf(
  PageResource resource, [
  List<PageResourceKind> kinds = pageResourceKinds,
]) =>
    kinds.where((kind) => kind.matches(resource)).firstOrNull?.name ?? 'other';

/// What the page downloaded, from the browser's Resource Timing: web
/// only ([platform] is `null` elsewhere).
abstract interface class PageResources {
  /// The browser's; `null` outside a browser or in one without Resource
  /// Timing.
  static PageResources? platform() => browser.pageResources();

  /// Every download the browser kept, the page first.
  List<PageResource> read();

  /// Whether the browser's list was full: it adds no entry past its
  /// buffer (250 unless raised), so later downloads are missing.
  bool get full;
}
