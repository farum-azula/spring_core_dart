import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The app's assets (`assets/` in pubspec.yaml) as injected resources:
/// `@Value('asset:...')` gives an `AssetResource`, as
/// `@Value('classpath:...')` gives a file of `lib/resources/` in Spring.
///
/// `@BuildContextAccess` generates the `context.appAssets` getter.
@Component()
@BuildContextAccess()
class AppAssets {
  AppAssets(
    @Value('asset:assets/images/leaf.png') this.logo,
    @Value('asset:assets/texts/about.txt') this.about,
  );

  /// The logo image.
  final Resource logo;

  /// The About page's text, in English; next to it `about_<language>.txt`
  /// for other languages.
  final Resource about;

  /// The logo for `Image`: Flutter's image APIs take the asset key.
  ImageProvider get logoImage => AssetImage((logo as AssetResource).key);

  final _texts = <String, Future<String>>{};

  /// The About text in [locale]'s language (`about_ja.txt` for Japanese),
  /// or the English one; read once, then kept.
  Future<String> aboutText(Locale locale) =>
      _texts.putIfAbsent(locale.languageCode, () async {
        if (locale.languageCode != 'en') {
          // A file next to about.txt, like Resource.createRelative in Spring.
          final translated = about.createRelative(
            'about_${locale.languageCode}.txt',
          );
          if (translated.exists()) {
            return (await translated.readAsString()).trim();
          }
        }
        return (await about.readAsString()).trim();
      });
}
