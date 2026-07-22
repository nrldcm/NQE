import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/sync/sync_engine.dart';

SyncRecord rec(String id, String updated,
        {bool deleted = false, String table = 'trades', Object? val}) =>
    SyncRecord(
      table: table,
      id: id,
      updatedAt: updated,
      deleted: deleted,
      data: {'v': val ?? id},
    );

void main() {
  group('SyncEngine merge', () {
    test('new remote record is added (no duplicates by id)', () {
      final local = [rec('a', '2026-01-01')];
      final remote = [rec('b', '2026-01-02')];
      final r = SyncEngine.apply(local, remote);
      expect(r.merged.length, 2);
      expect(r.applied.map((e) => e.id), ['b']);
    });

    test('newer update wins (last-write-wins)', () {
      final local = [rec('a', '2026-01-01', val: 'old')];
      final remote = [rec('a', '2026-02-01', val: 'new')];
      final r = SyncEngine.apply(local, remote);
      expect(r.merged.length, 1);
      expect(r.merged.single.data['v'], 'new');
      expect(r.applied.length, 1);
    });

    test('older remote update is ignored', () {
      final local = [rec('a', '2026-02-01', val: 'new')];
      final remote = [rec('a', '2026-01-01', val: 'old')];
      final r = SyncEngine.apply(local, remote);
      expect(r.merged.single.data['v'], 'new');
      expect(r.applied, isEmpty);
    });

    test('delete tombstone propagates', () {
      final local = [rec('a', '2026-01-01')];
      final remote = [rec('a', '2026-02-01', deleted: true)];
      final r = SyncEngine.apply(local, remote);
      expect(r.merged.single.deleted, isTrue);
    });

    test('restore: newer live record overrides older tombstone', () {
      final local = [rec('a', '2026-01-01', deleted: true)];
      final remote = [rec('a', '2026-02-01', deleted: false, val: 'back')];
      final r = SyncEngine.apply(local, remote);
      expect(r.merged.single.deleted, isFalse);
      expect(r.merged.single.data['v'], 'back');
    });

    test('idempotent: applying the same payload twice changes nothing', () {
      final local = [rec('a', '2026-01-01')];
      final remote = [rec('a', '2026-02-01', val: 'x'), rec('b', '2026-02-01')];
      final first = SyncEngine.apply(local, remote);
      final second = SyncEngine.apply(first.merged, remote);
      expect(second.applied, isEmpty);
      expect(second.merged.length, first.merged.length);
    });

    test('commutative: merge(a,b) has the same winning set as merge(b,a)', () {
      final a = [rec('x', '2026-01-01', val: '1'), rec('y', '2026-03-01')];
      final b = [rec('x', '2026-02-01', val: '2'), rec('z', '2026-01-01')];
      final ab = SyncEngine.merge(a, b);
      final ba = SyncEngine.merge(b, a);
      Map<String, String> winners(List<SyncRecord> rs) => {
            for (final r in rs) r.key: '${r.updatedAt}:${r.data['v']}'
          };
      expect(winners(ab), winners(ba));
      // x resolves to the 2026-02-01 version on both sides.
      expect(ab.firstWhere((r) => r.id == 'x').data['v'], '2');
    });

    test('tie on timestamp: live row beats tombstone (favours restore)', () {
      final a = [rec('a', '2026-01-01', deleted: true)];
      final b = [rec('a', '2026-01-01', deleted: false, val: 'kept')];
      final merged = SyncEngine.merge(a, b);
      expect(merged.single.deleted, isFalse);
      expect(merged.single.data['v'], 'kept');
    });

    test('payload encode/decode round-trips', () {
      final recs = [
        rec('a', '2026-01-01', table: 'accounts', val: 'NQE'),
        rec('b', '2026-02-01', deleted: true, table: 'trades'),
      ];
      final json = SyncEngine.encodePayload(recs);
      final back = SyncEngine.decodePayload(json);
      expect(back.length, 2);
      expect(back[0].table, 'accounts');
      expect(back[1].deleted, isTrue);
    });
  });
}
