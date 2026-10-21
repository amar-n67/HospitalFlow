# Patient billing and document copies

The selected hospital's PostgreSQL ledger is the source for patient rows, care history, pharmacy, billing and receipt copies. Admission charges accrue automatically from dated Admin ward tariffs, including bed, ward, ICU and nursing components. Admin must configure ward prices before bed charges can be posted; the application does not invent a room price. Dispensing medicine posts the selling-price snapshot once; nursing administration does not create a duplicate medicine sale.

## Inclusive GST

Admin can configure hospital rates in **Charges & tariffs → Configure inclusive GST**. Initial application settings requested by the project owner are 18% for bed/ward/ICU, 7% for medicines and 0% for other charges. These are configurable application policies, not a claim about statutory tax treatment.

For each positive charge, its rate is captured when posting. The calculation after allocating discounts/credits is:

`base = round(inclusive net amount / (1 + rate / 100), 2)`

`included GST = inclusive net amount - base`

Thus ₹100 at 18% remains ₹100: ₹84.75 base + ₹15.25 GST. At 7%, ₹100 is ₹93.46 + ₹6.54. A ₹10 discount on the first example leaves ₹90 = ₹76.27 + ₹13.73. Payments reduce the balance, not the invoice's taxable value. Proportional discount allocations use cumulative rounding so invoice cents reconcile exactly.

Existing charges created before migration 028 receive their initial tax snapshot when first read under this policy. Their recorded charges/payments are unchanged. Later rate changes affect newly posted charges; existing snapshots remain immutable. All settings, discounts, charge changes and payments retain audit evidence.

## Access

- Admin and Reception can enter general patient charges, approve discounts and record receipts in their own hospital. Developer retains full access.
- Pharmacy can update medicine prices and apply optional discounts to medicine-only invoices. It cannot access bed/service invoices through finance or receipt endpoints.
- Doctors and Nurses can view detailed invoices for patients in their authorized care scope; billing edits are denied by the API and database routines.
- Patients see their own invoices, GST, discounts, receipts and balance. Portal settlement remains explicitly **TEST ONLY** until a real provider is configured.
- Legacy Billing permission provides read access; it does not authorize financial edits.

## PDF, print and CSV

Document actions include PDF (opens print preview; choose **Save as PDF**), Print and Download (standalone printable HTML). Copies include the HospitalFlow logo, selected hospital name/address, generation time in IST, patient identifiers, line details, tax split and payment history. Hospital branding repeats on printed pages. Current Chrome supports the stylesheet's Page X of Y print-margin counters. Disable browser-added headers/footers if they overlap your printer's own settings.

CSV exports include application/logo text, hospital and IST export time alongside records, and billing exports include base, included GST, grand total, paid and outstanding amounts. CSV is an unpaginated text format: it cannot embed a logo image or printed page counters. Use PDF for a branded paginated copy.
