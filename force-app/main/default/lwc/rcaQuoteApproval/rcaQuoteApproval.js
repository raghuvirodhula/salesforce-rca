import { LightningElement, api, wire, track } from 'lwc';
import { getRecord }        from 'lightning/uiRecordApi';
import { ShowToastEvent }   from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import submitForApproval    from '@salesforce/apex/RCAApprovalController.submitForApproval';
import recallApproval       from '@salesforce/apex/RCAApprovalController.recallApproval';

const QUOTE_FIELDS = [
    'Quote.Status',
    'Quote.TotalPrice',
    'Quote.Name',
    'Quote.ExpirationDate'
];

/**
 * rcaQuoteApproval
 *
 * Quick Action LWC for submitting a native RCA Quote through
 * Salesforce Flow Orchestration approval.
 */
export default class RcaQuoteApproval extends LightningElement {

    @api recordId;

    @track comments   = '';
    @track isLoading  = false;
    @track quoteData  = null;

    @wire(getRecord, { recordId: '$recordId', fields: QUOTE_FIELDS })
    wiredQuote({ data, error }) {
        if (data) this.quoteData = data.fields;
        if (error) this.showToast('Error', 'Failed to load quote.', 'error');
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    get quoteName()   { return this.quoteData?.Name?.value; }
    get quoteStatus() { return this.quoteData?.Status?.value; }
    get quoteTotal()  {
        const val = this.quoteData?.TotalPrice?.value;
        return val != null
            ? new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(val)
            : '—';
    }

    get canSubmit()  { return this.quoteStatus === 'Draft' || this.quoteStatus === 'Needs Review'; }
    get canRecall()  { return this.quoteStatus === 'Pending Approval'; }
    get isApproved() { return this.quoteStatus === 'Approved'; }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    handleCommentsChange(event) {
        this.comments = event.target.value;
    }

    async handleSubmit() {
        this.isLoading = true;
        try {
            await submitForApproval({
                quoteId:   this.recordId,
                comments:  this.comments
            });
            this.showToast('Submitted', 'Quote submitted for approval.', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (err) {
            this.showToast('Error', err.body?.message || 'Submission failed.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRecall() {
        this.isLoading = true;
        try {
            await recallApproval({ quoteId: this.recordId });
            this.showToast('Recalled', 'Approval request recalled.', 'info');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (err) {
            this.showToast('Error', err.body?.message || 'Recall failed.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
