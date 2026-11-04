//! sideport-icon: scarica le icone delle app installate su un dispositivo iOS.
//!
//! libimobiledevice espone le icone solo tramite il servizio SpringBoard
//! (`sbservices_get_icon_pngdata`) e nessuno dei suoi tool a riga di comando
//! lo usa: questo helper colma il vuoto con un'unica sessione per tutte le app.
//!
//! Uso: sideport-icon [-n] -u UDID -o CARTELLA BUNDLEID...
//!
//! Con `-n` il dispositivo si cerca tra quelli visibili in rete invece che tra
//! quelli collegati via cavo, come il flag omonimo dei tool libimobiledevice.
//!
//! Scrive CARTELLA/<bundleid>.png e stampa una riga per app su stdout:
//!   OK <bundleid>
//!   ERR <bundleid> <motivo>
//! Esce con 1 se il dispositivo o il servizio non sono raggiungibili, 2 per
//! argomenti non validi.

mod springboard;

use std::env;
use std::ffi::{CString, OsStr, OsString};
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use springboard::{Device, SpringBoard, Transport};

/// Etichetta con cui ci si presenta al servizio SpringBoard.
const SERVICE_LABEL: &str = "sideport-icon";

const EXIT_DEVICE: u8 = 1;
const EXIT_USAGE: u8 = 2;

fn usage() {
    eprintln!("Uso: sideport-icon [-n] -u UDID -o CARTELLA BUNDLEID...");
}

/// Argomenti della riga di comando, gia' validati.
struct Options {
    udid: OsString,
    output_dir: PathBuf,
    transport: Transport,
    bundle_ids: Vec<OsString>,
}

/// Legge `[-n] -u UDID -o CARTELLA BUNDLEID...`, nell'ordine: come il `getopt`
/// di macOS, le opzioni devono precedere i bundle ID.
///
/// Restituisce `None` per qualsiasi forma non valida, `-h` compreso.
fn parse_options(args: &[OsString]) -> Option<Options> {
    let mut udid = None;
    let mut output_dir = None;
    let mut transport = Transport::Usb;
    let mut index = 0;

    while let Some(flag) = args
        .get(index)
        .and_then(|arg| arg.to_str())
        .filter(|text| text.starts_with('-') && text.len() > 1)
    {
        index += 1;
        if flag == "--" {
            break;
        }
        // `-n` non ha valore: va riconosciuto prima di cercarne uno.
        if flag == "-n" {
            transport = Transport::Network;
            continue;
        }
        // `-u UDID` e `-uUDID` sono entrambe forme accettate da getopt.
        let (name, inline) = flag.split_at_checked(2)?;
        let value = if inline.is_empty() {
            let next = args.get(index)?.clone();
            index += 1;
            next
        } else {
            OsString::from(inline)
        };
        match name {
            "-u" => udid = Some(value),
            "-o" => output_dir = Some(value),
            _ => return None,
        }
    }

    let bundle_ids = args.get(index..).unwrap_or_default().to_vec();
    if bundle_ids.is_empty() {
        return None;
    }
    Some(Options {
        udid: udid?,
        output_dir: PathBuf::from(output_dir?),
        transport,
        bundle_ids,
    })
}

/// I bundle ID arrivano dal dispositivo ma diventano nomi di file: si scartano
/// quelli che potrebbero uscire dalla cartella di destinazione.
fn is_safe_bundle_id(bundle_id: &str) -> bool {
    !bundle_id.is_empty()
        && !bundle_id.starts_with('.')
        && !bundle_id.contains('/')
        && !bundle_id.contains('\0')
}

fn main() -> ExitCode {
    let args: Vec<OsString> = env::args_os().skip(1).collect();
    let Some(options) = parse_options(&args) else {
        usage();
        return ExitCode::from(EXIT_USAGE);
    };

    // argv e' fatto di stringhe gia' terminate da NUL: non puo' contenerne una interna.
    let udid =
        CString::new(options.udid.as_encoded_bytes()).expect("l'UDID da argv non contiene NUL");
    let Ok(device) = Device::open(&udid, options.transport) else {
        eprintln!(
            "Dispositivo {} non trovato.",
            options.udid.to_string_lossy()
        );
        return ExitCode::from(EXIT_DEVICE);
    };

    // Dichiarato dopo il dispositivo: la sessione si chiude per prima.
    let springboard = match SpringBoard::connect(
        &device,
        &CString::new(SERVICE_LABEL).expect("etichetta senza NUL"),
    ) {
        Ok(springboard) => springboard,
        Err(error) => {
            eprintln!("Impossibile avviare il servizio SpringBoard (errore {error}).");
            return ExitCode::from(EXIT_DEVICE);
        }
    };

    // Un handle solo per tutte le righe; e' un `LineWriter`, quindi ogni riga
    // raggiunge il chiamante appena stampata senza un flush esplicito. Gli
    // errori di scrittura su stdout non cambiano il lavoro da fare: si ignorano
    // qui invece di far fallire il programma a meta' elenco.
    let mut out = io::stdout().lock();
    for bundle_id in &options.bundle_ids {
        let Some(safe) = to_safe_bundle_id(bundle_id) else {
            let _ = writeln!(out, "ERR {} nome-non-valido", bundle_id.to_string_lossy());
            continue;
        };
        let _ = fetch_icon(&mut out, &springboard, safe, &options.output_dir);
    }

    ExitCode::SUCCESS
}

