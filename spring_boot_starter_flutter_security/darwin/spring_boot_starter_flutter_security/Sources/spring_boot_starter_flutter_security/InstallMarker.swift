import Foundation

/// Forgets the Keychain items of an earlier installation of the app at the
/// first start after a reinstall.
///
/// iOS keeps an app's Keychain items when the app is deleted, so a
/// reinstalled app would find the last user's tokens and DPoP key and log
/// them in again. The app's container (its files) goes with the app, and
/// an update keeps it. So each installation has an id, kept in a file of
/// the container (`Library/Application Support/<bundle id>/spring_boot_starter_flutter_security/install-id`)
/// and in the Keychain:
///
/// - neither has one: a new installation, or the first start after 0.4.x,
///   which kept no id. Nothing is removed (an update never logs anyone
///   out; so an app deleted under 0.4.x and installed again with this
///   version still finds the old login), and the new id goes to both.
/// - the Keychain has one, the file none: the app was deleted and
///   installed again. The secret store's items and the DPoP key are
///   removed before the first Keychain call, and a new id is written.
/// - the file has one, the Keychain none (a backup restored to another
///   device, where items "this device only" do not follow; a reset
///   Keychain): the id is written to the Keychain again.
/// - both, different (a container of another installation restored): the
///   items go too, and the Keychain gets the file's id.
///
/// The file is written first and the Keychain gets an id only once the
/// file has it, so a file that could not be written never reads as a
/// reinstall at the next start. The app's preferences (UserDefaults) play
/// no part: an app that clears them (`SharedPreferences.clear()`) logs
/// nobody out. An app that deletes its whole Application Support folder
/// does: the next start finds the Keychain's id without the file, and the
/// stored login goes, as after a reinstall. The file stays in backups, as
/// the Keychain items do (restored only to the same device): a device
/// restored from its backup gets both back and keeps the login.
///
/// macOS: deleting an app removes neither its data (the container of a
/// sandboxed app, `~/Library/Application Support/<bundle id>` of another)
/// nor its Keychain items, so a reinstalled app finds the last login
/// there. The marker acts only when the data was removed and the Keychain
/// items were not (an uninstaller that deletes the container, or the
/// folder deleted by hand): the stored login goes with the data.
///
/// Decided once per process, whatever the number of engines, on the
/// plugin's Keychain queue (one for the process) before the first
/// Keychain call; tried again at the next call when the Keychain or the
/// file cannot be read yet (before the first unlock).
final class InstallMarker {
  /// The marker of the app.
  static let shared = InstallMarker()

  private static let account = "install-id"
  private let marker: KeychainSecretStore
  private let file: URL?
  private let lock = NSLock()
  private var checked = false

  init(
    file: URL? = InstallMarker.defaultFile(),
    marker: KeychainSecretStore = KeychainSecretStore(serviceSuffix: "spring_install")
  ) {
    self.file = file
    self.marker = marker
  }

  /// `Library/Application Support/<bundle id>/spring_boot_starter_flutter_security/install-id`
  /// of the app's container (on iOS, and for a sandboxed macOS app) or of
  /// the user (a macOS app without a sandbox: the bundle id keeps apps
  /// apart).
  static func defaultFile() -> URL? {
    guard
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else {
      return nil
    }
    return
      support
      .appendingPathComponent(Bundle.main.bundleIdentifier ?? "app", isDirectory: true)
      .appendingPathComponent("spring_boot_starter_flutter_security", isDirectory: true)
      .appendingPathComponent("install-id", isDirectory: false)
  }

  func check(store: KeychainSecretStore, dPoPKey: DPoPKeyStore) {
    lock.lock()
    defer { lock.unlock() }
    if checked { return }
    guard let file = file else {
      // No Application Support folder: nothing to compare with.
      checked = true
      return
    }
    let installed: String?
    switch readFile(file) {
    case .missing: installed = nil
    case .found(let id): installed = id
    case .unreadable: return
    }
    let kept: String?
    do {
      kept = try marker.read(key: Self.account)
    } catch {
      return
    }
    checked = true
    switch (installed, kept) {
    case (nil, nil):
      remember(UUID().uuidString, in: file)
    case (nil, .some):
      // Reinstalled: the Keychain outlived the app.
      forget(store: store, dPoPKey: dPoPKey)
      remember(UUID().uuidString, in: file)
    case let (.some(id), nil):
      try? marker.write(key: Self.account, value: id)
    case let (.some(id), .some(other)) where id != other:
      forget(store: store, dPoPKey: dPoPKey)
      try? marker.write(key: Self.account, value: id)
    default:
      break
    }
  }

  private enum Stored {
    case missing
    case found(String)
    // It exists but cannot be read yet (data protection before the first
    // unlock): nothing is decided.
    case unreadable
  }

  private func readFile(_ file: URL) -> Stored {
    guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
    guard let data = try? Data(contentsOf: file) else { return .unreadable }
    let id = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    // An empty file was never written by the marker: as none.
    return id.isEmpty ? .missing : .found(id)
  }

  // The file first; the Keychain only when the file has the id. When the
  // file cannot be written, the Keychain's id goes too, so the next start
  // sees neither (no reinstall) and tries again.
  private func remember(_ id: String, in file: URL) {
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      var options: Data.WritingOptions = [.atomic]
      #if os(iOS)
        // Readable after the first unlock, as the Keychain items.
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
      #endif
      try Data(id.utf8).write(to: file, options: options)
    } catch {
      try? marker.delete(key: Self.account)
      return
    }
    try? marker.write(key: Self.account, value: id)
  }

  private func forget(store: KeychainSecretStore, dPoPKey: DPoPKeyStore) {
    try? store.deleteAll()
    try? dPoPKey.delete()
  }
}
