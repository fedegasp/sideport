# Sideport

App macOS nativa (SwiftUI) per scaricare le app iOS sul Mac e installarle sui dispositivi
collegati via cavo: download delle `.ipa` dall'App Store con il proprio Apple ID, libreria
locale, installazione su piu' dispositivi contemporaneamente, elenco e rimozione delle app
gia' presenti sul dispositivo.

## Requisiti

- macOS 14 o successivo
- Xcode 15+ / Swift 6 per compilare l'app, Rust 1.85+ per l'helper delle icone
- [libimobiledevice](https://libimobiledevice.org) per parlare con i dispositivi e
  [ipatool](https://github.com/majd/ipatool) per scaricare dall'App Store:

```bash
brew install libimobiledevice ideviceinstaller ipatool
brew install rust       # oppure rustup, per l'helper delle icone
brew install xcodegen   # genera il progetto Xcode, che non e' versionato
```

Tutti e tre i tool vengono copiati dentro `Sideport.app` in fase di build, quindi l'app
risultante funziona anche su un Mac senza Homebrew (il bundle pesa circa 40 MB,
di cui 30 sono ipatool).

Nel bundle finisce anche `sideport-icon`, un piccolo helper in Rust ([`Helpers/sideport-icon`](Helpers/sideport-icon/src/main.rs))
che legge le icone delle app installate dal servizio SpringBoard del dispositivo: nessun
tool di libimobiledevice lo espone. E' un crate senza dipendenze, compilato in fase di
build da `cargo` e collegato alla libimobiledevice di Homebrew (serve `pkg-config`); se
manca, le app installate mostrano un segnaposto.

## Build

### Xcode

```bash
make generate && open Sideport.xcodeproj
```

Schema **Sideport**, poi ⌘R. Il progetto compila l'app, genera l'icona e incorpora
libimobiledevice nel bundle tramite due fasi di script.

Il progetto e' generato da [`project.yml`](project.yml) con
[XcodeGen](https://github.com/yonaskolb/XcodeGen) e non e' versionato, quindi va
generato almeno una volta. L'elenco dei file viene risolto al momento della
generazione, quindi **dopo aver aggiunto o rinominato un sorgente** (oltre che dopo
aver cambiato la configurazione) va rigenerato:

```bash
make generate
```

Modificare il contenuto di file esistenti non richiede nulla. `make generate` produce
anche `Resources/AppIcon.icns`, che non e' versionata: XcodeGen risolve i percorsi al
momento della generazione, quindi `xcodegen generate` lanciato da solo lascerebbe l'app
senza icona.

### Riga di comando

```bash
make build      # rigenera il progetto e compila Release in ./build
make run        # compila e avvia l'app
make test       # esegue i test
make install    # copia l'app in ~/Applications
```

`make` da solo elenca i target disponibili. Il bundle finisce in
`build/Build/Products/Release/Sideport.app`, completo di icona, stringhe compilate e
tool incorporati: e' lo stesso che produce ⌘R in Xcode, perche' entrambi passano per
`project.yml` e per gli stessi script.

## Uso

1. Collega iPhone o iPad con il cavo, sbloccalo e tocca **Autorizza** quando richiesto
   (se salti il passaggio, l'app mostra un pulsante per riavviare l'abbinamento).
2. **Libreria** → *Importa* oppure trascina i file `.ipa` nella finestra.
3. Seleziona una o piu' app → **Installa su…** → spunta i dispositivi di destinazione → *Installa*.
   Il pulsante *Ispeziona* su ogni riga mostra il contenuto dell'archivio (cartelle e file
   con le dimensioni non compresse), letto dall'indice dello zip senza estrarlo. Da li' si
   trascinano file e cartelle nel Finder per estrarli, si estraggono gli elementi
   selezionati (⌘ o ⇧ per sceglierne piu' d'uno) con *Estrai selezione…*, oppure si estrae
   l'intero archivio con *Estrai tutto…*.
4. L'avanzamento e' nel pannello **Attivita'** nella barra strumenti (⇧⌘T).

Nella scheda di un dispositivo trovi le app installate, con icona, versione e spazio occupato
(app piu' documenti e dati, come in Impostazioni su iOS; il dettaglio e' nel tooltip), con
rimozione e, quando la libreria contiene una versione piu' recente della stessa app, un
pulsante *Aggiorna*. Le icone restano in cache in `~/Library/Caches/Sideport/Icone`, per bundle
ID e versione. Il pulsante *Informazioni* nell'intestazione apre un foglio con i dati del
dispositivo (modello, numero di serie, UDID, sistema, spazio) e la rinomina.

### Rifirma

Una `.ipa` firmata per un altro team non si installa: il dispositivo non e' nel profilo e
`ideviceinstaller` risponde `ApplicationVerificationFailed`. Il pulsante *Rifirma…* (nel
foglio del contenuto, accanto ai dati di firma, e nel menu contestuale della libreria)
rifa' la firma con un certificato del tuo portachiavi e un profilo di provisioning tuo,
e salva una nuova `.ipa` nella libreria, pronta da installare.

Il foglio elenca le identita' di firma iOS trovate nel portachiavi e i profili installati
in `~/Library/MobileDevice/Provisioning Profiles` e nella cartella di Xcode (oppure si
sceglie un file `.mobileprovision`), e prima di firmare controlla cio' che altrimenti si
scoprirebbe solo al momento dell'installazione: che il profilo copra l'app e le sue
estensioni, che accetti il certificato scelto, che non sia scaduto e che includa i
dispositivi collegati. Al momento della firma macOS puo' chiedere l'autorizzazione a usare
la chiave privata.

Si rifirma cio' che e' tecnicamente rifirmabile:

- **Le copie dell'App Store no.** Il binario e' cifrato con FairPlay e resta illeggibile a
  un Apple ID diverso: cambiare la firma non lo rende installabile.
- **Estensioni.** Hanno un identificativo proprio, quindi servono un profilo jolly
  (`TEAM.*`) oppure, come nei target di Xcode, un profilo installato per ciascuna: Sideport li
  cerca da solo fra quelli disponibili e lo dice nei controlli.
- **Identificativo diverso.** Con un profilo esplicito che copre un'altra app, Sideport propone
  di adottare l'identificativo del profilo: l'app si installa accanto all'originale invece
  di sostituirla, e le estensioni seguono il nuovo prefisso.

La firma segue l'ordine di Xcode (librerie e framework, poi le estensioni, infine il
bundle dell'app) e gli entitlements vengono dal profilo, con l'identificativo concreto al
posto del jolly: `*` dentro la firma del binario il dispositivo lo rifiuta.

In libreria l'originale e la copia rifirmata restano distinguibili: la colonna *Firma*
mostra il genere (App Store, Sviluppo, Ad Hoc, Enterprise, Distribuzione App Store) e chi
firma, e quando due `.ipa` hanno lo stesso identificativo accanto a quest'ultimo compare
il nome del file. Il nome del certificato si legge solo se il profilo ne ammette uno: chi
ha firmato davvero sta nel binario, e un profilo di squadra elenca i certificati di tutti,
quindi negli altri casi si mostra il team.

### Download dall'App Store

Nella scheda **Download** accedi con l'Apple ID che possiede le app. Da li' puoi cercare
nell'App Store o sfogliare l'elenco dei tuoi acquisti, e scaricare la `.ipa` direttamente
nella cartella libreria, da dove e' subito installabile.

- Le app gia' acquistate si scaricano con *Scarica*; quelle gratuite mai ottenute con
  *Ottieni e scarica*, che prima acquisisce la licenza sul tuo account.
- Le app a pagamento non acquistate vanno comprate dall'App Store: ipatool non effettua pagamenti.
- Se l'account ha la verifica in due fattori, Sideport chiede il codice e lo passa alla
  sessione di login gia' aperta, senza ripetere l'autenticazione (altrimenti Apple
  invierebbe un secondo codice invalidando il primo).

La password viene consegnata a ipatool tramite uno pseudo-terminale invece che come
argomento da riga di comando, quindi non e' visibile in `ps`; Sideport non la conserva.
Il token di sessione lo gestisce ipatool nel portachiavi di macOS, e al primo accesso
macOS puo' chiedere l'autorizzazione.

### Lingue

L'interfaccia e' in inglese (lingua sorgente) e in italiano, e segue la lingua di sistema.
Tutti i testi stanno in [`Sources/Sideport/Resources/Localizable.xcstrings`](Sources/Sideport/Resources/Localizable.xcstrings),
piu' [`Resources/InfoPlist.xcstrings`](Resources/InfoPlist.xcstrings) per copyright e nome
del tipo di documento. Nel codice si leggono con `.ui("…")`, che risolve il bundle in un
punto solo (`Core/LocalizedText.swift`).

Xcode compila i cataloghi a ogni build: dopo aver modificato le stringhe non serve
rigenerare nulla.

Per provare una lingua senza cambiare quella di sistema:

```bash
open build/Build/Products/Release/Sideport.app --args -AppleLanguages '(en)'
```

### Scorciatoie

| Tasti | Azione |
|---|---|
| ⌘1 / ⌘2 | Libreria / Download |
| ⇧⌘T | Pannello attivita' |
| ⇧⌘R | Rileggi i dispositivi |

## Limiti noti

- **Firma delle .ipa.** Un archivio scaricato dall'App Store e' protetto da FairPlay e si
  installa solo su dispositivi il cui Apple ID coincide con quello che ha acquistato l'app.
  Le .ipa firmate con un profilo di sviluppo o enterprise richiedono che il dispositivo
  sia incluso nel profilo. In caso contrario l'installazione fallisce con
  `ApplicationVerificationFailed`, che l'app traduce in un messaggio esplicito.
  Il foglio del contenuto mostra i dati di firma letti dall'archivio (profilo
  incorporato o metadati dell'acquisto), ma non la verifica: servirebbe estrarre il
  bundle e `codesign` su macOS non valuta comunque le firme iOS. Quando la firma e' il
  problema, *Rifirma…* la rifa' con un certificato e un profilo tuoi.
- **Estrazione delle app dal dispositivo.** Non supportata: le API di archiviazione di
  `installation_proxy` sono state rimosse da Apple a partire da iOS 9, quindi non esiste
  piu' un modo per ricostruire una `.ipa` da un'app installata.
- **Download dall'App Store.** Si appoggia a ipatool, che usa l'API privata dell'iTunes
  Store: non e' documentata da Apple e puo' cambiare senza preavviso. Si scaricano solo app
  gratuite o gia' acquistate con l'Apple ID usato, e il formato dell'avanzamento non e'
  affidabile, quindi durante il download Sideport mostra i byte scritti sul file invece di una
  percentuale.
- **Icone.** Le icone delle .ipa dell'App Store usano il PNG modificato (CgBI) di Apple;
  vengono convertite con `pngcrush` se Xcode e' presente, altrimenti si vede un segnaposto.

## Struttura

```
Sources/Sideport/
  App/          punto di ingresso e menu
  Core/         esecuzione processi, individuazione tool, parsing plist
  Models/       Device, InstalledApp, IPAPackage, IPASignature, IPAContents, TransferJob,
                StoreApp, SigningIdentity, ProvisioningProfile
  Services/     DeviceMonitor, InstalledAppsService, TransferQueue, LibraryStore,
                IPAInspector, IPAExtractor, IPAResigner, SigningAssets, StoreService
  State/        stato condiviso dell'interfaccia (UIState, Route)
  Views/        interfaccia SwiftUI, una cartella per sezione (Root, Library, Device,
                Download, Transfers) piu' Shared per i componenti comuni
  Resources/    catalogo di stringhe (.xcstrings)
Tests/          test della logica di parsing (Swift Testing): `make test`
Resources/      Info.plist, catalogo dell'Info.plist e icona generata (AppIcon.icns)
Helpers/        helper in Rust incorporati nel bundle (sideport-icon)
Scripts/        incorporamento dei tool e generazione dell'icona, richiamati dalle
                fasi di script del progetto
project.yml     sorgente del progetto Xcode (XcodeGen)
Makefile        generazione, build, test e installazione da riga di comando
```

L'app non parla direttamente con `usbmuxd` ne' con i server Apple: invoca i tool esterni e
ne analizza l'output (plist XML per gli elenchi, righe di avanzamento per le installazioni,
JSON per ipatool). I job di installazione sono serializzati per dispositivo e paralleli fra
dispositivi diversi.

`Core/PTYProcess.swift` esiste per un motivo solo: `ipatool auth login` legge la password
con `term.ReadPassword`, che pretende un vero terminale e rifiuta una pipe. Collegando solo
stdin a uno pseudo-terminale si soddisfa quel controllo tenendo stdout e stderr su pipe
normali, e la password non finisce in `argv`.

La libreria predefinita e' `~/Library/Application Support/Sideport/Libreria`, modificabile dal
menu *Cartella*.

## Licenza

Il codice di Sideport e' sotto licenza [MIT](LICENSE). L'app incorpora nel bundle alcuni tool
di terze parti (libimobiledevice, ideviceinstaller, ipatool) con licenze proprie: vedi
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