/// Il bundle ID come stringa, se puo' diventare un nome di file.
fn to_safe_bundle_id(bundle_id: &OsStr) -> Option<&str> {
    bundle_id.to_str().filter(|id| is_safe_bundle_id(id))
}

/// Scarica un'icona, la scrive in `output_dir` e ne riporta l'esito su `out`.
///
/// # Errors
///
/// Solo gli errori di scrittura su `out`: quelli del dispositivo e del disco
/// diventano una riga `ERR`, perche' le app successive vanno comunque provate.
fn fetch_icon(
    out: &mut impl Write,
    springboard: &SpringBoard<'_>,
    bundle_id: &str,
    output_dir: &Path,
) -> io::Result<()> {
    let name = CString::new(bundle_id).expect("bundle ID gia' validato senza NUL");
    let icon = match springboard.icon_png(&name) {
        Ok(icon) => icon,
        Err(error) => return writeln!(out, "ERR {bundle_id} servizio-{error}"),
    };
    match fs::write(output_dir.join(format!("{bundle_id}.png")), icon.as_bytes()) {
        Ok(()) => writeln!(out, "OK {bundle_id}"),
        Err(_) => writeln!(out, "ERR {bundle_id} scrittura"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(items: &[&str]) -> Vec<OsString> {
        items.iter().map(OsString::from).collect()
    }

    #[test]
    fn accetta_bundle_id_normali() {
        assert!(is_safe_bundle_id("com.apple.Preferences"));
        assert!(is_safe_bundle_id("a"));
    }

    #[test]
    fn scarta_bundle_id_che_escono_dalla_cartella() {
        assert!(!is_safe_bundle_id(""));
        assert!(!is_safe_bundle_id("."));
        assert!(!is_safe_bundle_id("../fuori"));
        assert!(!is_safe_bundle_id("com.apple/Preferences"));
        assert!(!is_safe_bundle_id("com.apple\0.Preferences"));
    }

    #[test]
    fn legge_opzioni_e_bundle_id() {
        let parsed = parse_options(&args(&["-u", "UDID", "-o", "/tmp/icone", "com.a", "com.b"]))
            .expect("argomenti validi");

        assert_eq!(parsed.udid, OsString::from("UDID"));
        assert_eq!(parsed.output_dir, PathBuf::from("/tmp/icone"));
        assert_eq!(parsed.transport, Transport::Usb);
        assert_eq!(parsed.bundle_ids, args(&["com.a", "com.b"]));
    }

    #[test]
    fn cerca_in_rete_con_n() {
        let parsed = parse_options(&args(&["-n", "-u", "UDID", "-o", "/tmp", "com.a"]))
            .expect("argomenti validi");

        assert_eq!(parsed.transport, Transport::Network);
        assert_eq!(parsed.udid, OsString::from("UDID"));
        assert_eq!(parsed.bundle_ids, args(&["com.a"]));
    }

    #[test]
    fn accetta_valori_attaccati_alla_opzione() {
        let parsed =
            parse_options(&args(&["-uUDID", "-o/tmp", "com.a"])).expect("argomenti validi");

        assert_eq!(parsed.udid, OsString::from("UDID"));
        assert_eq!(parsed.output_dir, PathBuf::from("/tmp"));
    }

    #[test]
    fn rifiuta_argomenti_incompleti() {
        assert!(parse_options(&args(&[])).is_none());
        assert!(parse_options(&args(&["-u", "UDID", "com.a"])).is_none());
        assert!(parse_options(&args(&["-o", "/tmp", "com.a"])).is_none());
        assert!(parse_options(&args(&["-u", "UDID", "-o", "/tmp"])).is_none());
        assert!(parse_options(&args(&["-h"])).is_none());
        assert!(parse_options(&args(&["-x", "1", "com.a"])).is_none());
        assert!(parse_options(&args(&["-u"])).is_none());
    }

    #[test]
    fn dopo_i_due_trattini_sono_tutti_bundle_id() {
        let parsed = parse_options(&args(&["-u", "UDID", "-o", "/tmp", "--", "-com.a"]))
            .expect("argomenti validi");

        assert_eq!(parsed.bundle_ids, args(&["-com.a"]));
    }
}
