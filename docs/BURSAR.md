# Bursar module

Tuition is paid outside the app (bank, mobile money, cash). The Bursar records
it; the app takes no payments.

## Data

`student_fees/{NSIN with _ for /}_Y{year}S{semester}`: `nsin`, `name`,
`programType`, `year`, `semester`, `tuition`, `paid`, `lastPaymentId`,
`updatedBy`, `updatedAt`. Amounts are whole shillings. Balance = tuition - paid.
Status: Not paid, Balance due, Cleared (balance zero or less).

`.../payments/{id}`: `amount`, `method`, `reference`, `recordedBy`, `createdAt`.

## Rules

- Bursar: read, open records, change tuition, record payments.
- Principal and Deputy Principal: read only.
- Everyone else, including Registrar, tutors and signed-out users: nothing.
- `paid` changes only together with a new payment of the same amount.
- Payments and records are never deleted or edited. Fix mistakes with a
  correction entry.

## Plan

1. Bursar screens: list, search, filter, totals, add student, record payment,
   history. **Built.**
2. Student fee view (read-only). **Needs a decision:** students enter with an
   NSIN only, which is guessable, so fees need a second secret. Proposed: the
   Bursar issues each student a fee access code.
3. Principal read-only screen.
4. Later: bulk tuition per class, CSV export, printable clearance.

## Known gaps

- A record's name, NSIN and semester cannot be edited after saving.
- Records typed before admission link by NSIN only; a mistyped NSIN will not
  match.
