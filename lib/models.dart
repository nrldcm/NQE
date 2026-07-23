// NQE — trading ledger domain models.
//
// Money is stored in each account's own currency. `fxToPhp` on an account and
// `fxRate` on individual foreign entries let the dashboard roll everything up
// into one PHP "Assets Under Management" figure.

const int kSchemaVersion = 2;

String _s(Object? v, [String def = '']) => v == null ? def : v.toString();
double _d(Object? v, [double def = 0]) {
  if (v == null) return def;
  final double? r = v is num ? v.toDouble() : double.tryParse(v.toString());
  // Reject NaN / Infinity — they poison calculations and break JSON export.
  if (r == null || !r.isFinite) return def;
  return r;
}

int _i(Object? v, [int def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

/// Guards against NaN/Infinity ever being persisted or JSON-encoded.
double _fin(double v) => v.isFinite ? v : 0.0;
double? _finN(double? v) => v == null ? null : (v.isFinite ? v : 0.0);

enum AccountKind { trading, dividend }

AccountKind kindFrom(String s) =>
    s == 'dividend' ? AccountKind.dividend : AccountKind.trading;

class Account {
  String id;
  String name;
  String broker;
  String currency;
  AccountKind kind;
  double startingCapital;
  double fxToPhp;
  int color;
  int sortOrder;
  int archived;
  String createdAt;

  Account({
    required this.id,
    required this.name,
    this.broker = '',
    this.currency = 'PHP',
    this.kind = AccountKind.trading,
    this.startingCapital = 0,
    this.fxToPhp = 1,
    this.color = 0xFF111111,
    this.sortOrder = 0,
    this.archived = 0,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'broker': broker,
        'currency': currency,
        'kind': kind == AccountKind.dividend ? 'dividend' : 'trading',
        'starting_capital': _fin(startingCapital),
        'fx_to_php': _fin(fxToPhp),
        'color': color,
        'sort_order': sortOrder,
        'archived': archived,
        'created_at': createdAt,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: _s(m['id']),
        name: _s(m['name']),
        broker: _s(m['broker']),
        currency: _s(m['currency'], 'PHP'),
        kind: kindFrom(_s(m['kind'], 'trading')),
        startingCapital: _d(m['starting_capital']),
        fxToPhp: _d(m['fx_to_php'], 1),
        color: _i(m['color'], 0xFF111111),
        sortOrder: _i(m['sort_order']),
        archived: _i(m['archived']),
        createdAt: _s(m['created_at']),
      );
}

class Cashflow {
  String id;
  String accountId;
  String date;
  String type; // 'deposit' | 'withdrawal'
  double amount;
  double fxRate;
  String remarks;
  String createdAt;

  Cashflow({
    required this.id,
    required this.accountId,
    required this.date,
    required this.type,
    this.amount = 0,
    this.fxRate = 1,
    this.remarks = '',
    required this.createdAt,
  });

  bool get isDeposit => type == 'deposit';
  double get php => amount * fxRate;

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'date': date,
        'type': type,
        'amount': _fin(amount),
        'fx_rate': _fin(fxRate),
        'remarks': remarks,
        'created_at': createdAt,
      };

  factory Cashflow.fromMap(Map<String, Object?> m) => Cashflow(
        id: _s(m['id']),
        accountId: _s(m['account_id']),
        date: _s(m['date']),
        type: _s(m['type'], 'deposit'),
        amount: _d(m['amount']),
        fxRate: _d(m['fx_rate'], 1),
        remarks: _s(m['remarks']),
        createdAt: _s(m['created_at']),
      );
}

/// A row in the Monthly Performance tracker (manually entered): the balance at
/// the start and end of a month, and the net wire-out (withdrawal +, deposit −)
/// for that month. P&L / % change / TWR / drawdown are all derived, not stored.
class PerfMonth {
  String id;
  String title; // free label, e.g. "January 2024" or "July (2nd half)"
  String currency; // 'USD' | 'EUR' | 'PHP' — this row's book currency
  int sortKey; // ordering, e.g. yyyymm*100 + slot (lower = earlier)
  double startBal;
  double endBal;
  double wireOut; // + = withdrawal (out), − = deposit (in)
  String note;
  String createdAt;

  PerfMonth({
    required this.id,
    this.title = '',
    this.currency = 'USD',
    this.sortKey = 0,
    this.startBal = 0,
    this.endBal = 0,
    this.wireOut = 0,
    this.note = '',
    required this.createdAt,
  });

  double get pnl => endBal - startBal;
  double get pctChange => startBal == 0 ? 0 : (endBal - startBal) / startBal * 100;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'currency': currency,
        'sort_key': sortKey,
        'start_bal': _fin(startBal),
        'end_bal': _fin(endBal),
        'wire_out': _fin(wireOut),
        'note': note,
        'created_at': createdAt,
      };

  factory PerfMonth.fromMap(Map<String, Object?> m) => PerfMonth(
        id: _s(m['id']),
        title: _s(m['title']),
        currency: _s(m['currency'], 'USD'),
        sortKey: (m['sort_key'] as num?)?.toInt() ?? 0,
        startBal: _d(m['start_bal']),
        endBal: _d(m['end_bal']),
        wireOut: _d(m['wire_out']),
        note: _s(m['note']),
        createdAt: _s(m['created_at']),
      );
}

class Trade {
  String id;
  String accountId;
  String date;
  String stock;
  double shares;
  double buyPrice;
  double? sellPrice;
  double fees;
  String holdingPeriod;
  String setup;
  String remarks;
  String status; // 'open' | 'closed'
  String createdAt;

  Trade({
    required this.id,
    required this.accountId,
    required this.date,
    this.stock = '',
    this.shares = 0,
    this.buyPrice = 0,
    this.sellPrice,
    this.fees = 0,
    this.holdingPeriod = '',
    this.setup = '',
    this.remarks = '',
    this.status = 'closed',
    required this.createdAt,
  });

  bool get isOpen => status == 'open' || sellPrice == null;

  /// Realised profit/loss in account currency (0 while the position is open).
  double get pnl {
    final sp = sellPrice;
    if (sp == null) return 0;
    return (sp - buyPrice) * shares - fees;
  }

  double get costBasis => buyPrice * shares + fees;

  double get pnlPct {
    final cb = costBasis;
    if (cb == 0) return 0;
    return pnl / cb;
  }

  bool get isWin => !isOpen && pnl > 0;
  bool get isLoss => !isOpen && pnl < 0;

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'date': date,
        'stock': stock,
        'shares': _fin(shares),
        'buy_price': _fin(buyPrice),
        'sell_price': _finN(sellPrice),
        'fees': _fin(fees),
        'holding_period': holdingPeriod,
        'setup': setup,
        'remarks': remarks,
        'status': status,
        'created_at': createdAt,
      };

  factory Trade.fromMap(Map<String, Object?> m) => Trade(
        id: _s(m['id']),
        accountId: _s(m['account_id']),
        date: _s(m['date']),
        stock: _s(m['stock']),
        shares: _d(m['shares']),
        buyPrice: _d(m['buy_price']),
        sellPrice: m['sell_price'] == null ? null : _d(m['sell_price']),
        fees: _d(m['fees']),
        holdingPeriod: _s(m['holding_period']),
        setup: _s(m['setup']),
        remarks: _s(m['remarks']),
        status: _s(m['status'], 'closed'),
        createdAt: _s(m['created_at']),
      );
}

