//! Wrapper sul servizio SpringBoard di libimobiledevice.
//!
//! Tutto l'`unsafe` del programma sta qui: fuori si vedono solo handle che
//! liberano da soli le risorse e restituiscono `Result`.

use std::ffi::{CStr, c_char, c_int, c_void};
use std::fmt;
use std::marker::PhantomData;
use std::ptr::{self, NonNull};
use std::slice;

/// Struttura interna del dispositivo: la libreria non la espone.
#[repr(C)]
struct IdevicePrivate {
    _opaque: [u8; 0],
}

/// Struttura interna del client SpringBoard: la libreria non la espone.
#[repr(C)]
struct SbservicesClientPrivate {
    _opaque: [u8; 0],
}

const IDEVICE_E_SUCCESS: c_int = 0;
const SBSERVICES_E_SUCCESS: c_int = 0;
/// `IDEVICE_LOOKUP_USBMUX`: solo dispositivi collegati via USB, niente rete.
const IDEVICE_LOOKUP_USBMUX: c_int = 1 << 1;

unsafe extern "C" {
    unsafe fn idevice_new_with_options(
        device: *mut *mut IdevicePrivate,
        udid: *const c_char,
        options: c_int,
    ) -> c_int;

    unsafe fn idevice_free(device: *mut IdevicePrivate) -> c_int;

    unsafe fn sbservices_client_start_service(
        device: *mut IdevicePrivate,
        client: *mut *mut SbservicesClientPrivate,
        label: *const c_char,
    ) -> c_int;

    unsafe fn sbservices_client_free(client: *mut SbservicesClientPrivate) -> c_int;

    unsafe fn sbservices_get_icon_pngdata(
        client: *mut SbservicesClientPrivate,
        bundle_id: *const c_char,
        pngdata: *mut *mut c_char,
        pngsize: *mut u64,
    ) -> c_int;

    /// I buffer restituiti da libimobiledevice arrivano da `malloc`.
    unsafe fn free(ptr: *mut c_void);
}

/// Codice di errore di libimobiledevice, riportato cosi' com'e' all'utente.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ErrorCode(c_int);

impl fmt::Display for ErrorCode {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}", self.0)
    }
}

/// Dispositivo iOS aperto via usbmux.
pub struct Device(NonNull<IdevicePrivate>);

impl Device {
    /// Apre il dispositivo con l'UDID indicato.
    ///
    /// # Errors
    ///
    /// Restituisce il codice di libimobiledevice se il dispositivo non e'
    /// collegato o non risponde.
    pub fn open(udid: &CStr) -> Result<Self, ErrorCode> {
        let mut device = ptr::null_mut();
        // SAFETY: `device` e' un puntatore valido a una variabile locale e
        // `udid` resta vivo per tutta la chiamata; la libreria popola `device`
        // solo in caso di successo.
        let error = unsafe {
            idevice_new_with_options(&raw mut device, udid.as_ptr(), IDEVICE_LOOKUP_USBMUX)
        };
        match NonNull::new(device) {
            Some(device) if error == IDEVICE_E_SUCCESS => Ok(Self(device)),
            _ => Err(ErrorCode(error)),
        }
    }
}

impl Drop for Device {
    fn drop(&mut self) {
        // SAFETY: il puntatore viene da `idevice_new_with_options` e non e'
        // ancora stato liberato: `Device` non e' `Clone` e questo e' l'unico
        // punto che chiama `idevice_free`.
        unsafe { idevice_free(self.0.as_ptr()) };
    }
}

/// Sessione aperta sul servizio SpringBoard di un dispositivo.
///
/// La lifetime lega la sessione al dispositivo: il client non puo'
/// sopravvivere all'handle da cui e' nato.
pub struct SpringBoard<'device> {
    client: NonNull<SbservicesClientPrivate>,
    device: PhantomData<&'device Device>,
}

impl<'device> SpringBoard<'device> {
    /// Avvia il servizio SpringBoard, presentandosi con `label`.
    ///
    /// # Errors
    ///
    /// Restituisce il codice di libimobiledevice se il servizio non parte, per
    /// esempio quando il dispositivo e' bloccato o non abbinato.
    pub fn connect(device: &'device Device, label: &CStr) -> Result<Self, ErrorCode> {
        let mut client = ptr::null_mut();
        // SAFETY: `device.0` e' un handle valido finche' vive `device`, e
        // `client` punta a una variabile locale che la libreria popola solo in
        // caso di successo.
        let error = unsafe {
            sbservices_client_start_service(device.0.as_ptr(), &raw mut client, label.as_ptr())
        };
        match NonNull::new(client) {
            Some(client) if error == SBSERVICES_E_SUCCESS => Ok(Self {
                client,
                device: PhantomData,
            }),
            _ => Err(ErrorCode(error)),
        }
    }

    /// Scarica il PNG dell'icona dell'app indicata.
    ///
    /// # Errors
    ///
    /// Restituisce il codice di libimobiledevice se l'app non esiste o se il
    /// servizio risponde con un buffer vuoto.
    pub fn icon_png(&self, bundle_id: &CStr) -> Result<IconData, ErrorCode> {
        let mut data: *mut c_char = ptr::null_mut();
        let mut size: u64 = 0;
        // SAFETY: il client e' valido, `bundle_id` resta vivo per tutta la
        // chiamata e `data`/`size` puntano a variabili locali.
        let error = unsafe {
            sbservices_get_icon_pngdata(
                self.client.as_ptr(),
                bundle_id.as_ptr(),
                &raw mut data,
                &raw mut size,
            )
        };

        // Il buffer va liberato anche quando la chiamata fallisce ma ha gia'
        // allocato: si costruisce comunque `IconData`, che ci pensa nel Drop.
        let icon = NonNull::new(data.cast::<u8>()).map(|ptr| IconData {
            ptr,
            len: usize::try_from(size).unwrap_or(0),
        });

        match icon {
            Some(icon) if error == SBSERVICES_E_SUCCESS && icon.len > 0 => Ok(icon),
            _ => Err(ErrorCode(error)),
        }
    }
}

impl Drop for SpringBoard<'_> {
    fn drop(&mut self) {
        // SAFETY: il puntatore viene da `sbservices_client_start_service` e non
        // e' ancora stato liberato; il dispositivo e' ancora vivo grazie alla
        // lifetime 'device.
        unsafe { sbservices_client_free(self.client.as_ptr()) };
    }
}

/// Buffer PNG allocato da libimobiledevice.
pub struct IconData {
    ptr: NonNull<u8>,
    len: usize,
}

impl IconData {
    /// I byte del PNG.
    #[must_use]
    pub fn as_bytes(&self) -> &[u8] {
        // SAFETY: la libreria garantisce `len` byte inizializzati a partire da
        // `ptr`, e la slice non sopravvive a `self`.
        unsafe { slice::from_raw_parts(self.ptr.as_ptr(), self.len) }
    }
}

impl Drop for IconData {
    fn drop(&mut self) {
        // SAFETY: il buffer arriva da `malloc` dentro libimobiledevice e viene
        // liberato una volta sola, qui.
        unsafe { free(self.ptr.as_ptr().cast::<c_void>()) };
    }
}
