//! A `dart_spring_lsp` on the PATH (a local build: `dart run tool/install_language_server.dart`),
//! started only when `dart_spring_lsp --version` is this extension's version, so that a stale
//! build does not win over the release the extension was made for. The process capability of
//! `extension.toml` allows exactly that command.

use zed_extension_api::{self as zed, Worktree};

use crate::server_files::EXECUTABLE;
use crate::version::{reported_version, same_version, EXTENSION_VERSION};
use crate::warnings::Warnings;

/// The server on the PATH, when it is this extension's version; a warning when it is not.
pub fn find(worktree: &Worktree, warnings: &mut Warnings) -> Option<String> {
    let path = worktree.which(EXECUTABLE)?;
    match verify(&path, ask_version(worktree)) {
        Ok(()) => Some(path),
        Err(warning) => {
            warnings.add(warning);
            None
        }
    }
}

/// How the server answered `--version`.
enum VersionAnswer {
    /// It printed this and exited with 0.
    Printed(String),
    /// It ran, and failed so (a server before `--version` takes it for LSP, reads no input and
    /// ends with 1).
    Failed(String),
    /// It could not be run.
    NotRun(String),
}

/// Runs `dart_spring_lsp --version`. By its name, not its path: the capability names the
/// command, and the shell's PATH finds the same file `which` did.
fn ask_version(worktree: &Worktree) -> VersionAnswer {
    let output = zed::process::Command::new(EXECUTABLE)
        .arg("--version")
        .envs(worktree.shell_env())
        .output();
    match output {
        Ok(output) if output.status == Some(0) => {
            VersionAnswer::Printed(String::from_utf8_lossy(&output.stdout).into_owned())
        }
        Ok(output) => VersionAnswer::Failed(match output.status {
            Some(code) => format!("exit code {code}"),
            None => "ended by a signal".to_string(),
        }),
        Err(e) => VersionAnswer::NotRun(e),
    }
}

/// Whether the server at [path], which gave [answer] to `--version`, is this extension's version;
/// the warning that says why it is passed over when not.
fn verify(path: &str, answer: VersionAnswer) -> Result<(), String> {
    let instead = format!(
        "started the release's server {EXTENSION_VERSION} instead \
         (lsp.dart-spring.binary.path starts any build)"
    );
    match answer {
        VersionAnswer::Printed(text) => match reported_version(&text) {
            Some(version) if same_version(version, EXTENSION_VERSION) => Ok(()),
            Some(version) => Err(format!(
                "{path} is version {version}, not {EXTENSION_VERSION}: {instead}"
            )),
            None => Err(format!("{path} printed no version: {instead}")),
        },
        VersionAnswer::Failed(how) => Err(format!(
            "{path} does not know --version ({how}), so it is older than {EXTENSION_VERSION}: \
             {instead}"
        )),
        VersionAnswer::NotRun(e) => Err(format!(
            "could not ask {path} for its version ({e}): {instead}"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PATH: &str = "/home/me/.pub-cache/bin/dart_spring_lsp";

    #[test]
    fn a_server_of_this_version_is_started() {
        assert_eq!(
            verify(
                PATH,
                VersionAnswer::Printed(format!("dart_spring_lsp {EXTENSION_VERSION}\n"))
            ),
            Ok(())
        );
    }

    #[test]
    fn a_server_of_another_version_is_passed_over() {
        let warning = verify(
            PATH,
            VersionAnswer::Printed("dart_spring_lsp 0.0.1\n".into()),
        )
        .err()
        .unwrap();
        assert_eq!(
            warning,
            format!(
                "{PATH} is version 0.0.1, not {EXTENSION_VERSION}: started the release's server \
                 {EXTENSION_VERSION} instead (lsp.dart-spring.binary.path starts any build)"
            )
        );
    }

    #[test]
    fn a_server_that_prints_nothing_is_passed_over() {
        let warning = verify(PATH, VersionAnswer::Printed(String::new()))
            .err()
            .unwrap();
        assert!(
            warning.starts_with(&format!("{PATH} printed no version: ")),
            "{warning}"
        );
    }

    #[test]
    fn a_server_without_the_version_flag_is_passed_over() {
        let warning = verify(PATH, VersionAnswer::Failed("exit code 1".into()))
            .err()
            .unwrap();
        assert!(
            warning.starts_with(&format!(
                "{PATH} does not know --version (exit code 1), so it is older than"
            )),
            "{warning}"
        );
    }

    #[test]
    fn a_server_that_cannot_be_run_is_passed_over() {
        let warning = verify(PATH, VersionAnswer::NotRun("not granted".into()))
            .err()
            .unwrap();
        assert!(
            warning.starts_with(&format!(
                "could not ask {PATH} for its version (not granted): "
            )),
            "{warning}"
        );
    }
}
