# Bursar module

Tuition is paid outside the app (bank, mobile money, cash). The Bursar records
it; the app takes no payments.

## Data

`student_fees/{paymentNumber}_Y{year}S{semester}`: `paymentNumber`, `nsin`,
`name`, `programType`, `year`, `semester`, `tuition`, `paid`, `lastPaymentId`,
`updatedBy`, `updatedAt`. Amounts are whole shillings. Balance = tuition - paid.
`fee_numbers/{paymentNumber}`: the owning `nsin`. Empty for a new student;
filled in once with **Add student number**.
Payment numbers: 4 to 10 letters or digits, one per student.
Status: Not paid, Balance due, Cleared (balance zero or less).

`fee_guardians/{paymentNumber}`: one or two parent or guardian `names`,
entered by the Bursar.
`student_bio/{student number key, or payment code}`: `dateOfBirth`,
`district`, `village`, `primarySchool`, `secondarySchool`, entered by the
Academic Registrar (**Students**, then a student's menu, **Bio data**; for a student with no
number yet, search the payment code).

`.../payments/{id}`: `amount`, `method`, `reference`, `recordedBy`, `createdAt`.

## Rules

- Bursar: read, open records, change tuition, record payments.
- Principal and Deputy Principal: read only.
- Fee records, payments, guardian names and bio data are private.
- Registrar, tutors and other staff cannot list records.
- `paid` changes only together with a new payment of the same amount.
- Payments and records are never deleted or edited. Fix mistakes with a
  correction entry.

## Student numbers

The Academic Registrar sets one to five formats under **Student Number
Format** (`settings/studentNumber`): `#` digit, `@` letter, `*` either, all
else literal. The app checks sign-in, admission and the Bursar's entries
against them. With none set, any 3 to 30 character number of letters, digits,
`/`, `.` or `-` is accepted. The rules enforce only that basic shape, so the
format is not a security control. The database field is still named `nsin`.
`student_bio` ids replace `/` with `_`; numbers without `/` are prefixed `N_`.

## Viewing fees

The app asks the Worker (`POST /fees`, `worker/src/fees.js`), which reads the
records with the Firebase service account.

- Signed-in student (**My fees**): payment code only. The app sends the
  session student number, which must match the record.
- Parents, guardians and students without a student number (**Use payment code** on the
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

- student numbers are public, and the signed-in route asks only for the code and the
  student number. Anyone holding a code who knows or guesses the student number can skip the
  parent questions. Closing this needs real student sign-in.
- Anyone who knows a code can use up its five attempts and lock it for the day.
- The service account key held by the Worker has broad rights over the
  Firebase project. A dedicated, database-only account would be safer.
- A wrongly typed payment number cannot be changed in the app.
- A record's name, student number and semester cannot be edited after saving.
- A mistyped student number stops the student seeing the record.
