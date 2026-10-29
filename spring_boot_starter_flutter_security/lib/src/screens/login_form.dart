import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_security/src/screens/login_design.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    hide Banner, Size;

/// Logs a user name and password in; the result is the authenticated
/// user (`null` when the code that logged in keeps it to itself).
typedef LoginFormAuthenticate = Future<Authentication?> Function(
  String username,
  String password,
);

/// Builds one field of a [LoginForm] from its [LoginFormField]
/// description.
typedef LoginFormFieldBuilder = Widget Function(
  BuildContext context,
  LoginFormField field,
);

/// Builds the submit button of a [LoginForm] from its
/// [LoginFormSubmitButton] description.
typedef LoginFormSubmitButtonBuilder = Widget Function(
  BuildContext context,
  LoginFormSubmitButton button,
);

/// Builds the message of a refused or failed login.
typedef LoginFormErrorBuilder = Widget Function(
  BuildContext context,
  String message,
);

/// Which of the two fields a [LoginFormField] is.
enum LoginFormFieldKind {
  /// The user name (or email, whatever the users log in with).
  username,

  /// The password, obscured.
  password,
}

/// Everything a field of [LoginForm] needs, for a
/// [LoginForm.fieldBuilder] that draws the fields itself: connect the
/// [controller], [focusNode], [obscureText], [autofillHints],
/// [textInputAction] and [onSubmitted] to a text field and show [label]
/// and [errorText].
final class LoginFormField {
  /// A description of one field; made by [LoginForm].
  const LoginFormField({
    required this.kind,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.errorText,
    required this.enabled,
    required this.obscureText,
    required this.toggleObscured,
    required this.toggleLabel,
    required this.autofillHints,
    required this.keyboardType,
    required this.textInputAction,
    required this.onSubmitted,
  });

  /// Which field this is.
  final LoginFormFieldKind kind;

  /// The field's text.
  final TextEditingController controller;

  /// The field's focus; Enter in the user name moves it to the password.
  final FocusNode focusNode;

  /// The field's label, from the app's messages.
  final String label;

  /// The field's own error (empty when submitted), or `null`.
  final String? errorText;

  /// `false` while the login runs.
  final bool enabled;

  /// Whether the text is hidden: the password, until the user shows it.
  final bool obscureText;

  /// Shows or hides the password; `null` for the user name.
  final VoidCallback? toggleObscured;

  /// What the show / hide control says ("Show password", "Hide
  /// password"); `null` for the user name.
  final String? toggleLabel;

  /// [AutofillHints.username] or [AutofillHints.password], so password
  /// managers fill and save them.
  final Iterable<String> autofillHints;

  /// The keyboard of the field.
  final TextInputType keyboardType;

  /// [TextInputAction.next] for the user name, [TextInputAction.done]
  /// for the password.
  final TextInputAction textInputAction;

  /// Enter: next field, or submit from the password.
  final ValueChanged<String> onSubmitted;
}

/// Everything the submit button of [LoginForm] needs, for a
/// [LoginForm.submitButtonBuilder].
final class LoginFormSubmitButton {
  /// A description of the button; made by [LoginForm].
  const LoginFormSubmitButton({
    required this.label,
    required this.onPressed,
    required this.busy,
  });

  /// The button's text, from the app's messages ("Log in").
  final String label;

  /// Submits the form; `null` while the login runs.
  final VoidCallback? onPressed;

  /// Whether the login runs: show progress.
  final bool busy;
}

