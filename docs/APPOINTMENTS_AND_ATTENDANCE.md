# Appointments, booking payments and staff attendance

Patients use **My appointments → Book appointment**. Admin, Developer, Doctor and reception staff use **Appointments → Book appointment**, selecting the registered patient first. The booking wizard lists active doctors at the selected hospital, their departments and registration IDs, a date, available 10-minute slots in IST, visit type and payment method.

- Each new booking or reschedule must start at least two hours ahead, within the doctor's shift and configured sessions. Dates are available up to 90 days ahead.
- Booked slots, active payment holds, approved leave and marked absence are unavailable. PostgreSQL serialises competing mutations and checks availability again on submission. No other patient's identity is returned by the slots endpoint.
- Selecting a slot reserves it for up to ten minutes (or until the two-hour booking cutoff, whichever is earlier). It remains **Pending** until payment confirmation. An expired hold cannot confirm or block availability. The original hold is retained as expired history.
- Each hospital starts at ₹200. Admin/Developer can set a fee between ₹200 and ₹750 from **Attendance & leave → Configure booking fee**. Changing a fee does not alter an existing reservation's quoted amount.
- Patients choose UPI, Netbanking, Card or QR. Staff bookings offer Cash or QR. The application never asks for a card number, PIN, CVV or UPI PIN.

## Local payment mode

The user selected local test payments. `Payments:Mode=Test` is enabled in Development only. Online payment methods simulate confirmation and refunds, visibly marked **TEST**, without moving money or displaying a real banking QR. Production always disables these simulated methods; a real provider integration is required before accepting real online payments. Setting a configuration string alone does not install a provider.

Cash is a real operational receipt and requires an authorised staff member to explicitly confirm that cash was received. Patient accounts cannot confirm cash. Confirmed bookings appear in the doctor appointment row with payment state, amount, method and test-mode label. Unpaid holds and outstanding cash refunds appear below the queue with patient identity.

## Rescheduling and cancellation

A patient can change their own future Scheduled appointment. Authorised booking staff can change registered appointments in their selected hospital. Rescheduling keeps the appointment ID and original fee/payment; the old slot is released only after the new slot passes all database checks in one transaction. In-progress, completed and past visits cannot be rescheduled through this flow.

Cancellation retains the appointment row, payment record, audit history and refund evidence. The current policy permits cancelling a future Scheduled appointment with a full refund; the two-hour restriction applies to booking and the new reschedule slot. Test payments refund to the original **test** source without real money movement. Cash enters **Refund pending** until Admin/Developer explicitly confirms the cash was returned. The original staff cancellation command also creates refund tracking, preventing a bypass through the older status endpoint. No online refund is claimed as real.

Older appointments without booking-payment records show **Not recorded**, preserving their existing billing history.

## Attendance and leave

Every non-patient account has **Attendance & leave**. Staff can submit their own Present/Absent attendance and check out for the current day, see their own history, apply for leave and cancel their own pending/approved leave. Attendance submissions start **Pending** and require approval by an active Admin/Developer explicitly assigned to that same hospital. Administrators may approve their own attendance and use Manage employee attendance to enter or correct attendance for staff assigned to their hospital, with a recorded reason. They can approve or reject requests in their hospital and approve/reject leave. Administrators cannot approve their own leave; another administrator is required. Overlapping pending/approved leave applications are rejected. Patient accounts cannot use these actions, including by calling the API directly.

Approved leave and administrator-approved doctor absence block new slots. Pending or rejected absence requests do not change patient availability. Existing appointments remain visible, with a warning on **My appointments** and the patient's overview, so the patient can reschedule or cancel. A doctor's login must be linked to their provider through the person profile created by typed Doctor registration. Unknown attendance is not treated as absence. Existing provider-calendar absences also affect availability.

Patient appointment/overview and staff appointment/attendance screens refresh availability every 30 seconds when the page is visible and no modal is open. Manual Refresh is also available. No external email or SMS absence notification is claimed.

## Storage and verification

Migration `016_booking_and_attendance.sql` adds hospital booking settings, payment holds/booking records, append-only booking-event evidence, staff attendance and leave. Mutations pass through authenticated hospital-scoped database commands, with row history and activity logging. Existing migration checksums remain unchanged.

`tests/booking.py`, run by `tests/postgres.py`, verifies slot boundaries, holds/concurrency, payment retries, price bounds, patient and hospital isolation, rescheduling, leave warnings, refunds and expiry in disposable databases. Live clinical records are not used as test fixtures.

## Hospital and department selection

