import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import previewRamp from '@salesforce/apex/RCABulkBillingService.previewRamp';

const COLUMNS = [
    { label: 'Year',           fieldName: 'yearNumber',         type: 'number', initialWidth: 70 },
    { label: 'Period Start',   fieldName: 'periodStartDate',    type: 'date-local' },
    { label: 'Period End',     fieldName: 'periodEndDate',      type: 'date-local' },
    { label: 'Discount %',     fieldName: 'discountPercentage', type: 'percent-fixed',
        cellAttributes: { alignment: 'right' },
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 } },
    { label: 'Net Annual',     fieldName: 'netAnnualPrice',     type: 'currency',
        cellAttributes: { alignment: 'right' } }
];

export default class RcaBulkBillingRampViewer extends LightningElement {

    @api productCode      = 'BB1';
    @api contractStartDate;            // ISO string; defaults to today on connect
    @api termYears        = 3;
    @api baseAnnualPrice  = 0;

    @track tiers              = [];
    @track totalContractValue = 0;
    @track error;
    @track isLoading          = false;

    columns = COLUMNS;

    connectedCallback() {
        if (!this.contractStartDate) {
            this.contractStartDate = new Date().toISOString().slice(0, 10);
        }
    }

    @wire(previewRamp, {
        productCode:       '$productCode',
        contractStartDate: '$contractStartDate',
        termYears:         '$termYears',
        baseAnnualPrice:   '$baseAnnualPrice'
    })
    handleRamp({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.tiers              = data.tiers || [];
            this.totalContractValue = data.totalContractValue;
            this.error              = undefined;
        } else if (error) {
            this.tiers              = [];
            this.totalContractValue = 0;
            this.error              = this.reduceError(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Ramp preview failed',
                message: this.error,
                variant: 'error'
            }));
        }
    }

    // ─── input handlers ──────────────────────────────────────────────────────

    handleProductCodeChange(event) {
        this.productCode = event.target.value;
    }

    handleStartDateChange(event) {
        this.contractStartDate = event.target.value;
    }

    handleTermChange(event) {
        const v = parseInt(event.target.value, 10);
        this.termYears = Number.isFinite(v) ? v : this.termYears;
    }

    handlePriceChange(event) {
        const v = parseFloat(event.target.value);
        this.baseAnnualPrice = Number.isFinite(v) ? v : 0;
    }

    // ─── helpers ─────────────────────────────────────────────────────────────

    get hasTiers() {
        return this.tiers && this.tiers.length > 0;
    }

    reduceError(error) {
        if (!error) return 'Unknown error';
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        if (error.body && error.body.message) return error.body.message;
        if (typeof error.message === 'string') return error.message;
        return JSON.stringify(error);
    }
}
