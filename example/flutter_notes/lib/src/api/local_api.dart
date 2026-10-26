import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// Where the app's API listens, for the screen: set when the server starts
/// (`WebServerInitializedEvent`, with the real port, also for
/// `server.port=0`) and cleared when it stops. In the background the
/// context pauses, so the server stops and frees the port; it starts again
/// when the app comes back.
@ChangeNotifierComponent()
class LocalApi {
  LocalApi(@Value(r'${server.address:127.0.0.1}') this._host);

  final String _host;
  String? _url;

  /// `http://127.0.0.1:8080/api/notes`, or `null` while no server runs.
  String? get url => _url;

  @EventListener()
  void started(WebServerInitializedEvent event) =>
      _url = 'http://$_host:${event.port}/api/notes';

  @EventListener()
  void stopped(ContextStoppedEvent event) => _url = null;
}
