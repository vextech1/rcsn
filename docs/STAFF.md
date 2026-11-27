# Staff positions

Tapping **Staff** on the role screen opens a list of positions. The person picks theirs, then signs in with the email and password the Principal or Deputy Principal created for them.

## The list

- **Built in:** Principal, Deputy Principal, Registrar, Bursar.
- **Custom:** anything the Principal or Deputy Principal adds (Askari, Accountant, Clinical Instructor, ...). On the Staff management screen, tap the list icon at the top. Stored in `staff_positions`.
- **Every position stays on the list**, Principal and Deputy Principal included. Only the account that really holds a position can sign in under it, so showing the option to everyone is harmless.

Picking a position grants nothing. Accounts are still created by the Principal or Deputy Principal (Staff > Add staff, choose a position). Sign-in is rejected if the account is not in the position that was picked.

## Who can do what

| | Principal | Deputy Principal | Registrar / Bursar | Custom position |
|---|---|---|---|---|
| Add Registrar, Bursar, custom staff | yes | yes | no | no |
| Add the Deputy Principal | yes | no | no | no |
| Suspend / reactivate staff | yes | yes (not Principal or Deputy) | no | no |
| Terminate the Deputy Principal | yes | no | no | no |
| Add / remove positions | yes | yes | no | no |
| Announcements, moderation, academic screens | yes | yes | as before | no (read-only) |

- Terminating a Deputy is one-way. Appoint a new Deputy with a new account.
- There is one active Deputy Principal at a time (checked in the app when adding one). After a termination the Principal can appoint a new Deputy.
- Custom positions land on a simple home screen with the Public Space. Per-position powers come later.

## Deploying

Firestore rules deploy automatically from `main` after CI passes (`deploy-firebase.yml`).
