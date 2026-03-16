/**
 * @description Controller Apex per la gestione paginata e ordinata degli Account.
 *              Espone metodi @AuraEnabled per LWC con focus su sicurezza e bulkification.
 * @author      Nicola Bartolini
 */
public with sharing class AccountController {

    // ─────────────────────────────────────────────
    // INNER CLASSES (Data Transfer Objects)
    // ─────────────────────────────────────────────

    /**
     * @description DTO che incapsula sia i record della pagina corrente
     *              sia i metadati di paginazione. Riduce il numero di chiamate
     *              Apex da 2 (getData + getCount) a 1 sola chiamata.
     */
    public class AccountPage {
        @AuraEnabled public List<Account> records { get; set; }
        @AuraEnabled public Integer totalRecords { get; set; }
        @AuraEnabled public Integer totalPages { get; set; }
        @AuraEnabled public Integer currentPage { get; set; }
    }

    /**
     * @description DTO per il risultato dell'operazione di mass update.
     *              Permette di restituire sia un flag di successo sia un messaggio
     *              di errore senza dover gestire eccezioni lato JS.
     */
    public class MassUpdateResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Integer updatedCount { get; set; }
    }

    // ─────────────────────────────────────────────
    // METODI PRINCIPALI
    // ─────────────────────────────────────────────

    /**
     * @description Recupera una pagina di Account con supporto a paginazione e ordinamento.
     *
     * SCELTA ARCHITETTURALE - Server-Side Sorting:
     * L'ordinamento avviene in SOQL (ORDER BY) e non in JavaScript.
     * Motivo: con un dataset di 100k record, ordinare lato client richiederebbe
     * di caricare tutti i record in memoria. Con l'approccio server-side, ogni
     * query ritorna SOLO i record della pagina corrente (es. 10 record).
     *
     * SCELTA ARCHITETTURALE - WITH USER_MODE:
     * Utilizziamo WITH USER_MODE invece di with sharing + Security.stripInaccessible
     * perché è più conciso e gestisce automaticamente sia FLS che CRUD enforcement.
     * Disponibile da API v56.0+.
     *
     * @param pageNumber    Numero della pagina (1-based)
     * @param pageSize      Numero di record per pagina
     * @param sortField     Campo su cui ordinare (es. 'Name')
     * @param sortDirection Direzione di ordinamento ('ASC' o 'DESC')
     * @return              AccountPage con records e metadati
     */
    @AuraEnabled(cacheable=true)
    public static AccountPage getAccounts(
        Integer pageNumber,
        Integer pageSize,
        String  sortField,
        String  sortDirection
    ) {
        // ── Validazione Input (prevenzione SOQL Injection) ──────────────────
        // Non usiamo mai String.format diretto con input utente in SOQL.
        // Whitelist sui campi ordinabili: accettiamo SOLO campi noti.
        Set<String> allowedSortFields = new Set<String>{
            'Name', 'Type', 'Phone', 'CreatedDate'
        };
        if (!allowedSortFields.contains(sortField)) {
            sortField = 'Name';
        }
        // Whitelist sulla direzione
        sortDirection = (sortDirection == 'DESC') ? 'DESC' : 'ASC';

        // Sanitizza pageSize e pageNumber
        pageSize   = (pageSize   != null && pageSize   > 0) ? pageSize   : 10;
        pageNumber = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;

        // ── Conteggio Totale Record ──────────────────────────────────────────
        // WITH USER_MODE: applica FLS e CRUD dell'utente corrente.
        // Nota: la count() è separata dalla query dati per efficienza.
        Integer totalRecords = [
            SELECT COUNT()
            FROM   Account
            WITH   USER_MODE
        ];

        // ── Calcolo Metadati Paginazione ─────────────────────────────────────
        Integer totalPages = (Integer) Math.ceil((Double) totalRecords / pageSize);
        totalPages = Math.max(totalPages, 1); // Evita divisione per zero

        // Assicura che pageNumber non superi il totale
        pageNumber = Math.min(pageNumber, totalPages);

        Integer offsetValue = (pageNumber - 1) * pageSize;

        // ── Query Dati con OFFSET e ORDER BY ─────────────────────────────────
        // LIMITAZIONE NOTA: SOQL OFFSET ha un limite di 2000 record.
        // Per dataset > 200k righe, considera Cursor-based Pagination
        // (usando l'Id dell'ultimo record come "cursor").
        String soqlQuery =
            'SELECT Id, Name, Type, Phone, CreatedDate ' +
            'FROM   Account ' +
            'WITH   USER_MODE ' +
            'ORDER BY ' + sortField + ' ' + sortDirection + ' NULLS LAST ' +
            'LIMIT  :pageSize ' +
            'OFFSET :offsetValue';

        List<Account> records = Database.query(soqlQuery);

        // ── Costruzione risposta ─────────────────────────────────────────────
        AccountPage result    = new AccountPage();
        result.records        = records;
        result.totalRecords   = totalRecords;
        result.totalPages     = totalPages;
        result.currentPage    = pageNumber;

        return result;
    }

    /**
     * @description Aggiorna il campo Description per una lista di Account ID.
     *
     * SCELTA ARCHITETTURALE - Bulkification:
     * Il metodo riceve una LISTA di ID (non un singolo ID) e usa una singola
     * DML operation (update). Questo rispetta il pattern Bulkification:
     * - 1 SOQL query invece di N query in un loop
     * - 1 DML statement invece di N DML in un loop
     * Non cacheable=true perché modifica dati.
     *
     * SICUREZZA: with sharing è dichiarato a livello di classe.
     * Database.update con allOrNothing=false gestisce errori parziali
     * e permette di restituire un report dettagliato.
     *
     * @param accountIds    Lista degli ID degli Account da aggiornare
     * @param newDescription Nuovo valore per il campo Description
     * @return              MassUpdateResult con esito operazione
     */
    @AuraEnabled
    public static MassUpdateResult massUpdateAccounts(
        List<Id>   accountIds,
        String     newDescription
    ) {
        MassUpdateResult result = new MassUpdateResult();

        // ── Validazione Input ────────────────────────────────────────────────
        if (accountIds == null || accountIds.isEmpty()) {
            result.success = false;
            result.message = 'Nessun record selezionato.';
            return result;
        }

        // ── Preparazione Record (Bulkification) ──────────────────────────────
        // Costruiamo la lista in-memory senza query SOQL:
        // sappiamo già gli ID, quindi non serve un SELECT.
        List<Account> accountsToUpdate = new List<Account>();
        for (Id accId : accountIds) {
            accountsToUpdate.add(new Account(
                Id          = accId,
                Description = newDescription
            ));
        }

        // ── DML con gestione errori parziali ─────────────────────────────────
        // allOrNothing=false: se 1 record fallisce, gli altri vengono salvati.
        // In un contesto reale, valuta se preferisci allOrNothing=true
        // per garantire atomicità della transazione.
        List<Database.SaveResult> saveResults = Database.update(
            accountsToUpdate,
            false // allOrNothing
        );

        // ── Analisi risultati ─────────────────────────────────────────────────
        Integer successCount = 0;
        List<String> errors  = new List<String>();

        for (Database.SaveResult sr : saveResults) {
            if (sr.isSuccess()) {
                successCount++;
            } else {
                for (Database.Error err : sr.getErrors()) {
                    errors.add(err.getMessage());
                }
            }
        }

        result.success      = errors.isEmpty();
        result.updatedCount = successCount;
        result.message      = errors.isEmpty()
            ? successCount + ' record aggiornati con successo.'
            : 'Aggiornamento parziale. Errori: ' + String.join(errors, '; ');

        return result;
    }
}