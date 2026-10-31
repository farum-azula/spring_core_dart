#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// The iOS and macOS side of spring_boot_starter_flutter_security: the secret store
/// (`spring_boot_starter_flutter_security/secret_store`) on the Keychain, the
/// DPoP key (`spring_boot_starter_flutter_security/dpop_key`) in the Secure Enclave
/// or the Keychain, and the login window
/// (`spring_boot_starter_flutter_security/authorization_window`) on
/// ASWebAuthenticationSession, and Sign in with Apple's sheet
/// (`spring_boot_starter_flutter_security/native_sign_in`).
public final class SpringBootStarterFlutterSecurityPlugin: NSObject, FlutterPlugin {
  private let secretStore = KeychainSecretStore()
  private let dPoPKey = DPoPKeyStore()
  private let window = WebAuthenticationWindow()
  private let appleIdSignIn = AppleIdSignIn()
  private let installMarker = InstallMarker.shared
  // Keychain calls may block: they run here, one after the other, for
  // every engine of the process (two engines starting together never
  // race on the install marker, a new item or the DPoP key's creation).
  private static let keychainQueue = DispatchQueue(label: "spring_boot_starter_flutter_security.keychain")
  private var keychainQueue: DispatchQueue { Self.keychainQueue }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let instance = SpringBootStarterFlutterSecurityPlugin()
    // Published so iOS calls detachFromEngine(for:) when the engine goes.
    registrar.publish(instance)
    FlutterMethodChannel(name: "spring_boot_starter_flutter_security/secret_store", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in instance.handleSecretStore(call, result: result) }
    FlutterMethodChannel(name: "spring_boot_starter_flutter_security/dpop_key", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in instance.handleDPoPKey(call, result: result) }
    FlutterMethodChannel(
      name: "spring_boot_starter_flutter_security/authorization_window", binaryMessenger: messenger
    ).setMethodCallHandler { call, result in instance.handleWindow(call, result: result) }
    FlutterMethodChannel(
      name: "spring_boot_starter_flutter_security/native_sign_in", binaryMessenger: messenger
    ).setMethodCallHandler { call, result in instance.handleNativeSignIn(call, result: result) }
  }

  #if os(iOS)
    // The engine went away: a login it started has nobody to answer.
    // (macOS has no such call: the window cancels its login when it is
    // released with the plugin.)
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
      window.cancel()
    }
  #endif

  // Sign in with Apple's sheet. The answer holds credentials: never
  // logged, never put into an error.
  private func handleNativeSignIn(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "appleIdSignIn" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let arguments = call.arguments as? [String: Any]
    guard let nonce = arguments?["nonce"] as? String, !nonce.isEmpty,
      let state = arguments?["state"] as? String, !state.isEmpty
    else {
      result(FlutterError(code: "failed", message: "nonce and state are required", details: nil))
      return
    }
    let scopes = arguments?["scopes"] as? [String] ?? []
    appleIdSignIn.signIn(scopes: scopes, nonce: nonce, state: state, result: result)
  }

  private func handleSecretStore(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let method = call.method
    guard ["read", "write", "delete", "keys", "deleteAll"].contains(method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    let arguments = call.arguments as? [String: Any]
    let key = arguments?["key"] as? String ?? ""
    if ["read", "write", "delete"].contains(method) && key.isEmpty {
      result(FlutterError(code: "keychain", message: "a key is required", details: nil))
      return
    }
    let value = arguments?["value"] as? String
    if method == "write" && value == nil {
      result(FlutterError(code: "keychain", message: "a value is required", details: nil))
      return
    }
    let store = secretStore
    let dPoP = dPoPKey
    let marker = installMarker
    keychainQueue.async {
      marker.check(store: store, dPoPKey: dPoP)
      let answer: Any?
      do {
        switch method {
        case "read": answer = try store.read(key: key)
        case "write":
          try store.write(key: key, value: value!)
          answer = nil
        case "delete":
          try store.delete(key: key)
          answer = nil
        case "keys": answer = try store.keys()
        default:
          try store.deleteAll()
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

  // Never puts key material into an error or a log: the messages carry
  // OSStatus codes only.
  private func handleDPoPKey(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let method = call.method
    guard ["dpopPublicJwk", "dpopSign", "dpopDelete"].contains(method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    let arguments = call.arguments as? [String: Any]
    let data = (arguments?["data"] as? FlutterStandardTypedData)?.data
    if method == "dpopSign" && data == nil {
      result(FlutterError(code: "dpop_key", message: "data is required", details: nil))
      return
    }
    let key = dPoPKey
    let store = secretStore
    let marker = installMarker
    keychainQueue.async {
      marker.check(store: store, dPoPKey: key)
      let answer: Any?
      do {
        switch method {
        case "dpopPublicJwk":
          let (point, storage) = try key.publicKey()
          answer = ["publicKey": FlutterStandardTypedData(bytes: point), "storage": storage]
        case "dpopSign":
          answer = FlutterStandardTypedData(bytes: try key.sign(data!))
        default:
          try key.delete()
          answer = nil
        }
      } catch let error as DPoPKeyError {
        answer = FlutterError(code: error.code, message: error.message, details: nil)
      } catch {
        answer = FlutterError(code: "dpop_key", message: "\(type(of: error))", details: nil)
      }
      DispatchQueue.main.async { result(answer) }
    }
  }

  private func handleWindow(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
    // The first login of the engine's root isolate: a login still running
    // belongs to the isolate a hot restart replaced (a background isolate
    // never sends it).
    let replaceStale = arguments?["replaceStale"] as? Bool ?? false
    window.authorize(
      url: url, redirect: redirect, ephemeral: ephemeral, replaceStale: replaceStale, result: result)
  }
}
