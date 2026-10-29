import CryptoKit
import Foundation
import Security

/// A failed DPoP key call; the message has the OSStatus or the reason,
/// never key material.
struct DPoPKeyError: Error {
  let code: String
  let message: String

  init(_ operation: String, _ status: OSStatus) {
    let text = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "unknown error"
    code = "dpop_key"
    message = "DPoP key \(operation) failed: \(text) (OSStatus \(status))"
  }

  init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

/// The app's DPoP key (RFC 9449): an EC P-256 key pair that signs proofs,
/// whose private key never leaves the Secure Enclave or the Keychain.
///
/// - With a Secure Enclave (iPhones, iPads, Macs with Apple silicon or a
///   T2 chip) the key is made inside it (`kSecAttrTokenIDSecureEnclave`)
///   and only used there.
/// - Without one (the iOS simulator, older Macs), or where it cannot be
///   used (a macOS build signed without the data protection keychain's
///   entitlements: -34018), a software key of the Keychain; the system
///   signs with it, the app never sees it.
///
/// Both are permanent Keychain keys with the application tag
/// `<bundle id>.spring_dpop_key`, usable after the first unlock, on this
/// device only (never in iCloud Keychain or in a backup moved to another
/// device). On macOS without the data protection keychain the software
/// key goes to the login keychain, as the secret store's values do.
final class DPoPKeyStore {
  private let tag = Data(((Bundle.main.bundleIdentifier ?? "app") + ".spring_dpop_key").utf8)

  #if os(macOS)
    // Decided once, as in KeychainSecretStore: the data protection
    // keychain needs entitlements a locally signed debug build lacks.
    private lazy var dataProtection: Bool = {
      var probe: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "app") + ".spring_secret_store",
        kSecAttrAccount as String: "spring_secret_store.probe",
        kSecAttrSynchronizable as String: false,
      ]
      probe[kSecUseDataProtectionKeychain as String] = true
      return SecItemDelete(probe as CFDictionary) != errSecMissingEntitlement
    }()
  #endif

  /// The public key as the uncompressed point `0x04 || X || Y` and where
  /// the private key is (`secureEnclave` or `keychain`); makes the key
  /// when there is none.
  func publicKey() throws -> (Data, String) {
    let (key, storage) = try existingKey() ?? createKey()
    guard let publicKey = SecKeyCopyPublicKey(key) else {
      throw DPoPKeyError(code: "dpop_key", message: "the DPoP key has no public key")
    }
    var error: Unmanaged<CFError>?
    guard let point = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
      throw DPoPKeyError(code: "dpop_key", message: "the public key could not be exported: \(describe(error))")
    }
    return (point, storage)
  }

  /// The DER ECDSA P-256 SHA-256 signature of `data`; fails with the code
  /// `no_key` when there is no key (it is never made here: the Dart side
  /// put the old public key into the proof's header).
  func sign(_ data: Data) throws -> Data {
    guard let found = try existingKey() else {
      throw DPoPKeyError(code: "no_key", message: "there is no DPoP key")
    }
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        found.0, .ecdsaSignatureMessageX962SHA256, data as CFData, &error) as Data?
    else {
      throw DPoPKeyError(code: "dpop_key", message: "signing failed: \(describe(error))")
    }
    return signature
  }

  /// Removes the key (every key with the tag); nothing happens when there
  /// is none.
  func delete() throws {
    // The macOS login keychain deletes one match at a time.
    for _ in 0..<8 {
      let status = SecItemDelete(baseQuery() as CFDictionary)
      if status == errSecItemNotFound {
        return
      }
      guard status == errSecSuccess else { throw DPoPKeyError("delete", status) }
    }
  }

  private func existingKey() throws -> (SecKey, String)? {
    var query = baseQuery()
    query[kSecReturnRef as String] = true
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let attributes = item as? [String: Any],
        let reference = attributes[kSecValueRef as String]
      else {
        return nil
      }
      // swiftlint:disable:next force_cast
      let key = reference as! SecKey
      let token = attributes[kSecAttrTokenID as String] as? String
      let storage = token == (kSecAttrTokenIDSecureEnclave as String) ? "secureEnclave" : "keychain"
      return (key, storage)
    case errSecItemNotFound:
      return nil
    #if os(macOS)
      case errSecInteractionNotAllowed, errSecAuthFailed:
        // A key of another build of an unsigned app, which the login
        // keychain would ask the user about: replaced by a new one.
        try? delete()
        return nil
    #endif
    default:
      throw DPoPKeyError("read", status)
    }
  }

  private func createKey() throws -> (SecKey, String) {
    if usesDataProtection && SecureEnclave.isAvailable {
      if let key = try? createKey(secureEnclave: true) {
        return (key, "secureEnclave")
      }
      // A Secure Enclave the app may not use: a Keychain key instead.
    }
    return (try createKey(secureEnclave: false), "keychain")
  }

  private func createKey(secureEnclave: Bool) throws -> SecKey {
    var privateAttributes: [String: Any] = [
      kSecAttrIsPermanent as String: true,
      kSecAttrApplicationTag as String: tag,
    ]
    if secureEnclave {
      // A Secure Enclave key needs an access control that allows its use.
      var error: Unmanaged<CFError>?
      guard
        let access = SecAccessControlCreateWithFlags(
          kCFAllocatorDefault, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
          .privateKeyUsage, &error)
      else {
        throw DPoPKeyError(code: "dpop_key", message: "no access control: \(describe(error))")
      }
      privateAttributes[kSecAttrAccessControl as String] = access
    } else if usesDataProtection {
      privateAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    }
    var attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecPrivateKeyAttrs as String: privateAttributes,
    ]
    if secureEnclave {
      attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
    }
    #if os(macOS)
      if usesDataProtection {
        attributes[kSecUseDataProtectionKeychain as String] = true
      }
    #endif
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw DPoPKeyError(code: "dpop_key", message: "the DPoP key could not be made: \(describe(error))")
    }
    return key
  }

  private var usesDataProtection: Bool {
    #if os(macOS)
      return dataProtection
    #else
      return true
    #endif
  }

  private func baseQuery() -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
    ]
    #if os(macOS)
      if usesDataProtection {
        query[kSecUseDataProtectionKeychain as String] = true
      } else {
        // Never show the login keychain's prompt.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
      }
    #endif
    return query
  }

  // The error's code and domain only: CFError descriptions are safe, but
  // short is enough.
  private func describe(_ error: Unmanaged<CFError>?) -> String {
    guard let error = error?.takeRetainedValue() else { return "unknown error" }
    return "\(CFErrorGetDomain(error) as String) \(CFErrorGetCode(error))"
  }
}
