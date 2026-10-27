//! Chiede a pkg-config dove sta libimobiledevice e passa i flag al linker.
//!
//! Xcode esegue le fasi di script con un PATH ridotto, quindi pkg-config va
//! cercato esplicitamente fra le installazioni Homebrew note.

use std::path::Path;
use std::process::Command;

const PKG_CONFIG_CANDIDATES: [&str; 3] = [
    "/opt/homebrew/bin/pkg-config",
    "/usr/local/bin/pkg-config",
    "pkg-config",
];

fn main() {
    println!("cargo::rerun-if-changed=build.rs");
    println!("cargo::rerun-if-env-changed=PKG_CONFIG_PATH");

    let flags = pkg_config_libs().unwrap_or_else(|| {
        panic!("libimobiledevice non trovata: installala con 'brew install libimobiledevice pkg-config'.")
    });

    for flag in flags.split_whitespace() {
        if let Some(dir) = flag.strip_prefix("-L") {
            println!("cargo::rustc-link-search=native={dir}");
        } else if let Some(lib) = flag.strip_prefix("-l") {
            println!("cargo::rustc-link-lib={lib}");
        }
    }
}

/// `--libs` del primo pkg-config disponibile che conosce libimobiledevice.
fn pkg_config_libs() -> Option<String> {
    for candidate in PKG_CONFIG_CANDIDATES {
        // L'ultimo candidato e' un nome da risolvere nel PATH, gli altri percorsi assoluti.
        if candidate.starts_with('/') && !Path::new(candidate).is_file() {
            continue;
        }
        let output = Command::new(candidate)
            .args(["--libs", "libimobiledevice-1.0"])
            .output();
        if let Ok(output) = output
            && output.status.success()
        {
            return String::from_utf8(output.stdout).ok();
        }
    }
    None
}
