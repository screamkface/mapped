# Mapped

MVP Flutter `Android-first` per gestire siti di lavoro, cantieri e altre destinazioni operative in una vista tabellare stile Excel e su mappa, con import `CSV/XLSX`, dettaglio record e apertura della navigazione esterna con Google Maps.

## Caso d'uso

L'app e' pensata per un singolo utente operativo che deve:

- importare o inserire manualmente destinazioni di lavoro
- vedere i punti validi sulla mappa
- filtrare e cercare rapidamente i record
- aprire Google Maps quando deve raggiungere un sito

## Funzionalita'

- tabella stile foglio dati con ricerca e filtro per stato
- creazione, modifica ed eliminazione manuale delle destinazioni
- import da file locale `CSV` e `XLSX`
- import rapido del file di esempio incluso in `assets/sample_destinations.csv`
- geocodifica automatica dell'indirizzo quando mancano le coordinate
- supporto a colonne extra personalizzate importate da Excel/CSV
- acquisizione foto direttamente dalla fotocamera Android
- collegamento a un file `CSV/XLSX` su Google Drive con sincronizzazione manuale e all'avvio
- marker su Google Maps solo per record con coordinate valide
- dettaglio destinazione con pulsante `Naviga`
- persistenza locale dei dati tramite `shared_preferences`

## Struttura

- `lib/models/destination.dart`: model, serializzazione JSON, parsing righe CSV
- `lib/controllers/destination_controller.dart`: stato applicativo, filtri, persistenza, import e sync Drive
- `lib/services/`: storage locale, import file, Google Drive, geocoding, foto e apertura Google Maps
- `lib/screens/`: home tabellare, mappa e dettaglio
- `lib/widgets/`: tabella dati e form di inserimento/modifica

## Configurazione Google Maps Android

La mappa in-app richiede una API key Google Maps per Android.

### Android

1. Crea una API key in Google Cloud Console
2. Abilita solo `Maps SDK for Android`
3. Applica una restriction di tipo `Android apps`
4. Inserisci `package name` e `SHA-1` della tua app
5. Apri `android/gradle.properties` oppure il tuo `~/.gradle/gradle.properties`
6. Aggiungi:

```properties
MAPS_API_KEY=LA_TUA_CHIAVE_ANDROID
```

L'app legge la chiave nel manifest tramite placeholder Gradle.

## Configurazione Google Drive Android

L'integrazione Drive e' pensata per un uso `single-user` su Android: l'app elenca i file Drive dell'utente, permette di collegarne uno e sincronizza la copia aggiornata all'avvio o su richiesta.

### Cosa devi configurare in Google Cloud

1. Abilita `Google Drive API`
2. Crea un client OAuth `Android` con:
   - `package name`: `com.example.mapped_app`
   - `SHA-1`: quello del keystore che usi per eseguire l'app
3. Crea anche un client OAuth `Web application`
4. Apri `android/gradle.properties` oppure `~/.gradle/gradle.properties`
5. Aggiungi:

```properties
GOOGLE_DRIVE_SERVER_CLIENT_ID=IL_TUO_WEB_CLIENT_ID.apps.googleusercontent.com
```

L'app legge il `serverClientId` dal manifest Android tramite placeholder Gradle, quindi non serve lanciare `flutter run` con `--dart-define`.

### Nota importante sullo scope Drive

Per questa MVP il collegamento usa accesso `read-only` a Google Drive per poter elencare e scaricare il file scelto direttamente dall'app. Per un progetto interno/single-user va bene; per una distribuzione pubblica conviene rivalutare il flusso OAuth e la verifica dell'app.

Nota: il progetto contiene ancora anche lo scaffold iOS generato da Flutter, ma per questa fase la documentazione e il setup sono focalizzati solo su Android.

## Esecuzione Android

```bash
flutter pub get
flutter run -d android
```

Se vuoi lanciare il progetto su un telefono Android fisico:

1. abilita le `Opzioni sviluppatore`
2. abilita `Debug USB`
3. collega il dispositivo
4. verifica che Flutter lo veda con `flutter devices`
5. esegui `flutter run -d <device_id>`

## Checklist rapida

- inserisci la `MAPS_API_KEY`
- inserisci `GOOGLE_DRIVE_SERVER_CLIENT_ID` se vuoi usare Drive
- esegui `flutter pub get`
- avvia l'app con `flutter run -d android`
- premi `Carica esempio` per vedere subito alcuni marker
- prova `Nuova riga` per aggiungere un cantiere manualmente
- apri un record e verifica il pulsante `Naviga`
- se vuoi sincronizzare un file cloud, usa `Collega Drive`

## Import dati

- file supportati: `.csv`, `.xlsx`
- intestazioni flessibili supportate: `nome/name`, `indirizzo/address`, `città/city`, `cap/postalCode/zip`, `telefono/phone`, `note/notes`, `lat/latitude`, `lng/lon/longitude`, `stato/status`
- tutte le altre colonne vengono importate come campi personalizzati e mostrate nel dettaglio record
- se una colonna manca, l'import usa valori di default e non fallisce
- se mancano le coordinate, l'app prova prima a geocodificare l'indirizzo
- se la geocodifica non trova un risultato, il record resta in lista ma non viene mostrato sulla mappa
- le foto scattate dal form vengono copiate nello storage locale dell'app e restano associate al record
- con Google Drive puoi collegare un file `CSV`, `XLSX` o un `Google Sheet` esportato automaticamente in `XLSX`

## CSV di esempio

Puoi:

- importare un file locale dal pulsante `Importa CSV/XLSX`
- caricare subito l'esempio incorporato dal pulsante `Carica esempio`

Il file di esempio si trova in [assets/sample_destinations.csv](/home/nicola/Documents/mapped/assets/sample_destinations.csv).

## Note MVP

- la navigazione usa un URL esterno di Google Maps
- se Google Maps non e' disponibile, l'app mostra un messaggio di errore
- la geocodifica usa il servizio geocoder di Android tramite il package `geocoding`
- la geocodifica mantiene una cache locale persistente di successi e fallimenti recenti per evitare lookup ripetuti inutili
- il campo foto usa la fotocamera Android tramite `image_picker` e la foto e' apribile dalla scheda dettaglio
- la sync Drive mantiene metadati e cache locale dell'ultimo file scaricato e riscarica solo quando cambia `modifiedTime`
- il caso target attuale e' `single user`, con dati salvati solo localmente sul dispositivo
