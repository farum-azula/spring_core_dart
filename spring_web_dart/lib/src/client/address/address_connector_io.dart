import 'dart:io' as io;

import 'package:spring_web_dart/src/client/address/allowed_addresses.dart';
import 'package:spring_web_dart/src/client/address/ip_address.dart';

/// The `HttpClient.connectionFactory` of an `IoHttpTransport` with
/// [allowed]: it resolves the host itself, keeps the addresses [allowed]
/// lets through and connects to them in order until one answers (as
/// `Socket.connect` does for a name: `localhost` is `::1` and then
/// `127.0.0.1`), so the address checked is the address connected to (a
/// second lookup cannot return another: DNS rebinding). An `https`
/// connection is then secured for the host name, with [context] and
/// [onBadCertificate]. [lookup] resolves names (`InternetAddress.lookup`
/// by default).
///
/// Through a proxy it connects to the proxy as configured: the target's
/// name was checked, its addresses are the proxy's business.
Future<io.ConnectionTask<io.Socket>> Function(Uri, String?, int?)
checkedConnectionFactory(
  AllowedAddresses allowed, {
  io.SecurityContext? context,
  bool Function(io.X509Certificate certificate, String host, int port)?
  onBadCertificate,
  Future<List<io.InternetAddress>> Function(String host)? lookup,
}) => (url, proxyHost, proxyPort) async {
  if (proxyHost != null && proxyPort != null) {
    return await io.Socket.startConnect(proxyHost, proxyPort);
  }
  final host = url.host;
  final port = url.port;
  final literal = IpAddress.tryParse(host);
  final candidates = literal != null
      ? [io.InternetAddress.fromRawAddress(literal.bytes)]
      : await (lookup ?? io.InternetAddress.lookup)(host);
  final allowedAddresses = allowed.allowedAddressesOf(host, [
    for (final candidate in candidates)
      IpAddress.fromBytes(candidate.rawAddress),
  ]);
  final targets = [
    for (final address in allowedAddresses)
      candidates.firstWhere(
        (candidate) => IpAddress.fromBytes(candidate.rawAddress) == address,
      ),
  ];
  final task = targets.length == 1
      ? await io.Socket.startConnect(targets.single, port)
      : _firstThatConnects(targets, port);
  if (url.scheme != 'https') {
    return task;
  }
  final secured = task.socket.then(
    (socket) => io.SecureSocket.secure(
      socket,
      host: host,
      context: context,
      onBadCertificate: onBadCertificate == null
          ? null
          : (certificate) => onBadCertificate(certificate, host, port),
    ),
  );
  return io.ConnectionTask.fromSocket(secured, task.cancel);
};

// A connection to the first of [targets] that accepts one, tried one after
// the other; cancelling gives up the attempt under way and the rest.
io.ConnectionTask<io.Socket> _firstThatConnects(
  List<io.InternetAddress> targets,
  int port,
) {
  io.ConnectionTask<io.Socket>? attempt;
  var cancelled = false;
  Future<io.Socket> connect() async {
    Object? failure;
    StackTrace? failureStack;
    for (final target in targets) {
      if (cancelled) {
        break;
      }
      final current = attempt = await io.Socket.startConnect(target, port);
      try {
        return await current.socket;
      } on io.SocketException catch (error, stackTrace) {
        failure = error;
        failureStack = stackTrace;
      }
    }
    if (failure == null) {
      throw const io.SocketException('Connection attempt cancelled');
    }
    Error.throwWithStackTrace(failure, failureStack!);
  }

  return io.ConnectionTask.fromSocket(connect(), () {
    cancelled = true;
    attempt?.cancel();
  });
}
