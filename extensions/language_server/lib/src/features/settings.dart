import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';

/// Takes the settings the editor sends when the user changes them
/// (`workspace/didChangeConfiguration`), and has what depends on them
/// shown again.
final class Settings extends ServerFeature {
  /// The settings of [session].
  Settings(this.session);

  /// The session it serves.
  final SpringSession session;

  @override
  Map<String, NotificationHandler> get notifications => {
    'workspace/didChangeConfiguration': (params) {
      final settings = params['settings'];
      if (settings is! Map) {
        return;
      }
      session.settings = SessionSettings.from(settings);
      session.changed();
      if (session.refreshesInlayHints) {
        session.editor.request('workspace/inlayHint/refresh');
      }
    },
  };
}
