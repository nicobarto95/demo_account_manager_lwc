/**
 * @description JS controller for the accountTable LWC.
 *              Manages pagination state, column sorting, row selection,
 *              and the mass update operation.
 *
 * ARCHITECTURAL PATTERNS:
 * - Centralised state via reactive properties (@track for objects/arrays)
 * - Clear separation between: UI state management / Apex calls / error handling
 * - Imperative Apex calls instead of @wire: getAccounts has multiple dynamic
 *   parameters (page, sort, pageSize) that change together. Using @wire would
 *   fire a separate Apex call for each individual property change, resulting in
 *   redundant network requests. The imperative approach guarantees exactly one
 *   call per user interaction.
 *
 * @author  Nicola Bartolini
 * @version 1.0
 */
import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccounts        from '@salesforce/apex/AccountController.getAccounts';
import massUpdateAccounts from '@salesforce/apex/AccountController.massUpdateAccounts';

// ─────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────

/**
 * Column definitions. fieldName must match the SOQL field API name exactly.
 * sortable: false prevents the column header from triggering an ORDER BY call.
 * Description is excluded from sorting — long textarea fields cannot be indexed
 * by Salesforce and will throw a runtime error if used in ORDER BY.
 */
const COLUMNS = [
    { label: 'Name',         fieldName: 'Name',        isSorted: false, sortIcon: '', sortable: true  },
    { label: 'Type',         fieldName: 'Type',        isSorted: false, sortIcon: '', sortable: true  },
    { label: 'Phone',        fieldName: 'Phone',       isSorted: false, sortIcon: '', sortable: true  },
    { label: 'Description',  fieldName: 'Description', isSorted: false, sortIcon: '', sortable: false },
    { label: 'Created Date', fieldName: 'CreatedDate', isSorted: false, sortIcon: '', sortable: true  },
];

/** Options for the rows-per-page combobox. Values must be strings — lightning-combobox requirement. */
const PAGE_SIZE_OPTIONS = [
    { label: '5',  value: '5'  },
    { label: '10', value: '10' },
    { label: '25', value: '25' },
    { label: '50', value: '50' },
];

export default class AccountTable extends LightningElement {

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    /**
     * Column state including sort indicators and CSS classes.
     * @track is required so LWC detects mutations to nested object properties.
     * thClass is pre-computed here to avoid repeated ternary logic in the template.
     */
    @track columns = COLUMNS.map(c => ({
        ...c,
        thClass: c.sortable ? 'at-th at-th--sort' : 'at-th'
    }));

    /** Records for the current page, enriched with UI-specific properties. */
    @track records = [];

    /**
     * Map of selected record IDs → true.
     * A Map is used instead of an Array because Map.has(id) is O(1),
     * while Array.includes(id) is O(n). Reassignment (not mutation) is required
     * to trigger LWC reactivity.
     */
    @track selectedIds = new Map();

    // Pagination
    currentPage  = 1;
    totalPages   = 1;
    totalRecords = 0;

    /**
     * Public page size property configurable via App Builder (js-meta.xml).
     * @api makes it read-only inside the component, so all runtime changes
     * are managed through the private _pageSize copy below.
     */
    @api pageSize = 10;

    /** Internal mutable copy of pageSize used for all runtime logic. */
    _pageSize = 10;

    // Sorting
    sortField     = 'Name';
    sortDirection = 'ASC';

    // UI flags
    isLoading    = false;
    errorMessage = '';

    // ─────────────────────────────────────────────
    // LIFECYCLE
    // ─────────────────────────────────────────────

    connectedCallback() {
        // Copy the @api value into the internal property so App Builder
        // configuration is respected, while still allowing runtime changes.
        this._pageSize = this.pageSize;
        this.loadAccounts();
    }

    // ─────────────────────────────────────────────
    // GETTERS — derived state, never stored
    // ─────────────────────────────────────────────

    get hasData()    { return !this.isLoading && !this.hasError && this.records.length > 0; }
    get isEmpty()    { return !this.isLoading && !this.hasError && this.records.length === 0; }
    get hasError()   { return !!this.errorMessage; }
    get isFirstPage(){ return this.currentPage <= 1; }
    get isLastPage() { return this.currentPage >= this.totalPages; }

    get selectedCount()        { return this.selectedIds.size; }
    get isMassUpdateDisabled() { return this.selectedIds.size === 0; }

    get allSelected() {
        if (this.records.length === 0) return false;
        return this.records.every(r => this.selectedIds.has(r.Id));
    }

    get pageSizeOptions() { return PAGE_SIZE_OPTIONS; }

    /** lightning-combobox requires value to be a string, not an integer. */
    get pageSizeString() { return String(this._pageSize); }

    // ─────────────────────────────────────────────
    // DATA LOADING
    // ─────────────────────────────────────────────

