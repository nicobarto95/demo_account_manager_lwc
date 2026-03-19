/**
 * @description Apex controller for paginated and sorted Account management.
 *              Exposes @AuraEnabled methods for LWC with a focus on security
 *              and bulkification best practices.
 * @author      Nicola Bartolini
 */
public with sharing class AccountController {

    // ─────────────────────────────────────────────
    // INNER CLASSES (Data Transfer Objects)
    // ─────────────────────────────────────────────

    /**
     * @description DTO that wraps both the current page records and pagination
     *              metadata. Reduces Apex round-trips from 2 (getData + getCount)
     *              down to a single call.
     */
    public class AccountPage {
        @AuraEnabled public List<Account> records { get; set; }
        @AuraEnabled public Integer totalRecords  { get; set; }
        @AuraEnabled public Integer totalPages    { get; set; }
        @AuraEnabled public Integer currentPage   { get; set; }
    }

    /**
     * @description DTO for the mass update operation result.
     *              Returns both a success flag and a human-readable message
     *              without relying on JS-side exception handling.
     */
    public class MassUpdateResult {
        @AuraEnabled public Boolean success      { get; set; }
        @AuraEnabled public String  message      { get; set; }
        @AuraEnabled public Integer updatedCount { get; set; }
    }

    // ─────────────────────────────────────────────
    // PUBLIC METHODS
    // ─────────────────────────────────────────────

    /**
     * @description Retrieves a page of Account records with pagination and sorting support.
     *
     * ARCHITECTURAL DECISION — Server-Side Sorting:
     * Sorting is performed via SOQL ORDER BY, not in JavaScript.
     * Reason: with a dataset of 100k records, client-side sorting would require
     * loading all records into memory. With server-side sorting, each query
     * returns ONLY the records for the current page (e.g. 10 records).
     *
     * ARCHITECTURAL DECISION — WITH USER_MODE:
     * We use WITH USER_MODE instead of with sharing + Security.stripInaccessible
     * because it is more concise and automatically enforces both FLS and CRUD.
     * Available from API v56.0+.
     *
     * KNOWN LIMITATION — SOQL OFFSET:
     * SOQL OFFSET has a hard limit of 2000 records. For datasets larger than
     * ~200k rows consider switching to Cursor-based Pagination using the last
     * record Id as the cursor.
     *
     * @param pageNumber    Page number (1-based index)
     * @param pageSize      Number of records per page
     * @param sortField     Field to sort by (e.g. 'Name')
     * @param sortDirection Sort direction ('ASC' or 'DESC')
     * @return              AccountPage containing records and pagination metadata
     */
    @AuraEnabled
    public static AccountPage getAccounts(
        Integer pageNumber,
        Integer pageSize,
        String  sortField,
        String  sortDirection
    ) {
        // ── Input Validation — SOQL Injection Prevention ────────────────────
        // Never concatenate raw user input directly into a SOQL string.
        // Accept ONLY known, whitelisted field names for ORDER BY.
        // Note: Description is intentionally excluded — textarea fields
        // cannot be used in ORDER BY clauses.
        Set<String> allowedSortFields = new Set<String>{
            'Name', 'Type', 'Phone', 'CreatedDate'
        };
        if (!allowedSortFields.contains(sortField)) {
            sortField = 'Name';
        }

        // Whitelist on sort direction — accept only DESC, default to ASC
        sortDirection = (sortDirection == 'DESC') ? 'DESC' : 'ASC';

        // Sanitize pageSize and pageNumber — fall back to safe defaults if null or invalid
        pageSize   = (pageSize   != null && pageSize   > 0) ? pageSize   : 10;
        pageNumber = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;

        // ── Total Record Count ───────────────────────────────────────────────
        // WITH USER_MODE enforces the running user's FLS and CRUD permissions.
        // Count query is kept separate from the data query for clarity.
        Integer totalRecords = [
            SELECT COUNT()
            FROM   Account
            WITH   USER_MODE
        ];

        // ── Pagination Metadata ──────────────────────────────────────────────
        // Cast to Double before dividing to avoid integer truncation (e.g. 13/10 = 1, not 1.3)
        Integer totalPages = (Integer) Math.ceil((Double) totalRecords / pageSize);
        totalPages = Math.max(totalPages, 1); // Guard against empty dataset returning 0 pages

        // Clamp pageNumber to a valid range — prevents out-of-bounds OFFSET
        pageNumber = Math.min(pageNumber, totalPages);

        Integer offsetValue = (pageNumber - 1) * pageSize;

        // ── Data Query ───────────────────────────────────────────────────────
        // sortField is safe to concatenate here because it has been validated
        // against the whitelist above. Bind variables (:pageSize, :offsetValue)
        // are used for all other dynamic values to prevent injection.
        String soqlQuery =
            'SELECT Id, Name, Type, Phone, Description, CreatedDate ' +
            'FROM   Account '                                          +
            'WITH   USER_MODE '                                        +
            'ORDER BY ' + sortField + ' ' + sortDirection + ' NULLS LAST ' +
            'LIMIT  :pageSize '                                        +
            'OFFSET :offsetValue';

        List<Account> records = Database.query(soqlQuery);

        // ── Build and Return Response ────────────────────────────────────────
        AccountPage result  = new AccountPage();
        result.records      = records;
        result.totalRecords = totalRecords;
        result.totalPages   = totalPages;
        result.currentPage  = pageNumber;

        return result;
    }

    /**
     * @description Updates the Description field for a list of Account IDs.
     *
     * ARCHITECTURAL DECISION — Bulkification:
     * The method accepts a LIST of IDs (not a single ID) and performs a single
     * DML operation. This follows the Bulkification pattern:
     * - 0 SOQL queries (IDs are already known, no SELECT needed)
     * - 1 DML statement regardless of how many records are updated
     * Not marked cacheable=true because this method writes data.
     *
     * SECURITY: sharing rules are enforced at class level via 'with sharing'.
     * Database.update with allOrNothing=false allows partial saves and returns
     * a detailed per-record result report.
     *
     * @param accountIds     List of Account IDs to update
     * @param newDescription New value for the Description field
     * @return               MassUpdateResult with operation outcome
     */
    @AuraEnabled
    public static MassUpdateResult massUpdateAccounts(
        List<Id> accountIds,
        String   newDescription
    ) {
        MassUpdateResult result = new MassUpdateResult();

        // ── Input Validation ─────────────────────────────────────────────────
        if (accountIds == null || accountIds.isEmpty()) {
            result.success = false;
            result.message = 'No records selected.';
            return result;
        }

        // ── Build Update List in Memory (Bulkification) ──────────────────────
        // Construct partial Account objects with only Id + Description.
        // Salesforce recognises the presence of an Id as an update operation —
        // there is no need to SELECT the full record first.
        List<Account> accountsToUpdate = new List<Account>();
        for (Id accId : accountIds) {
            accountsToUpdate.add(new Account(
                Id          = accId,
                Description = newDescription
            ));
        }

        // ── DML with Partial Error Handling ──────────────────────────────────
        // allOrNothing=false: if one record fails (e.g. validation rule),
        // the remaining records are still saved.
        // Switch to allOrNothing=true if atomic behaviour is required.
        List<Database.SaveResult> saveResults = Database.update(
            accountsToUpdate,
            false // allOrNothing
        );

        // ── Analyse Save Results ─────────────────────────────────────────────
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
            ? successCount + ' record(s) updated successfully.'
            : 'Partial update. Errors: ' + String.join(errors, '; ');

        return result;
    }
}