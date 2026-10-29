import AuthenticationServices

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import AppKit
  import FlutterMacOS
#endif

/// Sign in with Apple in the system's own sheet
/// (`ASAuthorizationAppleIDProvider`), not in a browser: Face ID, Touch ID
/// or the device passcode, with the Apple Account of the device.
///
/// The request carries the scopes (`name`, `email`), the `nonce` (the
/// Dart side passes the SHA-256 hash of a fresh random value; Apple puts
/// it into the identity token as given) and the `state`. The answer is
/// the user identifier, the authorization code, the identity token (a
/// JWT signed by Apple) and, on the first authorization of the app only,
/// the name and e-mail. Nothing is logged: the code and the token are
/// credentials.
///
/// Needs the "Sign in with Apple" capability (the
/// `com.apple.developer.applesignin` entitlement) in the app.
final class AppleIdSignIn: NSObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private var controller: ASAuthorizationController?
  private var result: FlutterResult?

  func signIn(scopes: [String], nonce: String, state: String, result: @escaping FlutterResult) {
    guard controller == nil else {
      result(FlutterError(code: "in_progress", message: "a sign-in is already running", details: nil))
      return
    }
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = scopes.compactMap { scope in
      switch scope {
      case "name": return .fullName
      case "email": return .email
      default: return nil
      }
    }
    request.nonce = nonce
    request.state = state
    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.presentationContextProvider = self
    self.controller = controller
    self.result = result
    controller.performRequests()
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      finish(FlutterError(code: "failed", message: "not an Apple ID credential", details: nil))
      return
    }
    guard let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }),
      let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
    else {
      finish(
        FlutterError(
          code: "failed", message: "the credential has no authorization code or identity token",
          details: nil))
      return
    }
    var answer: [String: Any] = [
      "user": credential.user,
      "authorizationCode": code,
      "identityToken": identityToken,
    ]
    if let state = credential.state { answer["state"] = state }
    if let email = credential.email { answer["email"] = email }
    if let name = credential.fullName {
      if let given = name.givenName { answer["givenName"] = given }
      if let family = name.familyName { answer["familyName"] = family }
    }
    finish(answer)
  }

  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithError error: Error
  ) {
    if let error = error as? ASAuthorizationError {
      // 1000 (unknown) is also what a device without an Apple Account
      // answers.
      let code = error.code == .canceled ? "cancelled" : "failed"
      finish(
        FlutterError(
          code: code, message: "Sign in with Apple failed (\(error.code.rawValue))", details: nil))
    } else {
      finish(FlutterError(code: "failed", message: "Sign in with Apple failed", details: nil))
    }
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    #if os(iOS)
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
      return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
    #else
      let app = NSApplication.shared
      return app.keyWindow ?? app.mainWindow ?? app.windows.first ?? ASPresentationAnchor()
    #endif
  }

  private func finish(_ answer: Any) {
    let result = self.result
    self.result = nil
    self.controller = nil
    DispatchQueue.main.async { result?(answer) }
  }
}