/// A user name and password form that logs the user in with the app's
/// `AuthenticationManager`: two fields, the checks, the progress, the
/// error, and the user in the `SecurityContextHolder` afterwards.
///
/// Use it for logins where the user types a password into the app: the
/// app's own `AuthenticationProvider` that asks its server, or an
/// in-memory user store in a demo. (Logins at a provider, where the
/// password is typed into the provider's page, are
/// [OAuth2LoginButton]'s.) What it does on submit (Enter in the password
/// field, or the button):
///
/// 1. checks that both fields are filled (an error under the empty one);
/// 2. trims the user name (as Spring Security's form login does) and asks
///    the `AuthenticationManager` bean with a
///    `UsernamePasswordAuthenticationToken`; the button shows progress
///    and the fields are locked meanwhile;
/// 3. on success puts the result into the `SecurityContextHolder` (so
///    `PrincipalNotifier`, `PrincipalBuilder` and `@PreAuthorize` see the
///    user), publishes an `InteractiveAuthenticationSuccessEvent`, tells
///    password managers to save the login, and calls [onSuccess];
/// 4. on failure shows an error and calls [onError]: a wrong name or
///    password, an unknown user and a refused account
///    (`BadCredentialsException`, `UsernameNotFoundException`,
///    `AccountStatusException`) all show the same text, so nobody learns
///    which part was wrong or which names exist; anything else (the
///    server down, `AuthenticationServiceException`) says the login could
///    not be checked. The password field is cleared.
///
/// The fields have the autofill hints of a login (`username`,
/// `password`), the password is obscured with a show / hide control.
/// Nothing is logged, the password least of all.
///
/// **Its look** follows the app ([LoginDesign]): Material fields and a
/// filled button below a `MaterialApp`, styled by the app's theme (the
/// `spring.flutter.theme.components.input.*` and `button.*` properties);
/// Cupertino ones below a `CupertinoApp`; plain fields coloured from the
/// `SpringTheme` below a `WidgetsApp`. [fieldBuilder],
/// [submitButtonBuilder] and [errorBuilder] replace its parts.
///
/// **Its texts** come from the app's messages files (with these English
/// defaults), or from [usernameLabel], [passwordLabel] and [submitLabel]:
///
/// ```properties
/// login-form.username=User name
/// login-form.password=Password
/// login-form.submit=Log in
/// login-form.show-password=Show password
/// login-form.hide-password=Hide password
/// login-form.username-required=Enter your user name
/// login-form.password-required=Enter your password
/// login-form.bad-credentials=Wrong user name or password
/// login-form.service-error=The login could not be checked. Try again later.
/// ```
///
/// ```dart
/// // A login screen that closes once the user is in.
/// Scaffold(
///   appBar: AppBar(title: const Text('Log in')),
///   body: Padding(
///     padding: const EdgeInsets.all(16),
///     child: LoginForm(onSuccess: (_) => Navigator.of(context).pop()),
///   ),
/// )
/// ```
///
/// Spring has no widget; the nearest is the login page of Spring
/// Security's `formLogin()`, whose `UsernamePasswordAuthenticationFilter`
/// does the same steps on a server.
class LoginForm extends StatefulWidget {
  /// A login form on the app's `AuthenticationManager`, or on
  /// [authenticate].
  const LoginForm({
    this.onSuccess,
    this.onError,
    this.authenticate,
    this.authenticationManager,
    this.design,
    this.usernameLabel,
    this.passwordLabel,
    this.submitLabel,
    this.errorMessage,
    this.fieldBuilder,
    this.submitButtonBuilder,
    this.errorBuilder,
    this.usernameKeyboardType = TextInputType.text,
    this.initialUsername,
    this.autofocus = false,
    this.spacing,
    super.key,
  });

  /// Called after a successful login with the authenticated user (`null`
  /// when [authenticate] returned none): close the screen here.
  final ValueChanged<Authentication?>? onSuccess;

  /// Called after a refused or failed login with the error (the form
  /// shows its message anyway): count failures, log them here.
  final ValueChanged<Object>? onError;

  /// Logs in instead of the `AuthenticationManager`, for an app whose own
  /// service does the login (and more: events of its own). The form then
  /// sets no security context and publishes nothing; it shows what the
  /// function throws as above.
  final LoginFormAuthenticate? authenticate;

  /// The manager that checks the login; the application's
  /// `AuthenticationManager` bean by default.
  final AuthenticationManager? authenticationManager;

  /// The look; the app's ([LoginDesign.of]) by default.
  final LoginDesign? design;

  /// The user name field's label; message `login-form.username` by
  /// default.
  final String? usernameLabel;

  /// The password field's label; message `login-form.password` by
  /// default.
  final String? passwordLabel;

  /// The button's text; message `login-form.submit` by default.
  final String? submitLabel;

  /// The text shown for a failed login; [defaultErrorMessage] by default.
  /// Keep a wrong name and a wrong password the same text.
  final String Function(BuildContext context, Object error)? errorMessage;

  /// Draws each field; the design's text field by default.
  final LoginFormFieldBuilder? fieldBuilder;

  /// Draws the submit button; the design's filled button by default.
  final LoginFormSubmitButtonBuilder? submitButtonBuilder;

  /// Draws the error of a failed login; a text in the error colour by
  /// default (read out by screen readers).
  final LoginFormErrorBuilder? errorBuilder;

