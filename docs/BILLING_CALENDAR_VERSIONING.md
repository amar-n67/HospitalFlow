# Billing, holiday calendars and application versions

## Daily stay charges

Admin and Developer can open **Charges & tariffs → Configure daily rates** (also available from Patient care pathway). Define the bed, ward, ICU and nursing components for each ward and an effective date. Enter zero explicitly for an unused component. No default money amount is invented for an unconfigured ward.

An active admission accrues one charge per hospital calendar day in Asia/Kolkata, including the admission and discharge dates. The first bed occupied that day determines its ward/category. ICU charges apply only to an ICU-labelled bed or ward. The background worker checks every five minutes, catches up missed days after downtime and stops accrual at discharge. Managed discharge performs a strict final calculation. Duplicate runs do not duplicate a day's charge. The worker now covers all active admissions, including older stays.

Admin may revise a tariff for the same effective date. The latest version is used for days not yet posted. Posted line items and their original rate references remain immutable, including previously posted zero-charge days. Revisions do not silently rewrite historical invoices. Use an approved discount or other existing credit workflow for a correction to posted charges. Doctor and Nurse can see the full dated tariff list and each authorized patient's accumulated charges.

## Medicine costs and discounts

**Charges & tariffs** lists medicine selling prices. Admin can change a batch's unit price with a reason; previous/new prices, author and timestamp are recorded. Dispensing uses the current price and snapshots quantity and unit price on the invoice. A subsequent price edit or nursing administration does not reprice or duplicate the original issue charge.

Patient care and patient invoices show issued medicine quantities, issue-time unit prices, total medicine charges, gross charges, discounts, other credits, net total, retained payments and outstanding balance. Doctor and Nurse see this information only for patients within their care scope. Pharmacy/Billing retain their existing operational scope. Pending prescriptions remain in the care/pharmacy queues until fulfilled.

Admin or hospital Billing can apply a fixed-amount discount with a reason. An authorized treating Doctor can also discount invoices for patients within their care scope. Pharmacy can discount medicine-only invoices; it cannot discount bed or mixed service invoices. The discount is an immutable negative invoice line with approving identity and timestamp. It cannot exceed the unpaid balance or produce a negative balance. Other historical credit adjustments are shown separately from explicit discounts.

Patients can use **My invoices & payments → Pay total outstanding (TEST)** to settle all outstanding invoices for their selected hospital atomically, or **Pay via portal (TEST)** for one invoice. For either option they can choose UPI, Netbanking, Card or QR, confirm the simulation and settle the full combined balance, or pay all or part of an individual invoice. No banking credentials are collected and no banking QR or real transfer is produced. The server validates ownership, supported method, confirmation and current balance. Idempotency keys and transactional locking prevent repeat payment/overpayment. Receipts and updated balances are visible to the authorized care team. Original payment reversals remain reflected in retained-payment totals.

Real online settlement remains disabled until an actual provider with server-side verification is integrated. The previous local-test payment choice remains in force.

## Annual hospital leave calendar

Open **Hospital leave** for a twelve-month calendar. Change the year, use previous/next, or select a day to see its holidays and approved employee leave. Patient accounts cannot access staff calendars. Private leave reasons are not exposed.

