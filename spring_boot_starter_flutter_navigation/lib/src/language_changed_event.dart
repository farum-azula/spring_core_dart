import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The app's language switched: the address got another language's prefix
/// (`/ja/...`), or `RouteTemplate.switchLanguage` was called. Published by
/// the navigation; listen with `@EventListener` to act on it (load the
/// language's data, log it).
///
/// ```dart
/// @Component()
/// class LanguageLog {
///   @EventListener()
///   void changed(LanguageChangedEvent event) =>
///       _log.info('${event.from} -> ${event.to}');
/// }
/// ```
///
/// The texts of the screens change with it; `ThemeText` changes them the
/// theme's way (`motion.text-change`).
final class LanguageChangedEvent extends ApplicationEvent {
  /// The language changed from [from] to [to] in the navigation [source].
  LanguageChangedEvent(super.source, {required this.from, required this.to});

  /// The language before, `null` before the first one was set.
  final String? from;

  /// The language now.
  final String to;

  @override
  String toString() => 'LanguageChangedEvent[$from -> $to]';
}
