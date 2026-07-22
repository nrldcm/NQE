import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/models.dart';
import 'package:nqe/services/crypto_service.dart';

void main() {
  test('LedgerSnapshot JSON round-trips through encryption', () async {
    final snap = LedgerSnapshot(
      schema: kSchemaVersion,
      exportedAt: '2026-07-22T00:00:00.000Z',
      accounts: [
        Account(id: 'a1', name: 'NQE Growth', broker: 'InvestaTrade',
            currency: 'PHP', startingCapital: 45500, createdAt: 'x'),
      ],
      cashflows: [
        Cashflow(id: 'c1', accountId: 'a1', date: '2026-05-14',
            type: 'deposit', amount: 45500, fxRate: 1, createdAt: 'x'),
      ],
      trades: [
        Trade(id: 't1', accountId: 'a1', date: '2026-06-01', stock: 'SPC',
            shares: 42000, buyPrice: 10.73, sellPrice: 10.5, status: 'closed',
            createdAt: 'x'),
      ],
      dividends: const [],
      holdings: const [],
    );

    final bytes = await CryptoService.instance.encryptJson(snap.toJson());
    final json = await CryptoService.instance.decryptJson(bytes);
    final restored = LedgerSnapshot.fromJson(json);

    expect(restored.accounts.length, 1);
    expect(restored.accounts.first.name, 'NQE Growth');
    expect(restored.trades.length, 1);
    expect(restored.trades.first.stock, 'SPC');
    expect(restored.cashflows.first.amount, 45500);
  });
}
