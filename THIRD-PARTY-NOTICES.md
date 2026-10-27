# Note di terze parti

Il codice sorgente di Sideport è distribuito sotto licenza MIT (vedi [`LICENSE`](LICENSE)).
In fase di build ([`Scripts/bundle-tools.sh`](Scripts/bundle-tools.sh)) l'app incorpora
però alcuni eseguibili di terze parti, invocati come processi esterni separati (Sideport
legge il loro output, non ne importa né modifica il codice). Ogni tool resta coperto
dalla propria licenza originale, elencata qui sotto insieme agli obblighi che ne derivano
quando `Sideport.app` viene distribuita a terzi (per solo uso locale questi obblighi non
scattano).

## libimobiledevice — LGPL-2.1-or-later

Tool incorporati: `idevice_id`, `ideviceinfo`, `idevicepair`, `idevicename`,
`idevicediagnostics`.

- Sorgente: <https://github.com/libimobiledevice/libimobiledevice>
- Anche l'helper [`Helpers/sideport-icon`](Helpers/sideport-icon) si collega dinamicamente a
  `libimobiledevice` (via `pkg-config`, vedi [`build.rs`](Helpers/sideport-icon/build.rs)):
  il collegamento dinamico soddisfa di per sé il requisito LGPL §6 di permettere
  all'utente di sostituire la libreria.
- Obblighi in caso di distribuzione: includere il testo della licenza LGPL-2.1 e
  rendere disponibile il sorgente della versione di libimobiledevice usata (o un
  riferimento preciso a dove reperirlo).

## ideviceinstaller — GPL-2.0

- Sorgente: <https://github.com/libimobiledevice/ideviceinstaller>
- Sideport lo invoca come binario esterno non modificato (aggregazione, non linking):
  questo non estende l'obbligo di copyleft al codice sorgente di Sideport.
- Obblighi in caso di distribuzione: includere il testo della licenza GPL-2.0 e
  rendere disponibile il sorgente della versione usata (o un'offerta scritta valida
  a fornirlo), come richiesto dalla GPL per qualunque programma GPL ridistribuito
  in forma binaria, anche se invariato.

## ipatool — MIT

- Sorgente: <https://github.com/majd/ipatool>
- Licenza permissiva: va mantenuto l'avviso di copyright nella distribuzione.

## Come restare in regola alla distribuzione

Quando si pubblica una build di `Sideport.app` (non solo per uso locale):

1. Annotare la versione esatta di ciascun tool incorporata (es. `brew list --versions
   libimobiledevice ideviceinstaller ipatool` al momento della build).
2. Accludere questo file e i testi integrali delle licenze LGPL-2.1 e GPL-2.0 insieme
   al pacchetto distribuito.
3. Tenere un riferimento (link o copia) al sorgente di quella versione esatta, cosí da
   soddisfare l'obbligo di disponibilità del sorgente per le parti GPL/LGPL.
