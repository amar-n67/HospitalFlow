# Linked fictional workflow test data

Populated **20 October 2026 (IST)** in **HospitalFlow (H-0001)** using the existing five Doctors, five Nurses, five Patients and five Volunteers. No additional people were created and no passwords, DOBs or activation states were changed. See [people and login details](DEMO_PEOPLE.md).

Every clinical instruction, note, referral and attendance example is synthetic. No real treatment, medicine administration, money transfer or external notification was performed. Online booking payments use **Test** mode; invoice cash receipts are fictional bookkeeping examples.

| Workspace | Examples |
|---|---|
| Appointments | 5 completed history visits on 19 October; 5 paid TEST follow-up bookings on 23 October |
| Clinical workspace | 10 visit-linked prescriptions, doctor/nursing notes, 5 clinical orders and 5 follow-up plans |
| Pharmacy | 7 dispensed prescriptions and 3 pending prescriptions, with inventory movements and linked medicine invoices |
| Nursing | 5 timestamped medication administration records, admission records and nursing notes |
| Admissions / beds | 3 active admissions, 2 discharged admissions, retained assignment/event history |
| Billing | 7 pharmacy invoices and 5 service invoices, including paid, partially paid and unpaid examples |
| Patient My care | Each patient's own prescription, invoice, admission and nursing history |
| Referrals | 5 pending same-hospital specialist referrals, each to the next Doctor in the list |
| Work assignments | 30 tasks for the 5 Nurses and 5 Volunteers: Assigned, In progress and Completed |
| Attendance | 45 approved historical attendance entries (17–19 October, 8 hours/day), plus 15 pending check-ins on 20 October |
| Leave | 15 requests for 23–24 October: 3 approved, 3 rejected and 9 pending |
| Hospital leave calendar | Approved leave for Doctor 1, Nurse 1 and Volunteer 1 |

Doctor 1 has an existing booking during approved leave on 23 October, allowing the patient-facing doctor-unavailability warning to be tested. Pending attendance can be reviewed by the hospital Admin. Historical visits intentionally have no fabricated booking-payment history; future bookings have TEST payment evidence.

## Patient workflow references

| Patient | Assigned Doctor / Nurse | History visit | Future appointment | Admission | Dispensed prescription | Second prescription | Main pharmacy invoice | Service invoice |
|---|---|---|---|---|---|---|---|---|
| Aarush Malhotra · P-001095 | Kavya Menon / Anjali Nair | APT-10161 | APT-10173 | ADM-10172 (discharged) | RX-10162 | RX-10163 (dispensed) | INV-10166 | INV-10169 |
| Diya Chatterjee · P-001097 | Arjun Sethi / Rohit Verma | APT-10180 | APT-10192 | ADM-10191 (discharged) | RX-10181 | RX-10182 (dispensed) | INV-10185 | INV-10188 |
| Vivaan Shah · P-001099 | Meera Kulkarni / Pooja Bansal | APT-10199 | APT-10211 | ADM-10210 (active) | RX-10200 | RX-10201 (pending) | INV-10204 | INV-10207 |
| Ishita Rao · P-001101 | Nikhil Raman / Kiran Joseph | APT-10212 | APT-10224 | ADM-10223 (active) | RX-10213 | RX-10214 (pending) | INV-10217 | INV-10220 |
| Kabir Deshmukh · P-001103 | Sana Mirza / Neha Sinha | APT-10225 | APT-10236 | ADM-10235 (active) | RX-10226 | RX-10227 (pending) | INV-10230 | INV-10233 |

Refresh the application to reload the database records. Start with People & registrations, then Appointments, Clinical workspace, Nursing workspace, Pharmacy, Billing, Attendance & leave, and Work assignments. Role permissions remain enforced. The maintenance seed records a completion marker and refuses to add duplicate scenarios on repeat runs.