class Dividend {
  String id;
  String accountId;
  String date;
  String stock;
  double shares;
  double divRate;
  double netAmount;
  String remarks;
  String createdAt;

  Dividend({
    required this.id,
    required this.accountId,
    required this.date,
    this.stock = '',
    this.shares = 0,
    this.divRate = 0,
    this.netAmount = 0,
    this.remarks = '',
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'date': date,
        'stock': stock,
        'shares': _fin(shares),
        'div_rate': _fin(divRate),
        'net_amount': _fin(netAmount),
        'remarks': remarks,
        'created_at': createdAt,
      };

  factory Dividend.fromMap(Map<String, Object?> m) => Dividend(
        id: _s(m['id']),
        accountId: _s(m['account_id']),
        date: _s(m['date']),
        stock: _s(m['stock']),
        shares: _d(m['shares']),
        divRate: _d(m['div_rate']),
        netAmount: _d(m['net_amount']),
        remarks: _s(m['remarks']),
        createdAt: _s(m['created_at']),
      );
}

class Holding {
  String id;
  String accountId;
  String stock;
  double goalShares;
  double currentShares;
  double avgPrice;
  String createdAt;

  Holding({
    required this.id,
    required this.accountId,
    this.stock = '',
    this.goalShares = 0,
    this.currentShares = 0,
    this.avgPrice = 0,
    required this.createdAt,
  });

