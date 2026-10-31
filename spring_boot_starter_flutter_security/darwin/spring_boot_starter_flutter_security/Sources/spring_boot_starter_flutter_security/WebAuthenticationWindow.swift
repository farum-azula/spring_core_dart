import AuthenticationServices

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import AppKit
  import FlutterMacOS
#endif

/// The login page in ASWebAuthenticationSession, the system's login window
/// (a Safari sheet with Safari's cookies, so single sign-on, unless
/// ephemeral), which closes by itself when the provider redirects to the
/// app.
///
/// One login at a time, answered once. A login left running by a Dart
/// isolate that a hot restart replaced is cancelled by the next login's
/// `replaceStale`; one of an engine that went away by [cancel] (the
/// plugin's detach) or when the window is released.
final class WebAuthenticationWindow: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?
  // The answer of the running login, given once: by the session's
  // completion, or by [cancel] (a cancelled session's completion, when
  // it comes, answers nothing).
  private var pendingResult: FlutterResult?
  // Which login the session belongs to: a completion of a cancelled
  // session must not touch the next one.
  private var generation = 0

  deinit {
    session?.cancel()
  }

  /// Ends the running login, if any, answering it `cancelled` (nobody may
  /// hear it: a replaced isolate, an engine gone).
  func cancel() {
    guard let running = session else { return }
    let result = pendingResult
    session = nil
    pendingResult = nil
    generation += 1
    running.cancel()
    result?(FlutterError(code: "cancelled", message: "the login was replaced", details: nil))
  }

  func authorize(
    url: URL, redirect: URL, ephemeral: Bool, replaceStale: Bool = false,
    result: @escaping FlutterResult
  ) {
    if replaceStale {
      cancel()
    }
    guard session == nil else {
      result(FlutterError(code: "in_progress", message: "a login is already running", details: nil))
      return
    }
    generation += 1
    let current = generation
    let completion: (URL?, Error?) -> Void = { [weak self] callback, error in
      DispatchQueue.main.async {
        guard let self = self, self.generation == current else { return }
        self.session = nil
        self.pendingResult = nil
        if let callback = callback {
          result(callback.absoluteString)
        } else if let error = error as? ASWebAuthenticationSessionError,
          error.code == .canceledLogin
        {
          result(FlutterError(code: "cancelled", message: "the user closed the login page", details: nil))
        } else {
          result(
            FlutterError(
              code: "failed", message: error?.localizedDescription ?? "the login failed", details: nil))
        }
      }
    }
    guard let scheme = redirect.scheme?.lowercased() else {
      result(FlutterError(code: "failed", message: "the redirect URI has no scheme", details: nil))
      return
    }
    let session: ASWebAuthenticationSession
    if scheme == "https" {
      guard #available(iOS 17.4, macOS 14.4, *) else {
        result(
          FlutterError(
            code: "unsupported",
            message: "an https redirect needs iOS 17.4 or macOS 14.4: use a custom scheme",
            details: nil))
        return
      }
      guard let host = redirect.host else {
        result(FlutterError(code: "failed", message: "the redirect URI has no host", details: nil))
        return
      }
      let path = redirect.path.isEmpty ? "/" : redirect.path
      session = ASWebAuthenticationSession(
        url: url, callback: .https(host: host, path: path), completionHandler: completion)
    } else if scheme == "http" {
      result(
        FlutterError(
          code: "unsupported",
          message: "an http redirect cannot return to the app: use a custom scheme",
          details: nil))
      return
    } else if #available(iOS 17.4, macOS 14.4, *) {
      session = ASWebAuthenticationSession(
        url: url, callback: .customScheme(scheme), completionHandler: completion)
    } else {
      session = ASWebAuthenticationSession(
        url: url, callbackURLScheme: scheme, completionHandler: completion)
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = ephemeral
    self.session = session
    pendingResult = result
    if !session.start() {
      self.session = nil
      pendingResult = nil
      generation += 1
      result(FlutterError(code: "failed", message: "the login page could not open", details: nil))
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
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
}
