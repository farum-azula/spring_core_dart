import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_security/src/login/oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/screens/brand_logos.dart';
import 'package:spring_boot_starter_flutter_security/src/screens/login_design.dart';
import 'package:spring_boot_starter_flutter_security/src/screens/oauth2_login_button.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show Authentication;

// The four ready buttons. Each is an OAuth2LoginButton of a registration
// (whose id may be any) drawn in the provider's look, as its sign-in
// branding rules fix it: colours, logo, font, size, padding and the
// allowed texts. What the rules let an app choose (a theme, a shape, a
// text) is a parameter; nothing else is, because a button that breaks the
// rules gets an app rejected in review (Apple) or breaks its terms of use
// (Google). Sources in the README, section "Login screens".

/// The colours of a [GoogleLoginButton], the three of Google's branding
/// guidelines.
enum GoogleButtonTheme {
  /// White with a grey outline, dark text: on light backgrounds.
  light,

  /// Near-black with a grey outline, light text: on dark backgrounds.
  dark,

  /// Light grey without an outline, dark text.
  neutral,
}

/// The shape of a [GoogleLoginButton] or [GitHubLoginButton].
enum LoginButtonShape {
  /// Slightly rounded corners (Google: 4, GitHub: 6 logical pixels).
  rectangular,

  /// Fully rounded ends (a circle when icon-only).
  pill,
}

/// What a brand button says: the texts the providers allow.
enum LoginButtonText {
  /// "Sign in with ...".
  signIn,

  /// "Sign up with ...".
  signUp,

  /// "Continue with ...".
  continueWith,
}

/// The "Sign in with Google" button, in the look Google's branding
/// guidelines fix, logging in with the registration [registrationId]
/// (`google` by default) through `OAuth2LoginService`.
///
/// Google asks apps that offer its login to show this button: the
/// full-colour "G" at 20 × 20 (never recoloured or resized), Google Sans
/// Medium 14/20, one of three themes, and paddings of 12 / 10 / 12 (Android
/// and the web, 40 high) or 16 / 12 / 16 (iOS and macOS, 44 high). What an
/// app chooses: [theme], [shape], [text], [iconOnly] (the "G" alone in a
/// square or a circle). The texts are translated in the app's messages
/// (`login-button.google.sign-in`, `.sign-up`, `.continue`), which must
/// keep their meaning; "Google" alone is not allowed. Google also asks
/// that its button be at least as prominent as the other providers'.
///
/// The font is Google Sans when the app has it (it is Google's, not
/// shipped here); otherwise Roboto, then the system font.
///
/// ```dart
/// GoogleLoginButton(
///   text: LoginButtonText.continueWith,
///   onSuccess: (_) => Navigator.of(context).pop(),
/// )
/// ```
///
/// Source: developers.google.com/identity/branding-guidelines and its
/// `signin-assets.zip`.
class GoogleLoginButton extends StatelessWidget {
  /// A Google button logging in with [registrationId].
  const GoogleLoginButton({
    this.registrationId = 'google',
    this.theme = GoogleButtonTheme.light,
    this.shape = LoginButtonShape.rectangular,
    this.text = LoginButtonText.signIn,
    this.iconOnly = false,
    this.onSuccess,
    this.onError,
    this.additionalParameters = const {},
    this.loginService,
    this.login,
    super.key,
  });

  /// The registration of the properties; `google` by default.
  final String registrationId;

  /// The colours.
  final GoogleButtonTheme theme;

  /// The corners.
  final LoginButtonShape shape;

  /// What it says.
  final LoginButtonText text;

  /// The "G" alone (a screen reader still says the text).
  final bool iconOnly;

  /// See [OAuth2LoginButton.onSuccess].
  final ValueChanged<Authentication?>? onSuccess;

  /// See [OAuth2LoginButton.onError].
  final ValueChanged<Object>? onError;

  /// See [OAuth2LoginButton.additionalParameters].
  final Map<String, String> additionalParameters;

  /// See [OAuth2LoginButton.loginService].
  final OAuth2LoginService? loginService;

  /// See [OAuth2LoginButton.login].
  final OAuth2LoginAction? login;

