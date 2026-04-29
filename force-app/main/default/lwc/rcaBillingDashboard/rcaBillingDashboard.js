import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent }   from 'lightning/platformShowToastEvent';
import getBillingMetrics    from '@salesforce/apex/RCABillingDashboardController.getBillingMetrics';
import getOverdueInvoices   from '@salesforce/apex/RCABillingDashboardController.getOverdueInvoices';
import postSelectedInvoices from '@salesforce/apex/RCABillingDashboardController.postInvoices';

/**
 * rcaBillingDashboard
 *
 * Dashboard for native RCA billing operations.
 * Surfaces Invoice and BillingSchedule data — no blng__ namespace.
 */
export default class RcaBillingDashboard extends LightningElement {

    @track metrics         = { totalOutstanding: 0, overdueCount: 0, thisMonthCount: 0 };
    @track overdueInvoices = [];
    @track selectedIds     = [];
    @track isLoading       = false;

    columns = [
        { label: 'Invoice Number', fieldName: 'InvoiceNumber',    type: 'text'     },
        { label: 'Account',        fieldName: 'BillingAccountName', type: 'text'   },
        { label: 'Total',          fieldName: 'TotalAmount',      type: 'currency' },
        { label: 'Balance',        fieldName: 'Balance',          type: 'currency' },
        { label: 'Due Date',       fieldName: 'DueDate',          type: 'date'     },
        { label: 'Days Overdue',   fieldName: 'daysOverdue',      type: 'number'   },
        { label: 'Status',         fieldName: 'Status',           type: 'text'     }
    ];

    // ─── Wire ─────────────────────────────────────────────────────────────────

    @wire(getBillingMetrics)
    wiredMetrics({ data, error }) {
        if (data)  this.metrics = data;
        if (error) this.showToast('Error', 'Could not load billing metrics.', 'error');
    }

    @wire(getOverdueInvoices)
    wiredInvoices({ data, error }) {
        if (data) {
            const today = new Date();
            this.overdueInvoices = data.map(inv => ({
                ...inv,
                BillingAccountName: inv.BillingAccount?.Name,
                daysOverdue: Math.floor(
                    (today - new Date(inv.DueDate)) / (1000 * 60 * 60 * 24)
                )
            }));
        }
        if (error) this.showToast('Error', 'Could not load overdue invoices.', 'error');
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    get formattedOutstanding() {
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })
            .format(this.metrics.totalOutstanding ?? 0);
    }

    get hasOverdue()      { return this.overdueInvoices.length > 0; }
    get hasSelection()    { return this.selectedIds.length > 0; }
    get selectionLabel()  { return `Post ${this.selectedIds.length} Invoice(s)`; }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    handleRowSelection(event) {
        this.selectedIds = event.detail.selectedRows.map(r => r.Id);
    }

    async handlePostSelected() {
        this.isLoading = true;
        try {
            await postSelectedInvoices({ invoiceIds: this.selectedIds });
            this.showToast('Posted', `${this.selectedIds.length} invoice(s) posted successfully.`, 'success');
            this.selectedIds = [];
            // Force refresh
            this.template.querySelector('lightning-datatable').selectedRows = [];
        } catch (err) {
            this.showToast('Error', err.body?.message || 'Posting failed.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
