// The side of LoopbackAuthorizationWindow without dart:io (a web page):
// nothing works. Internal.

const _message =
    'The app login does not run in a web page: log in on the server with '
    'oauth2Login() of spring_boot_starter_security (the page keeps only '
    'the session cookie).';

/// Throws an [UnsupportedError]: no system browser to open from a page.
Future<void> openSystemBrowser(Uri uri) =>
    throw UnsupportedError('No system browser to open from a web page');

/// Throws an [UnsupportedError]: no server socket in a page.
Future<Uri> authorize({
  required Uri redirectUri,
  required Uri Function(Uri redirectUri) authorizationUri,
  required Future<void> Function(Uri uri) open,
  required Duration timeout,
}) => throw UnsupportedError(_message);
