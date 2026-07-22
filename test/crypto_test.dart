import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/services/crypto_service.dart';

void main() {
  final svc = CryptoService.instance;

  test('encrypt → decrypt round-trips JSON', () async {
    final data = {
      'schema': 1,
      'accounts': [
        {'id': 'a1', 'name': 'NQE', 'starting_capital': 45500.0},
      ],
      'note': 'unicode ✓ ₱ €',
    };
    final bytes = await svc.encryptJson(data);
    expect(bytes.length, greaterThan(20));

    final back = await svc.decryptJson(bytes);
    expect(back['schema'], 1);
    expect(back['note'], 'unicode ✓ ₱ €');
    expect((back['accounts'] as List).length, 1);
  });

  test('corrupted ciphertext is rejected (integrity check)', () async {
    final bytes = await svc.encryptJson({'x': 1});
    final tampered = Uint8List.fromList(bytes);
    // Flip a byte deep in the ciphertext body.
    tampered[tampered.length - 1] ^= 0xFF;
    expect(() => svc.decryptJson(tampered), throwsA(isA<CryptoException>()));
  });

  test('non-NQE file is rejected by header check', () async {
    final junk = Uint8List.fromList(List<int>.filled(64, 7));
    expect(() => svc.decryptJson(junk), throwsA(isA<CryptoException>()));
  });
}
