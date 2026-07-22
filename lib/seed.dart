// First-run seed: pre-creates the three books from the original spreadsheets so
// the app opens with something meaningful instead of a blank screen.
import 'db/database.dart';
import 'models.dart';

String _uid() =>
    '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object()) & 0xffff}';

Future<void> seedIfEmpty() async {
  final db = LedgerDb.instance;
  if (!await db.isEmpty()) return;

  final now = DateTime.now().toIso8601String();
  final books = <Account>[
    Account(
      id: _uid(),
      name: 'NQE Growth Fund',
      broker: 'InvestaTrade',
      currency: 'PHP',
      kind: AccountKind.trading,
      startingCapital: 45500,
      fxToPhp: 1,
      color: 0xFF111111,
      sortOrder: 0,
      createdAt: now,
    ),
    Account(
      id: _uid(),
      name: 'Willong Capital',
      broker: 'DragonFi',
      currency: 'PHP',
      kind: AccountKind.trading,
      startingCapital: 139138,
      fxToPhp: 1,
      color: 0xFF1F6FEB,
      sortOrder: 1,
      createdAt: now,
    ),
    Account(
      id: _uid(),
      name: 'NQE Div Fund',
      broker: 'SBANKEN',
      currency: 'EUR',
      kind: AccountKind.dividend,
      startingCapital: 0,
      fxToPhp: 69.64,
      color: 0xFF2EA043,
      sortOrder: 2,
      createdAt: now,
    ),
  ];
  for (final a in books) {
    await db.upsertAccount(a);
  }
}