    /**
     * @description Calls Apex imperatively and updates local state.
     *              Sets isLoading before the call and clears it in the finally
     *              block so the spinner is always shown/hidden correctly,
     *              regardless of whether the call succeeds or fails.
     */
    async loadAccounts() {
        this.isLoading    = true;
        this.errorMessage = '';

        try {
            const result = await getAccounts({
                pageNumber:    this.currentPage,
                pageSize:      this._pageSize,
                sortField:     this.sortField,
                sortDirection: this.sortDirection
            });

            this.currentPage  = result.currentPage;
            this.totalPages   = result.totalPages;
            this.totalRecords = result.totalRecords;

            // Enrich each SOQL record with UI-only properties not present in Apex
            this.records = result.records.map(acc => ({
                ...acc,
                isSelected:     this.selectedIds.has(acc.Id),
                recordUrl:      `/lightning/r/Account/${acc.Id}/view`,
                rowClass:       this.selectedIds.has(acc.Id) ? 'at-row--selected' : '',
                typeBadgeClass: this._getTypeBadgeClass(acc.Type)
            }));

        } catch (error) {
            this.errorMessage = this._extractErrorMessage(error);
            this._showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────
    // HANDLERS — SORTING
    // ─────────────────────────────────────────────

    handleSort(event) {
        const clickedField = event.currentTarget.dataset.field;

        // Guard: ignore clicks on non-sortable columns (e.g. Description)
        const col = this.columns.find(c => c.fieldName === clickedField);
        if (!col || !col.sortable) return;

        // Toggle direction on the same column; default to ASC for a new column
        if (this.sortField === clickedField) {
            this.sortDirection = (this.sortDirection === 'ASC') ? 'DESC' : 'ASC';
        } else {
            this.sortField     = clickedField;
            this.sortDirection = 'ASC';
        }

        // Rebuild column state with updated sort indicators and CSS classes
        this.columns = this.columns.map(col => ({
            ...col,
            isSorted: col.fieldName === this.sortField,
            sortIcon: col.fieldName === this.sortField
                ? (this.sortDirection === 'ASC' ? '▲' : '▼')
                : '',
            ariaSort: col.fieldName === this.sortField
                ? (this.sortDirection === 'ASC' ? 'ascending' : 'descending')
                : 'none',
            thClass: col.sortable ? 'at-th at-th--sort' : 'at-th'
        }));

        // Reset to page 1 so the user sees the first results of the new sort order
        this.currentPage = 1;
        this.loadAccounts();
    }

    // ─────────────────────────────────────────────
    // HANDLERS — PAGINATION
    // ─────────────────────────────────────────────

    handleFirst()    { this.currentPage = 1;                                            this.loadAccounts(); }
    handleLast()     { this.currentPage = this.totalPages;                              this.loadAccounts(); }
    handlePrevious() { this.currentPage = Math.max(1, this.currentPage - 1);            this.loadAccounts(); }
    handleNext()     { this.currentPage = Math.min(this.totalPages, this.currentPage + 1); this.loadAccounts(); }

    handlePageSizeChange(event) {
        // lightning-combobox exposes the selected value on event.detail.value (string)
        this._pageSize   = parseInt(event.detail.value, 10);
        this.currentPage = 1; // Reset to page 1 when page size changes
        this.loadAccounts();
    }

    // ─────────────────────────────────────────────
    // HANDLERS — SELECTION
    // ─────────────────────────────────────────────

    handleRowSelect(event) {
        const accountId = event.target.dataset.id;
        const checked   = event.target.checked;

        // Create a new Map (instead of mutating the existing one) to trigger
        // LWC reactivity — @track only detects reassignment, not internal mutation.
        const newMap = new Map(this.selectedIds);
        if (checked) {
            newMap.set(accountId, true);
        } else {
            newMap.delete(accountId);
        }
        this.selectedIds = newMap;

        // Sync the isSelected and rowClass flags on the visible records
        this.records = this.records.map(r => ({
            ...r,
            isSelected: newMap.has(r.Id),
            rowClass:   newMap.has(r.Id) ? 'at-row--selected' : ''
        }));
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        const newMap  = new Map(this.selectedIds);

        this.records = this.records.map(r => {
            if (checked) {
                newMap.set(r.Id, true);
            } else {
                newMap.delete(r.Id);
            }
            return { ...r, isSelected: checked, rowClass: checked ? 'at-row--selected' : '' };
        });

        this.selectedIds = newMap;
    }

    // ─────────────────────────────────────────────
    // HANDLERS — MASS UPDATE
    // ─────────────────────────────────────────────

    async handleMassUpdate() {
        if (this.selectedIds.size === 0) return;

        // Build the new description value with the current timestamp
        const newDescription = `Updated on ${new Date().toLocaleString('en-GB')}`;
        const ids = Array.from(this.selectedIds.keys());

        this.isLoading = true;

        try {
            const result = await massUpdateAccounts({
                accountIds:     ids,
                newDescription: newDescription
            });

            if (result.success) {
                this._showToast('Success', result.message, 'success');
                // Clear all selections after a successful update
                this.selectedIds = new Map();
                await this.loadAccounts();
            } else {
                this._showToast('Warning', result.message, 'warning');
            }

        } catch (error) {
            this._showToast('Error', this._extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────
    // PRIVATE UTILITIES
    // ─────────────────────────────────────────────

    /**
     * @description Maps the Account Type field value to a CSS badge modifier class.
     *              Matching is case-insensitive and substring-based to handle
     *              values like 'Customer - Direct' and 'Customer - Channel'.
     */
    _getTypeBadgeClass(type) {
        if (!type) return 'at-type at-type--other';
        const t = type.toLowerCase();
        if (t.includes('customer')) return 'at-type at-type--customer';
        if (t.includes('prospect')) return 'at-type at-type--prospect';
        if (t.includes('partner'))  return 'at-type at-type--partner';
        return 'at-type at-type--other';
    }

    /**
     * @description Extracts a human-readable message from an Apex error object.
     *              Apex errors have a different structure than standard JS errors:
     *              the message is nested under error.body.message.
     */
    _extractErrorMessage(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message)      return error.body.message;
        if (error?.message)            return error.message;
        return 'An unexpected error occurred.';
    }

    /**
     * @description Convenience wrapper around ShowToastEvent to avoid repetition.
     */
    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}