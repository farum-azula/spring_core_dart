//! The files of downloaded servers in the extension's work directory: a folder per release
//! (`dart_spring_lsp-v0.8.4/dart_spring_lsp`), and a copy of the current one at `bin/`, a path that
//! does not change between versions, to run `dart_spring_lsp create my_app` by hand (see the
//! README).

use std::fs;
use std::path::Path;

use zed_extension_api::{self as zed, Os};

/// The server's executable, as the releases and `tool/install_language_server.dart` name it.
pub const EXECUTABLE: &str = "dart_spring_lsp";

/// `dart_spring_lsp`, `dart_spring_lsp.exe` on Windows.
pub fn executable_file_name(os: Os) -> String {
    match os {
        Os::Windows => format!("{EXECUTABLE}.exe"),
        Os::Mac | Os::Linux => EXECUTABLE.to_string(),
    }
}

/// The folder of the release [tag]: `dart_spring_lsp-v0.8.4`.
pub fn version_directory(tag: &str) -> String {
    format!("{EXECUTABLE}-{tag}")
}

/// Whether [name] is the folder of a release (`dart_spring_lsp-v0.8.4`, `dart_spring_lsp-v0.9.0-dev.1`),
/// and not anything else that starts the same, such as an asset (`dart_spring_lsp-macos-arm64`).
pub fn is_version_directory(name: &str) -> bool {
    let Some(version) = name
        .strip_prefix(EXECUTABLE)
        .and_then(|rest| rest.strip_prefix("-v"))
    else {
        return false;
    };
    let (core, suffix) = match version.find(['-', '+']) {
        Some(index) => version.split_at(index),
        None => (version, ""),
    };
    let numbers: Vec<&str> = core.split('.').collect();
    numbers.len() == 3
        && numbers
            .iter()
            .all(|number| !number.is_empty() && number.chars().all(|c| c.is_ascii_digit()))
        && suffix
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '+' | '.'))
}

/// `bin/dart_spring_lsp` (`.exe` on Windows).
pub fn stable_path(os: Os) -> String {
    format!("bin/{}", executable_file_name(os))
}

pub fn is_file(path: impl AsRef<Path>) -> bool {
    fs::metadata(path).is_ok_and(|stat| stat.is_file())
}

/// Copies [binary] to [stable_path].
pub fn publish_stable_copy(binary: &str, os: Os) -> Result<(), String> {
    let stable = stable_path(os);
    let failed = |e: String| format!("could not copy the server to {stable}: {e}");
    fs::create_dir_all("bin").map_err(|e| failed(e.to_string()))?;
    fs::copy(binary, &stable).map_err(|e| failed(e.to_string()))?;
    zed::make_file_executable(&stable).map_err(failed)
}

/// Deletes the folders of other releases in [directory], keeping [keep]; the deletions that
/// failed.
pub fn remove_other_versions(directory: &Path, keep: &str) -> Vec<String> {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(e) => return vec![format!("could not list {}: {e}", directory.display())],
    };
    entries
        .flatten()
        .filter(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            name != keep && is_version_directory(&name) && entry.path().is_dir()
        })
        .filter_map(|entry| {
            fs::remove_dir_all(entry.path())
                .err()
                .map(|e| format!("could not delete {}: {e}", entry.path().display()))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_executable_has_exe_on_windows_only() {
        assert_eq!(executable_file_name(Os::Mac), "dart_spring_lsp");
        assert_eq!(executable_file_name(Os::Linux), "dart_spring_lsp");
        assert_eq!(executable_file_name(Os::Windows), "dart_spring_lsp.exe");
        assert_eq!(stable_path(Os::Windows), "bin/dart_spring_lsp.exe");
        assert_eq!(stable_path(Os::Mac), "bin/dart_spring_lsp");
    }

    #[test]
    fn a_release_has_a_folder_of_its_tag() {
        assert_eq!(version_directory("v0.8.4"), "dart_spring_lsp-v0.8.4");
        assert!(is_version_directory(&version_directory("v0.8.4")));
    }

    #[test]
    fn release_folders_are_told_from_other_files() {
        for name in [
            "dart_spring_lsp-v0.8.3",
            "dart_spring_lsp-v10.0.12",
            "dart_spring_lsp-v0.9.0-dev.1",
            "dart_spring_lsp-v0.9.0+build.7",
        ] {
            assert!(is_version_directory(name), "{name}");
        }
        for name in [
            "dart_spring_lsp-macos-arm64",
            "dart_spring_lsp-macos-arm64.tar.gz",
            "dart_spring_lsp-linux-x64",
            "dart_spring_lsp-windows-x64.zip",
            "dart_spring_lsp-v0.8",
            "dart_spring_lsp-v0.8.x",
            "dart_spring_lsp-v",
            "dart_spring_lsp-0.8.4",
            "dart_spring_lsp",
            "bin",
            "other-v0.8.4",
        ] {
            assert!(!is_version_directory(name), "{name}");
        }
    }

    #[test]
    fn only_the_folders_of_other_releases_are_deleted() {
        let root =
            std::env::temp_dir().join(format!("dart_spring_server_files_{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        for folder in [
            "dart_spring_lsp-v0.8.3",
            "dart_spring_lsp-v0.8.4",
            "dart_spring_lsp-macos-arm64",
            "bin",
        ] {
            fs::create_dir_all(root.join(folder)).unwrap();
        }
        fs::write(root.join("dart_spring_lsp-v0.8.2"), "a file, not a folder").unwrap();

        let failures = remove_other_versions(&root, "dart_spring_lsp-v0.8.4");

        let mut left: Vec<String> = fs::read_dir(&root)
            .unwrap()
            .flatten()
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .collect();
        left.sort();
        fs::remove_dir_all(&root).unwrap();
        assert!(failures.is_empty(), "{failures:?}");
        assert_eq!(
            left,
            [
                "bin",
                "dart_spring_lsp-macos-arm64",
                "dart_spring_lsp-v0.8.2",
                "dart_spring_lsp-v0.8.4"
            ]
        );
    }

    #[test]
    fn a_folder_that_cannot_be_listed_is_reported() {
        let failures = remove_other_versions(Path::new("/no/such/folder"), "x");
        assert_eq!(failures.len(), 1);
        assert!(failures[0].starts_with("could not list /no/such/folder"));
    }
}