  /// The user name's keyboard; [TextInputType.emailAddress] for logins
  /// with an email.
  final TextInputType usernameKeyboardType;

  /// The user name to start with (the last one used, a `login_hint`).
  final String? initialUsername;

  /// Whether the first empty field takes the focus at once.
  final bool autofocus;

  /// The space between the parts; the theme's `m` spacing (16 by
  /// default).
  final double? spacing;

  /// The message for [error]: the same text for a wrong name or password,
  /// an unknown user and a refused account (`login-form.bad-credentials`),
  /// another one for everything else (`login-form.service-error`).
  static String defaultErrorMessage(BuildContext context, Object error) =>
      switch (error) {
        BadCredentialsException() ||
        UsernameNotFoundException() ||
        AccountStatusException() => loginMessage(
          context,
          'login-form.bad-credentials',
          'Wrong user name or password',
        ),
        _ => loginMessage(
          context,
          'login-form.service-error',
          'The login could not be checked. Try again later.',
        ),
      };

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  late final _username = TextEditingController(text: widget.initialUsername);
  final _password = TextEditingController();
  final _usernameFocus = FocusNode(debugLabel: 'LoginForm.username');
  final _passwordFocus = FocusNode(debugLabel: 'LoginForm.password');
  var _obscured = true;
  var _busy = false;
  String? _usernameError;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _password.clear();
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final username = _username.text.trim();
    final password = _password.text;
    setState(() {
      _error = null;
      _usernameError = username.isEmpty
          ? loginMessage(
              context,
              'login-form.username-required',
              'Enter your user name',
            )
          : null;
      _passwordError = password.isEmpty
          ? loginMessage(
              context,
              'login-form.password-required',
              'Enter your password',
            )
          : null;
    });
    if (_usernameError != null) {
      _usernameFocus.requestFocus();
      return;
    }
    if (_passwordError != null) {
      _passwordFocus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _login(username, password);
      if (!mounted) {
        return;
      }
      TextInput.finishAutofillContext();
      setState(() => _busy = false);
      widget.onSuccess?.call(result);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final message = (widget.errorMessage ?? LoginForm.defaultErrorMessage)(
        context,
        error,
      );
      _password.clear();
      setState(() {
        _busy = false;
        _error = message;
      });
      _passwordFocus.requestFocus();
      widget.onError?.call(error);
    }
  }

  Future<Authentication?> _login(String username, String password) async {
    if (widget.authenticate case final authenticate?) {
      return authenticate(username, password);
    }
    final spring = SpringScope.maybeOf(context, listen: false);
    final manager =
        widget.authenticationManager ??
        spring?.findBean<AuthenticationManager>() ??
        (throw StateError(
          'LoginForm needs an AuthenticationManager: declare an '
          'AuthenticationProvider or a UserDetailsService bean, or pass '
          'authenticationManager or authenticate',
        ));
    final result = await manager.authenticate(
      UsernamePasswordAuthenticationToken.unauthenticated(username, password),
    );
    // As Spring's AbstractAuthenticationProcessingFilter: a new context
    // for the user, then the interactive login event.
    final securityContext = SecurityContextHolder.createEmptyContext()
      ..authentication = result;
    SecurityContextHolder.setContext(securityContext);
    spring?.publishEvent(InteractiveAuthenticationSuccessEvent(result));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final design = widget.design ?? LoginDesign.of(context);
    final spacing =
        widget.spacing ?? SpringTheme.maybeOf(context)?.space('m') ?? 16;
    final fields = [
      LoginFormField(
        kind: LoginFormFieldKind.username,
        controller: _username,
        focusNode: _usernameFocus,
        label:
            widget.usernameLabel ??
            loginMessage(context, 'login-form.username', 'User name'),
        errorText: _usernameError,
        enabled: !_busy,
        obscureText: false,
        toggleObscured: null,
        toggleLabel: null,
        autofillHints: const [AutofillHints.username],
        keyboardType: widget.usernameKeyboardType,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _passwordFocus.requestFocus(),
      ),
      LoginFormField(
        kind: LoginFormFieldKind.password,
        controller: _password,
        focusNode: _passwordFocus,
        label:
            widget.passwordLabel ??
            loginMessage(context, 'login-form.password', 'Password'),
        errorText: _passwordError,
        enabled: !_busy,
        obscureText: _obscured,
        toggleObscured: () => setState(() => _obscured = !_obscured),
        toggleLabel: _obscured
            ? loginMessage(context, 'login-form.show-password', 'Show password')
            : loginMessage(
                context,
                'login-form.hide-password',
                'Hide password',
              ),
        autofillHints: const [AutofillHints.password],
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
    ];
    final button = LoginFormSubmitButton(
      label:
          widget.submitLabel ??
          loginMessage(context, 'login-form.submit', 'Log in'),
      onPressed: _busy ? null : _submit,
      busy: _busy,
    );
    final fieldBuilder =
        widget.fieldBuilder ??
        (context, field) => _DefaultField(
          design: design,
          field: field,
          // The first field to fill: the password when the user name
          // was given.
          autofocus:
              widget.autofocus &&
              (field.kind == LoginFormFieldKind.username) ==
                  (widget.initialUsername?.isEmpty ?? true),
        );
    final buttonBuilder =
        widget.submitButtonBuilder ??
        (context, button) =>
            _DefaultSubmitButton(design: design, button: button);
    final errorBuilder =
        widget.errorBuilder ??
        (context, message) => _DefaultError(design: design, message: message);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              fieldBuilder(context, fields[0]),
              SizedBox(height: spacing),
              fieldBuilder(context, fields[1]),
            ],
          ),
        ),
        if (_error case final message?) ...[
          SizedBox(height: spacing),
          errorBuilder(context, message),
        ],
        SizedBox(height: spacing),
        buttonBuilder(context, button),
      ],
    );
    // A Material field needs a Material above it; a screen without a
    // Scaffold gets a transparent one.
    return design == LoginDesign.material && Material.maybeOf(context) == null
        ? Material(type: MaterialType.transparency, child: column)
        : column;
  }
}

