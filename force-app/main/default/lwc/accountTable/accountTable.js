/**
 * @description Controller JS per accountTable LWC.
 *              Gestisce stato di paginazione, ordinamento, selezione e mass update.
 *
 * PATTERN ARCHITETTURALE:
 * - Stato centralizzato in proprietà reactive (@track implicito in LWC moderno)
 * - Separazione netta tra: gestione stato UI / chiamate Apex / gestione errori
 * - wire non usato intenzionalmente: getAccounts ha parametri dinamici
 *   (page, sort), quindi usiamo chiamate imperative con refreshApex manuale.
 *
 * @author  Senior Technical Architect Demo
 * @version 1.0
 */
import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccounts       from '@salesforce/apex/AccountController.getAccounts';
import massUpdateAccounts from '@salesforce/apex/AccountController.massUpdateAccounts';

// ─────────────────────────────────────────────
// COSTANTI
// ─────────────────────────────────────────────

/** Definizione colonne: fieldName corrisponde ai campi SOQL */
const COLUMNS = [
    { label: 'Name',         fieldName: 'Name',        isSorted: false, sortIcon: '' },
    { label: 'Type',         fieldName: 'Type',        isSorted: false, sortIcon: '' },
    { label: 'Phone',        fieldName: 'Phone',       isSorted: false, sortIcon: '' },
    { label: 'Created Date', fieldName: 'CreatedDate', isSorted: false, sortIcon: '' },
];

const PAGE_SIZE_OPTIONS = [
    { label: '5',  value: '5'  },
    { label: '10', value: '10' },
    { label: '25', value: '25' },
    { label: '50', value: '50' },
];

export default class AccountTable extends LightningElement {

    // ─────────────────────────────────────────────
    // STATE (reactive properties)
    // ─────────────────────────────────────────────

    /** Copia profonda delle colonne per modificare isSorted senza mutare COLUMNS */
    @track columns = JSON.parse(JSON.stringify(COLUMNS));

    /** Record della pagina corrente con proprietà aggiuntive per la UI */
    @track records = [];

    /** Mappa Id → boolean per tracciare selezioni (più efficiente di un array) */
    @track selectedIds = new Map();

    // Paginazione
    currentPage  = 1;
    totalPages   = 1;
    totalRecords = 0;
    @api pageSize     = 10;

    // Ordinamento
    sortField     = 'Name';
    sortDirection = 'ASC';

    // UI State
    isLoading    = false;
    errorMessage = '';

    // ─────────────────────────────────────────────
    // LIFECYCLE
    // ─────────────────────────────────────────────

    connectedCallback() {
        this.loadAccounts();
    }

    // ─────────────────────────────────────────────
    // GETTERS (derivati dallo stato, non memorizzati)
    // ─────────────────────────────────────────────

    get hasData()    { return !this.isLoading && !this.hasError && this.records.length > 0; }
    get isEmpty()    { return !this.isLoading && !this.hasError && this.records.length === 0; }
    get hasError()   { return !!this.errorMessage; }
    get isFirstPage(){ return this.currentPage <= 1; }
    get isLastPage() { return this.currentPage >= this.totalPages; }

    get selectedCount()     { return this.selectedIds.size; }
    get isMassUpdateDisabled() { return this.selectedIds.size === 0; }
    get selectionLabel()    { return `${this.selectedIds.size} record selezionati`; }

    get allSelected() {
        if (this.records.length === 0) return false;
        return this.records.every(r => this.selectedIds.has(r.Id));
    }

    get pageSizeOptions() { return PAGE_SIZE_OPTIONS; }
    // lightning-combobox richiede che value sia una stringa, non un intero
    // Aggiungi questo getter nel file .js
    get pageSizeString() {
        return this.pageSize.toString();
    }

    // ─────────────────────────────────────────────
    // DATA LOADING
    // ─────────────────────────────────────────────

    /**
     * @description Chiama Apex in modo imperativo e aggiorna lo stato locale.
     *              Usiamo chiamata imperativa (non @wire) perché i parametri
     *              cambiano dinamicamente (sort, page) e @wire non si adatta
     *              bene a parametri mutevoli senza @wire refresh.
     */
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

