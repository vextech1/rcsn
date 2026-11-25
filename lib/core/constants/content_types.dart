/// Default content-type categories, seeded on first Admin setup so the app
/// is usable from day one.
///
/// Deliberately NOT an enum. Section 4.3 of the project document specifies
/// content types are Admin-extensible — Admin can create new categories at
/// runtime through a management screen. An enum would make that impossible
/// without a code change and app update. These four ship as real Firestore
/// documents on first run; from then on, the live list in Firestore is the
/// source of truth, not this constant.
const List<String> kSeededContentTypes = [
  'Timetable',
  'Revision Notes',
  'Past Papers',
  'Announcements',
];
