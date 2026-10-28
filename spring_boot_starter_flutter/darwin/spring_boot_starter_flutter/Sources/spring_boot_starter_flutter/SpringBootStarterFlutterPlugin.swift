#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// The iOS and macOS side of spring_boot_starter_flutter: the token store
/// (`spring_boot_starter_flutter/token_store`) on the Keychain and the
/// login browser (`spring_boot_starter_flutter/authorization_browser`) on
/// ASWebAuthenticationSession.
public final class SpringBootStarterFlutterPlugin: NSObject, FlutterPlugin {
  private let tokenStore = KeychainTokenStore()
  private let browser = WebAuthenticationBrowser()
  // Keychain calls may block: they run here, one after the other.
  private let keychainQueue = DispatchQueue(label: "spring_boot_starter_flutter.keychain")

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let instance = SpringBootStarterFlutterPlugin()
    FlutterMethodChannel(name: "spring_boot_starter_flutter/token_store", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in instance.handleTokenStore(call, result: result) }
    FlutterMethodChannel(
      name: "spring_boot_starter_flutter/authorization_browser", binaryMessenger: messenger
    ).setMethodCallHandler { call, result in instance.handleBrowser(call, result: result) }
  }

  private func handleTokenStore(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    guard let key = arguments?["key"] as? String, !key.isEmpty else {
      result(FlutterError(code: "keychain", message: "a key is required", details: nil))
      return
    }
    let value = arguments?["value"] as? String
    let method = call.method
    if method == "write" && value == nil {
      result(FlutterError(code: "keychain", message: "a value is required", details: nil))
      return
    }
    guard ["read", "write", "delete"].contains(method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    let store = tokenStore
    keychainQueue.async {
      let answer: Any?
      do {
        switch method {
        case "read": answer = try store.read(key: key)
        case "write":
          try store.write(key: key, value: value!)
          answer = nil
        default:
          try store.delete(key: key)
          answer = nil
        }
      } catch let error as KeychainError {
        answer = FlutterError(code: "keychain", message: error.message, details: nil)
      } catch {
        answer = FlutterError(code: "keychain", message: "\(error)", details: nil)
      }
      DispatchQueue.main.async { result(answer) }
    }
  }

  private func handleBrowser(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "authorize" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let arguments = call.arguments as? [String: Any]
    guard let url = (arguments?["url"] as? String).flatMap(URL.init(string:)),
      let redirect = (arguments?["redirectUri"] as? String).flatMap(URL.init(string:))
    else {
      result(FlutterError(code: "failed", message: "url and redirectUri are required", details: nil))
      return
    }
    let ephemeral = arguments?["preferEphemeralSession"] as? Bool ?? false
    browser.authorize(url: url, redirect: redirect, ephemeral: ephemeral, result: result)
  }
}
