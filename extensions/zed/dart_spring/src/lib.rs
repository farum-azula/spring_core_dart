//! Starts the dart_spring language server for Dart, YAML and `.properties` files.
//!
//! The server is looked up in this order:
//! 1. `lsp.dart-spring.binary` in Zed settings (`path` and `arguments`): any build;
//! 2. a `dart_spring_lsp` executable on the PATH (for development:
//!    `dart run tool/install_language_server.dart`), when `dart_spring_lsp --version` is this
//!    extension's version ([`path_server`]);
//! 3. the binary of this extension's version, downloaded once from the GitHub release
//!    `v<version>` of farum-azula/spring_core_dart and run only when its SHA-256 is the one the
//!    release wrote into this build ([`downloaded_server`], [`checksums`]); no other release.
//!
//! Trust: Zed reads `lsp.dart-spring.binary` (1.) from the worktree's `.zed/settings.json` as
//! well as from the user's settings, and the extension API offers no way to tell them apart, so a
//! cloned repository can name the executable that starts; the PATH of (2.) is the worktree's
//! shell environment (direnv and the like). Open only repositories you trust, or check their
//! `.zed/settings.json` first.
//!
//! What is passed over on the way (a stale server on the PATH, an older release) is shown as the
//! server's status in Zed ([`warnings`]).
//!
//! It must be a native executable: `dart pub global run` prints resolution messages to stdout,
//! which is the channel LSP uses.

mod checksums;
mod downloaded_server;
mod path_server;
mod release;
mod server_files;
mod version;
mod warnings;

use zed_extension_api::serde_json::Value;
use zed_extension_api::settings::LspSettings;
use zed_extension_api::{self as zed, LanguageServerId, Result, Worktree};

use downloaded_server::DownloadedServer;
use warnings::Warnings;

struct DartSpring {
    downloaded: DownloadedServer,
}

impl DartSpring {
    /// The server on the PATH when it is this extension's version, else the downloaded one.
    fn server(&mut self, id: &LanguageServerId, worktree: &Worktree) -> Result<String> {
        let mut warnings = Warnings::default();
        let server = match path_server::find(worktree, &mut warnings) {
            Some(path) => Ok(path),
            None => self.downloaded.path(id, &mut warnings),
        };
        match server {
            Ok(path) => {
                warnings.report(id);
                Ok(path)
            }
            Err(error) => Err(warnings.append_to(error)),
        }
    }
}

/// The user's settings of the server [id] (`lsp.dart-spring`).
fn lsp_settings(id: &LanguageServerId, worktree: &Worktree) -> Result<LspSettings> {
    LspSettings::for_worktree(id.as_ref(), worktree)
        .map_err(|e| format!("dart_spring: could not read the settings lsp.{id}: {e}"))
}

impl zed::Extension for DartSpring {
    fn new() -> Self {
        DartSpring {
            downloaded: DownloadedServer::default(),
        }
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<zed::Command> {
        let binary = lsp_settings(language_server_id, worktree)?.binary;
        let args = binary
            .as_ref()
            .and_then(|binary| binary.arguments.clone())
            .unwrap_or_default();
        let command = match binary.and_then(|binary| binary.path) {
            Some(path) => path,
            None => self.server(language_server_id, worktree)?,
        };
        Ok(zed::Command {
            command,
            args,
            env: worktree.shell_env(),
        })
    }

    /// The server's settings (`lsp.dart-spring.settings`, such as
    /// `activeProfiles`) when it starts: its `initialization_options` if set,
    /// else the same `settings` it gets later.
    fn language_server_initialization_options(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Option<Value>> {
        let settings = lsp_settings(language_server_id, worktree)?;
        Ok(settings.initialization_options.or(settings.settings))
    }

    /// The server's `settings`, sent again (`workspace/didChangeConfiguration`)
    /// when the user changes them.
    fn language_server_workspace_configuration(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Option<Value>> {
        Ok(lsp_settings(language_server_id, worktree)?.settings)
    }
}

zed::register_extension!(DartSpring);
