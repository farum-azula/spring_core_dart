import 'package:spring_boot_dart/spring_boot_dart.dart';

/// How the native title bar of a desktop window looks: the value of
/// `spring.flutter.desktop.window.title-bar`.
enum TitleBarStyle {
  /// The OS's own title bar (`default`); the window is left untouched.
  defaultStyle('default'),

  /// The content is drawn under a transparent title bar and the window
  /// buttons stay over it (`transparent`). On Linux (GTK) a header bar
  /// cannot be drawn under: it becomes a flat, titleless one of its own.
  transparent('transparent'),

  /// No title bar at all (`hidden`): the window buttons are hidden where
  /// the OS allows it, and the app draws its own and moves the window with
  /// a `WindowDragArea`.
  hidden('hidden');

  const TitleBarStyle(this.propertyValue);

  /// The text of the property.
  final String propertyValue;

  /// The style named [value] (case does not matter); throws an
  /// [ArgumentError] naming [DesktopWindowSettings.titleBarProperty] and
  /// the allowed values for any other.
  static TitleBarStyle parse(String value) {
    final wanted = value.trim().toLowerCase();
    for (final style in values) {
      if (style.propertyValue == wanted) {
        return style;
      }
    }
    throw ArgumentError.value(
      value,
      DesktopWindowSettings.titleBarProperty,
      'Must be one of ${values.map((v) => v.propertyValue).join(', ')}',
    );
  }
}

/// A window size in logical pixels: the value of
/// `spring.flutter.desktop.window.initial-size` and `min-size`.
final class WindowSize {
  /// A size of [width] by [height] logical pixels, both positive.
  const WindowSize(this.width, this.height)
    : assert(width > 0 && height > 0, 'A window size is positive');

  /// The width in logical pixels.
  final double width;

  /// The height in logical pixels.
  final double height;

  static final _format = RegExp(
    r'^(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)$',
  );

  /// Reads `<width>x<height>` (`1280x800`); throws an [ArgumentError]
  /// naming [property] and the expected format for anything else
  /// (`1280x`, `-1x5`, `0x600`).
  static WindowSize parse(String value, {required String property}) {
    final match = _format.firstMatch(value.trim());
    final width = match == null ? null : double.parse(match[1]!);
    final height = match == null ? null : double.parse(match[2]!);
    if (width == null || height == null || width <= 0 || height <= 0) {
      throw ArgumentError.value(
        value,
        property,
        'Expected <width>x<height> in logical pixels, positive, '
        'such as 1280x800',
      );
    }
    return WindowSize(width, height);
  }

  @override
  bool operator ==(Object other) =>
      other is WindowSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${_number(width)}x${_number(height)}';

  static String _number(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}

/// The window of a desktop app as `spring.flutter.desktop.window.*` sets it.
///
/// Internal to the starter; read once while the application starts.
final class DesktopWindowSettings {
  /// Settings for a test or an app that knows them. Throws a
  /// [StateError] when [initialSize] is smaller than [minSize].
  DesktopWindowSettings({
    this.titleBar = TitleBarStyle.defaultStyle,
    this.initialSize,
    this.minSize,
  }) {
    final initial = initialSize;
    final min = minSize;
    if (initial != null &&
        min != null &&
        (initial.width < min.width || initial.height < min.height)) {
      throw StateError(
        '$initialSizeProperty=$initial is smaller than '
        '$minSizeProperty=$min: the window could not open with it.',
      );
    }
  }

  /// `spring.flutter.desktop.window.title-bar`.
  static const titleBarProperty = 'spring.flutter.desktop.window.title-bar';

  /// `spring.flutter.desktop.window.initial-size`.
  static const initialSizeProperty =
      'spring.flutter.desktop.window.initial-size';

  /// `spring.flutter.desktop.window.min-size`.
  static const minSizeProperty = 'spring.flutter.desktop.window.min-size';

  /// Reads the three properties of [environment]; a missing or empty one
  /// is its default. Throws for a malformed value (naming the key and the
  /// expected format) and for an initial size below the minimum.
  factory DesktopWindowSettings.fromEnvironment(Environment environment) {
    String? read(String key) {
      final text = environment.getProperty(key)?.trim() ?? '';
      return text.isEmpty ? null : text;
    }

    final titleBar = read(titleBarProperty);
    final initial = read(initialSizeProperty);
    final min = read(minSizeProperty);
    return DesktopWindowSettings(
      titleBar: titleBar == null
          ? TitleBarStyle.defaultStyle
          : TitleBarStyle.parse(titleBar),
      initialSize: initial == null
          ? null
          : WindowSize.parse(initial, property: initialSizeProperty),
      minSize: min == null
          ? null
          : WindowSize.parse(min, property: minSizeProperty),
    );
  }

  /// The title bar, `default` when not set.
  final TitleBarStyle titleBar;

  /// The size the window opens with, or null: the runner's.
  final WindowSize? initialSize;

  /// The smallest size the user can drag the window to, or null.
  final WindowSize? minSize;

  /// Whether nothing is set: the window stays as the runner made it.
  bool get isEmpty =>
      titleBar == TitleBarStyle.defaultStyle &&
      initialSize == null &&
      minSize == null;

  @override
  String toString() =>
      'DesktopWindowSettings(titleBar: ${titleBar.propertyValue}, '
      'initialSize: $initialSize, minSize: $minSize)';
}
