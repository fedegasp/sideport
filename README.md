# IMC

App macOS nativa (SwiftUI) per scaricare le app iOS sul Mac e installarle sui dispositivi
collegati via cavo: download delle `.ipa` dall'App Store con il proprio Apple ID, libreria
locale, installazione su piu' dispositivi contemporaneamente, elenco e rimozione delle app
gia' presenti sul dispositivo.

## Requisiti

- macOS 14 o successivo
- Xcode 15+ / Swift 6 per compilare
- [libimobiledevice](https://libimobiledevice.org) per parlare con i dispositivi e
  [ipatool](https://github.com/majd/ipatool) per scaricare dall'App Store:

```bash
brew install libimobiledevice ideviceinstaller ipatool
brew install xcodegen   # solo per rigenerare il progetto Xcode
```

Tutti e tre i tool vengono copiati dentro `IMC.app` in fase di build, quindi l'app
risultante funziona anche su un Mac senza Homebrew (il bundle pesa circa 40 MB,
di cui 30 sono ipatool).

## Build

### Xcode

```bash
open IMC.xcodeproj
```

Schema **IMC**, poi ⌘R. Il progetto compila l'app, genera l'icona e incorpora
libimobiledevice nel bundle tramite due fasi di script.

Il progetto e' generato da [`project.yml`](project.yml) con
[XcodeGen](https://github.com/yonaskolb/XcodeGen). L'elenco dei file viene risolto
al momento della generazione, quindi **dopo aver aggiunto o rinominato un sorgente**
(oltre che dopo aver cambiato la configurazione) va rigenerato:

```bash
xcodegen generate
```

Modificare il contenuto di file esistenti non richiede nulla.

### Riga di comando

```bash
./Scripts/build-app.sh
```

Produce `dist/IMC.app`. Opzioni:

- `./Scripts/build-app.sh --no-tools` — non incorpora libimobiledevice, usa quello di sistema
- `swift build && swift run` — esecuzione rapida in sviluppo (senza icona e senza tool incorporati)

I due percorsi condividono gli stessi sorgenti e gli stessi script, quindi producono
bundle equivalenti.

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

Nella scheda di un dispositivo trovi le app installate, con rimozione e, quando la libreria
contiene una versione piu' recente della stessa app, un pulsante *Aggiorna*.

### Download dall'App Store

Nella scheda **Download** accedi con l'Apple ID che possiede le app. Da li' puoi cercare
nell'App Store o sfogliare l'elenco dei tuoi acquisti, e scaricare la `.ipa` direttamente
nella cartella libreria, da dove e' subito installabile.

- Le app gia' acquistate si scaricano con *Scarica*; quelle gratuite mai ottenute con
  *Ottieni e scarica*, che prima acquisisce la licenza sul tuo account.
- Le app a pagamento non acquistate vanno comprate dall'App Store: ipatool non effettua pagamenti.
- Se l'account ha la verifica in due fattori, IMC chiede il codice e lo passa alla sessione
  di login gia' aperta, senza ripetere l'autenticazione (altrimenti Apple invierebbe un
  secondo codice invalidando il primo).

La password viene consegnata a ipatool tramite uno pseudo-terminale invece che come
argomento da riga di comando, quindi non e' visibile in `ps`; IMC non la conserva. Il token
di sessione lo gestisce ipatool nel portachiavi di macOS, e al primo accesso macOS puo'
chiedere l'autorizzazione.

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
- **Estrazione delle app dal dispositivo.** Non supportata: le API di archiviazione di
  `installation_proxy` sono state rimosse da Apple a partire da iOS 9, quindi non esiste
  piu' un modo per ricostruire una `.ipa` da un'app installata.
- **Download dall'App Store.** Si appoggia a ipatool, che usa l'API privata dell'iTunes
  Store: non e' documentata da Apple e puo' cambiare senza preavviso. Si scaricano solo app
  gratuite o gia' acquistate con l'Apple ID usato, e il formato dell'avanzamento non e'
  affidabile, quindi durante il download IMC mostra i byte scritti sul file invece di una
  percentuale.
- **Icone.** Le icone delle .ipa dell'App Store usano il PNG modificato (CgBI) di Apple;
  vengono convertite con `pngcrush` se Xcode e' presente, altrimenti si vede un segnaposto.

## Struttura

```
Sources/IMC/
  App/          punto di ingresso e menu
  Core/         esecuzione processi, individuazione tool, parsing plist
  Models/       Device, InstalledApp, IPAPackage, IPAContents, TransferJob, StoreApp
  Services/     DeviceMonitor, InstalledAppsService, TransferQueue, LibraryStore,
                IPAInspector, IPAExtractor, StoreService
  Views/        interfaccia SwiftUI
Resources/      Info.plist e icona dell'app
Scripts/        build del bundle, incorporamento dei tool, generazione icona
project.yml     sorgente del progetto Xcode (XcodeGen)
Package.swift   build da riga di comando
```

L'app non parla direttamente con `usbmuxd` ne' con i server Apple: invoca i tool esterni e
ne analizza l'output (plist XML per gli elenchi, righe di avanzamento per le installazioni,
JSON per ipatool). I job di installazione sono serializzati per dispositivo e paralleli fra
dispositivi diversi.

`Core/PTYProcess.swift` esiste per un motivo solo: `ipatool auth login` legge la password
con `term.ReadPassword`, che pretende un vero terminale e rifiuta una pipe. Collegando solo
stdin a uno pseudo-terminale si soddisfa quel controllo tenendo stdout e stderr su pipe
normali, e la password non finisce in `argv`.

La libreria predefinita e' `~/Library/Application Support/IMC/Libreria`, modificabile dal
menu *Cartella*.

## Licenza

Il codice di IMC e' sotto licenza [MIT](LICENSE). L'app incorpora nel bundle alcuni tool
di terze parti (libimobiledevice, ideviceinstaller, ipatool) con licenze proprie: vedi
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