The booking wizard starts with **Hospital network → Department → Consulting doctor**. Doctor choices follow the selected department, and available slots follow the selected doctor. A different hospital requires **Continue at selected hospital** before choosing the appointment; this reloads its providers and fee.

Patients can register their existing patient identity at an active network hospital from this workflow. This grants access only to their own records, retains the same patient ID and keeps earlier hospital history. An explicitly revoked hospital membership cannot be restored through self-booking. Staff can switch only to hospitals already assigned to them. Rescheduling keeps the original hospital and payment; use a new booking or referral for another hospital.

Doctors can directly book only providers in their registered hospital department. Admin and Developer retain access to all departments in their authorised hospitals. The database applies this rule to reservations, legacy appointment inserts and rescheduling, so changing the browser request cannot bypass it. Only administration can change an existing doctor's registered department; profiles with no trusted department cannot book as a doctor until configured.

**Referrals** independently offers a receiving hospital, department and doctor. It supports another doctor at the same hospital as well as other network hospitals. Same-hospital referrals require a receiving doctor; referring a patient to the referring doctor's own provider identity is rejected. Referral acceptance retains original records and does not create or charge an appointment automatically.

## Attendance approval details

Migration `018_attendance_approval.sql` adds Pending/Approved/Rejected state, reviewer identity, review timestamp, reason and submission timestamp. **Overview** links assigned administrators to pending attendance approvals. **Attendance & leave** shows an administrator's pending review count, Approve/Reject controls and each staff member's own outcomes. Rejection requires a reason of 5–500 characters. Staff can correct rejected attendance by resubmitting for today. Checkout after an approval clears the old decision and returns the updated attendance to Pending. Repeating an unchanged submission does not create duplicate attendance or erase a review.

An administrator may approve their own attendance and employee attendance within their assigned hospital. A global network operator without an explicit active membership at the selected hospital cannot review that hospital's attendance. Patient accounts cannot submit or review attendance. Hospital ownership and reviewer permissions are checked on every request; legacy private SQL implementations are not executable by the runtime login. Attendance changes and reviews retain row-history and activity records.

Earlier attendance records are preserved under the previous policy and are labelled **Recorded before approval workflow**, with no invented reviewer. A new submission of such a record for today sends it for review. Tests in `tests/attendance_approval.py` cover approval, ownership, checkout reapproval, rejection/resubmission, hospital boundaries and the private legacy API restriction.

## Daily attendance hours and administrator management

Migration `019_attendance_hours_and_admin_review.sql` allows hospital administrators to approve their own attendance. **Manage employee attendance** lets an assigned administrator record or correct Present/Absent attendance, date and check-in/out times for an employee of the same hospital. A 5–500-character reason is required, the result is approved under that administrator's identity, and changes are audited. Invalid time order, future times, patient accounts and employees outside the hospital are rejected. Ordinary staff retain their self-service request flow.

Each daily row shows **Total hours** as hours, minutes and seconds, with decimal hours and the approval state. PostgreSQL derives completed `total_seconds` from check-in/out, restricted to the row's IST calendar date. Absent records count zero. An unfinished check-in has no final total; its server-calculated elapsed time appears as **In progress**, refreshed with the page every 30 seconds. Elapsed time cannot exceed the recorded calendar day. These are attendance durations; no break deductions, overtime or payroll rules are assumed. Administrator-entered start and end times must belong to the selected IST date; overnight work should be recorded under the corresponding calendar dates.

## Shared hospital leave calendar

All non-patient accounts have a **Hospital leave** page for the selected authorised hospital. It lists current and upcoming **approved** leave: employee name and registration ID, role/department, start date, inclusive end date, current/upcoming status and days remaining including today. Availability and remaining days are computed using the hospital's IST date. The page refreshes every 30 seconds while visible, and approvals/cancellations refresh it immediately through the normal save flow.

The shared calendar does not return private reasons, pending/rejected/cancelled applications, patient identities or contact details. Applicants and authorised admins keep their existing private application view under **Attendance & leave**. Inactive staff and revoked memberships do not appear in the public staff roster. Earlier leave records remain in the database; cancelling an approved leave removes it from shared availability without deleting its history.

Migration `020_hospital_leave_calendar.sql` exposes a narrowly scoped staff-only database function. `/api/leave/calendar` requires authentication, rejects patients at the database boundary and uses the selected hospital scope. `tests/leave_calendar.py` verifies staff access, date calculations, reason privacy, patient exclusion, hospital boundaries and cancellation behaviour in an isolated database.
