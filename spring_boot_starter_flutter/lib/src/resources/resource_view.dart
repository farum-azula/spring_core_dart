import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/resources/resource_cache.dart';
import 'package:spring_boot_starter_flutter/src/resources/resource_image.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';

/// What a [ResourceView] hands its renderer: the resource, its bytes, its
/// media type, and its location when it was given one.
typedef LoadedResource = ({
  Resource resource,
  Uint8List bytes,
  String mediaType,
  String? location,
});

/// Options of a renderer of its own for a [ResourceView]: a video's
/// `autoplay`, a document's page. The image renderer takes none.
class ResourceViewOptions {
  /// No options.
  const ResourceViewOptions();
}

/// How the [ResourceView] lays a resource out, given to every renderer.
typedef ResourceLayout = ({
  double? width,
  double? height,
  BoxFit? fit,
  AlignmentGeometry alignment,
  String? semanticLabel,
  ResourceViewOptions options,
});

/// Shows resources of some media types in a [ResourceView]: a bean. The
/// starter's shows images ([ImageResourceRenderer]); an app adds one for a
/// type of its own (a video, a document) as one more bean, asked before
/// the starter's.
abstract interface class ResourceRenderer {
  /// Whether it shows [mediaType] (`image/png`, `video/mp4`).
  bool supports(String mediaType);

  /// The widget of [resource], laid out by [layout].
  Widget build(
    BuildContext context,
    LoadedResource resource,
    ResourceLayout layout,
  );
}

/// Images: `image/*`.
final class ImageResourceRenderer implements ResourceRenderer {
  /// The renderer.
  const ImageResourceRenderer();

  @override
  bool supports(String mediaType) => mediaType.startsWith('image/');

  @override
  Widget build(
    BuildContext context,
    LoadedResource resource,
    ResourceLayout layout,
  ) => Image(
    // By location: one image in Flutter's cache for every view of it.
    image: switch (resource.location) {
      final location? => ResourceImage.using(
        _BytesLoader(location, resource.resource),
        location,
      ),
      null => MemoryImage(resource.bytes),
    },
    width: layout.width,
    height: layout.height,
    fit: layout.fit,
    alignment: layout.alignment,
    semanticLabel: layout.semanticLabel,
    excludeFromSemantics: layout.semanticLabel == null,
    gaplessPlayback: true,
  );
}

// The resource already read, for the image of a location.
final class _BytesLoader implements ResourceLoader {
  _BytesLoader(this.location, this.resource);

  final String location;
  final Resource resource;

  @override
  Resource getResource(String location) => resource;
}

/// A resource of any kind in the page, by its location or as a
/// [Resource]: an image now, a video or a document by a renderer of the
/// app's own ([ResourceRenderer]).
///
/// ```dart
/// ResourceView(player.avatarUrl, width: 40, height: 40, fit: BoxFit.cover,
///     shape: const CircleBorder(), placeholder: const AvatarPlaceholder())
/// ```
///
/// It reads the resource through the application's `ResourceLoader` (an
/// `https:` one kept on disk by the resources' cache,
/// `spring.flutter.resources.cache.*`), finds its media type (what the
/// server said, else the file's extension) and the first renderer that
/// shows it, and does the rest the same for every kind: [placeholder]
/// while it loads, [error] when it fails (else the placeholder again), the
/// fade over the placeholder (`spring.flutter.resources.view.fade`, none
/// when the system asks for less motion), the size, the [shape], the
/// [semanticLabel].
class ResourceView extends StatefulWidget {
  /// The resource at [location].
  const ResourceView(
    String this.location, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.shape,
    this.placeholder,
    this.error,
    this.semanticLabel,
    this.options = const ResourceViewOptions(),
  }) : resource = null;

  /// [resource] itself.
  const ResourceView.resource(
    Resource this.resource, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.shape,
    this.placeholder,
    this.error,
    this.semanticLabel,
    this.options = const ResourceViewOptions(),
  }) : location = null;

  /// Where the resource is.
  final String? location;

  /// The resource given.
  final Resource? resource;

  /// The width; `null`: the resource's or the parent's.
  final double? width;

  /// The height.
  final double? height;

  /// How it fills its box.
  final BoxFit? fit;

  /// Where it sits in its box.
  final AlignmentGeometry alignment;

  /// The shape it is clipped to (`CircleBorder` for an avatar).
  final ShapeBorder? shape;

  /// What shows while it loads.
  final Widget? placeholder;

  /// What shows when it cannot be shown; `null`: the placeholder.
  final Widget Function(BuildContext context, Object error)? error;

  /// What it is, for screen readers.
  final String? semanticLabel;

  /// Options of a renderer of the app's own.
  final ResourceViewOptions options;

  /// The media type of a file name's extension, `null` for none known.
  static String? mediaTypeOf(String? filename) {
    final name = filename?.toLowerCase() ?? '';
    final dot = name.lastIndexOf('.');
    return dot < 0 ? null : _extensions[name.substring(dot + 1)];
  }

  static const Map<String, String> _extensions = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'ico': 'image/x-icon',
    'svg': 'image/svg+xml',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'mp3': 'audio/mpeg',
    'json': 'application/json',
    'pdf': 'application/pdf',
  };

  @override
  State<ResourceView> createState() => _ResourceViewState();
}

