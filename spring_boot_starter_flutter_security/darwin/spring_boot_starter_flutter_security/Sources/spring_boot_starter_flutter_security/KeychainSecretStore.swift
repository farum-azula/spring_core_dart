import Foundation
import Security

/// A failed Keychain call; the message has the OSStatus, never a value.
struct KeychainError: Error {
  let message: String

  init(_ operation: String, _ status: OSStatus) {
    let text = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "unknown error"
    message = "Keychain \(operation) failed: \(text) (OSStatus \(status))"
  }
}

/// Values as generic passwords of the Keychain: the service
/// `<bundle id>.spring_secret_store`, the account is the key, readable
/// after the first unlock, on this device only, never synchronized.
///
/// On macOS the data protection keychain (the iOS-style one) is used when
/// the app may use it: it needs a signed app with an application
/// identifier or a keychain access group (a team). A debug build signed
/// to run locally gets errSecMissingEntitlement (-34018) there, so such an
/// app falls back to the login keychain (file-based; items are bound to
/// the app's code signature, and accessibility attributes do not apply).
final class KeychainSecretStore {
  private let service = (Bundle.main.bundleIdentifier ?? "app") + ".spring_secret_store"

  #if os(macOS)
    // Decided once: a search finds nothing without the entitlement (no
    // error), a delete of an item that does not exist reports it.
    private lazy var dataProtection: Bool = {
      let probe = baseQuery(account: "spring_secret_store.probe", dataProtection: true)
      return SecItemDelete(probe as CFDictionary) != errSecMissingEntitlement
    }()
  #endif

  func read(key: String) throws -> String? {
    var query = query(account: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
        return nil
      }
      return value
    case errSecItemNotFound:
      return nil
    #if os(macOS)
      case errSecInteractionNotAllowed, errSecAuthFailed:
        // The login keychain would ask the user (an item of another build
        // of an unsigned app): read as missing, the user logs in again.
        return nil
    #endif
    default:
      throw KeychainError("read", status)
    }
  }

  func write(key: String, value: String) throws {
    let data = Data(value.utf8)
    let query = query(account: key)
    var attributes: [String: Any] = [kSecValueData as String: data]
    if usesDataProtection {
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    }
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    #if os(macOS)
      if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
        // An item this build may not change: replaced.
        SecItemDelete(query as CFDictionary)
        status = errSecItemNotFound
      }
    #endif
    if status == errSecItemNotFound {
      let item = query.merging(attributes) { _, new in new }
      status = SecItemAdd(item as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw KeychainError("write", status) }
  }

  func delete(key: String) throws {
    let status = SecItemDelete(query(account: key) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError("delete", status)
    }
  }

  /// The accounts (keys) of this app's items; the values are not read.
  func keys() throws -> [String] {
    var query = baseQuery(account: nil, dataProtection: usesDataProtection)
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    var items: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &items)
    switch status {
    case errSecSuccess:
      let found = items as? [[String: Any]] ?? []
      return found.compactMap { $0[kSecAttrAccount as String] as? String }
    case errSecItemNotFound:
      return []
    default:
      throw KeychainError("list", status)
    }
  }

  /// Removes every item of this app, one key at a time (the macOS login
  /// keychain deletes only the first match of a broader query).
  func deleteAll() throws {
    for key in try keys() {
      try delete(key: key)
    }
  }

  private var usesDataProtection: Bool {
    #if os(macOS)
      return dataProtection
    #else
      return true
    #endif
  }

  private func query(account: String) -> [String: Any] {
    baseQuery(account: account, dataProtection: usesDataProtection)
  }

  private func baseQuery(account: String?, dataProtection: Bool) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if let account = account {
      query[kSecAttrAccount as String] = account
    }
    if dataProtection {
      query[kSecAttrSynchronizable as String] = false
      #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
      #endif
    } else {
      #if os(macOS)
        // Never show the login keychain's password prompt.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
      #endif
    }
    return query
  }
}
