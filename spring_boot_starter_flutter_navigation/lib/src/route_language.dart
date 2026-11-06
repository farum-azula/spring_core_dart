import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';

/// Puts the language of the address over the app
/// (`spring.flutter.navigation.languages`): `/ja/catalog` shows the app in
/// Japanese, `context.message` and Flutter's own widgets included. Nothing
/// changes without languages.
///
/// The navigation starter declares it; it wraps the app's `builder`.
final class RouteLanguageCustomizer implements FlutterAppCustomizer {
  /// The customizer of [navigation]'s language.
  RouteLanguageCustomizer(this.navigation);

  /// The navigation whose language the app shows.
  final Navigation navigation;

  @override
  void customize(FlutterAppSettings app) {
    if (navigation.languages.isEmpty) {
      return;
    }
    final inner = app.builder;
    app.builder = (context, child) => ValueListenableBuilder<String?>(
      valueListenable: navigation.languageListenable,
      builder: (context, language, _) {
        final content = inner == null ? child! : inner(context, child);
        return language == null
            ? content
            : Localizations.override(
                context: context,
                locale: localeOf(language),
                child: content,
              );
      },
    );
  }

  /// The locale of a language tag: `ja`, `pt-BR`, `zh-Hant`.
  static Locale localeOf(String tag) {
    final parts = tag.split(RegExp('[_-]'));
    if (parts.length == 1) {
      return Locale(parts.first);
    }
    return parts[1].length == 4
        ? Locale.fromSubtags(languageCode: parts.first, scriptCode: parts[1])
        : Locale(parts.first, parts[1]);
  }
}
