import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_security/src/login/oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/screens/login_design.dart';
import 'package:spring_boot_starter_flutter_security/src/screens/login_form.dart';
import 'package:spring_boot_starter_flutter_security/src/window/authorization_window.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    hide Banner, Size;

/// Starts the login of a registration; the result is the user, or `null`
/// (a browser leaves for the login page).
typedef OAuth2LoginAction = Future<Authentication?> Function(
  String registrationId,
);

/// Draws an [OAuth2LoginButton] of one's own: call [onPressed] (`null`
/// while the login runs) and show progress while [busy].
typedef OAuth2LoginButtonBuilder = Widget Function(
  BuildContext context,
  VoidCallback? onPressed,
  bool busy,
);

/// A button that logs the user in with one registration of the
/// configuration (`spring.security.oauth2.client.registration.<id>.*`):
/// it calls `OAuth2LoginService.login(registrationId)`, shows progress
/// while the login runs, and reports how it ended.
///
/// Use it for any provider: `OAuth2LoginButton('keycloak')` on a
/// company's SSO, one button per registration on a login screen. Google,
/// Apple, Microsoft and GitHub have ready buttons in their own look
/// ([GoogleLoginButton], [AppleLoginButton], [MicrosoftLoginButton],
/// [GitHubLoginButton]), built on this one. Which login runs is the
/// service's business: the system's login window on phones and desktops,
/// the server's login in a browser, the native Apple sheet for Apple on
/// iOS and macOS. The button names no provider endpoint.
///
/// How it ends:
///
/// - the user logged in: [onSuccess] with the authentication (`null` in a
///   browser, where the page leaves for the login and the app starts
///   again afterwards);
/// - the user closed the login window (`AuthorizationCancelledException`):
///   nothing, the button is ready again;
/// - anything else (the provider refused, the network): [onError] with
///   the error; without an [onError] the error goes to
///   `FlutterError.reportError` (no token or code is in it).
///
/// Its label is "Sign in with _client name_": the registration's
/// `client-name` property, else the name of a common provider
/// (`google` → Google, `github` → GitHub), else the registration id.
/// The text is the message `login-button.oauth2` (`Sign in with {0}`),
/// or [label]. Its look follows the app ([LoginDesign]): a filled
/// button of the Material or Cupertino theme, or a plain one; [builder]
/// draws one of one's own.
///
/// ```dart
/// // The company's single sign-on; the screen closes after the login.
/// OAuth2LoginButton(
///   'keycloak',
///   icon: const Icon(Icons.key),
///   onSuccess: (_) => Navigator.of(context).pop(),
///   onError: (error) => setState(() => _error = '$error'),
/// )
/// ```
///
/// Spring has no widget; the nearest is the list of links
/// (`/oauth2/authorization/{registrationId}`) on the login page of
/// Spring Security's `oauth2Login()`, labelled with each registration's
/// client name.
class OAuth2LoginButton extends StatefulWidget {
  /// A button logging in with [registrationId].
  const OAuth2LoginButton(
    this.registrationId, {
    this.label,
    this.icon,
    this.onSuccess,
    this.onError,
    this.additionalParameters = const {},
    this.loginService,
    this.login,
    this.design,
    this.builder,
    super.key,
  });

  /// The registration to log in with, as in the properties
  /// (`spring.security.oauth2.client.registration.<id>.*`).
  final String registrationId;

  /// The button's text; "Sign in with _client name_" by default.
  final String? label;

  /// Drawn before the text (replaced by a spinner while the login runs).
  final Widget? icon;

  /// Called after the login with the user (`null` in a browser).
  final ValueChanged<Authentication?>? onSuccess;

  /// Called when the login failed, not when the user closed the window.
  final ValueChanged<Object>? onError;

  /// Sent to the provider's page (`prompt=login`, `login_hint=...`).
  final Map<String, String> additionalParameters;

  /// The login service; the application's `OAuth2LoginService` bean by
  /// default.
  final OAuth2LoginService? loginService;

