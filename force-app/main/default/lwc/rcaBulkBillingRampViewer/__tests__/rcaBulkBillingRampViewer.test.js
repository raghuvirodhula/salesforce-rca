import { createElement } from 'lwc';
import RcaBulkBillingRampViewer from 'c/rcaBulkBillingRampViewer';

jest.mock(
    '@salesforce/apex/RCABulkBillingService.previewRamp',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
import previewRamp from '@salesforce/apex/RCABulkBillingService.previewRamp';

describe('c-rca-bulk-billing-ramp-viewer', () => {

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function mountWith(overrides = {}) {
        const el = createElement('c-rca-bulk-billing-ramp-viewer', { is: RcaBulkBillingRampViewer });
        el.productCode      = overrides.productCode      ?? 'BB1';
        el.contractStartDate = overrides.contractStartDate ?? '2026-01-01';
        el.termYears        = overrides.termYears        ?? 3;
        el.baseAnnualPrice  = overrides.baseAnnualPrice  ?? 1000;
        document.body.appendChild(el);
        return el;
    }

    it('renders the ramp table when wire adapter returns data', async () => {
        const el = mountWith();
        previewRamp.emit({
            productCode: 'BB1',
            termYears: 3,
            baseAnnualPrice: 1000,
            totalContractValue: 2700,
            tiers: [
                { yearNumber: 1, discountPercentage: 20, netAnnualPrice: 800,
                  periodStartDate: '2026-01-01', periodEndDate: '2026-12-31' },
                { yearNumber: 2, discountPercentage: 10, netAnnualPrice: 900,
                  periodStartDate: '2027-01-01', periodEndDate: '2027-12-31' },
                { yearNumber: 3, discountPercentage: 0,  netAnnualPrice: 1000,
                  periodStartDate: '2028-01-01', periodEndDate: '2028-12-31' }
            ]
        });
        await Promise.resolve();

        const dt = el.shadowRoot.querySelector('lightning-datatable');
        expect(dt).not.toBeNull();
        expect(dt.data).toHaveLength(3);
        expect(dt.data[0].netAnnualPrice).toBe(800);

        const tcv = el.shadowRoot.querySelector('lightning-formatted-number');
        expect(tcv.value).toBe(2700);
    });

    it('shows error UI when the wire returns an error', async () => {
        const el = mountWith();
        previewRamp.error({ body: { message: 'Term years must be between 1 and 30.' } });
        await Promise.resolve();

        const errEl = el.shadowRoot.querySelector('.error-message');
        expect(errEl).not.toBeNull();
        expect(errEl.textContent).toContain('Term years must be between 1 and 30');

        // No table should render in the error state
        expect(el.shadowRoot.querySelector('lightning-datatable')).toBeNull();
    });
});