class _ResourceViewState extends State<ResourceView> {
  Future<LoadedResource>? _loading;
  Object? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ResourceView old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final source = widget.location ?? widget.resource;
    if (source == _source && _loading != null) {
      return;
    }
    _source = source;
    final context = SpringScope.maybeOf(this.context);
    final resource =
        widget.resource ??
        (context ?? ResourceImage.application)?.getResource(widget.location!);
    _loading = resource == null
        ? Future.error(
            StateError('ResourceView(${widget.location}): no application runs'),
          )
        : _read(resource);
  }

  Future<LoadedResource> _read(Resource resource) async {
    final bytes = await resource.readAsBytes();
    final given = resource is CachedResource ? resource.contentType : null;
    final location = widget.location;
    final mediaType =
        _bare(given) ??
        ResourceView.mediaTypeOf(resource.filename) ??
        ResourceView.mediaTypeOf(resource.uri?.path) ??
        ResourceView.mediaTypeOf(
          location == null ? null : Uri.tryParse(location)?.path ?? location,
        ) ??
        'application/octet-stream';
    return (
      resource: resource,
      bytes: bytes,
      mediaType: mediaType,
      location: widget.location,
    );
  }

  // `image/png; charset=…` → `image/png`.
  static String? _bare(String? type) =>
      type?.split(';').first.trim().toLowerCase();

  List<ResourceRenderer> _renderers() {
    final context = SpringScope.maybeOf(this.context);
    return [
      if (context != null)
        ...context.getBeanProvider<ResourceRenderer>().orderedList().where(
          (renderer) => renderer is! ImageResourceRenderer,
        ),
      const ImageResourceRenderer(),
    ];
  }

  Duration _fade(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Duration.zero;
    }
    final scope = SpringScope.maybeOf(context);
    return scope
            ?.getBeanProvider<FlutterResourcesViewProperties>()
            .getIfAvailable()
            ?.fade ??
        const Duration(milliseconds: 200);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder =
        widget.placeholder ??
        SizedBox(width: widget.width, height: widget.height);
    final view = FutureBuilder<LoadedResource>(
      future: _loading,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.hasError) {
          child = KeyedSubtree(
            key: const ValueKey('error'),
            child: widget.error?.call(context, snapshot.error!) ?? placeholder,
          );
        } else if (snapshot.data case final loaded?) {
          final renderer = _renderers()
              .where(
                (renderer) => renderer.supports(loaded.mediaType),
              )
              .firstOrNull;
          child = KeyedSubtree(
            key: ValueKey(loaded.resource),
            child: renderer == null
                ? (widget.error?.call(
                        context,
                        UnsupportedError(
                          'no ResourceRenderer shows ${loaded.mediaType}',
                        ),
                      ) ??
                      placeholder)
                : renderer.build(context, loaded, (
                    width: widget.width,
                    height: widget.height,
                    fit: widget.fit,
                    alignment: widget.alignment,
                    semanticLabel: widget.semanticLabel,
                    options: widget.options,
                  )),
          );
        } else {
          child = KeyedSubtree(
            key: const ValueKey('placeholder'),
            child: placeholder,
          );
        }
        return AnimatedSwitcher(
          duration: _fade(context),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            children: [...previous, ?current],
          ),
          child: child,
        );
      },
    );
    final shape = widget.shape;
    return shape == null
        ? view
        : ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: view,
          );
  }
}
