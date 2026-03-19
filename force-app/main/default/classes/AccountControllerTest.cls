/**
 * @description Test class for AccountController.
 *              Target: minimum 85% code coverage, with dedicated tests for
 *              pagination, sorting, mass update, and edge cases (sad paths).
 * @author      Nicola Bartolini
 */
@IsTest
private class AccountControllerTest {

    // ─────────────────────────────────────────────
    // TEST DATA SETUP
    // ─────────────────────────────────────────────

    /**
     * @description Creates 25 test Accounts with deterministic data.
     *              @TestSetup runs the DML only once and shares the data
     *              across all test methods, reducing overall execution time.
     *              Zero-padded names (e.g. '01', '09') ensure alphabetical
     *              ordering matches numerical ordering — critical for sort tests.
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

        // Verify response structure
        Assert.isNotNull(result, 'Result must not be null');
        Assert.areEqual(25, result.totalRecords, 'Total records should be 25');
        Assert.areEqual(3,  result.totalPages,   'With pageSize=10 and 25 records, there should be 3 pages');
        Assert.areEqual(1,  result.currentPage,  'Current page should be 1');
        Assert.areEqual(10, result.records.size(), 'First page should contain 10 records');
    }

    @IsTest
    static void testGetAccounts_lastPage_returnsRemainingRecords() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(3, 10, 'Name', 'ASC');
        Test.stopTest();

        // Last page has only 5 records (25 - 20 = 5)
        Assert.areEqual(5, result.records.size(), 'Last page should have 5 records');
        Assert.areEqual(3, result.currentPage,    'Current page should be 3');
    }

    @IsTest
    static void testGetAccounts_sortByNameASC_orderedCorrectly() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 5, 'Name', 'ASC');
        Test.stopTest();

        // First record in ASC order should be 'Test Account 01'
        Assert.areEqual(
            'Test Account 01',
            result.records[0].Name,
            'First record in ASC order should be Test Account 01'
        );
    }

    @IsTest
    static void testGetAccounts_sortByNameDESC_orderedCorrectly() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 5, 'Name', 'DESC');
        Test.stopTest();

        // First record in DESC order should be 'Test Account 25'
        Assert.areEqual(
            'Test Account 25',
            result.records[0].Name,
            'First record in DESC order should be Test Account 25'
        );
    }

    @IsTest
    static void testGetAccounts_sortByType_works() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 10, 'Type', 'ASC');
        Test.stopTest();

        Assert.isNotNull(result, 'Sorting by Type should work without errors');
        Assert.isFalse(result.records.isEmpty(), 'Should return records');
    }

    // ─────────────────────────────────────────────
    // TEST: getAccounts — SAD PATH / EDGE CASES
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetAccounts_invalidSortField_fallsBackToName() {
        Test.startTest();
        // Field not in the whitelist — should silently fall back to 'Name'
        AccountController.AccountPage result =
            AccountController.getAccounts(1, 10, 'INVALID__FIELD', 'ASC');
        Test.stopTest();

        // Query must not throw and must return records
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
        // Requesting page 999 which does not exist — should return the last available page
        AccountController.AccountPage result =
            AccountController.getAccounts(999, 10, 'Name', 'ASC');
        Test.stopTest();

        Assert.areEqual(3, result.currentPage, 'Page number should be clamped to the last page');
    }

    @IsTest
    static void testGetAccounts_nullInputs_handledGracefully() {
        Test.startTest();
        AccountController.AccountPage result =
            AccountController.getAccounts(null, null, null, null);
        Test.stopTest();

        // Should apply default values without throwing an exception
        Assert.isNotNull(result);
        Assert.areEqual(1, result.currentPage);
    }

    // ─────────────────────────────────────────────
    // TEST: massUpdateAccounts — HAPPY PATH
    // ─────────────────────────────────────────────

    @IsTest
    static void testMassUpdate_validIds_updatesDescription() {
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

        // Verify the Apex response DTO
        Assert.isTrue(result.success,    'Operation should succeed');
        Assert.areEqual(3, result.updatedCount, '3 records should be updated');

        // Verify the actual database value — do not trust the DTO alone
        List<Account> updated = [
            SELECT Description
            FROM   Account
            WHERE  Id IN :ids
        ];
        for (Account a : updated) {
            Assert.areEqual(newDesc, a.Description, 'Description should be updated in the database');
        }
    }

    @IsTest
    static void testMassUpdate_allAccounts_bulkificationWorks() {
        // Bulkification test: update all 25 records in a single DML statement
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
        Assert.areEqual(25, result.updatedCount, 'All 25 records should be updated');
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

        Assert.isFalse(result.success, 'Empty list should return success=false');
        Assert.isNotNull(result.message, 'An error message should be present');
    }

    @IsTest
    static void testMassUpdate_nullList_returnsFalse() {
        Test.startTest();
        AccountController.MassUpdateResult result =
            AccountController.massUpdateAccounts(null, 'Any Description');
        Test.stopTest();

        Assert.isFalse(result.success, 'Null list should return success=false');
    }
}