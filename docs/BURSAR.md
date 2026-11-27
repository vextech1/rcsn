# Bursar module

Tuition is paid outside the app (bank, mobile money, cash). The Bursar records
it; the app takes no payments.

## Data

`student_fees/{paymentNumber}_Y{year}S{semester}`: `paymentNumber`, `nsin`,
`name`, `programType`, `year`, `semester`, `tuition`, `paid`, `lastPaymentId`,
`updatedBy`, `updatedAt`. Amounts are whole shillings. Balance = tuition - paid.
`fee_numbers/{paymentNumber}`: the owning `nsin`. Empty for a new student;
filled in once with **Add NSIN**.
Payment numbers: 4 to 10 letters or digits, one per student.
Status: Not paid, Balance due, Cleared (balance zero or less).

`.../payments/{id}`: `amount`, `method`, `reference`, `recordedBy`, `createdAt`.

## Rules

- Bursar: read, open records, change tuition, record payments.
- Principal and Deputy Principal: read only.
- Parents and students (no sign-in): the NSIN or the payment code opens that
  student's records and payment history. No listing, searching or writing.
  `fee_links/{NSIN with _ for /}` holds the payment code for an NSIN.
- Registrar, tutors and other staff cannot list records.
- `paid` changes only together with a new payment of the same amount.
- Payments and records are never deleted or edited. Fix mistakes with a
  correction entry.

## Plan

1. Bursar screens: list, search, filter, totals, add student, record payment,
   history. **Built.**
2. Fee view: **Parents: check fees** on the sign-in screen (NSIN or code), or
   **My fees** after sign-in. **Built.**
3. Principal read-only screen.
4. Later: bulk tuition per class, CSV export, printable clearance.

## Known gaps

- **Privacy (school decision):** NSINs are sequential and the `students`
  collection is publicly readable, so anyone with technical skill or a guessed
  NSIN can see any student's fees and payments. Revisit before real data.
- A wrongly typed payment number cannot be changed in the app.
- A record's name, NSIN and semester cannot be edited after saving.
- A mistyped NSIN stops the student seeing the record.
