//! The version the language server must have: this extension's (the server and the extension are
//! released together, in lockstep with the spring_core_dart family).

/// This extension's version, `0.8.4`.
pub const EXTENSION_VERSION: &str = env!("CARGO_PKG_VERSION");

/// The tag of this extension's GitHub release: `v0.8.4`.
pub fn own_tag() -> String {
    format!("v{EXTENSION_VERSION}")
}

/// The version in what `dart_spring_lsp --version` printed (`dart_spring_lsp 0.8.4`): the last
/// word of its first line, without a leading `v`.
pub fn reported_version(output: &str) -> Option<&str> {
    let line = output.lines().find(|line| !line.trim().is_empty())?;
    let word = line.split_whitespace().last()?;
    Some(word.strip_prefix('v').unwrap_or(word))
}

/// Whether [a] and [b] name the same version, `v0.8.4` and `0.8.4` included.
pub fn same_version(a: &str, b: &str) -> bool {
    let bare = |version: &str| version.trim().trim_start_matches('v').to_string();
    bare(a) == bare(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_own_tag_is_the_version_with_a_v() {
        assert_eq!(own_tag(), format!("v{}", env!("CARGO_PKG_VERSION")));
    }

    #[test]
    fn reads_the_version_the_server_prints() {
        assert_eq!(reported_version("dart_spring_lsp 0.8.4\n"), Some("0.8.4"));
        assert_eq!(reported_version("0.8.4"), Some("0.8.4"));
        assert_eq!(
            reported_version("dart_spring_lsp v0.9.0-dev.1"),
            Some("0.9.0-dev.1")
        );
        assert_eq!(
            reported_version("\n  dart_spring_lsp 0.8.4\nmore\n"),
            Some("0.8.4")
        );
    }

    #[test]
    fn no_output_is_no_version() {
        assert_eq!(reported_version(""), None);
        assert_eq!(reported_version(" \n\t\n"), None);
    }

    #[test]
    fn compares_versions_with_or_without_the_v() {
        assert!(same_version("0.8.4", "0.8.4"));
        assert!(same_version("v0.8.4", "0.8.4"));
        assert!(same_version("0.8.4\n", "v0.8.4"));
        assert!(!same_version("0.8.3", "0.8.4"));
        assert!(!same_version("0.8.4", "0.8.40"));
        assert!(!same_version("0.8.4-dev", "0.8.4"));
    }
}
