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

`fee_guardians/{paymentNumber}`: one or two parent or guardian `names`,
entered by the Bursar.
`student_bio/{NSIN with _ for /, or payment code}`: `dateOfBirth`,
`district`, `village`, `primarySchool`, `secondarySchool`, entered by the
Academic Registrar (**Student Bio Data**).

`.../payments/{id}`: `amount`, `method`, `reference`, `recordedBy`, `createdAt`.

## Rules

- Bursar: read, open records, change tuition, record payments.
- Principal and Deputy Principal: read only.
- Fee records, payments, guardian names and bio data are private.
- Registrar, tutors and other staff cannot list records.
- `paid` changes only together with a new payment of the same amount.
- Payments and records are never deleted or edited. Fix mistakes with a
  correction entry.

## Viewing fees

The app asks the Worker (`POST /fees`, `worker/src/fees.js`), which reads the
records with the Firebase service account.

- Signed-in student (**My fees**): payment code only. The app sends the
  session NSIN, which must match the record.
- Parents, guardians and students without an NSIN (**Use payment code** on the
  sign-in screen): payment code, parent or guardian names, and two of: date of
  birth, home district and village, student's full name, primary school,
  secondary school.
- Capitals, punctuation and word order are ignored; spelling must match.
- The reply never says which answer was wrong. Five wrong attempts lock a
  payment code until the next day (UTC; 03:00 in Uganda).

The deploy workflow copies the `FIREBASE_SERVICE_ACCOUNT` GitHub secret to the
Worker. Fee viewing works only after the Worker has been deployed from `main`.

## Plan

1. Bursar screens: list, search, filter, totals, add student, record payment,
   history. **Built.**
2. Verified fee view (see above). **Built.**
3. Principal and Deputy Principal read-only view (**Student Fees**). **Built.**
4. **Built:**
   - **Class tuition** (Bursar): one amount for every record of a programme,
     year and semester. It changes existing records only.
   - **Export CSV**: the records currently shown, saved to the phone
     (Bursar, Principal, Deputy).
   - **Clearance slip** (Bursar): a PDF to print, sign and stamp. Offered when
     the semester and all earlier recorded semesters are paid.

## Known gaps

- NSINs are public, and the signed-in route asks only for the code and the
  NSIN. Anyone holding a code who knows or guesses the NSIN can skip the
  parent questions. Closing this needs real student sign-in.
- Anyone who knows a code can use up its five attempts and lock it for the day.
- The service account key held by the Worker has broad rights over the
  Firebase project. A dedicated, database-only account would be safer.
- A wrongly typed payment number cannot be changed in the app.
- A record's name, NSIN and semester cannot be edited after saving.
- A mistyped NSIN stops the student seeing the record.