            this.currentPage  = result.currentPage;
            this.totalPages   = result.totalPages;
            this.totalRecords = result.totalRecords;

            // Arricchisce ogni record con proprietà UI
            this.records = result.records.map(acc => ({
                ...acc,
                isSelected:     this.selectedIds.has(acc.Id),
                recordUrl:      `/lightning/r/Account/${acc.Id}/view`,
                rowClass:       this.selectedIds.has(acc.Id) ? 'at-row--selected' : '',
                typeBadgeClass: this._getTypeBadgeClass(acc.Type)
            }));

        } catch (error) {
            this.errorMessage = this._extractErrorMessage(error);
            this._showToast('Errore', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────
    // HANDLERS: SORTING
    // ─────────────────────────────────────────────

    handleSort(event) {
        const clickedField = event.currentTarget.dataset.field;

        // Toggle direction se stesso campo, altrimenti ASC di default
        if (this.sortField === clickedField) {
            this.sortDirection = (this.sortDirection === 'ASC') ? 'DESC' : 'ASC';
        } else {
            this.sortField     = clickedField;
            this.sortDirection = 'ASC';
        }

        // Aggiorna indicatori visivi nelle colonne
        this.columns = this.columns.map(col => ({
            ...col,
            isSorted: col.fieldName === this.sortField,
            sortIcon: col.fieldName === this.sortField
                ? (this.sortDirection === 'ASC' ? '▲' : '▼')
                : '',
            ariaSort: col.fieldName === this.sortField
                ? (this.sortDirection === 'ASC' ? 'ascending' : 'descending')
                : 'none'
        }));

        // Ritorna alla pagina 1 quando cambia l'ordinamento
        this.currentPage = 1;
        this.loadAccounts();
    }

    // ─────────────────────────────────────────────
    // HANDLERS: PAGINAZIONE
    // ─────────────────────────────────────────────

    handleFirst()    { this.currentPage = 1;               this.loadAccounts(); }
    handleLast()     { this.currentPage = this.totalPages;  this.loadAccounts(); }
    handlePrevious() { this.currentPage = Math.max(1, this.currentPage - 1); this.loadAccounts(); }
    handleNext()     { this.currentPage = Math.min(this.totalPages, this.currentPage + 1); this.loadAccounts(); }

    handlePageSizeChange(event) {
        // lightning-combobox espone il valore su event.detail.value (stringa)
        const raw = event.detail.value;
        const parsed = parseInt(raw, 10);

        console.log('[PageSize Debug]', { raw, parsed });

        this.pageSize    = parsed;
        this.currentPage = 1;
        this.loadAccounts();
    }

    // ─────────────────────────────────────────────
    // HANDLERS: SELEZIONE
    // ─────────────────────────────────────────────

    handleRowSelect(event) {
        const accountId = event.target.dataset.id;
        const checked   = event.target.checked;

        // Usiamo una nuova Map per triggherare la reattività LWC
        const newMap = new Map(this.selectedIds);
        if (checked) {
            newMap.set(accountId, true);
        } else {
            newMap.delete(accountId);
        }
        this.selectedIds = newMap;

        // Aggiorna lo stato isSelected sui record visualizzati
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
    // HANDLERS: MASS UPDATE
    // ─────────────────────────────────────────────

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
                // Deseleziona tutto dopo un aggiornamento riuscito
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

    // ─────────────────────────────────────────────
    // UTILITY PRIVATE
    // ─────────────────────────────────────────────

    /**
     * @description Mappa il campo Type a una classe CSS badge colorata.
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
     * @description Estrae il messaggio di errore leggibile da un'eccezione Apex.
     *              Gli errori Apex hanno struttura diversa dagli errori JS standard.
     */
    _extractErrorMessage(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message)       return error.message;
        return 'Si è verificato un errore imprevisto.';
    }

    /**
     * @description Wrapper per ShowToastEvent per evitare ripetizioni.
     */
    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}