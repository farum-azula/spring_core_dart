import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_connection_manager.dart';

/// The address of a client, from [raw] (an annotation's `url` or the
/// configured one): its `${...}` placeholders resolved by [environment],
/// and checked to start with `ws://` or `wss://`.
///
/// What is wrong is added to [problems], [missing] when there is no
/// address at all, and `null` is returned. Internal to the starter (not
/// exported).
Uri? resolveClientUrl(
  Environment environment,
  String? raw,
  List<String> problems, {
  required String missing,
}) {
  if (raw == null || raw.trim().isEmpty) {
    problems.add(missing);
    return null;
  }
  final String resolved;
  try {
    resolved = environment.resolveRequiredPlaceholders(raw.trim());
  } on Object catch (error) {
    problems.add('cannot resolve the URL "$raw": $error');
    return null;
  }
  final url = Uri.tryParse(resolved);
  if (url == null || (url.scheme != 'ws' && url.scheme != 'wss')) {
    // A token in the query or a password must not reach the log.
    final shown = url == null ? redactText(resolved) : '${redactUrl(url)}';
    problems.add('the URL "$shown" must start with ws:// or wss://');
    return null;
  }
  return url;
}
