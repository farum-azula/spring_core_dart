//! The GitHub release to download the server from: this extension's own (`v<version>`) only. A
//! binary of another release would not match the SHA-256 this build of the extension carries
//! ([`crate::checksums`]), so there is no fallback to the latest release.

use zed_extension_api::{self as zed, Architecture, GithubRelease, Os, Result};

use crate::server_files::EXECUTABLE;

pub const REPOSITORY: &str = "farum-azula/spring_core_dart";

/// Where releases come from.
pub trait ReleaseSource {
    fn by_tag(&self, tag: &str) -> Result<GithubRelease>;
}

/// The releases of [REPOSITORY] on GitHub.
pub struct GithubReleases;

impl ReleaseSource for GithubReleases {
    fn by_tag(&self, tag: &str) -> Result<GithubRelease> {
        zed::github_release_by_tag_name(REPOSITORY, tag)
    }
}

/// `dart_spring_lsp-macos-arm64.tar.gz`, ... as `.github/workflows/language-server.yml` builds
/// them.
pub fn asset_name(os: Os, arch: Architecture) -> Result<String> {
    let platform = match (os, arch) {
        (Os::Mac, Architecture::Aarch64) => "macos-arm64.tar.gz",
        (Os::Linux, Architecture::X8664) => "linux-x64.tar.gz",
        (Os::Linux, Architecture::Aarch64) => "linux-arm64.tar.gz",
        (Os::Windows, Architecture::X8664) => "windows-x64.zip",
        _ => {
            return Err(format!(
                "dart_spring: no prebuilt language server for this platform. \
                 Build it with `dart run tool/install_language_server.dart` in the \
                 {REPOSITORY} repository and put {EXECUTABLE} on the PATH."
            ))
        }
    };
    Ok(format!("{EXECUTABLE}-{platform}"))
}

/// The release [own_tag] when it has [asset_name]; otherwise an error that says how to get a
/// server meanwhile.
pub fn release_with(
    releases: &impl ReleaseSource,
    own_tag: &str,
    asset_name: &str,
) -> Result<GithubRelease> {
    let problem = match releases.by_tag(own_tag) {
        Ok(release) if has_asset(&release, asset_name) => return Ok(release),
        Ok(_) => format!("release {own_tag} has no {asset_name} yet (try again later)"),
        Err(e) => format!("release {own_tag} could not be read ({e})"),
    };
    Err(format!(
        "dart_spring: {problem}. Meanwhile put a dart_spring_lsp of this version on the PATH \
         (`dart run tool/install_language_server.dart`), or set lsp.dart-spring.binary.path."
    ))
}

pub fn has_asset(release: &GithubRelease, asset_name: &str) -> bool {
    release.assets.iter().any(|asset| asset.name == asset_name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use zed_extension_api::GithubReleaseAsset;

    const ASSET: &str = "dart_spring_lsp-macos-arm64.tar.gz";

    fn release(version: &str, assets: &[&str]) -> GithubRelease {
        GithubRelease {
            version: version.into(),
            assets: assets
                .iter()
                .map(|name| GithubReleaseAsset {
                    name: name.to_string(),
                    download_url: format!("https://example.com/{version}/{name}"),
                })
                .collect(),
        }
    }

    struct FakeReleases {
        own: Result<GithubRelease>,
    }

    impl ReleaseSource for FakeReleases {
        fn by_tag(&self, _tag: &str) -> Result<GithubRelease> {
            self.own.clone()
        }
    }

    fn choose(releases: FakeReleases) -> Result<String> {
        release_with(&releases, "v0.8.4", ASSET).map(|release| release.version)
    }

    #[test]
    fn names_the_asset_of_each_platform() {
        assert_eq!(
            asset_name(Os::Mac, Architecture::Aarch64).unwrap(),
            "dart_spring_lsp-macos-arm64.tar.gz"
        );
        assert_eq!(
            asset_name(Os::Linux, Architecture::X8664).unwrap(),
            "dart_spring_lsp-linux-x64.tar.gz"
        );
        assert_eq!(
            asset_name(Os::Linux, Architecture::Aarch64).unwrap(),
            "dart_spring_lsp-linux-arm64.tar.gz"
        );
        assert_eq!(
            asset_name(Os::Windows, Architecture::X8664).unwrap(),
            "dart_spring_lsp-windows-x64.zip"
        );
    }

    #[test]
    fn a_platform_without_a_binary_says_how_to_build_one() {
        let error = asset_name(Os::Mac, Architecture::X8664).err().unwrap();
        assert!(
            error.contains("tool/install_language_server.dart"),
            "{error}"
        );
        assert!(asset_name(Os::Windows, Architecture::Aarch64).is_err());
        assert!(asset_name(Os::Linux, Architecture::X86).is_err());
    }

    #[test]
    fn the_own_release_is_taken() {
        assert_eq!(
            choose(FakeReleases {
                own: Ok(release("v0.8.4", &[ASSET])),
            }),
            Ok("v0.8.4".into())
        );
    }

    #[test]
    fn without_its_binaries_no_other_release_is_taken() {
        let error = choose(FakeReleases {
            own: Ok(release("v0.8.4", &["dart_spring_lsp-linux-x64.tar.gz"])),
        })
        .unwrap_err();
        assert!(
            error.contains("release v0.8.4 has no dart_spring_lsp-macos-arm64.tar.gz yet"),
            "{error}"
        );
        assert!(error.contains("binary.path"), "{error}");
    }

    #[test]
    fn an_own_release_that_cannot_be_read_is_an_error() {
        let error = choose(FakeReleases {
            own: Err("rate limited".into()),
        })
        .unwrap_err();
        assert!(
            error.contains("release v0.8.4 could not be read (rate limited)"),
            "{error}"
        );
    }
}
