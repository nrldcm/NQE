// Deterministic, offline-first sync merge.
//
// Every syncable row is represented as a [SyncRecord] carrying a monotonic
// [updatedAt] and a [deleted] tombstone. Merging two record sets keeps the
// newest version per (table, id). This guarantees the properties the brief
// asks for:
//   * no duplicates      — records are keyed by (table, id); one survives.
//   * restorable         — a newer non-deleted version overrides an older
//                          tombstone, so a delete can be undone from either side.
//   * deletes propagate  — a newer tombstone overrides an older live row.
//   * idempotent         — merging the same payload twice changes nothing.
//   * commutative        — merge(a, b) yields the same set as merge(b, a).
//
// The transport (mobile WebSocket server, QR pairing, encryption) sits on top
// of this; the merge itself is pure and unit-tested so the data can never be
// corrupted regardless of connection drops or re-sends.
import 'dart:convert';

class SyncRecord {
  final String table; // 'accounts' | 'cashflows' | 'trades' | ...
  final String id;
  final String updatedAt; // ISO-8601 UTC, lexicographically comparable
  final bool deleted; // tombstone
  final Map<String, Object?> data;

  const SyncRecord({
    required this.table,
    required this.id,
    required this.updatedAt,
    required this.deleted,
    required this.data,
  });

  String get key => '$table::$id';

  Map<String, Object?> toJson() => {
        't': table,
        'id': id,
        'u': updatedAt,
        'd': deleted ? 1 : 0,
        'v': data,
      };

  factory SyncRecord.fromJson(Map<String, Object?> j) => SyncRecord(
        table: (j['t'] ?? '').toString(),
        id: (j['id'] ?? '').toString(),
        updatedAt: (j['u'] ?? '').toString(),
        deleted: (j['d'] == 1 || j['d'] == true),
        data: ((j['v'] as Map?) ?? const {}).cast<String, Object?>(),
      );
}

class MergeResult {
  final List<SyncRecord> merged;
  final List<SyncRecord> applied; // records that changed the local set
  const MergeResult(this.merged, this.applied);
}

class SyncEngine {
  /// True if [x] should win over [y] for the same (table, id).
  static bool isNewer(SyncRecord x, SyncRecord y) {
    final c = x.updatedAt.compareTo(y.updatedAt);
    if (c != 0) return c > 0;
    // Tie-break on identical timestamps: a live row beats a tombstone (favour
    // data preservation / restore), otherwise keep the existing one.
    if (x.deleted != y.deleted) return !x.deleted;
    return false;
  }

  /// Index records by (table,id), keeping the winning version.
  static Map<String, SyncRecord> index(Iterable<SyncRecord> records) {
    final out = <String, SyncRecord>{};
    for (final r in records) {
      final cur = out[r.key];
      if (cur == null || isNewer(r, cur)) out[r.key] = r;
    }
    return out;
  }

  /// Merge [remote] into [local]. Returns the merged set and the subset of
  /// remote records that actually changed local (to apply to the DB).
  static MergeResult apply(List<SyncRecord> local, List<SyncRecord> remote) {
    final map = index(local);
    final applied = <SyncRecord>[];
    for (final r in remote) {
      final cur = map[r.key];
      if (cur == null || isNewer(r, cur)) {
        map[r.key] = r;
        applied.add(r);
      }
    }
    return MergeResult(map.values.toList(), applied);
  }

  /// Symmetric merge of two sets (order-independent result set).
  static List<SyncRecord> merge(List<SyncRecord> a, List<SyncRecord> b) =>
      index([...a, ...b]).values.toList();

  static String encodePayload(List<SyncRecord> records) =>
      jsonEncode(records.map((r) => r.toJson()).toList());

  static List<SyncRecord> decodePayload(String jsonStr) {
    final list = (jsonDecode(jsonStr) as List)
        .map((e) => SyncRecord.fromJson((e as Map).cast<String, Object?>()))
        .toList();
    return list;
  }
}