The chosen scope is **India national dates plus Admin-managed regional festivals**. Republic Day, Independence Day and Gandhi Jayanti repeat on their fixed dates. Fourteen 2026 festival/observance reference dates were imported from the [government 2026 calendar](https://dfe.gov.in/uploads/documents/list-of-gazetted-holidays-2026.pdf). They start as observances, not automatically approved employee leave. Their source is stored in the database; local dates and hospital policy require Admin review.

Admin can add/edit/deactivate a dated festival, choose its type, mark it as a hospital staff holiday and add policy notes. Fixed-date observances may repeat annually; February 29 appears only in leap years. Movable/lunar festival dates must be entered or verified for each year rather than copied to the same Gregorian date. Future-year regional calendars are maintained by Admin; the application does not claim an automatically complete list of every regional festival.

A holiday flag does not cancel patient appointments, remove emergency cover, or approve every employee's absence. Individual staff leave continues through the existing hospital Admin approval workflow. Historical approved leave is included when viewing its year.

## Versions and Git commits

The starting version is **1.0.0**. `VERSION` controls build version metadata; `release.json` carries the release history copied into build/publish output. The application registers this manifest in PostgreSQL at startup. Small text directly below the HospitalFlow logo shows only the compiled version in the sidebar and on login/recovery screens. Commit and source-state details remain on the Admin/Developer version-history page. **Application versions**, the detailed release-history page, is available only to Admin and Developer. Other roles are denied by both navigation and the API.

A tracked `.githooks/pre-commit` hook invokes `scripts/version_release.py`. It stages the next version and manifest in the same commit as the application changes. The minor and patch digits each range from 0 to 9:

```text
1.0.8 → 1.0.9 → 1.1.0
1.9.8 → 1.9.9 → 2.0.0
```

Each entry records its UTC release time, the source parent commit and a summary of staged changed paths. Recording the parent avoids inventing the final commit hash before Git has created it. Retrying a failed commit derives the next version from HEAD, preventing double increments. Merge/amend commits also increment when they contain staged changes. Git's standard `--no-verify` can bypass a local hook; teams should require normal commits or add CI enforcement if they need a mandatory release policy.

For another checkout, enable the hook using:

```sh
python3 scripts/install_git_hooks.py
```

The installer preserves any pre-existing custom hook configuration instead of overwriting it. Enabling the hook does not create a commit or deployment. When started with `./hospitalflow run`, the local commit supervisor automatically rebuilds and restarts after a new Git commit; the version label refreshes from the server within 15 seconds. A failed build preserves the old server. For plain `dotnet run`, debugger sessions or remote production, rebuild/restart or deploy explicitly. Uncommitted source edits do not falsely claim a new release version.

## Validation

`tests/enterprise_finance.py` exercises scoped invoice visibility, discount limits, concurrent/idempotent test payments, ownership rejection, unchanged historical medicine prices, same-date tariff revisions, leap-day calendars, holiday management and release permissions. It runs inside `tests/postgres.py` and the focused `--care-only` mode. `tests/version_release.py` creates real commits only inside a temporary Git repository to check the hook and rollover logic. Frontend tests check payment controls, calendar days and escaping.

## Patient rows and automatic refresh

The patient directory and pharmacy prescription rows show patient-specific gross charges, discounts, retained payments and outstanding balance. Patient journey, hospital history, My care and the care pathway include the detailed financial panel. Values remain scoped to the selected hospital and authorized patient; clinical staff cannot browse another hospital's bills.

The finance API catches up authorized active admissions before returning a balance, in addition to the five-minute worker. Refreshing does not duplicate daily entries. Medicine charges still post on dispensing, not when a Nurse administers an already issued dose. Bed prices must first be configured by Admin; an unconfigured rate is not an inferred free tariff.

Combined portal settlement locks the relevant billing workflow, compares the current server total with the amount the patient reviewed, and either settles every outstanding invoice or rolls back the whole transaction. A stale total requires the patient to refresh and review. Retrying the same operation key returns the same result rather than charging twice. Settlement covers currently posted charges, not future days of an ongoing stay. Payments remain simulated TEST payments until a real provider is integrated.

Build identity comes from the compiled assembly informational version (including the .NET SDK source commit) and build-time Git working-tree metadata. Startup rejects a release manifest whose version differs from the compiled version. It never reads a later live Git HEAD and presents it as the already running binary. For Docker/CI builds that exclude `.git`, supply `--build-arg SOURCE_REVISION_ID="$(git rev-parse HEAD)"` to preserve commit identity. The source-state label remains unavailable when the build cannot inspect a working tree.
