import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The language the user picked in Settings; `null` follows the device.
/// The app's languages are those of `lib/resources/messages*.properties`
/// (English and Japanese).
@ChangeNotifierComponent()
@BuildContextAccess()
class LanguageSelection {
  String? _languageCode;

  /// `en`, `ja`, or `null` for the device's language.
  String? get languageCode => _languageCode;

  void select(String? languageCode) => _languageCode = languageCode;
}

/// Puts the picked language over the app: `spring.flutter.app.*` has no
/// property for the locale, so a `FlutterAppCustomizer` bean wraps every
/// route (`MaterialApp.builder`) in `Localizations.override`. Texts from
/// `context.message` and Flutter's own widgets follow at once.
@Component()
class LanguageCustomizer implements FlutterAppCustomizer {
  LanguageCustomizer(this._selection);

  final LanguageSelection _selection;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) => ListenableBuilder(
      listenable: listenableOf(_selection),
      builder: (context, _) {
        final content = inner == null ? child! : inner(context, child);
        final code = _selection.languageCode;
        return code == null
            ? content
            : Localizations.override(
                context: context,
                locale: Locale(code),
                child: content,
              );
      },
    );
  }
}
