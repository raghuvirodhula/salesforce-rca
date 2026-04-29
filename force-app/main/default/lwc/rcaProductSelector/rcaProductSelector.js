import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProductsFromCatalog  from '@salesforce/apex/RCAProductController.getProductsFromCatalog';
import getSellingModels        from '@salesforce/apex/RCAProductController.getSellingModelsForProduct';
import addLineToQuote          from '@salesforce/apex/RCAProductController.addLineToQuote';

/**
 * rcaProductSelector
 *
 * LWC for browsing the native RCA Product Catalog and adding
 * products to a Quote with a chosen ProductSellingModel.
 *
 * Key native RCA concepts:
 *  - Products come from the native ProductCatalog / ProductCategory hierarchy
 *  - Each product can have multiple ProductSellingModels
 *    (e.g. 'Monthly Subscription', 'Annual Subscription', 'One-Time')
 *  - Pricing is resolved at line creation time via the pricing engine
 */
export default class RcaProductSelector extends LightningElement {

    @api recordId;  // Quote Id

    @track products        = [];
    @track sellingModels   = {};   // productId → [{ Id, Name, SellingModelType }]
    @track selectedModel   = {};   // productId → chosen selling model Id
    @track quantities      = {};   // productId → quantity
    @track isLoading       = false;
    @track searchTerm      = '';

    columns = [
        { label: 'Product',       fieldName: 'Name',            type: 'text'     },
        { label: 'Product Code',  fieldName: 'ProductCode',     type: 'text'     },
        { label: 'Family',        fieldName: 'Family',          type: 'text'     },
        { label: 'List Price',    fieldName: 'UnitPrice',       type: 'currency' }
    ];

    // ─── Wire ─────────────────────────────────────────────────────────────────

    @wire(getProductsFromCatalog, { searchTerm: '$searchTerm' })
    wiredProducts({ data, error }) {
        if (data) {
            this.products = data.map(p => ({
                ...p,
                _quantity: 1
            }));
            // Pre-load selling models for each product
            data.forEach(p => this.loadSellingModels(p.Id));
        }
        if (error) {
            this.showToast('Error', 'Failed to load product catalog.', 'error');
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    async loadSellingModels(productId) {
        try {
            const models = await getSellingModels({ productId });
            this.sellingModels = {
                ...this.sellingModels,
                [productId]: models
            };
            // Default to first selling model
            if (models.length > 0) {
                this.selectedModel = {
                    ...this.selectedModel,
                    [productId]: models[0].Id
                };
            }
        } catch (e) {
            console.error('Error loading selling models for ' + productId, e);
        }
    }

    getModelsForProduct(productId) {
        return this.sellingModels[productId] || [];
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    get hasProducts() {
        return this.products && this.products.length > 0;
    }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleQuantityChange(event) {
        const productId = event.target.dataset.productId;
        this.quantities = {
            ...this.quantities,
            [productId]: Number(event.target.value)
        };
    }

    handleModelChange(event) {
        const productId = event.target.dataset.productId;
        this.selectedModel = {
            ...this.selectedModel,
            [productId]: event.target.value
        };
    }

    async handleAddToQuote(event) {
        const productId = event.target.dataset.productId;
        const product   = this.products.find(p => p.Id === productId);
        if (!product) return;

        this.isLoading = true;
        try {
            await addLineToQuote({
                quoteId:          this.recordId,
                pricebookEntryId: product.PricebookEntryId,
                quantity:         this.quantities[productId] ?? 1,
                sellingModelId:   this.selectedModel[productId]
            });
            this.showToast('Success', `${product.Name} added to quote.`, 'success');
        } catch (err) {
            this.showToast('Error', err.body?.message || 'Failed to add product.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
