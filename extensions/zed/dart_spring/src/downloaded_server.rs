//! The server of this extension's release, downloaded once into the work directory (see
//! [`crate::release`] for which release, [`crate::server_files`] for where it goes), and run only
//! when its SHA-256 is the one this build of the extension carries ([`crate::checksums`]).

use std::fs;
use std::path::Path;

use zed_extension_api::{
    self as zed, DownloadedFileType, LanguageServerId, LanguageServerInstallationStatus, Os, Result,
};

use crate::checksums;
use crate::release::{asset_name, release_with, GithubReleases};
use crate::server_files::{
    executable_file_name, is_file, publish_stable_copy, remove_other_versions, stable_path,
    version_directory,
};
use crate::version::own_tag;
use crate::warnings::Warnings;

#[derive(Default)]
pub struct DownloadedServer {
    /// The path of the server, once downloaded.
    cached: Option<String>,
}

impl DownloadedServer {
    /// The server's path, downloaded first if need be; what went wrong without stopping it goes
    /// to [warnings].
    pub fn path(&mut self, id: &LanguageServerId, warnings: &mut Warnings) -> Result<String> {
        if let Some(path) = self.cached.as_ref().filter(|path| is_file(path)) {
            return Ok(path.clone());
        }

        zed::set_language_server_installation_status(
            id,
            &LanguageServerInstallationStatus::CheckingForUpdate,
        );
        let (os, arch) = zed::current_platform();
        let asset_name = asset_name(os, arch)?;
        let release = release_with(&GithubReleases, &own_tag(), &asset_name)?;
        let asset = release
            .assets
            .iter()
            .find(|asset| asset.name == asset_name)
            .ok_or_else(|| {
                format!(
                    "dart_spring: {asset_name} is missing in release {}",
                    release.version
                )
            })?;

        let directory = version_directory(&release.version);
        let binary = format!("{directory}/{}", executable_file_name(os));
        let downloaded = !is_file(&binary);
        if downloaded {
            zed::set_language_server_installation_status(
                id,
                &LanguageServerInstallationStatus::Downloading,
            );
            zed::download_file(&asset.download_url, &directory, archive_type(os))
                .map_err(|e| format!("dart_spring: downloading {asset_name} failed: {e}"))?;
        }
        // Checked on every start of the extension, not only after a download: a binary left in
        // the work directory is run only if it is still the release's build.
        if let Err(e) = checksums::verify(&binary, &asset_name) {
            let _ = fs::remove_dir_all(&directory);
            return Err(e);
        }
        if downloaded {
            zed::make_file_executable(&binary)?;
            for failure in remove_other_versions(Path::new("."), &directory) {
                warnings.add(failure);
            }
        }
        if downloaded || !is_file(stable_path(os)) {
            if let Err(e) = publish_stable_copy(&binary, os) {
                warnings.add(e);
            }
        }
        self.cached = Some(binary.clone());
        Ok(binary)
    }
}

/// How the release packs the server.
fn archive_type(os: Os) -> DownloadedFileType {
    match os {
        Os::Windows => DownloadedFileType::Zip,
        Os::Mac | Os::Linux => DownloadedFileType::GzipTar,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn windows_gets_a_zip_the_others_a_tarball() {
        assert!(matches!(archive_type(Os::Windows), DownloadedFileType::Zip));
        assert!(matches!(archive_type(Os::Mac), DownloadedFileType::GzipTar));
        assert!(matches!(
            archive_type(Os::Linux),
            DownloadedFileType::GzipTar
        ));
    }
}
