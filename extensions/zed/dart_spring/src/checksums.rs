//! The SHA-256 of each downloaded server, as the release built it: `server.sha256` beside
//! `Cargo.toml`, one `<hex>  <asset name>` line per asset (the hash of the executable inside the
//! archive, which is what `zed::download_file` leaves on disk). The release workflow writes the
//! file into the release commit, so the extension of a version only runs the binaries of that
//! version's build. An asset without a line is not run.

use std::fs::File;
use std::io::Read;

use sha2::{Digest, Sha256};

/// The hashes this extension was built with.
const SERVER_SHA256: &str = include_str!("../server.sha256");

/// The hash of [asset_name] in [listing] (`sha256sum` format), lower case.
pub fn expected_in(listing: &str, asset_name: &str) -> Option<String> {
    listing.lines().find_map(|line| {
        let mut parts = line.split_whitespace();
        let hash = parts.next()?;
        let name = parts.next()?.trim_start_matches('*');
        (name == asset_name && hash.len() == 64 && hash.chars().all(|c| c.is_ascii_hexdigit()))
            .then(|| hash.to_ascii_lowercase())
    })
}

/// The hex SHA-256 of the file at [path].
pub fn sha256_of(path: &str) -> Result<String, String> {
    let mut file = File::open(path).map_err(|e| format!("could not read {path}: {e}"))?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 1 << 16];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|e| format!("could not read {path}: {e}"))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect())
}

/// Whether the executable at [path] is the one the release built as [asset_name]; the reason
/// when it is not, or when this build of the extension knows no hash for it.
pub fn verify(path: &str, asset_name: &str) -> Result<(), String> {
    verify_against(SERVER_SHA256, path, asset_name)
}

fn verify_against(listing: &str, path: &str, asset_name: &str) -> Result<(), String> {
    let Some(expected) = expected_in(listing, asset_name) else {
        return Err(format!(
            "dart_spring: this build of the extension has no SHA-256 for {asset_name}, so the \
             download is not run. Put a dart_spring_lsp of this version on the PATH, or set \
             lsp.dart-spring.binary.path."
        ));
    };
    let actual = sha256_of(path)?;
    if actual != expected {
        return Err(format!(
            "dart_spring: the downloaded {asset_name} is not the release's build \
             (SHA-256 {actual}, expected {expected}); it was deleted and is not run"
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    const ASSET: &str = "dart_spring_lsp-macos-arm64.tar.gz";
    // SHA-256 of "abc".
    const ABC: &str = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";

    fn file_with(content: &[u8], name: &str) -> String {
        let path = std::env::temp_dir().join(format!("dart_spring_checksums_{name}"));
        fs::write(&path, content).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn reads_sha256sum_lines() {
        let listing = format!("{ABC}  {ASSET}\n{}  *other.zip\n", "0".repeat(64));
        assert_eq!(expected_in(&listing, ASSET), Some(ABC.to_string()));
        assert_eq!(expected_in(&listing, "other.zip"), Some("0".repeat(64)));
        assert_eq!(expected_in(&listing, "missing"), None);
        assert_eq!(expected_in(&format!("abc  {ASSET}"), ASSET), None);
    }

    #[test]
    fn hashes_a_file() {
        assert_eq!(sha256_of(&file_with(b"abc", "hash")).unwrap(), ABC);
    }

    #[test]
    fn the_release_build_passes() {
        let path = file_with(b"abc", "pass");
        assert_eq!(
            verify_against(&format!("{ABC}  {ASSET}"), &path, ASSET),
            Ok(())
        );
    }

    #[test]
    fn another_binary_is_refused() {
        let path = file_with(b"abd", "refused");
        let error = verify_against(&format!("{ABC}  {ASSET}"), &path, ASSET).unwrap_err();
        assert!(error.contains("not the release's build"), "{error}");
    }

    #[test]
    fn an_asset_without_a_hash_is_not_run() {
        let path = file_with(b"abc", "unknown");
        let error = verify_against("", &path, ASSET).unwrap_err();
        assert!(error.contains("no SHA-256"), "{error}");
    }
}