class _DefaultField extends StatelessWidget {
  const _DefaultField({
    required this.design,
    required this.field,
    required this.autofocus,
  });

  final LoginDesign design;
  final LoginFormField field;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => switch (design) {
    LoginDesign.material => _material(context),
    LoginDesign.cupertino => _cupertino(context),
    LoginDesign.widgets => _plain(context),
  };

  Widget _material(BuildContext context) => TextField(
    controller: field.controller,
    focusNode: field.focusNode,
    enabled: field.enabled,
    autofocus: autofocus,
    obscureText: field.obscureText,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: field.autofillHints,
    keyboardType: field.keyboardType,
    textInputAction: field.textInputAction,
    onSubmitted: field.onSubmitted,
    decoration: InputDecoration(
      labelText: field.label,
      errorText: field.errorText,
      suffixIcon: field.toggleObscured == null
          ? null
          : IconButton(
              onPressed: field.enabled ? field.toggleObscured : null,
              tooltip: field.toggleLabel,
              icon: Icon(
                field.obscureText ? Icons.visibility : Icons.visibility_off,
              ),
            ),
    ),
  );

  Widget _cupertino(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CupertinoTextField(
          controller: field.controller,
          focusNode: field.focusNode,
          enabled: field.enabled,
          autofocus: autofocus,
          obscureText: field.obscureText,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: field.autofillHints,
          keyboardType: field.keyboardType,
          textInputAction: field.textInputAction,
          onSubmitted: field.onSubmitted,
          placeholder: field.label,
          suffix: field.toggleObscured == null
              ? null
              : Semantics(
                  label: field.toggleLabel,
                  button: true,
                  excludeSemantics: true,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(44, 44),
                    onPressed: field.enabled ? field.toggleObscured : null,
                    child: Icon(
                      field.obscureText
                          ? CupertinoIcons.eye
                          : CupertinoIcons.eye_slash,
                      size: 20,
                    ),
                  ),
                ),
        ),
        if (field.errorText case final error?)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, top: 4),
            child: Text(
              error,
              style: theme.textTheme.textStyle.copyWith(
                fontSize: 13,
                color: CupertinoColors.destructiveRed.resolveFrom(context),
              ),
            ),
          ),
      ],
    );
  }

  Widget _plain(BuildContext context) {
    final colors = loginColorScheme(context);
    final text = DefaultTextStyle.of(context).style;
    final error = field.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            field.label,
            style: text.copyWith(
              fontSize: 12,
              color: error == null ? colors.onSurfaceVariant : colors.error,
            ),
          ),
        ),
        ListenableBuilder(
          listenable: field.focusNode,
          builder: (context, child) => DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(
                color: error != null
                    ? colors.error
                    : field.focusNode.hasFocus
                    ? colors.primary
                    : colors.outline,
                width: field.focusNode.hasFocus ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: child,
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Semantics(
                    label: field.label,
                    textField: true,
                    child: EditableText(
                      controller: field.controller,
                      focusNode: field.focusNode,
                      readOnly: !field.enabled,
                      autofocus: autofocus,
                      obscureText: field.obscureText,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: field.autofillHints,
                      keyboardType: field.keyboardType,
                      textInputAction: field.textInputAction,
                      onSubmitted: field.onSubmitted,
                      style: text.copyWith(color: colors.onSurface),
                      cursorColor: colors.primary,
                      backgroundCursorColor: colors.outlineVariant,
                      selectionColor: colors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              if (field.toggleObscured case final toggle?)
                LoginPressable(
                  onPressed: field.enabled ? toggle : null,
                  overlayColor: colors.primary,
                  semanticsLabel: field.toggleLabel,
                  builder: (context, overlay, focused) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    color: overlay,
                    child: Text(
                      field.toggleLabel!,
                      style: text.copyWith(
                        fontSize: 13,
                        color: colors.primary,
                        decoration: focused ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: text.copyWith(fontSize: 12, color: colors.error),
            ),
          ),
      ],
    );
  }
}

class _DefaultSubmitButton extends StatelessWidget {
  const _DefaultSubmitButton({required this.design, required this.button});

  final LoginDesign design;
  final LoginFormSubmitButton button;

  @override
  Widget build(BuildContext context) => switch (design) {
    LoginDesign.material => FilledButton(
      onPressed: button.onPressed,
      child: button.busy
          ? Semantics(
              label: button.label,
              child: const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Text(button.label),
    ),
    LoginDesign.cupertino => CupertinoButton.filled(
      onPressed: button.onPressed,
      child: button.busy
          ? Semantics(
              label: button.label,
              child: const CupertinoActivityIndicator(),
            )
          : Text(button.label),
    ),
    LoginDesign.widgets => PlainLoginButton(
      label: button.label,
      onPressed: button.onPressed,
      busy: button.busy,
    ),
  };
}

/// The filled button of the plain [LoginDesign.widgets] design, in the
/// `SpringTheme`'s primary colour; also [OAuth2LoginButton]'s there.
class PlainLoginButton extends StatelessWidget {
  /// A button saying [label], with [icon] before it.
  const PlainLoginButton({
    required this.label,
    required this.onPressed,
    required this.busy,
    this.icon,
    super.key,
  });

  /// The text.
  final String label;

  /// Pressed; `null` disables the button.
  final VoidCallback? onPressed;

  /// Shows a spinner instead of [icon] (or of the text without one).
  final bool busy;

  /// Drawn before the text.
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final colors = loginColorScheme(context);
    final enabled = onPressed != null;
    final foreground = enabled
        ? colors.onPrimary
        : colors.onSurface.withValues(alpha: 0.38);
    final background = enabled
        ? colors.primary
        : colors.onSurface.withValues(alpha: 0.12);
    final style = DefaultTextStyle.of(
      context,
    ).style.copyWith(color: foreground, fontWeight: FontWeight.w500);
    final spinner = LoginSpinner(color: foreground, size: 18);
    return LoginPressable(
      onPressed: onPressed,
      busy: busy,
      overlayColor: colors.onPrimary,
      semanticsLabel: label,
      builder: (context, overlay, focused) => Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(overlay, background),
          borderRadius: BorderRadius.circular(20),
          border: focused
              ? Border.all(color: colors.onSurface, width: 2)
              : null,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground, size: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                if (busy) spinner else icon!,
                const SizedBox(width: 8),
              ],
              if (busy && icon == null)
                spinner
              else
                Flexible(
                  child: Text(
                    label,
                    style: style,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefaultError extends StatelessWidget {
  const _DefaultError({required this.design, required this.message});

  final LoginDesign design;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = switch (design) {
      LoginDesign.material => Theme.of(context).colorScheme.error,
      LoginDesign.cupertino => CupertinoColors.destructiveRed.resolveFrom(
        context,
      ),
      LoginDesign.widgets => loginColorScheme(context).error,
    };
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: DefaultTextStyle.of(context).style.copyWith(color: color),
      ),
    );
  }
}
