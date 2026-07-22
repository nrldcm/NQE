import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/models.dart';
import 'package:nqe/services/auth_service.dart';
import 'package:nqe/services/crypto_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('passphrase-protected backups', () {
    final svc = CryptoService.instance;

    test('passphrase file cannot be opened without the passphrase', () async {
      final bytes =
          await svc.encryptJson({'x': 1}, passphrase: 'correct horse');
      expect(svc.isPassphraseProtected(bytes), isTrue);
      // No passphrase => rejected.
      expect(() => svc.decryptJson(bytes), throwsA(isA<CryptoException>()));
      // Wrong passphrase => rejected.
      expect(() => svc.decryptJson(bytes, passphrase: 'nope'),
          throwsA(isA<CryptoException>()));
      // Correct passphrase => works.
      final back = await svc.decryptJson(bytes, passphrase: 'correct horse');
      expect(back['x'], 1);
    });

    test('app-key (no passphrase) files still round-trip', () async {
      final bytes = await svc.encryptJson({'y': 2});
      expect(svc.isPassphraseProtected(bytes), isFalse);
      final back = await svc.decryptJson(bytes);
      expect(back['y'], 2);
    });
  });

  group('non-finite input is neutralised', () {
    test('Infinity/NaN never reach persisted maps', () {
      final t = Trade(
        id: 't', accountId: 'a', date: '2026-01-01',
        shares: double.infinity, buyPrice: double.nan, sellPrice: double.infinity,
        createdAt: 'x',
      );
      final m = t.toMap();
      expect(m['shares'], 0.0);
      expect(m['buy_price'], 0.0);
      expect(m['sell_price'], 0.0);
    });
  });

  group('PIN lockout', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('correct PIN unlocks, wrong PIN fails, lockout kicks in', () async {
      final auth = AuthService.instance;
      await auth.setPin('1234');
      expect(await auth.submitPin('1234'), isTrue);
      expect(await auth.submitPin('0000'), isFalse);

      // Exhaust attempts to trigger the lockout.
      for (var i = 0; i < 6; i++) {
        await auth.submitPin('0000');
      }
      expect(await auth.lockoutRemaining(), greaterThan(0));
      // While locked, even the correct PIN is refused.
      expect(await auth.submitPin('1234'), isFalse);
    });
  });
}
