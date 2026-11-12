import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// A ThemeImage on screen. Its `listenable` gives the picture to paint: the
/// asset, or for a network image the cache, else the fallback, else nothing
/// until the download ends.
class ThemePicture extends StatelessWidget {
  const ThemePicture(
    this.image, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final ThemeImage image;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ImageProvider?>(
    valueListenable: image.listenable,
    builder: (context, provider, _) => provider == null
        ? SizedBox(width: width, height: height)
        : Image(image: provider, width: width, height: height, fit: fit),
  );
}
