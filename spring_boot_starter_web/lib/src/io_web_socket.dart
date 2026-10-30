import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.server');

/// Accepts the WebSocket handshake of [request] and returns the open
/// session at [uri], with the server's limits.
///
/// `dart:io`'s `WebSocketTransformer` assembles messages of any size and
/// negotiates permessage-deflate; it has only a per-frame limit, which a
/// message in many frames passes. So the handshake is answered here, and
/// the session counts the client's frames before `dart:io` sees them: a
/// text message over [maxText] bytes, or a binary one over [maxBinary]
/// bytes (`-1`: no limit), is dropped unread and the session is closed
/// with 1009 (message too big), as Tomcat does. No extension is
/// negotiated (no permessage-deflate). What the session sends may wait in
/// memory up to [sendBufferSizeLimit] bytes and for [sendTimeLimit]; past
/// either the connection is dropped
/// (`IoWebSocketSession.fromUpgradedSocket`). [request] must be a valid
/// handshake ([asksForWebSocket], [checkWebSocketHandshake]).
Future<IoWebSocketSession> upgradeWebSocket(
  io.HttpRequest request,
  Uri uri, {
  required String? protocol,
  required int maxText,
  required int maxBinary,
  required int sendBufferSizeLimit,
  required Duration? sendTimeLimit,
}) async {
  final key = request.headers['Sec-WebSocket-Key']!.single.trim();
  final response = request.response
    ..statusCode = io.HttpStatus.switchingProtocols
    ..headers.add(io.HttpHeaders.connectionHeader, 'Upgrade')
    ..headers.add(io.HttpHeaders.upgradeHeader, 'websocket')
    ..headers.add('Sec-WebSocket-Accept', webSocketAccept(key));
  if (protocol != null) {
    response.headers.add('Sec-WebSocket-Protocol', protocol);
  }
  // A 101 has no body: neither Content-Length (RFC 9110 §8.6) nor
  // dart:io's default Transfer-Encoding: chunked.
  response.headers.chunkedTransferEncoding = false;
  final raw = await response.detachSocket();
  final session = IoWebSocketSession.fromUpgradedSocket(
    raw,
    uri,
    serverSide: true,
    protocol: protocol,
    maxTextMessageSize: maxText,
    maxBinaryMessageSize: maxBinary,
    sendBufferSizeLimit: sendBufferSizeLimit,
    sendTimeLimit: sendTimeLimit,
  );
  unawaited(
    session.done.then((_) {
      final status = session.closeStatus;
      if (status != null && status.equalsCode(CloseStatus.sessionNotReliable)) {
        _log.warning(
          'WebSocket session at ${uri.path} dropped: ${status.reason}',
        );
      } else if (status != null &&
          status.equalsCode(CloseStatus.tooBigToProcess)) {
        _log.debug(
          'WebSocket session at ${uri.path} closed with 1009: a message '
          'was larger than the limit',
        );
      }
    }),
  );
  return session;
}

/// Whether [request] asks to open a WebSocket: a `GET` with
/// `Connection: Upgrade` and `Upgrade: websocket` (each may be a list,
/// or sent twice). Unlike `dart:io`'s
/// `WebSocketTransformer.isUpgradeRequest`, it never throws for a header
/// sent twice; [checkWebSocketHandshake] checks the rest.
bool asksForWebSocket(io.HttpRequest request) {
  bool hasToken(String name, String token) =>
      (request.headers[name] ?? const <String>[]).any(
        (value) =>
            value.split(',').any((part) => part.trim().toLowerCase() == token),
      );
  return request.method == 'GET' &&
      hasToken(io.HttpHeaders.connectionHeader, 'upgrade') &&
      hasToken(io.HttpHeaders.upgradeHeader, 'websocket');
}

/// Checks the rest of a WebSocket handshake (RFC 6455 §4.2.1): one
/// `Sec-WebSocket-Key` of 16 bytes in base64, and one
/// `Sec-WebSocket-Version` of 13. Throws an [ErrorResponseException]: a
/// 400 for a missing, repeated or malformed key or a repeated version, a
/// 426 with `Sec-WebSocket-Version: 13` for another version, as Tomcat
/// and Spring answer.
void checkWebSocketHandshake(io.HttpRequest request) {
  Never refuse(String detail) =>
      throw ResponseStatusException(HttpStatus.badRequest, detail);
  final versions = request.headers['Sec-WebSocket-Version'] ?? const [];
  if (versions.length > 1) {
    refuse('The Sec-WebSocket-Version header is sent more than once');
  }
  if (versions.isEmpty || versions.single.trim() != '13') {
    throw ErrorResponseException(
      HttpStatus.upgradeRequired,
      body: ProblemDetail.forStatusAndDetail(
        HttpStatus.upgradeRequired,
        'Only WebSocket version 13 is supported',
      ),
      headers: HttpHeaders({'Sec-WebSocket-Version': '13'}),
    );
  }
  final keys = request.headers['Sec-WebSocket-Key'] ?? const [];
  if (keys.isEmpty) {
    refuse('The Sec-WebSocket-Key header is missing');
  }
  if (keys.length > 1) {
    refuse('The Sec-WebSocket-Key header is sent more than once');
  }
  if (!isValidWebSocketKey(keys.single)) {
    refuse('The Sec-WebSocket-Key header is not 16 bytes in base64');
  }
}

/// Whether [key] is a valid `Sec-WebSocket-Key`: 16 bytes in base64
/// (24 characters), as RFC 6455 asks and Tomcat checks.
bool isValidWebSocketKey(String key) {
  final text = key.trim();
  if (text.length != 24) {
    return false;
  }
  try {
    return base64.decode(text).length == 16;
  } on FormatException {
    return false;
  }
}