  @override
  Widget build(BuildContext context) {
    final apple = _onApplePlatform;
    final height = apple ? 44.0 : 40.0;
    final (background, border, foreground) = switch (theme) {
      GoogleButtonTheme.light => (
        const Color(0xFFFFFFFF),
        const Color(0xFF747775),
        const Color(0xFF1F1F1F),
      ),
      GoogleButtonTheme.dark => (
        const Color(0xFF131314),
        const Color(0xFF8E918F),
        const Color(0xFFE3E3E3),
      ),
      GoogleButtonTheme.neutral => (
        const Color(0xFFF2F2F2),
        null,
        const Color(0xFF1F1F1F),
      ),
    };
    final label = switch (text) {
      LoginButtonText.signIn => loginMessage(
        context,
        'login-button.google.sign-in',
        'Sign in with Google',
      ),
      LoginButtonText.signUp => loginMessage(
        context,
        'login-button.google.sign-up',
        'Sign up with Google',
      ),
      LoginButtonText.continueWith => loginMessage(
        context,
        'login-button.google.continue',
        'Continue with Google',
      ),
    };
    return OAuth2LoginButton(
      registrationId,
      onSuccess: onSuccess,
      onError: onError,
      additionalParameters: additionalParameters,
      loginService: loginService,
      login: login,
      builder: (context, onPressed, busy) => BrandButton(
        onPressed: onPressed,
        busy: busy,
        label: label,
        logo: const GoogleLogo(),
        iconOnly: iconOnly,
        height: height,
        paddingStart: apple ? 16 : 12,
        gap: apple ? 12 : 10,
        paddingEnd: apple ? 16 : 12,
        radius: shape == LoginButtonShape.pill ? height / 2 : 4,
        background: background,
        border: border,
        foreground: foreground,
        textStyle: TextStyle(
          inherit: false,
          color: foreground,
          fontFamily: 'Google Sans',
          fontFamilyFallback: ['Roboto', ..._appFonts(context)],
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.25,
          textBaseline: TextBaseline.alphabetic,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}

/// The colours of an [AppleLoginButton], the three of Apple's Human
/// Interface Guidelines.
enum AppleButtonStyle {
  /// Black with a white logo and title: on white or light backgrounds.
  black,

  /// White with a black logo and title: on dark backgrounds.
  white,

  /// White with a black outline: on white backgrounds.
  whiteOutline,
}

/// The colour of the Apple logo an [AppleLoginButton] asks for.
enum AppleLogoColor {
  /// The black logo (on the white styles).
  black,

  /// The white logo (on the black style).
  white,
}

/// The Apple logo artwork an [AppleLoginButton] needs: which file of
/// Apple's "Sign in with Apple" logo download to show.
final class AppleLogoArtwork {
  /// The artwork of [color], for a logo-only button or one with a title,
  /// [height] logical pixels high.
  const AppleLogoArtwork({
    required this.color,
    required this.logoOnly,
    required this.height,
  });

  /// Black or white, the opposite of the button's background.
  final AppleLogoColor color;

  /// `true`: the logo-only file (square, padded on every side); `false`:
  /// the file for buttons with a title (padded to the button's edge and
  /// to the title).
  final bool logoOnly;

  /// The button's height: the file's height must match it (do not crop
  /// the file or add padding).
  final double height;
}

/// Builds the Apple logo artwork for an [AppleLoginButton] from the
/// app's own copy of Apple's files.
typedef AppleLogoBuilder = Widget Function(
  BuildContext context,
  AppleLogoArtwork artwork,
);

/// The "Sign in with Apple" button, in the look of Apple's Human
/// Interface Guidelines, logging in with the registration
/// [registrationId] (`apple` by default) through `OAuth2LoginService`.
///
/// The App Store asks apps that offer Google's or another provider's
/// login for an equivalent privacy-focused one, in practice this; App
/// Review checks custom Sign in with Apple buttons against these rules,
/// which the button follows: black, white or white with an outline, the
/// logo and the title of one colour (white or black), the title "Sign in
/// with Apple", "Sign up with Apple" or "Continue with Apple" in the system
/// font at 43 % of the button's height, at least 140 × 30 points (44 high
/// by default), a margin after the title of at least 8 % of the width,
/// rectangular with the corner radius of the app's buttons ([cornerRadius])
/// or logo-only, square or [circular].
///
/// **The logo comes from the app.** Apple allows only its own artwork
/// ("never create a custom Apple logo"), and its Developer Artwork License
/// lets only an Apple Developer Program member use it, in their own app;
/// a library may not redistribute it. So download "Sign in with Apple
/// Logo" from developer.apple.com/design/resources, add the files to the
/// app's assets, and pass them as [logo]: the PNG files are made for
/// buttons 44 points high (the default).
///
/// ```dart
/// AppleLoginButton(
///   logo: (context, artwork) => Image.asset(
///     'assets/apple/${artwork.logoOnly ? 'logo-only' : 'left-aligned'}-'
///     '${artwork.color.name}.png',
///     height: artwork.height,
///   ),
/// )
/// ```
///
/// On iOS and macOS, `OAuth2LoginService.login('apple')` opens Apple's
/// native sheet rather than a browser.
///
/// Source: developer.apple.com/design/human-interface-guidelines/sign-in-with-apple.
class AppleLoginButton extends StatelessWidget {
  /// An Apple button logging in with [registrationId], showing the app's
  /// copy of Apple's [logo].
  const AppleLoginButton({
    required this.logo,
    this.registrationId = 'apple',
    this.style = AppleButtonStyle.black,
    this.text = LoginButtonText.signIn,
    this.iconOnly = false,
    this.circular = false,
    this.height = 44,
    this.cornerRadius,
    this.onSuccess,
    this.onError,
    this.additionalParameters = const {},
    this.loginService,
    this.login,
    super.key,
  }) : assert(height >= 30, 'Apple asks for at least 30 points');

  /// The Apple logo, from Apple's artwork in the app's assets.
  final AppleLogoBuilder logo;

  /// The registration of the properties; `apple` by default.
  final String registrationId;

  /// The colours.
  final AppleButtonStyle style;

  /// What it says.
  final LoginButtonText text;

  /// The logo alone, in a square button (a screen reader still says the
  /// text).
  final bool iconOnly;

  /// A logo-only button in a circle instead of a square.
  final bool circular;

  /// The height, at least 30; 44 by default (Apple's recommendation).
  final double height;

  /// The corner radius, to match the app's other buttons; 15 % of the
  /// height by default (Apple's web button), at most half of it.
  final double? cornerRadius;

  /// See [OAuth2LoginButton.onSuccess].
  final ValueChanged<Authentication?>? onSuccess;

  /// See [OAuth2LoginButton.onError].
  final ValueChanged<Object>? onError;

  /// See [OAuth2LoginButton.additionalParameters].
  final Map<String, String> additionalParameters;

  /// See [OAuth2LoginButton.loginService].
  final OAuth2LoginService? loginService;

  /// See [OAuth2LoginButton.login].
  final OAuth2LoginAction? login;

  @override
  Widget build(BuildContext context) {
    final black = style == AppleButtonStyle.black;
    final background = black
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    final foreground = black
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    final label = switch (text) {
      LoginButtonText.signIn => loginMessage(
        context,
        'login-button.apple.sign-in',
        'Sign in with Apple',
      ),
      LoginButtonText.signUp => loginMessage(
        context,
        'login-button.apple.sign-up',
        'Sign up with Apple',
      ),
      LoginButtonText.continueWith => loginMessage(
        context,
        'login-button.apple.continue',
        'Continue with Apple',
      ),
    };
    final radius = iconOnly && circular
        ? height / 2
        : (cornerRadius ?? height * 0.15).clamp(0.0, height / 2);
    return OAuth2LoginButton(
      registrationId,
      onSuccess: onSuccess,
      onError: onError,
      additionalParameters: additionalParameters,
      loginService: loginService,
      login: login,
      builder: (context, onPressed, busy) => BrandButton(
        onPressed: onPressed,
        busy: busy,
        label: label,
        logo: SizedBox(
          // The artwork is as high as the button, inside its outline.
          height: style == AppleButtonStyle.whiteOutline ? height - 2 : height,
          child: logo(
            context,
            AppleLogoArtwork(
              color: black ? AppleLogoColor.white : AppleLogoColor.black,
              logoOnly: iconOnly,
              height: height,
            ),
          ),
        ),
        iconOnly: iconOnly,
        height: height,
        // The artwork carries the margins to the edge and to the title.
        paddingStart: 0,
        gap: 0,
        paddingEnd: height / 2,
        endFraction: 0.08,
        minWidth: 140,
        centerContent: true,
        radius: radius,
        background: background,
        border: style == AppleButtonStyle.whiteOutline
            ? const Color(0xFF000000)
            : null,
        foreground: foreground,
        textStyle: TextStyle(
          inherit: false,
          color: foreground,
          // Apple prefers the system font and allows the app's.
          fontFamily: DefaultTextStyle.of(context).style.fontFamily,
          fontFamilyFallback: DefaultTextStyle.of(
            context,
          ).style.fontFamilyFallback,
          fontSize: height * 0.43,
          fontWeight: FontWeight.w500,
          textBaseline: TextBaseline.alphabetic,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}

/// The colours of a [MicrosoftLoginButton], the two of Microsoft's
/// branding guidelines.
enum MicrosoftButtonTheme {
  /// White with a grey border and grey text.
  light,

  /// Dark grey with white text.
  dark,
}

/// What a [MicrosoftLoginButton] says.
enum MicrosoftButtonText {
  /// "Sign in with Microsoft".
  signInWithMicrosoft,

  /// "Sign in", where there is no room for the long text.
  signIn,
}

/// The "Sign in with Microsoft" button, in the look of Microsoft's
/// identity platform branding guidelines, logging in with the registration
/// [registrationId] (`microsoft` by default) through `OAuth2LoginService`.
///
/// The guidelines fix: the four-colour Microsoft logo (never altered), 41
/// pixels high, 12 pixels before the logo, between logo and text and after
/// the text, Segoe UI semibold (600) 15, light (`#FFFFFF`, a `#8C8C8C`
/// border, text `#5E5E5E`) or dark (`#2F2F2F`, text `#FFFFFF`), square
/// corners, "Sign in with Microsoft" or the short "Sign in". What an app
/// chooses: [theme] and [text], translated in the app's messages
/// (`login-button.microsoft.sign-in-with`, `.sign-in`). Segoe UI is
/// Windows' font; elsewhere the system font is used.
///
/// Microsoft's issuer depends on the tenant
/// (`https://login.microsoftonline.com/<tenant>/v2.0`): the registration's
/// properties say which; the button names no endpoint.
///
/// Source: learn.microsoft.com/entra/identity-platform/howto-add-branding-in-apps.
class MicrosoftLoginButton extends StatelessWidget {
  /// A Microsoft button logging in with [registrationId].
  const MicrosoftLoginButton({
    this.registrationId = 'microsoft',
    this.theme = MicrosoftButtonTheme.light,
    this.text = MicrosoftButtonText.signInWithMicrosoft,
    this.onSuccess,
    this.onError,
    this.additionalParameters = const {},
    this.loginService,
    this.login,
    super.key,
  });

  /// The registration of the properties; `microsoft` by default.
  final String registrationId;

  /// The colours.
  final MicrosoftButtonTheme theme;

  /// What it says.
  final MicrosoftButtonText text;

  /// See [OAuth2LoginButton.onSuccess].
  final ValueChanged<Authentication?>? onSuccess;

  /// See [OAuth2LoginButton.onError].
  final ValueChanged<Object>? onError;

  /// See [OAuth2LoginButton.additionalParameters].
  final Map<String, String> additionalParameters;

  /// See [OAuth2LoginButton.loginService].
  final OAuth2LoginService? loginService;

  /// See [OAuth2LoginButton.login].
  final OAuth2LoginAction? login;

  @override
  Widget build(BuildContext context) {
    final light = theme == MicrosoftButtonTheme.light;
    final foreground = light
        ? const Color(0xFF5E5E5E)
        : const Color(0xFFFFFFFF);
    final label = switch (text) {
      MicrosoftButtonText.signInWithMicrosoft => loginMessage(
        context,
        'login-button.microsoft.sign-in-with',
        'Sign in with Microsoft',
      ),
      MicrosoftButtonText.signIn => loginMessage(
        context,
        'login-button.microsoft.sign-in',
        'Sign in',
      ),
    };
    return OAuth2LoginButton(
      registrationId,
      onSuccess: onSuccess,
      onError: onError,
      additionalParameters: additionalParameters,
      loginService: loginService,
      login: login,
      builder: (context, onPressed, busy) => BrandButton(
        onPressed: onPressed,
        busy: busy,
        label: label,
        // The 21-pixel logo box (squares of 9 with a pixel around them)
        // 12 from the edge and 12 from the text, as Microsoft's SVG.
        logo: const MicrosoftLogo(),
        semanticsLabel: text == MicrosoftButtonText.signIn
            ? loginMessage(
                context,
                'login-button.microsoft.sign-in-with',
                'Sign in with Microsoft',
              )
            : null,
        iconOnly: false,
        height: 41,
        paddingStart: 12,
        gap: 12,
        paddingEnd: 12,
        radius: 0,
        background: light ? const Color(0xFFFFFFFF) : const Color(0xFF2F2F2F),
        border: light ? const Color(0xFF8C8C8C) : null,
        foreground: foreground,
        textStyle: TextStyle(
          inherit: false,
          color: foreground,
          fontFamily: 'Segoe UI',
          fontFamilyFallback: _appFonts(context),
          fontSize: 15,
          fontWeight: FontWeight.w600,
          textBaseline: TextBaseline.alphabetic,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}

/// The colours of a [GitHubLoginButton].
enum GitHubButtonTheme {
  /// Dark with the white mark and white text.
  dark,

  /// White with a grey border, the black mark and dark text.
  light,
}

/// The "Sign in with GitHub" button, with GitHub's Invertocat mark,
/// logging in with the registration [registrationId] (`github` by default)
/// through `OAuth2LoginService`.
///
/// GitHub publishes no sign-in button, only logo rules: the mark in black
/// or white only (never recoloured, distorted, with shadows or
/// gradients), allowed to show that an app works with GitHub, less
/// prominent than the app's own name. The button keeps those and takes
/// the size of the others (40 high, 12 / 10 / 12, a 20-pixel mark,
/// semibold 14) so a login screen's buttons line up. What an app chooses:
/// [theme], [shape], [text] (`login-button.github.sign-in`, `.sign-up`,
/// `.continue` in the app's messages), [iconOnly].
///
/// GitHub is OAuth 2.0 without OpenID Connect: the user comes from its
/// user info endpoint (`CommonOAuth2Provider.github`).
///
/// Source: brand.github.com/foundations/logo; the mark from GitHub's
/// Octicons (MIT).
class GitHubLoginButton extends StatelessWidget {
  /// A GitHub button logging in with [registrationId].
  const GitHubLoginButton({
    this.registrationId = 'github',
    this.theme = GitHubButtonTheme.dark,
    this.shape = LoginButtonShape.rectangular,
    this.text = LoginButtonText.signIn,
    this.iconOnly = false,
    this.onSuccess,
    this.onError,
    this.additionalParameters = const {},
    this.loginService,
    this.login,
    super.key,
  });

  /// The registration of the properties; `github` by default.
  final String registrationId;

  /// The colours.
  final GitHubButtonTheme theme;

  /// The corners.
  final LoginButtonShape shape;

  /// What it says.
  final LoginButtonText text;

  /// The mark alone (a screen reader still says the text).
  final bool iconOnly;

  /// See [OAuth2LoginButton.onSuccess].
  final ValueChanged<Authentication?>? onSuccess;

  /// See [OAuth2LoginButton.onError].
  final ValueChanged<Object>? onError;

  /// See [OAuth2LoginButton.additionalParameters].
  final Map<String, String> additionalParameters;

  /// See [OAuth2LoginButton.loginService].
  final OAuth2LoginService? loginService;

  /// See [OAuth2LoginButton.login].
  final OAuth2LoginAction? login;

  @override
  Widget build(BuildContext context) {
    final dark = theme == GitHubButtonTheme.dark;
    final foreground = dark ? const Color(0xFFFFFFFF) : const Color(0xFF1F2328);
    final label = switch (text) {
      LoginButtonText.signIn => loginMessage(
        context,
        'login-button.github.sign-in',
        'Sign in with GitHub',
      ),
      LoginButtonText.signUp => loginMessage(
        context,
        'login-button.github.sign-up',
        'Sign up with GitHub',
      ),
      LoginButtonText.continueWith => loginMessage(
        context,
        'login-button.github.continue',
        'Continue with GitHub',
      ),
    };
    return OAuth2LoginButton(
      registrationId,
      onSuccess: onSuccess,
      onError: onError,
      additionalParameters: additionalParameters,
      loginService: loginService,
      login: login,
      builder: (context, onPressed, busy) => BrandButton(
        onPressed: onPressed,
        busy: busy,
        label: label,
        logo: GitHubLogo(
          color: dark ? GitHubMarkColor.white : GitHubMarkColor.black,
          size: 20,
        ),
        iconOnly: iconOnly,
        height: 40,
        paddingStart: 12,
        gap: 10,
        paddingEnd: 12,
        radius: shape == LoginButtonShape.pill ? 20 : 6,
        background: dark ? const Color(0xFF24292F) : const Color(0xFFFFFFFF),
        border: dark ? null : const Color(0xFFD1D9E0),
        foreground: foreground,
        textStyle: TextStyle(
          inherit: false,
          color: foreground,
          // GitHub fixes no font: the app's.
          fontFamily: DefaultTextStyle.of(context).style.fontFamily,
          fontFamilyFallback: DefaultTextStyle.of(
            context,
          ).style.fontFamilyFallback,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
          textBaseline: TextBaseline.alphabetic,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}

// The app's font and its fallbacks, after the brand's own font.
List<String> _appFonts(BuildContext context) {
  final style = DefaultTextStyle.of(context).style;
  return [?style.fontFamily, ...?style.fontFamilyFallback];
}

bool get _onApplePlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// The look all brand buttons share, without Material or Cupertino: a
/// box of the brand's colours and border, the logo and the label in the
/// brand's paddings, a spinner in place of the label while the login
/// runs, the hover, press and focus states, and the semantics of a
/// button. Internal to the brand buttons (not exported).
class BrandButton extends StatelessWidget {
  /// A brand button; see the brand buttons for the values.
  const BrandButton({
    required this.onPressed,
    required this.busy,
    required this.label,
    required this.logo,
    required this.iconOnly,
    required this.height,
    required this.paddingStart,
    required this.gap,
    required this.paddingEnd,
    required this.radius,
    required this.background,
    required this.border,
    required this.foreground,
    required this.textStyle,
    this.semanticsLabel,
    this.centerContent = false,
    this.minWidth = 0,
    this.endFraction,
    super.key,
  });

  /// Pressed; `null` while the login runs.
  final VoidCallback? onPressed;

  /// Whether the login runs.
  final bool busy;

  /// The text (and what a screen reader says).
  final String label;

  /// What a screen reader says instead of [label].
  final String? semanticsLabel;

  /// The brand's logo.
  final Widget logo;

  /// Only the logo, in a square (or a circle with a radius of half the
  /// height).
  final bool iconOnly;

  /// The height at the normal text size; larger text makes it taller.
  final double height;

  /// Before the logo.
  final double paddingStart;

  /// Between the logo and the text.
  final double gap;

  /// After the text.
  final double paddingEnd;

  /// The corner radius.
  final double radius;

  /// The fill.
  final Color background;

  /// The one-pixel border inside the edge, or none.
  final Color? border;

  /// The colour of the text, the spinner and the overlays.
  final Color foreground;

  /// The brand's text style.
  final TextStyle textStyle;

  /// Logo and text centred together (Apple); otherwise the logo stays at
  /// the start and the text is centred in the rest (Google's default).
  final bool centerContent;

  /// The narrowest the button may be.
  final double minWidth;

  /// The share of a bounded width kept free after the text (Apple: 8 %).
  final double? endFraction;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return LoginPressable(
      onPressed: onPressed,
      busy: busy,
      overlayColor: foreground,
      semanticsLabel: semanticsLabel ?? label,
      builder: (context, overlay, focused) => LayoutBuilder(
        builder: (context, constraints) => Container(
          constraints: BoxConstraints(
            minHeight: height,
            minWidth: iconOnly ? height : minWidth,
          ),
          width: iconOnly ? height : null,
          height: iconOnly ? height : null,
          decoration: BoxDecoration(
            color: Color.alphaBlend(overlay, background),
            borderRadius: shape,
            border: border == null ? null : Border.all(color: border!),
          ),
          foregroundDecoration: focused
              ? BoxDecoration(
                  borderRadius: shape,
                  border: Border.all(color: foreground, width: 2),
                )
              : null,
          clipBehavior: Clip.antiAlias,
          child: iconOnly
              ? Center(child: busy ? _spinner : logo)
              : _content(constraints),
        ),
      ),
    );
  }

  Widget get _spinner => LoginSpinner(color: foreground);

  Widget _content(BoxConstraints constraints) {
    final bounded = constraints.hasBoundedWidth;
    // The border is drawn inside the edge: the paddings are measured from
    // the edge, as in the brands' artwork.
    final inset = border == null ? 0.0 : 1.0;
    final end =
        (bounded && endFraction != null
            ? (constraints.maxWidth * endFraction!).clamp(
                paddingEnd,
                double.infinity,
              )
            : paddingEnd) -
        inset;
    // The label keeps its width while the spinner shows, so the button
    // does not jump.
    final text = Stack(
      alignment: Alignment.center,
      children: [
        Visibility.maintain(
          visible: !busy,
          child: Text(
            label,
            style: textStyle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (busy) _spinner,
      ],
    );
    final row = Row(
      mainAxisSize: bounded && !centerContent
          ? MainAxisSize.max
          : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: (paddingStart - inset).clamp(0, paddingStart)),
        logo,
        SizedBox(width: gap),
        if (bounded && !centerContent)
          Expanded(child: text)
        else
          Flexible(child: text),
        SizedBox(width: end.toDouble()),
      ],
    );
    return centerContent ? Center(widthFactor: 1, child: row) : row;
  }
}
