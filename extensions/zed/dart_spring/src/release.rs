//! The GitHub release to download the server from: this extension's own (`v<version>`), else the
//! latest one, with a warning (the binaries are built after the tag is pushed, so for a while a
//! new release has none).

use zed_extension_api::{
    self as zed, Architecture, GithubRelease, GithubReleaseOptions, Os, Result,
};

use crate::server_files::EXECUTABLE;
use crate::warnings::Warnings;

pub const REPOSITORY: &str = "farum-azula/spring_core_dart";

/// Where releases come from.
pub trait ReleaseSource {
    fn by_tag(&self, tag: &str) -> Result<GithubRelease>;
    /// The latest release that has binaries.
    fn latest(&self) -> Result<GithubRelease>;
}

/// The releases of [REPOSITORY] on GitHub.
pub struct GithubReleases;

impl ReleaseSource for GithubReleases {
    fn by_tag(&self, tag: &str) -> Result<GithubRelease> {
        zed::github_release_by_tag_name(REPOSITORY, tag)
    }

    fn latest(&self) -> Result<GithubRelease> {
        zed::latest_github_release(
            REPOSITORY,
            GithubReleaseOptions {
                require_assets: true,
                pre_release: false,
            },
        )
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

/// The release [own_tag] when it has [asset_name], else the latest one, with a warning when that
/// is another release.
pub fn release_with(
    releases: &impl ReleaseSource,
    own_tag: &str,
    asset_name: &str,
    warnings: &mut Warnings,
) -> Result<GithubRelease> {
    let problem = match releases.by_tag(own_tag) {
        Ok(release) if has_asset(&release, asset_name) => return Ok(release),
        Ok(_) => format!("release {own_tag} has no {asset_name} yet"),
        Err(e) => format!("release {own_tag} could not be read ({e})"),
    };
    let latest = releases
        .latest()
        .map_err(|e| format!("dart_spring: {problem}, nor the latest release ({e})"))?;
    if latest.version != own_tag {
        warnings.add(format!(
            "{problem}: started the server of {} instead",
            latest.version
        ));
    }
    Ok(latest)
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
        latest: Result<GithubRelease>,
    }

    impl ReleaseSource for FakeReleases {
        fn by_tag(&self, _tag: &str) -> Result<GithubRelease> {
            self.own.clone()
        }

        fn latest(&self) -> Result<GithubRelease> {
            self.latest.clone()
        }
    }

    fn choose(releases: FakeReleases) -> (Result<String>, Vec<String>) {
        let mut warnings = Warnings::default();
        let chosen =
            release_with(&releases, "v0.8.4", ASSET, &mut warnings).map(|release| release.version);
        (chosen, warnings.into_messages())
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
    fn the_own_release_comes_first() {
        let (chosen, warnings) = choose(FakeReleases {
            own: Ok(release("v0.8.4", &[ASSET])),
            latest: Ok(release("v0.9.0", &[ASSET])),
        });
        assert_eq!(chosen, Ok("v0.8.4".into()));
        assert!(warnings.is_empty());
    }

    #[test]
    fn without_its_binaries_the_latest_one_is_taken_with_a_warning() {
        let (chosen, warnings) = choose(FakeReleases {
            own: Ok(release("v0.8.4", &["dart_spring_lsp-linux-x64.tar.gz"])),
            latest: Ok(release("v0.8.3", &[ASSET])),
        });
        assert_eq!(chosen, Ok("v0.8.3".into()));
        assert_eq!(
            warnings,
            ["release v0.8.4 has no dart_spring_lsp-macos-arm64.tar.gz yet: started the server of v0.8.3 instead"]
        );
    }

    #[test]
    fn an_own_release_that_cannot_be_read_is_said_too() {
        let (chosen, warnings) = choose(FakeReleases {
            own: Err("rate limited".into()),
            latest: Ok(release("v0.8.3", &[ASSET])),
        });
        assert_eq!(chosen, Ok("v0.8.3".into()));
        assert_eq!(
            warnings,
            ["release v0.8.4 could not be read (rate limited): started the server of v0.8.3 instead"]
        );
    }

    #[test]
    fn no_warning_when_the_latest_is_the_own_release() {
        let (chosen, warnings) = choose(FakeReleases {
            own: Err("timeout".into()),
            latest: Ok(release("v0.8.4", &[ASSET])),
        });
        assert_eq!(chosen, Ok("v0.8.4".into()));
        assert!(warnings.is_empty());
    }

    #[test]
    fn neither_release_is_an_error_naming_both_problems() {
        let (chosen, _) = choose(FakeReleases {
            own: Ok(release("v0.8.4", &[])),
            latest: Err("offline".into()),
        });
        assert_eq!(
            chosen,
            Err("dart_spring: release v0.8.4 has no dart_spring_lsp-macos-arm64.tar.gz yet, nor the latest release (offline)".into())
        );
    }
}