  double get progress => goalShares <= 0 ? 0 : (currentShares / goalShares).clamp(0, 1);

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'stock': stock,
        'goal_shares': _fin(goalShares),
        'current_shares': _fin(currentShares),
        'avg_price': _fin(avgPrice),
        'created_at': createdAt,
      };

  factory Holding.fromMap(Map<String, Object?> m) => Holding(
        id: _s(m['id']),
        accountId: _s(m['account_id']),
        stock: _s(m['stock']),
        goalShares: _d(m['goal_shares']),
        currentShares: _d(m['current_shares']),
        avgPrice: _d(m['avg_price']),
        createdAt: _s(m['created_at']),
      );
}

/// A stored third-party integration credential. The secret itself is kept
/// encrypted ([secretEnc]); only a short [hint] (last few chars) is ever shown.
/// Deliberately NOT part of the ledger backup — integration keys stay on-device.
class ApiKey {
  String id;
  String label; // user-facing name, e.g. "TradingView"
  String service; // category, e.g. "tradingview" | "data" | "broker"
  String secretEnc; // base64 AES-GCM ciphertext of the secret
  String hint; // last 4 chars, for masked display
  String createdAt;

  ApiKey({
    required this.id,
    required this.label,
    this.service = '',
    required this.secretEnc,
    this.hint = '',
    required this.createdAt,
  });

  String get masked => '••••••${hint.isEmpty ? '' : ' $hint'}';

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'service': service,
        'secret_enc': secretEnc,
        'hint': hint,
        'created_at': createdAt,
      };

  factory ApiKey.fromMap(Map<String, Object?> m) => ApiKey(
        id: _s(m['id']),
        label: _s(m['label']),
        service: _s(m['service']),
        secretEnc: _s(m['secret_enc']),
        hint: _s(m['hint']),
        createdAt: _s(m['created_at']),
      );
}

/// Full database image used for encrypted export / import.
class LedgerSnapshot {
  final int schema;
  final String exportedAt;
  final List<Account> accounts;
  final List<Cashflow> cashflows;
  final List<Trade> trades;
  final List<Dividend> dividends;
  final List<Holding> holdings;

  LedgerSnapshot({
    required this.schema,
    required this.exportedAt,
    required this.accounts,
    required this.cashflows,
    required this.trades,
    required this.dividends,
    required this.holdings,
  });

  Map<String, Object?> toJson() => {
        'schema': schema,
        'exportedAt': exportedAt,
        'accounts': accounts.map((e) => e.toMap()).toList(),
        'cashflows': cashflows.map((e) => e.toMap()).toList(),
        'trades': trades.map((e) => e.toMap()).toList(),
        'dividends': dividends.map((e) => e.toMap()).toList(),
        'holdings': holdings.map((e) => e.toMap()).toList(),
      };

  factory LedgerSnapshot.fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> arr(String k) {
      final v = j[k];
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();
    }
    return LedgerSnapshot(
      schema: _i(j['schema'], kSchemaVersion),
      exportedAt: _s(j['exportedAt']),
      accounts: arr('accounts').map(Account.fromMap).toList(),
      cashflows: arr('cashflows').map(Cashflow.fromMap).toList(),
      trades: arr('trades').map(Trade.fromMap).toList(),
      dividends: arr('dividends').map(Dividend.fromMap).toList(),
      holdings: arr('holdings').map(Holding.fromMap).toList(),
    );
  }
}
