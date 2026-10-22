//! Starts the flutter_spring language server for Dart files.
//!
//! The server is looked up in this order:
//! 1. `lsp.flutter-spring.binary` in Zed settings (`path` and `arguments`);
//! 2. a `flutter_spring_lsp` executable on the PATH (for development:
//!    `dart run tool/install_language_server.dart`);
//! 3. the binary of this extension's version, downloaded once from the
//!    GitHub release `v<version>` of farum-azula/spring_core_dart (the
//!    latest release if that one has no binaries).
//!
//! It must be a native executable: `dart pub global run` prints resolution
//! messages to stdout, which is the channel LSP uses.

use std::fs;

use zed_extension_api::{
    self as zed, settings::LspSettings, Architecture, DownloadedFileType, GithubRelease,
    GithubReleaseOptions, LanguageServerId, LanguageServerInstallationStatus, Os, Result,
};

const REPOSITORY: &str = "farum-azula/spring_core_dart";
const EXECUTABLE: &str = "flutter_spring_lsp";

struct FlutterSpring {
    /// Path of the downloaded server, once known.
    cached: Option<String>,
}

impl FlutterSpring {
    fn downloaded_server(&mut self, id: &LanguageServerId) -> Result<String> {
        if let Some(path) = &self.cached {
            if fs::metadata(path).is_ok_and(|stat| stat.is_file()) {
                return Ok(path.clone());
            }
        }

        zed::set_language_server_installation_status(
            id,
            &LanguageServerInstallationStatus::CheckingForUpdate,
        );
        let (os, arch) = zed::current_platform();
        let asset_name = asset_name(os, arch)?;
        let release = release_with(&asset_name)?;
        let asset = release
            .assets
            .iter()
            .find(|asset| asset.name == asset_name)
            .ok_or_else(|| format!("{asset_name} is missing in release {}", release.version))?;

        let directory = format!("{EXECUTABLE}-{}", release.version);
        let binary = format!(
            "{directory}/{EXECUTABLE}{}",
            if os == Os::Windows { ".exe" } else { "" }
        );
        if !fs::metadata(&binary).is_ok_and(|stat| stat.is_file()) {
            zed::set_language_server_installation_status(
                id,
                &LanguageServerInstallationStatus::Downloading,
            );
            let file_type = if os == Os::Windows {
                DownloadedFileType::Zip
            } else {
                DownloadedFileType::GzipTar
            };
            zed::download_file(&asset.download_url, &directory, file_type)
                .map_err(|error| format!("downloading {asset_name} failed: {error}"))?;
            zed::make_file_executable(&binary)?;
            remove_other_versions(&directory);
        }
        zed::set_language_server_installation_status(id, &LanguageServerInstallationStatus::None);
        self.cached = Some(binary.clone());
        Ok(binary)
    }
}

/// `flutter_spring_lsp-macos-arm64.tar.gz`, ... as built by
/// `.github/workflows/language-server.yml`.
fn asset_name(os: Os, arch: Architecture) -> Result<String> {
    let name = match (os, arch) {
        (Os::Mac, Architecture::Aarch64) => "macos-arm64.tar.gz",
        (Os::Linux, Architecture::X8664) => "linux-x64.tar.gz",
        (Os::Linux, Architecture::Aarch64) => "linux-arm64.tar.gz",
        (Os::Windows, Architecture::X8664) => "windows-x64.zip",
        _ => {
            return Err(format!(
                "flutter_spring: no prebuilt language server for this platform. \
                 Build it with `dart run tool/install_language_server.dart` in the \
                 {REPOSITORY} repository and put {EXECUTABLE} on the PATH."
            ))
        }
    };
    Ok(format!("{EXECUTABLE}-{name}"))
}

/// The release of this extension's version, else the latest one with
/// [asset_name] (the server and the extension are released together).
fn release_with(asset_name: &str) -> Result<GithubRelease> {
    let own = format!("v{}", env!("CARGO_PKG_VERSION"));
    if let Ok(release) = zed::github_release_by_tag_name(REPOSITORY, &own) {
        if release.assets.iter().any(|asset| asset.name == asset_name) {
            return Ok(release);
        }
    }
    zed::latest_github_release(
        REPOSITORY,
        GithubReleaseOptions {
            require_assets: true,
            pre_release: false,
        },
    )
}

fn remove_other_versions(keep: &str) {
    let Ok(entries) = fs::read_dir(".") else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with(&format!("{EXECUTABLE}-")) && name != keep {
            let _ = fs::remove_dir_all(entry.path());
        }
    }
}

impl zed::Extension for FlutterSpring {
    fn new() -> Self {
        FlutterSpring { cached: None }
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let env = worktree.shell_env();
        let binary = LspSettings::for_worktree(language_server_id.as_ref(), worktree)
            .ok()
            .and_then(|settings| settings.binary);
        let args = binary
            .as_ref()
            .and_then(|binary| binary.arguments.clone())
            .unwrap_or_default();

        let command = match binary.and_then(|binary| binary.path) {
            Some(path) => path,
            None => match worktree.which(EXECUTABLE) {
                Some(path) => path,
                None => self.downloaded_server(language_server_id)?,
            },
        };
        Ok(zed::Command { command, args, env })
    }
}

zed::register_extension!(FlutterSpring);