  /// Runs the login instead of the service, for an app whose own service
  /// wraps it (and publishes events of its own).
  final OAuth2LoginAction? login;

  /// The look; the app's ([LoginDesign.of]) by default.
  final LoginDesign? design;

  /// Draws the button instead of the design: the brand buttons do.
  final OAuth2LoginButtonBuilder? builder;

  /// The name shown for [registrationId]: its `client-name` property in
  /// [environment], else a common provider's name (`Google`, `GitHub`,
  /// `Facebook`, `Okta`), else the id itself (Spring's default client
  /// name). Reads no registration, so no discovery request is made.
  static String clientName(String registrationId, Environment? environment) {
    final configured = environment
        ?.getProperty(
          'spring.security.oauth2.client.registration.$registrationId.client-name',
        )
        ?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    final provider = CommonOAuth2Provider.of(registrationId);
    if (provider != null) {
      try {
        // The provider's own name (Google, GitHub, Apple, ...); the
        // client id is only there for the builder to build.
        return provider
            .getBuilder(registrationId)
            .clientId('-')
            .build()
            .clientName;
      } on Object {
        // A provider whose registration needs more (an issuer).
      }
    }
    return registrationId;
  }

  @override
  State<OAuth2LoginButton> createState() => _OAuth2LoginButtonState();
}

class _OAuth2LoginButtonState extends State<OAuth2LoginButton> {
  var _busy = false;

  Future<void> _press() async {
    if (_busy) {
      return;
    }
    final login = widget.login ?? _serviceLogin();
    setState(() => _busy = true);
    try {
      final result = await login(widget.registrationId);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      widget.onSuccess?.call(result);
    } on AuthorizationCancelledException {
      // The user closed the provider's page: no error.
      if (mounted) {
        setState(() => _busy = false);
      }
    } on Object catch (error, stack) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      if (widget.onError case final onError?) {
        onError(error);
      } else {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'spring_boot_starter_flutter_security',
            context: ErrorDescription(
              'while logging in with ${widget.registrationId}',
            ),
          ),
        );
      }
    }
  }

  OAuth2LoginAction _serviceLogin() {
    final service =
        widget.loginService ??
        SpringScope.maybeOf(
          context,
          listen: false,
        )?.findBean<OAuth2LoginService>() ??
        (throw StateError(
          'OAuth2LoginButton needs an OAuth2LoginService: configure a '
          'registration (spring.security.oauth2.client.registration.'
          '${widget.registrationId}.*) or pass loginService',
        ));
    return (id) =>
        service.login(id, additionalParameters: widget.additionalParameters);
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = _busy ? null : _press;
    if (widget.builder case final builder?) {
      return builder(context, onPressed, _busy);
    }
    final label =
        widget.label ??
        loginMessage(context, 'login-button.oauth2', 'Sign in with {0}', [
          OAuth2LoginButton.clientName(
            widget.registrationId,
            SpringScope.maybeOf(context)?.environment,
          ),
        ]);
    final icon = widget.icon;
    switch (widget.design ?? LoginDesign.of(context)) {
      case LoginDesign.material:
        const spinner = SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        final text = Text(label);
        return Semantics(
          value: _busy ? '…' : null,
          child: icon == null
              ? FilledButton(
                  onPressed: onPressed,
                  child: _busy ? Semantics(label: label, child: spinner) : text,
                )
              : FilledButton.icon(
                  onPressed: onPressed,
                  icon: _busy ? spinner : icon,
                  label: text,
                ),
        );
      case LoginDesign.cupertino:
        return Semantics(
          value: _busy ? '…' : null,
          child: CupertinoButton.filled(
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy) const CupertinoActivityIndicator() else ?icon,
                if (_busy || icon != null) const SizedBox(width: 8),
                Flexible(child: Text(label)),
              ],
            ),
          ),
        );
      case LoginDesign.widgets:
        return PlainLoginButton(
          label: label,
          onPressed: onPressed,
          busy: _busy,
          icon: icon ?? (_busy ? const SizedBox.shrink() : null),
        );
    }
  }
}
