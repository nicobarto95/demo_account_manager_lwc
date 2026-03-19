# Onboarding Tecnico — Account Manager LWC
## Guida completa riga per riga per chi parte da zero

---

## Indice

1. [Cos'è questo progetto e come funziona in 2 minuti](#1-cosè-questo-progetto-e-come-funziona-in-2-minuti)
2. [Glossario: termini che userai ogni giorno](#2-glossario-termini-che-userai-ogni-giorno)
3. [Struttura del progetto e perché ogni file esiste](#3-struttura-del-progetto-e-perché-ogni-file-esiste)
4. [AccountController.cls — Il cervello del backend](#4-accountcontrollercls--il-cervello-del-backend)
5. [accountTable.js — Il controller del frontend](#5-accounttablejs--il-controller-del-frontend)
6. [accountTable.html — Il template visivo](#6-accounttablehtml--il-template-visivo)
7. [accountTable.css — Il design system](#7-accounttablecss--il-design-system)
8. [AccountControllerTest.cls — I test automatici](#8-accountcontrollertestcls--i-test-automatici)
9. [Il flusso completo dall'apertura della pagina al click](#9-il-flusso-completo-dallapertura-della-pagina-al-click)
10. [Errori comuni e come riconoscerli](#10-errori-comuni-e-come-riconoscerli)

---

## 1. Cos'è questo progetto e come funziona in 2 minuti

Immagina di aprire una pagina web dentro Salesforce. Vedi una tabella con tutti gli Account della tua azienda: nome, tipo, telefono, descrizione, data di creazione. Puoi navigare tra le pagine, ordinare le colonne cliccandoci sopra, selezionare più righe con dei checkbox e aggiornare tutte le righe selezionate in un solo click.

Questo è **Account Manager**.

### Chi fa cosa

Il progetto è diviso in due macro-parti che parlano tra loro:

```
┌─────────────────────────────────┐        ┌──────────────────────────────────┐
│         BROWSER (Frontend)      │        │       SERVER SALESFORCE (Backend) │
│                                 │        │                                  │
│  accountTable.html  ← cosa vedi │  HTTP  │  AccountController.cls           │
│  accountTable.js    ← logica UI │ ◄────► │  ↕ SOQL                          │
│  accountTable.css   ← stile     │        │  Database Salesforce (Account)   │
└─────────────────────────────────┘        └──────────────────────────────────┘
```

Il browser mostra la tabella, l'utente interagisce, il JS decide cosa fare, manda una richiesta al server, il server interroga il database, risponde con i dati, il JS aggiorna la tabella.

---

## 2. Glossario: termini che userai ogni giorno

Prima di entrare nel codice, devi avere chiari questi concetti. Torna qui ogni volta che incontri un termine sconosciuto.

| Termine | Cosa significa in pratica |
|---|---|
| **Salesforce** | Una piattaforma CRM cloud. Il tuo codice gira su un server Salesforce, non sul tuo PC. |
| **Org** | Un'istanza Salesforce. Come un "server" dedicato a te o alla tua azienda. |
| **Apex** | Il linguaggio di programmazione lato server di Salesforce. Simile a Java. Gira sul server, non nel browser. |
| **LWC** | Lightning Web Component. Un framework JavaScript per costruire UI in Salesforce. Simile a React. |
| **SOQL** | Salesforce Object Query Language. Come SQL ma per il database Salesforce. `SELECT Name FROM Account` |
| **Account** | Un oggetto standard Salesforce. Rappresenta un'azienda o organizzazione cliente. |
| **@AuraEnabled** | Un'annotazione Apex che dice a Salesforce "questo metodo può essere chiamato dal browser via JavaScript". |
| **FLS** | Field-Level Security. Chi può vedere quale campo. Un utente potrebbe non avere accesso a "Phone". |
| **CRUD** | Create, Read, Update, Delete. Permessi sugli oggetti. Un utente potrebbe non poter creare Account. |
| **DML** | Data Manipulation Language. Le operazioni che modificano il database: `insert`, `update`, `delete`. |
| **Bulkification** | Pattern Salesforce: operare su liste di record con 1 sola query/DML, mai dentro un loop. |
| **Governor Limits** | Salesforce limita quante operazioni puoi fare per transazione (es. max 100 SOQL query, max 150 DML). |
| **DTO** | Data Transfer Object. Una classe usata solo per trasportare dati tra server e client. |
| **Reactive** | Una proprietà JS che, quando cambia, fa ri-renderizzare automaticamente il template HTML. |
| **@track** | Decorator LWC che rende un oggetto/array completamente reattivo (anche le proprietà interne). |
| **Wire** | Meccanismo LWC per chiamate Apex dichiarative (automatiche). Alternativa alla chiamata imperativa. |
| **Toast** | Notifica temporanea che appare in alto a destra (verde = successo, rosso = errore). |
| **SLDS** | Salesforce Lightning Design System. Il CSS framework ufficiale di Salesforce. |

---

## 3. Struttura del progetto e perché ogni file esiste

```
sf-account-demo/
│
├── force-app/main/default/
│   │
│   ├── classes/
│   │   ├── AccountController.cls             ← Apex: legge e scrive dati
│   │   ├── AccountController.cls-meta.xml    ← Configurazione deploy (versione API)
│   │   ├── AccountControllerTest.cls         ← Test automatici per AccountController
│   │   └── AccountControllerTest.cls-meta.xml
│   │
│   └── lwc/accountTable/
│       ├── accountTable.html                 ← HTML: struttura visiva della tabella
│       ├── accountTable.js                   ← JS: logica, stato, chiamate Apex
│       ├── accountTable.css                  ← CSS: colori, font, layout, animazioni
│       └── accountTable.js-meta.xml          ← Dove può essere usato il componente
│
└── README.md
```

### Perché i file `.cls-meta.xml`?

Salesforce non è un semplice server web. Ogni file di codice deve essere accompagnato da un file XML di metadati che dice a Salesforce che versione dell'API usare per compilarlo. Senza questo file, il deploy fallisce. Non devi mai toccarli salvo cambiare la versione API.

### Perché `accountTable.js-meta.xml`?

Questo file dice a Salesforce **dove** può essere trascinato il componente nell'interfaccia grafica (App Builder). Senza di esso, il componente non appare nel pannello componenti di App Builder.

---

## 4. AccountController.cls — Il cervello del backend

Questo file gira interamente sul **server Salesforce**, non nel browser. Il suo compito è interrogare il database e restituire i dati al JavaScript.

### La dichiarazione della classe

```apex
public with sharing class AccountController {
```

Scomponila parola per parola:

- **`public`** → questa classe è accessibile da qualsiasi altro codice nell'org
- **`with sharing`** → rispetta le regole di condivisione (Sharing Rules) dell'organizzazione. Se un utente non ha accesso a certi Account, non li vedrà. L'alternativa `without sharing` ignorerebbe queste regole — pericoloso.
- **`class AccountController`** → il nome della classe. Per convenzione Salesforce, i controller finiscono in "Controller".

### Le Inner Class: AccountPage

```apex
public class AccountPage {
    @AuraEnabled public List<Account> records { get; set; }
    @AuraEnabled public Integer totalRecords { get; set; }
    @AuraEnabled public Integer totalPages { get; set; }
    @AuraEnabled public Integer currentPage { get; set; }
}
```

Una **inner class** è una classe definita dentro un'altra classe. `AccountPage` è un **DTO (Data Transfer Object)**: una scatola che contiene dati da spedire al browser.

Perché esiste? Senza di essa, per sapere quanti record ci sono in totale e quali record ci sono nella pagina corrente, il JavaScript dovrebbe fare **due chiamate Apex separate**:
1. `getAccounts()` → dammi i 10 record di questa pagina
2. `getTotalCount()` → dimmi quanti record esistono in totale

Con `AccountPage`, il server risponde a tutto in **una sola chiamata**. Dimezza la latenza.

- **`@AuraEnabled`** → ogni proprietà che vuoi rendere visibile al JavaScript **deve** avere questa annotazione. Senza di essa, il campo esiste in Apex ma è invisibile al browser.
- **`{ get; set; }`** → sintassi Apex per getter e setter automatici. Equivale a scrivere manualmente `getRecords()` e `setRecords()`.
- **`List<Account>`** → una lista (array) di record Account del database Salesforce.
- **`Integer`** → numero intero. In Apex non c'è `int`, si usa `Integer` con la maiuscola.

### Le Inner Class: MassUpdateResult

```apex
public class MassUpdateResult {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public String message { get; set; }
    @AuraEnabled public Integer updatedCount { get; set; }
}
```

Stesso principio di `AccountPage`, ma per l'operazione di aggiornamento. Contiene:
- `success`: true se tutto è andato bene, false se c'è stato almeno un errore
- `message`: il testo da mostrare all'utente nel toast
- `updatedCount`: quanti record sono stati effettivamente aggiornati

Perché non usare semplicemente un'eccezione in caso di errore? Perché con `MassUpdateResult` possiamo gestire **errori parziali**: se 9 record su 10 vengono aggiornati e 1 fallisce, possiamo dirlo all'utente invece di far fallire tutto.

---

### Il metodo getAccounts()

```apex
@AuraEnabled(cacheable=true)
public static AccountPage getAccounts(
    Integer pageNumber,
    Integer pageSize,
    String  sortField,
    String  sortDirection
) {
```

- **`@AuraEnabled(cacheable=true)`** → rende il metodo chiamabile dal browser. `cacheable=true` significa che Salesforce può mettere in cache il risultato (ottimizzazione delle performance). **Importante**: `cacheable=true` è consentito SOLO su metodi che non modificano dati. Questo metodo legge soltanto.
- **`public static`** → `static` significa che non serve istanziare la classe per chiamare il metodo. Il JavaScript lo chiama direttamente: `AccountController.getAccounts(...)`.
- **`AccountPage`** → il tipo di ritorno. Il metodo restituisce un oggetto `AccountPage`.
- I quattro parametri arrivano direttamente dal JavaScript del browser.

#### Validazione input — prevenzione SOQL Injection

```apex
Set<String> allowedSortFields = new Set<String>{
    'Name', 'Type', 'Phone', 'CreatedDate'
};
if (!allowedSortFields.contains(sortField)) {
    sortField = 'Name';
}
sortDirection = (sortDirection == 'DESC') ? 'DESC' : 'ASC';
pageSize   = (pageSize   != null && pageSize   > 0) ? pageSize   : 10;
pageNumber = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;
```

Questo blocco è critico per la **sicurezza**. Il problema: `sortField` viene usato nella query SOQL con concatenazione di stringhe. Se un utente malintenzionato passasse `sortField = "Name FROM User WHERE Name != null LIMIT 1 --"`, potrebbe iniettare SOQL arbitrario e leggere dati che non dovrebbe vedere.

La soluzione è una **whitelist**: accettiamo soltanto i valori che conosciamo. Qualsiasi altro valore viene silenziosamente rimpiazzato con `'Name'`. Stesso principio per `sortDirection`: accettiamo solo `'DESC'`, altrimenti forziamo `'ASC'`.

Il controllo su `pageSize` e `pageNumber` serve a gestire il caso in cui il JavaScript passi `null` (es. al primo render, prima che lo stato sia inizializzato).

#### La query di conteggio

```apex
Integer totalRecords = [
    SELECT COUNT()
    FROM   Account
    WITH   USER_MODE
];
```

Questa è una **SOQL query inline**. In Apex puoi scrivere le query direttamente nel codice tra parentesi quadre. `COUNT()` non restituisce record ma un numero intero: quanti Account esistono nel database.

**`WITH USER_MODE`** è la parola chiave di sicurezza: applica automaticamente i permessi FLS (Field-Level Security) e CRUD dell'utente che sta usando il componente. Se un utente ha accesso solo a 50 dei 100 Account presenti, `COUNT()` restituisce 50, non 100.

#### Calcolo della paginazione

```apex
Integer totalPages = (Integer) Math.ceil((Double) totalRecords / pageSize);
totalPages = Math.max(totalPages, 1);
pageNumber = Math.min(pageNumber, totalPages);
Integer offsetValue = (pageNumber - 1) * pageSize;
```

Esempio pratico con 13 record e pageSize=10:

```
totalPages  = ceil(13.0 / 10) = ceil(1.3) = 2  → ci sono 2 pagine
Math.max(2, 1) = 2                               → almeno 1 pagina (evita 0 se il db è vuoto)
pageNumber  = min(1, 2) = 1                      → non può superare il totale pagine
offsetValue = (1 - 1) * 10 = 0                  → pagina 1: parti dal record 0
```

Per la pagina 2: `offsetValue = (2-1) * 10 = 10` → salta i primi 10 record.

Il cast `(Double)` prima della divisione è necessario: in Apex, `13 / 10` con due Integer fa `1` (divisione intera). Convertendo in Double prima, ottieni `1.3` su cui `Math.ceil` restituisce correttamente `2`.

#### La query dati principale

```apex
String soqlQuery =
    'SELECT Id, Name, Type, Phone, Description, CreatedDate ' +
    'FROM   Account ' +
    'WITH   USER_MODE ' +
    'ORDER BY ' + sortField + ' ' + sortDirection + ' NULLS LAST ' +
    'LIMIT  :pageSize ' +
    'OFFSET :offsetValue';

List<Account> records = Database.query(soqlQuery);
```

Nota la differenza tra `sortField` (concatenato come stringa) e `:pageSize` / `:offsetValue` (bind variables con i due punti). Le bind variables sono automaticamente sicure da injection perché vengono gestite separatamente dall'interprete SOQL. I campi ORDER BY non supportano bind variables, per questo abbiamo usato la whitelist prima.

- **`NULLS LAST`** → i record con quel campo vuoto vanno in fondo all'ordinamento invece che in cima.
- **`LIMIT :pageSize`** → restituisce al massimo `pageSize` record (es. 10).
- **`OFFSET :offsetValue`** → salta i primi `offsetValue` record. È così che funziona la paginazione: pagina 1 salta 0 record, pagina 2 salta 10, pagina 3 salta 20.
- **`Database.query(soqlQuery)`** → esegue la query costruita dinamicamente come stringa. Non si può usare la sintassi `[SELECT ...]` inline con ORDER BY dinamico.

---

### Il metodo massUpdateAccounts()

```apex
@AuraEnabled
public static MassUpdateResult massUpdateAccounts(
    List<Id>   accountIds,
    String     newDescription
) {
```

Nota che qui manca `cacheable=true`. Questo metodo **modifica dati** (scrive nel database), quindi non può essere messo in cache.

- **`List<Id>`** → una lista di ID Salesforce. Ogni record Salesforce ha un ID univoco di 18 caratteri (es. `0012w00000AbCdEFGH`). Il tipo `Id` in Apex è come `String` ma con validazione extra.

#### Validazione input

```apex
if (accountIds == null || accountIds.isEmpty()) {
    result.success = false;
    result.message = 'Nessun record selezionato.';
    return result;
}
```

Controllo difensivo. Se il JavaScript manda una lista vuota o null (possibile in caso di bug lato client), il metodo risponde subito con un errore controllato invece di esplodere su un DML vuoto.

#### Bulkification — il pattern più importante in Apex

```apex
List<Account> accountsToUpdate = new List<Account>();
for (Id accId : accountIds) {
    accountsToUpdate.add(new Account(
        Id          = accId,
        Description = newDescription
    ));
}
List<Database.SaveResult> saveResults = Database.update(accountsToUpdate, false);
```

**Questo è il cuore della bulkification.** Confronta i due approcci:

```apex
// ❌ ANTI-PATTERN: DML nel loop → violazione dei Governor Limits
for (Id accId : accountIds) {
    Account a = [SELECT Id FROM Account WHERE Id = :accId]; // SOQL nel loop!
    a.Description = newDescription;
    update a;  // DML nel loop! Con 200 record → 200 DML → limite è 150 → ECCEZIONE
}

// ✅ BULKIFICATION: 0 SOQL + 1 solo DML, qualunque sia il numero di record
List<Account> toUpdate = new List<Account>();
for (Id accId : accountIds) {
    toUpdate.add(new Account(Id = accId, Description = newDescription));
    // Costruisce solo oggetti in memoria, nessuna query al database
}
Database.update(toUpdate, false); // 1 sola operazione DML, anche con 50.000 record
```

Perché `new Account(Id = accId, Description = newDescription)` funziona senza fare un SELECT prima? Perché stiamo creando un oggetto Account "parziale" con solo l'ID e il campo da aggiornare. Salesforce sa che, se l'ID è presente, si tratta di un aggiornamento. Non serve caricare tutti gli altri campi.

- **`Database.update(lista, false)`** → il secondo parametro `false` è `allOrNothing`. Con `false`, se 2 record su 10 falliscono (es. per una validation rule), gli altri 8 vengono comunque salvati. Con `true`, un solo fallimento annullerebbe tutto (comportamento atomico).

#### Analisi dei risultati

```apex
for (Database.SaveResult sr : saveResults) {
    if (sr.isSuccess()) {
        successCount++;
    } else {
        for (Database.Error err : sr.getErrors()) {
            errors.add(err.getMessage());
        }
    }
}
```

`Database.update` restituisce una lista di `SaveResult`, uno per ogni record inviato. Ogni `SaveResult` dice se quel record specifico è stato salvato o no. Questo ciclo conta i successi e raccoglie i messaggi di errore per ogni fallimento.

---

## 5. accountTable.js — Il controller del frontend

Questo file gira nel **browser dell'utente**, non sul server. Gestisce lo stato della UI e coordina le chiamate al backend Apex.

### Le importazioni

```javascript
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccounts        from '@salesforce/apex/AccountController.getAccounts';
import massUpdateAccounts from '@salesforce/apex/AccountController.massUpdateAccounts';
```

Ogni riga `import` porta dentro questo file una funzionalità esterna.

- **`LightningElement`** → la classe base di tutti i componenti LWC. Come `React.Component` in React. Il tuo componente la estende.
- **`track`** → decorator che rende un oggetto/array completamente reattivo. Senza `@track`, LWC non rileva i cambiamenti interni a oggetti e array.
- **`ShowToastEvent`** → classe per creare le notifiche toast (il messaggio verde/rosso in alto a destra).
- **`@salesforce/apex/AccountController.getAccounts`** → questa importazione speciale dice a Salesforce: "voglio poter chiamare il metodo `getAccounts` della classe Apex `AccountController`". Salesforce trasforma questa riga in una funzione JavaScript che, quando chiamata, fa una richiesta HTTP al server e restituisce una Promise.

### Le costanti

```javascript
const COLUMNS = [
    { label: 'Name',        fieldName: 'Name',        isSorted: false, sortIcon: '' },
    { label: 'Type',        fieldName: 'Type',        isSorted: false, sortIcon: '' },
    { label: 'Phone',       fieldName: 'Phone',       isSorted: false, sortIcon: '' },
    { label: 'Description', fieldName: 'Description', isSorted: false, sortIcon: '' },
    { label: 'Created Date',fieldName: 'CreatedDate', isSorted: false, sortIcon: '' },
];
```

`COLUMNS` è dichiarata con `const` fuori dalla classe perché non cambia mai tra le istanze del componente. È una lista di oggetti che descrivono le colonne della tabella:
- `label`: il testo mostrato nell'intestazione
- `fieldName`: il nome del campo Salesforce corrispondente (deve corrispondere esattamente al nome SOQL)
- `isSorted`: true se questa colonna è quella attualmente ordinata
- `sortIcon`: il carattere ▲ o ▼ mostrato accanto all'intestazione

```javascript
const PAGE_SIZE_OPTIONS = [
    { label: '5',  value: '5'  },
    { label: '10', value: '10' },
    { label: '25', value: '25' },
    { label: '50', value: '50' },
];
```

Le opzioni del dropdown "Righe per pagina". `label` è il testo visibile, `value` è il valore restituito dall'evento. Nota: entrambi sono stringhe — `lightning-combobox` di Salesforce non accetta valori numerici.

### Lo stato del componente

```javascript
@track columns  = JSON.parse(JSON.stringify(COLUMNS));
@track records  = [];
@track selectedIds = new Map();
```

Queste tre proprietà sono marcate con `@track` perché sono oggetti complessi (array e Map). In LWC, le proprietà primitive (numeri, stringhe, booleani) sono automaticamente reattive. Ma per gli oggetti, LWC osserva solo la riassegnazione (`this.records = nuovaLista`), non le modifiche interne (`this.records.push(...)` non trigghera il render). `@track` risolve questo.

- **`JSON.parse(JSON.stringify(COLUMNS))`** → crea una **copia profonda** (deep copy) dell'array COLUMNS. Senza questa copia, modificare `this.columns` modificherebbe anche la costante `COLUMNS` originale (gli oggetti JS sono passati per riferimento). La copia profonda isola lo stato del componente dalla costante condivisa.

- **`new Map()`** → una Map JavaScript è una struttura dati chiave-valore, come un dizionario. La usiamo per le selezioni perché `map.has(id)` è O(1) — tempo costante. Un array richiederebbe `array.includes(id)` che è O(n) — proporzionale alla dimensione. Con 1000 record selezionati la differenza è significativa.

```javascript
currentPage  = 1;
totalPages   = 1;
totalRecords = 0;
pageSize     = 10;
sortField     = 'Name';
sortDirection = 'ASC';
isLoading    = false;
errorMessage = '';
```

Questi sono valori primitivi, automaticamente reattivi in LWC moderno senza bisogno di `@track`. Rappresentano lo stato corrente della UI: in che pagina sei, come stai ordinando, se sta caricando, se c'è un errore.

### Il ciclo di vita — connectedCallback()

```javascript
connectedCallback() {
    this.loadAccounts();
}
```

`connectedCallback` è un metodo speciale che LWC chiama automaticamente nel momento in cui il componente viene aggiunto al DOM — cioè quando appare per la prima volta sulla pagina. Non devi chiamarlo tu. Viene chiamato esattamente una volta all'inizio della vita del componente.

Il suo unico compito qui è avviare il caricamento iniziale dei dati.

### I getter — proprietà calcolate

```javascript
get hasData()    { return !this.isLoading && !this.hasError && this.records.length > 0; }
get isEmpty()    { return !this.isLoading && !this.hasError && this.records.length === 0; }
get hasError()   { return !!this.errorMessage; }
get isFirstPage(){ return this.currentPage <= 1; }
get isLastPage() { return this.currentPage >= this.totalPages; }
```

I getter sono proprietà calcolate: non memorizzano un valore, ma lo **calcolano ogni volta che vengono letti**. L'HTML del template usa `{hasData}`, `{isFirstPage}` ecc. come se fossero semplici proprietà. LWC ricalcola automaticamente i getter quando cambia una delle proprietà da cui dipendono.

- **`!!this.errorMessage`** → il doppio `!` converte una stringa in booleano. `!''` è `true`, `!!''` è `false`. Se `errorMessage` è una stringa vuota (nessun errore), `hasError` è `false`. Se è una stringa con testo, `hasError` è `true`.

```javascript
get isMassUpdateDisabled() { return this.selectedIds.size === 0; }
```

Controlla se ci sono selezioni attive. Questo getter è usato dall'HTML per disabilitare il pulsante Mass Update. Quando `selectedIds.size` diventa > 0, il getter restituisce `false`, e il pulsante si abilita automaticamente senza nessun codice extra.

```javascript
get allSelected() {
    if (this.records.length === 0) return false;
    return this.records.every(r => this.selectedIds.has(r.Id));
}
```

`every()` restituisce `true` solo se la funzione interna è vera per **tutti** gli elementi. Se anche solo un record non è nella Map delle selezioni, `allSelected` è `false` e il checkbox globale appare non spuntato.

```javascript
get pageSizeString() { return String(this.pageSize); }
```

`lightning-combobox` di Salesforce richiede che `value` sia una stringa. `this.pageSize` è un numero intero. Questo getter converte il numero in stringa ogni volta che il template lo legge. Senza di esso, il combobox non mostrerebbe il valore selezionato correttamente.

### loadAccounts() — la chiamata Apex

```javascript
async loadAccounts() {
    this.isLoading    = true;
    this.errorMessage = '';

    try {
        const result = await getAccounts({
            pageNumber:    this.currentPage,
            pageSize:      this.pageSize,
            sortField:     this.sortField,
            sortDirection: this.sortDirection
        });
        ...
    } catch (error) {
        this.errorMessage = this._extractErrorMessage(error);
        this._showToast('Errore', this.errorMessage, 'error');
    } finally {
        this.isLoading = false;
    }
}
```

La parola chiave `async` rende la funzione asincrona: può "aspettare" operazioni che richiedono tempo (come una chiamata al server) senza bloccare il browser.

`await getAccounts({...})` dice: "chiama il metodo Apex, aspetta la risposta (il server può impiegare qualche secondo), e solo quando hai la risposta continua con la riga successiva". Nel frattempo il browser è libero di fare altro — per questo `isLoading = true` viene impostato prima: mostra lo spinner mentre si aspetta.

Il blocco `try/catch/finally` gestisce i tre scenari:
- **`try`** → tutto va bene, aggiorna i dati
- **`catch`** → qualcosa è andato storto (server down, permessi, etc.) → mostra l'errore
- **`finally`** → viene eseguito **sempre**, sia in caso di successo che di errore → nasconde lo spinner

#### Il record mapping

```javascript
this.records = result.records.map(acc => ({
    ...acc,
    isSelected:     this.selectedIds.has(acc.Id),
    recordUrl:      `/lightning/r/Account/${acc.Id}/view`,
    rowClass:       this.selectedIds.has(acc.Id) ? 'at-row--selected' : '',
    typeBadgeClass: this._getTypeBadgeClass(acc.Type)
}));
```

`result.records` è la lista di Account che viene dal server Apex — oggetti con solo i campi SOQL (`Name`, `Type`, `Phone`, ecc.). Il metodo `.map()` trasforma ogni Account in un nuovo oggetto arricchito con proprietà extra necessarie alla UI.

- **`...acc`** → spread operator. Copia tutte le proprietà esistenti dell'Account nel nuovo oggetto. Equivale a scrivere `Name: acc.Name, Type: acc.Type, ...` manualmente.
- **`isSelected`** → controlla se l'ID di questo record è nella Map delle selezioni. Usato dal checkbox della riga.
- **`recordUrl`** → URL per aprire il record Account. Template string con l'ID dinamico.
- **`rowClass`** → classe CSS applicata alla riga `<tr>`. Se selezionata, applica `at-row--selected` che la colora di azzurro.
- **`typeBadgeClass`** → classe CSS per il badge colorato del campo Type (verde, arancio, blu).

### handleSort() — l'ordinamento

```javascript
handleSort(event) {
    const clickedField = event.currentTarget.dataset.field;

    if (this.sortField === clickedField) {
        this.sortDirection = (this.sortDirection === 'ASC') ? 'DESC' : 'ASC';
    } else {
        this.sortField     = clickedField;
        this.sortDirection = 'ASC';
    }
    ...
    this.currentPage = 1;
    this.loadAccounts();
}
```

`event.currentTarget.dataset.field` legge l'attributo `data-field` dall'elemento HTML cliccato. Nel template ogni `<th>` ha `data-field="Name"`, `data-field="Type"`, ecc. Questo è il modo in LWC per passare dati da HTML a JavaScript senza dover creare un handler separato per ogni colonna.

La logica di toggle: se clicchi sulla stessa colonna già ordinata, inverti la direzione. Se clicchi su una colonna diversa, ordina quella in ASC.

`this.currentPage = 1` prima di `loadAccounts()` è importante: se sei a pagina 5 e cambi ordinamento, vuoi vedere i primi risultati del nuovo ordine, non i risultati della pagina 5.

### Gestione selezioni — il pattern Map

```javascript
handleRowSelect(event) {
    const accountId = event.target.dataset.id;
    const checked   = event.target.checked;

    const newMap = new Map(this.selectedIds);  // crea una COPIA della Map
    if (checked) {
        newMap.set(accountId, true);
    } else {
        newMap.delete(accountId);
    }
    this.selectedIds = newMap;  // riassegna per triggerare la reattività
    ...
}
```

**Perché creare una nuova Map invece di modificare quella esistente?**

In LWC, `@track` osserva le riassegnazioni (`this.selectedIds = nuovaMap`). Se mutassi la Map esistente (`this.selectedIds.set(id, true)`) senza riassegnarla, LWC non se ne accorgerebbe e il template non si aggiornerebbe. Creare una nuova Map e riassegnarla garantisce che LWC rilevi il cambiamento.

### handleMassUpdate() — l'aggiornamento massivo

```javascript
async handleMassUpdate() {
    if (this.selectedIds.size === 0) return;

    const newDescription = `Aggiornato in massa il ${new Date().toLocaleString('it-IT')}`;
    const ids = Array.from(this.selectedIds.keys());

    this.isLoading = true;

    try {
        const result = await massUpdateAccounts({
            accountIds:     ids,
            newDescription: newDescription
        });

        if (result.success) {
            this._showToast('Successo', result.message, 'success');
            this.selectedIds = new Map();
            await this.loadAccounts();
        } else {
            this._showToast('Attenzione', result.message, 'warning');
        }
    } catch (error) {
        this._showToast('Errore', this._extractErrorMessage(error), 'error');
    } finally {
        this.isLoading = false;
    }
}
```

- **`Array.from(this.selectedIds.keys())`** → converte le chiavi della Map (gli ID degli Account) in un array JavaScript normale, necessario per passarli ad Apex come `List<Id>`.
- **`new Date().toLocaleString('it-IT')`** → genera una stringa con data e ora nel formato italiano (es. "13/03/2026, 14:32:05"). Questa diventa il nuovo valore del campo Description.
- **`this.selectedIds = new Map()`** → dopo un aggiornamento riuscito, azzera tutte le selezioni. L'utente riparte da zero.

---

## 6. accountTable.html — Il template visivo

Il template HTML usa una sintassi speciale di LWC per legare i dati JavaScript alla UI.

### La struttura generale

```html
<template>
    <div class="at-wrapper">
        <div class="at-card">
            <!-- HEADER -->
            <!-- BODY (loading | errore | tabella | vuoto) -->
        </div>
    </div>
</template>
```

Il `<template>` è il tag radice obbligatorio di ogni LWC. Al suo interno, la struttura è:
- `at-wrapper` → padding esterno
- `at-card` → la card bianca con ombra e bordi arrotondati

### Il binding dei dati — le parentesi graffe

```html
<h1 class="at-header__title">Account Manager</h1>
<p class="at-header__subtitle">{totalRecords} account totali</p>
```

`{totalRecords}` è un binding unidirezionale: LWC legge la proprietà `totalRecords` dal JavaScript e la inserisce nel DOM. Ogni volta che `totalRecords` cambia nel JS, il testo si aggiorna automaticamente senza nessun codice extra.

### I blocchi condizionali — lwc:if

```html
<template lwc:if={isLoading}>
    <!-- spinner -->
</template>

<template lwc:elseif={hasError}>
    <!-- messaggio errore -->
</template>

<template lwc:elseif={hasData}>
    <!-- tabella -->
</template>

<template lwc:elseif={isEmpty}>
    <!-- nessun dato -->
</template>
```

Solo uno di questi blocchi è visibile alla volta. LWC valuta le condizioni in ordine: se `isLoading` è `true`, mostra lo spinner e ignora il resto. Se è `false` ma `hasError` è `true`, mostra l'errore. E così via. Questo pattern si chiama **mutual exclusion di stati**.

### Il loop — for:each

```html
<template for:each={records} for:item="acc">
    <tr key={acc.Id} class={acc.rowClass}>
        ...
    </tr>
</template>
```

`for:each` itera sull'array `records`. Per ogni elemento, crea un `<tr>`. La variabile `for:item="acc"` dà un nome all'elemento corrente dell'iterazione — poi usato come `{acc.Name}`, `{acc.Type}` ecc.

**`key={acc.Id}`** è obbligatorio in LWC per i loop. Deve essere un valore univoco. Serve al motore di rendering per identificare quale riga aggiornare quando i dati cambiano, senza ridisegnare tutta la tabella.

### Il binding degli attributi — data-field e data-id

```html
<th class="at-th at-th--sort"
    onclick={handleSort}
    data-field={col.fieldName}>
```

```html
<input type="checkbox"
       data-id={acc.Id}
       onchange={handleRowSelect} />
```

Gli attributi `data-*` sono attributi HTML custom. Nel JavaScript si leggono con `event.currentTarget.dataset.field` e `event.target.dataset.id`. Questo è il modo corretto di passare dati contestuali a un event handler in LWC senza dover creare un handler separato per ogni elemento.

### Gli event handler

```html
onclick={handleSort}
onchange={handleRowSelect}
onchange={handlePageSizeChange}
```

La sintassi `{nomeHandler}` lega un evento DOM a un metodo del controller JS. Il nome dell'evento è sempre prefissato da `on`. Quando l'utente clicca, LWC chiama automaticamente il metodo corrispondente passando l'oggetto `event`.

### I componenti SLDS

```html
<lightning-icon icon-name="standard:account" size="small"></lightning-icon>
<lightning-spinner alternative-text="Caricamento..." size="medium" variant="brand"></lightning-spinner>
<lightning-formatted-phone value={acc.Phone}></lightning-formatted-phone>
<lightning-formatted-date-time value={acc.CreatedDate} year="numeric" month="short" day="2-digit">
</lightning-formatted-date-time>
```

Questi sono **componenti standard di Salesforce**, già pronti all'uso. Non devi implementarli. `lightning-formatted-phone` mostra un numero di telefono formattato e cliccabile su mobile. `lightning-formatted-date-time` formatta una data in base al locale dell'utente.

### Il footer paginazione

```html
<button class="at-pgbtn" disabled={isFirstPage} onclick={handleFirst}>«</button>
```

`disabled={isFirstPage}` → quando `isFirstPage` è `true`, l'attributo `disabled` viene aggiunto al bottone HTML, che appare grigio e non cliccabile. Quando è `false`, l'attributo viene rimosso. Questo funziona correttamente con `<button>` HTML nativo perché il binding `{...}` in LWC traduce il booleano JavaScript in presenza/assenza dell'attributo HTML.

---

## 7. accountTable.css — Il design system

Il CSS è scritto con **CSS custom properties (variabili)** per garantire coerenza visiva e facilità di manutenzione.

### Le variabili CSS — :host

```css
:host {
    --at-blue:       #3B82F6;
    --at-navy:       #0F172A;
    --at-slate-700:  #334155;
    --at-radius:     12px;
    --at-shadow-lg:  0 8px 32px rgba(15,23,42,.12);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}
```

`:host` si riferisce al componente stesso — l'elemento radice del Shadow DOM di LWC. Le variabili definite qui (`--at-blue`, `--at-navy`, ecc.) sono accessibili da tutto il CSS del componente tramite `var(--at-blue)`. Se vuoi cambiare il colore principale, cambi solo questa riga e si aggiorna ovunque.

Il font stack `system-ui` usa il font nativo del sistema operativo: San Francisco su macOS/iOS, Segoe UI su Windows, Roboto su Android. Veloce da caricare, sempre disponibile, nativo nella piattaforma.

### L'header con gradiente

```css
.at-card__header {
    background: linear-gradient(135deg, var(--at-navy) 0%, #1E3A5F 100%);
    border-bottom: 3px solid var(--at-blue);
}
```

`linear-gradient(135deg, ...)` crea uno sfondo sfumato diagonale da sinistra-alto (navy scuro) a destra-basso (blu navy più chiaro). Il bordo inferiore blu crea la separazione visiva con il corpo bianco della card.

### Il fix critico — overflow: visible

```css
.at-card {
    overflow: visible;  /* FIX: era hidden, bloccava il dropdown del combobox */
}
.at-footer {
    overflow: visible;
    position: relative;
}
```

`overflow: hidden` è spesso usato per applicare i border-radius agli elementi figli. Ma ha un effetto collaterale: taglia tutto ciò che esce dai bordi del contenitore, **inclusi i dropdown**. Il combobox "Righe per pagina" apre un dropdown verso il basso che veniva tagliato dal `overflow: hidden` della card. Cambiandolo in `visible`, il dropdown è libero di uscire dai bordi della card.

### Il sistema di badge colorati

```css
.at-type              { /* base: padding, border-radius, font-size */ }
.at-type--customer    { background: var(--at-green-bg);  color: var(--at-green);  }
.at-type--prospect    { background: var(--at-orange-bg); color: var(--at-orange); }
.at-type--partner     { background: var(--at-blue-light); color: var(--at-blue);  }
.at-type--other       { background: var(--at-slate-100); color: var(--at-slate-500); }
```

Pattern **BEM (Block Element Modifier)**: `.at-type` è la classe base con lo stile comune, `.at-type--customer` è un modificatore che aggiunge/sovrascrive solo colore e sfondo. Nel JavaScript, `_getTypeBadgeClass()` decide quale combinazione di classi applicare in base al valore del campo Type.

### La colonna Description con ellipsis

```css
.at-td--description { max-width: 220px; }
.at-description {
    display: block;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 220px;
}
```

`text-overflow: ellipsis` tronca il testo con `...` quando supera la larghezza massima. Richiede obbligatoriamente tre proprietà in coppia: `overflow: hidden` (taglia il testo), `white-space: nowrap` (impedisce l'a-capo), `display: block` o `width` definita. Senza tutte e tre insieme, l'ellipsis non funziona.

---

## 8. AccountControllerTest.cls — I test automatici

In Salesforce, prima di fare il deploy in produzione, i test automatici devono coprire almeno il 75% del codice Apex. Il nostro obiettivo è 92%.

### Il setup dei dati — @TestSetup

```apex
@TestSetup
static void makeData() {
    List<Account> testAccounts = new List<Account>();
    for (Integer i = 1; i <= 25; i++) {
        testAccounts.add(new Account(
            Name        = 'Test Account ' + String.valueOf(i).leftPad(2, '0'),
            Type        = (Math.mod(i, 2) == 0) ? 'Customer' : 'Prospect',
            Phone       = '02-' + String.valueOf(1000000 + i),
            Description = 'Original Description'
        ));
    }
    insert testAccounts;
}
```

`@TestSetup` è un metodo speciale che Salesforce esegue **una sola volta** prima di tutti i test della classe. I dati creati qui sono disponibili per tutti i metodi `@IsTest`. Questo è più efficiente di creare dati in ogni singolo test.

`String.valueOf(i).leftPad(2, '0')` formatta il numero con zero iniziale: `1` diventa `'01'`, `9` diventa `'09'`. Questo garantisce che l'ordinamento alfabetico corrisponda all'ordinamento numerico — fondamentale per i test che verificano l'ordine ASC/DESC.

### La struttura dei test

```apex
@IsTest
static void testGetAccounts_firstPage_returnsCorrectData() {
    Test.startTest();
    AccountController.AccountPage result =
        AccountController.getAccounts(1, 10, 'Name', 'ASC');
    Test.stopTest();

    Assert.areEqual(25, result.totalRecords, 'Totale record deve essere 25');
    Assert.areEqual(3,  result.totalPages,   'Con pageSize=10 e 25 record, ci sono 3 pagine');
    Assert.areEqual(10, result.records.size(), 'La prima pagina deve contenere 10 record');
}
```

- **`@IsTest`** → marca il metodo come test. Salesforce lo esegue in un ambiente isolato, senza toccare i dati reali dell'org.
- **`Test.startTest()` / `Test.stopTest()`** → delimitano il codice da testare. Reset dei governor limits all'interno. Tutto il codice tra questi due marker ha i suoi limiti indipendenti.
- **`Assert.areEqual(atteso, effettivo, messaggio)`** → verifica che i due valori siano uguali. Se non lo sono, il test fallisce e mostra il messaggio. L'ordine (atteso, effettivo) è importante per i messaggi di errore leggibili.

### Il test di bulkification

```apex
@IsTest
static void testMassUpdate_allAccounts_bulkificationWorks() {
    List<Account> allAccounts = [SELECT Id FROM Account];
    List<Id> allIds = new List<Id>();
    for (Account a : allAccounts) { allIds.add(a.Id); }

    Test.startTest();
    AccountController.MassUpdateResult result =
        AccountController.massUpdateAccounts(allIds, 'Bulk Updated');
    Test.stopTest();

    Assert.areEqual(25, result.updatedCount, 'Tutti i 25 record devono essere aggiornati');
}
```

Questo test verifica che aggiornare 25 record in un colpo solo funzioni senza violare i governor limits. Se il codice avesse il DML nel loop, questo test fallirebbe con "Too many DML statements".

### Il test che verifica il database reale

```apex
List<Account> updated = [SELECT Description FROM Account WHERE Id IN :ids];
for (Account a : updated) {
    Assert.areEqual(newDesc, a.Description, 'La descrizione deve essere aggiornata');
}
```

Questo è un dettaglio importante: non basta verificare che il metodo Apex restituisca `success=true`. Potrebbe restituire `true` anche con un bug che non ha effettivamente scritto nel database. La verifica finale fa una query SOQL indipendente e controlla che il dato sia effettivamente cambiato nel database.

---

## 9. Il flusso completo dall'apertura della pagina al click

Ecco cosa succede esattamente, in ordine cronologico, dalla prima apertura alla pagina fino al click su Mass Update:

```
1. L'utente apre la pagina "AccountControllerDemo" nel browser

2. Salesforce carica il componente LWC accountTable nel browser

3. LWC chiama automaticamente connectedCallback() nel JS

4. connectedCallback() chiama loadAccounts()

5. loadAccounts() imposta isLoading=true
   → LWC rileva il cambiamento
   → il template mostra lo spinner (lwc:if={isLoading})

6. loadAccounts() chiama getAccounts({pageNumber:1, pageSize:10, sortField:'Name', sortDirection:'ASC'})
   → questa è una chiamata HTTP verso il server Salesforce

7. Sul server, AccountController.getAccounts() viene eseguito:
   a. Valida i parametri in input
   b. Conta tutti gli Account: SELECT COUNT() FROM Account WITH USER_MODE → 13
   c. Calcola: totalPages = ceil(13/10) = 2, offsetValue = (1-1)*10 = 0
   d. Esegue la query: SELECT Id, Name, Type, Phone, Description, CreatedDate
                       FROM Account WITH USER_MODE
                       ORDER BY Name ASC NULLS LAST
                       LIMIT 10 OFFSET 0
   e. Crea e restituisce AccountPage{records:[10 account], totalRecords:13, totalPages:2, currentPage:1}

8. La risposta HTTP arriva al browser
   La Promise risolve, await getAccounts() restituisce l'oggetto AccountPage

9. loadAccounts() aggiorna lo stato JS:
   - this.currentPage = 1
   - this.totalPages = 2
   - this.totalRecords = 13
   - this.records = [i 10 account arricchiti con isSelected, recordUrl, rowClass, typeBadgeClass]

10. isLoading = false nel blocco finally

11. LWC rileva tutti i cambiamenti di stato
    → ricalcola i getter: hasData=true, isFirstPage=true, isLastPage=false...
    → aggiorna il DOM: nasconde lo spinner, mostra la tabella, aggiorna "Pagina 1 di 2"

--- L'utente ora vede la tabella ---

12. L'utente spunta il checkbox di "Burlington Textiles"

13. handleRowSelect() viene chiamato con l'evento
    - legge data-id dall'elemento HTML: '0012w00000...'
    - crea newMap = copia di selectedIds
    - newMap.set('0012w00000...', true)
    - this.selectedIds = newMap  → LWC rileva la riassegnazione
    - aggiorna records con rowClass='at-row--selected' per quella riga

14. LWC ricalcola i getter:
    - selectedCount = 1 → il badge "1 selezionati" appare nell'header
    - isMassUpdateDisabled = false → il pulsante Mass Update si abilita

15. L'utente clicca "Mass Update"

16. handleMassUpdate() viene chiamato:
    - newDescription = "Aggiornato in massa il 13/03/2026, 14:32:05"
    - ids = ['0012w00000...']
    - isLoading = true → spinner visibile

17. Chiama massUpdateAccounts({accountIds:['0012w00000...'], newDescription:'Aggiornato...'})
    → chiamata HTTP al server

18. Sul server, AccountController.massUpdateAccounts() viene eseguito:
    a. Valida: accountIds non è vuoto
    b. Crea Account{Id='0012w00000...', Description='Aggiornato in massa il 13/03/2026, 14:32:05'}
    c. Database.update([quell'account], false)
       → il database Salesforce viene aggiornato
    d. Analizza SaveResult: success=true
    e. Restituisce MassUpdateResult{success:true, message:'1 record aggiornati con successo.', updatedCount:1}

19. La risposta arriva al browser

20. handleMassUpdate() riceve result.success=true:
    - ShowToastEvent con titolo "Successo" e variante "success" → toast verde visibile 3 secondi
    - this.selectedIds = new Map() → selezioni azzerate
    - await this.loadAccounts() → ricarica la tabella dal server

21. La tabella si ricarica (passi 6-11 di nuovo)
    → questa volta "Burlington Textiles" ha Description = "Aggiornato in massa il..."
    → la colonna Description mostra il testo in corsivo grigio
```

---

## 10. Errori comuni e come riconoscerli

### "Cannot read properties of undefined (reading 'map')"
**Causa**: `result.records` è `undefined` — la risposta Apex non ha il campo `records`.
**Dove guardare**: verifica che in `AccountController.cls` la classe `AccountPage` abbia `@AuraEnabled` su `records` e che `result.records = records` sia presente nel metodo.

### Il pulsante Mass Update è sempre grigio
**Causa**: `disabled` su un elemento nativo riceve una stringa invece di un booleano. Usa sempre `lightning-button` per i pulsanti che hanno `disabled` legato a un getter booleano.

### Il dropdown "Righe" non mostra le opzioni
**Causa**: il contenitore padre ha `overflow: hidden`. Verifica che `.at-card` abbia `overflow: visible`.

### "Too many SOQL queries: 101"
**Causa**: stai eseguendo query SOQL dentro un loop. In Apex, il limite è 100 query per transazione. Sposta le query fuori dal loop.

### La tabella mostra sempre gli stessi 10 record anche cambiando pageSize
**Causa**: `event.detail.value` vs `event.target.value`. Con `lightning-combobox` usa sempre `event.detail.value`. Con `<select>` nativo usa `event.target.value`.

### "Error: You already have a debug level with that name"
**Causa**: Salesforce ha già un debug level con quel nome dalla sessione precedente.
**Soluzione**: `sf apex tail log --debug-level NomeUnivoco` oppure cancella il debug level da Setup → Debug Levels.

### I test falliscono con "System.AssertException"
**Causa**: l'asserzione non è soddisfatta — il valore atteso non corrisponde a quello effettivo.
**Come leggere l'errore**: il messaggio di Assert.areEqual dice `Expected: X, Actual: Y`. Confronta i due valori per capire cosa sta tornando di diverso dal previsto.

---

*Documento di onboarding — Account Manager LWC Demo*
*Versione 1.0 — Marzo 2026*
