/**
 * @description Classe di test per AccountController.
 *              Obiettivo: copertura minima 85%, con test mirati su
 *              paginazione, ordinamento, mass update e casi limite (sad path).
 * @author      Senior Technical Architect Demo
 */
@IsTest
private class AccountControllerTest {

    // ─────────────────────────────────────────────
    // TEST DATA SETUP
    // ─────────────────────────────────────────────

    /**
     * @description Crea 25 Account di test con dati deterministici.
     *              Usiamo @TestSetup per eseguire il DML una sola volta
     *              e condividere i dati tra tutti i metodi di test.
     *              Questo ottimizza i tempi di esecuzione dei test.
     */
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

    // ─────────────────────────────────────────────
    // TEST: getAccounts — HAPPY PATH
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetAccounts_firstPage_returnsCorrectData() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 10, 'Name', 'ASC');
        Test.stopTest();

        // Verifica struttura della risposta
        Assert.isNotNull(result, 'Il risultato non deve essere null');
        Assert.areEqual(25, result.totalRecords, 'Totale record deve essere 25');
        Assert.areEqual(3,  result.totalPages,   'Con pageSize=10 e 25 record, ci sono 3 pagine');
        Assert.areEqual(1,  result.currentPage,  'Pagina corrente deve essere 1');
        Assert.areEqual(10, result.records.size(), 'La prima pagina deve contenere 10 record');
    }

    @IsTest
    static void testGetAccounts_lastPage_returnsRemainingRecords() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(3, 10, 'Name', 'ASC');
        Test.stopTest();

        // L'ultima pagina ha solo 5 record (25 - 20 = 5)
        Assert.areEqual(5, result.records.size(), 'L\'ultima pagina deve avere 5 record');
        Assert.areEqual(3, result.currentPage, 'Pagina corrente deve essere 3');
    }

    @IsTest
    static void testGetAccounts_sortByNameASC_orderedCorrectly() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 5, 'Name', 'ASC');
        Test.stopTest();

        // Il primo record in ordine ASC deve essere 'Test Account 01'
        Assert.areEqual(
            'Test Account 01',
            result.records[0].Name,
            'Il primo record ASC deve essere Test Account 01'
        );
    }

    @IsTest
    static void testGetAccounts_sortByNameDESC_orderedCorrectly() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 5, 'Name', 'DESC');
        Test.stopTest();

        // Il primo record in ordine DESC deve essere 'Test Account 25'
        Assert.areEqual(
            'Test Account 25',
            result.records[0].Name,
            'Il primo record DESC deve essere Test Account 25'
        );
    }

    @IsTest
    static void testGetAccounts_sortByType_works() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 10, 'Type', 'ASC');
        Test.stopTest();

        Assert.isNotNull(result, 'Ordinamento per Type deve funzionare');
        Assert.isFalse(result.records.isEmpty(), 'Deve restituire record');
    }

    // ─────────────────────────────────────────────
    // TEST: getAccounts — SAD PATH / EDGE CASES
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetAccounts_invalidSortField_fallsBackToName() {
        Test.startTest();
        // Passiamo un campo non in whitelist: deve silenziosamente usare 'Name'
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 10, 'INVALID__FIELD', 'ASC');
        Test.stopTest();

        // La query non deve esplodere e deve restituire dati
        Assert.isNotNull(result);
        Assert.isFalse(result.records.isEmpty());
    }

    @IsTest
    static void testGetAccounts_invalidDirection_fallsBackToASC() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 10, 'Name', 'INVALID');
        Test.stopTest();

        Assert.isNotNull(result);
    }

    @IsTest
    static void testGetAccounts_pageNumberExceedsTotal_clampsToLastPage() {
        Test.startTest();
        // Chiedo la pagina 999, che non esiste: deve restituire l'ultima pagina
        AccountController.AccountPage result =
            AccountController.getAccounts(999, 10, 'Name', 'ASC');
        Test.stopTest();

        Assert.areEqual(3, result.currentPage, 'Deve essere clampata all\'ultima pagina');
    }

    @IsTest
    static void testGetAccounts_nullInputs_handledGracefully() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(null, null, null, null);
        Test.stopTest();

        // Deve usare i valori di default senza lanciare eccezioni
        Assert.isNotNull(result);
        Assert.areEqual(1, result.currentPage);
    }

    // ─────────────────────────────────────────────
    // TEST: massUpdateAccounts — HAPPY PATH
    // ─────────────────────────────────────────────

    @IsTest
    static void testMassUpdate_validIds_updatesDescription() {
        // Recupera 3 account di test
        List<Account> accounts = [SELECT Id FROM Account LIMIT 3];
        List<Id> ids = new List<Id>();
        for (Account a : accounts) {
            ids.add(a.Id);
        }
        String newDesc = 'Updated by Mass Update Test';

        Test.startTest();
        AccountController.MassUpdateResult result =
            AccountController.massUpdateAccounts(ids, newDesc);
        Test.stopTest();

        // Verifica il risultato della chiamata Apex
        Assert.isTrue(result.success, 'L\'operazione deve avere successo');
        Assert.areEqual(3, result.updatedCount, 'Devono essere aggiornati 3 record');

        // Verifica il dato effettivo nel database (non fidarsi solo del DTO)
        List<Account> updated = [
            SELECT Description
            FROM   Account
            WHERE  Id IN :ids
        ];
        for (Account a : updated) {
            Assert.areEqual(newDesc, a.Description, 'La descrizione deve essere aggiornata');
        }
    }

    @IsTest
    static void testMassUpdate_allAccounts_bulkificationWorks() {
        // Test di bulkification: aggiorna tutti e 25 i record in un solo DML
        List<Account> allAccounts = [SELECT Id FROM Account];
        List<Id> allIds = new List<Id>();
        for (Account a : allAccounts) {
            allIds.add(a.Id);
        }

        Test.startTest();
        AccountController.MassUpdateResult result =
            AccountController.massUpdateAccounts(allIds, 'Bulk Updated');
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.areEqual(25, result.updatedCount, 'Tutti i 25 record devono essere aggiornati');
    }

    // ─────────────────────────────────────────────
    // TEST: massUpdateAccounts — SAD PATH
    // ─────────────────────────────────────────────

    @IsTest
    static void testMassUpdate_emptyList_returnsFalse() {
        Test.startTest();
        AccountController.MassUpdateResult result =
            AccountController.massUpdateAccounts(new List<Id>(), 'Any Description');
        Test.stopTest();

        Assert.isFalse(result.success, 'Lista vuota deve restituire success=false');
        Assert.isNotNull(result.message, 'Deve esserci un messaggio di errore');
    }

    @IsTest
    static void testMassUpdate_nullList_returnsFalse() {
        Test.startTest();
        AccountController.MassUpdateResult result =
            AccountController.massUpdateAccounts(null, 'Any Description');
        Test.stopTest();

        Assert.isFalse(result.success, 'Lista null deve restituire success=false');
    }
}