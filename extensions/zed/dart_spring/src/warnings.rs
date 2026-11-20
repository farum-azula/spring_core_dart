//! What went wrong on the way to a running server without stopping it (a stale server on the
//! PATH, a release without binaries, a copy that could not be made): shown as the server's
//! status in Zed (its activity indicator; a click shows the message) and written to stderr.

use zed_extension_api::{self as zed, LanguageServerId, LanguageServerInstallationStatus};

#[derive(Default)]
pub struct Warnings {
    messages: Vec<String>,
}

impl Warnings {
    pub fn add(&mut self, message: String) {
        self.messages.push(message);
    }

    /// Shows the warnings as [id]'s status, or clears the status when there are none.
    pub fn report(self, id: &LanguageServerId) {
        let status = match self.message() {
            Some(message) => {
                eprintln!("{message}");
                LanguageServerInstallationStatus::Failed(message)
            }
            None => LanguageServerInstallationStatus::None,
        };
        zed::set_language_server_installation_status(id, &status);
    }

    /// [error], followed by the warnings: what was passed over on the way to it.
    pub fn append_to(self, error: String) -> String {
        if self.messages.is_empty() {
            error
        } else {
            format!("{error} (before that: {})", self.messages.join("; "))
        }
    }

    #[cfg(test)]
    pub fn into_messages(self) -> Vec<String> {
        self.messages
    }

    fn message(&self) -> Option<String> {
        (!self.messages.is_empty()).then(|| format!("dart_spring: {}", self.messages.join("; ")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_warnings_no_message() {
        assert_eq!(Warnings::default().message(), None);
    }

    #[test]
    fn the_warnings_make_one_message() {
        let mut warnings = Warnings::default();
        warnings.add("one".into());
        warnings.add("two".into());
        assert_eq!(warnings.message().as_deref(), Some("dart_spring: one; two"));
    }

    #[test]
    fn an_error_names_the_warnings_before_it() {
        assert_eq!(Warnings::default().append_to("failed".into()), "failed");
        let mut warnings = Warnings::default();
        warnings.add("a stale server on the PATH".into());
        assert_eq!(
            warnings.append_to("download failed".into()),
            "download failed (before that: a stale server on the PATH)"
        );
    }
}
