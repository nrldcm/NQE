// The Sandbox order ticket: pick spot/margin, buy/sell, order type
// (Market / Limit / Stop / Take-profit), quantity and leverage, with a live
// read-out of last price, buying power, estimated cost/collateral, fee and
// (for margin) the resulting liquidation price. Submits through [simState].
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../util.dart';
import '../sim_engine.dart';
import '../sim_market.dart';
import '../sim_models.dart';
import '../sim_state.dart';
import 'sandbox_common.dart';

class SandboxTradeTicket extends StatefulWidget {
  final String symbol;

  /// When shown as a bottom sheet, pop after a successful order.
  final bool popOnSuccess;
  const SandboxTradeTicket(
      {super.key, required this.symbol, this.popOnSuccess = false});

  @override
  State<SandboxTradeTicket> createState() => _SandboxTradeTicketState();
}

class _SandboxTradeTicketState extends State<SandboxTradeTicket> {
  TradeMode _mode = TradeMode.spot;
  OrderSide _side = OrderSide.buy;
  OrderType _type = OrderType.market;
  double _leverage = 2;
  bool _submitting = false;

  final _qtyCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  final _stopCtrl = TextEditingController();

  SimSymbol get _inst =>
      instrumentFor(widget.symbol) ??
      SimSymbol(widget.symbol, widget.symbol, SimMarket.crypto,
          seedPriceFor(widget.symbol));
  SimMarket get _market => _inst.market;

  double get _last => simState.priceOf(widget.symbol);
  double get _qty => double.tryParse(_qtyCtrl.text.trim()) ?? 0;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _limitCtrl.dispose();
    _stopCtrl.dispose();
    super.dispose();
  }

  double get _lev => _mode == TradeMode.margin ? _leverage : 1.0;

  /// FX multiplier from the instrument's quote currency to the account base.
  double get _fx => simState.fxOf(widget.symbol);

  double get _buyingPower {
    final cash = simState.freeCash; // base currency
    return _mode == TradeMode.margin ? cash * _leverage : cash;
  }

  double _maxQty(double price) {
    if (price <= 0) return 0;
    final fee = SimEngine.feeRate(_market);
    final pxBase = price * _fx; // price in the account base currency
    if (pxBase <= 0) return 0;
    if (_mode == TradeMode.spot) {
      return simState.freeCash / (pxBase * (1 + fee));
    }
    return simState.freeCash / (pxBase / _leverage + pxBase * fee);
  }

  void _setQtyPct(double pct) {
    final price = _refPrice;
    final max = _maxQty(price);
    final q = max * pct;
    _qtyCtrl.text = _market == SimMarket.crypto
        ? q.toStringAsFixed(4)
        : q.floor().toString();
    setState(() {});
  }

  double get _refPrice {
    if (_type == OrderType.limit) {
      return double.tryParse(_limitCtrl.text.trim()) ?? _last;
    }
    if (_type == OrderType.stop || _type == OrderType.takeProfit) {
      return double.tryParse(_stopCtrl.text.trim()) ?? _last;
    }
    return _last;
  }

  double? get _liqPreview {
    if (_mode != TradeMode.margin || _leverage <= 1) return null;
    final entry = _refPrice;
    final f = 1 / _leverage;
    return _side == OrderSide.buy ? entry * (1 - f) : entry * (1 + f);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final qty = _qty;
    if (!(qty > 0)) {
      _toast('Enter a quantity.', error: true);
      return;
    }
    double? limit;
    double? stop;
    if (_type == OrderType.limit) {
      limit = double.tryParse(_limitCtrl.text.trim());
      if (limit == null || limit <= 0) {
        _toast('Enter a valid limit price.', error: true);
        return;
      }
    }
    if (_type == OrderType.stop || _type == OrderType.takeProfit) {
      stop = double.tryParse(_stopCtrl.text.trim());
      if (stop == null || stop <= 0) {
        _toast('Enter a valid trigger price.', error: true);
        return;
      }
    }

    final order = SimOrder(
      id: uid(),
      accountId: simState.account?.id ?? 'acc',
      symbol: widget.symbol,
      market: _market,
      mode: _mode,
      side: _side,
      type: _type,
      qty: qty,
      leverage: _lev,
      limitPrice: limit,
      stopPrice: stop,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() => _submitting = true);
    final reject = await simState.placeOrder(order);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (reject != null) {
      _toast(reject, error: true);
      return;
    }
    HapticFeedback.mediumImpact();
    final verb = _type == OrderType.market ? 'submitted' : 'placed';
    _toast('${_side == OrderSide.buy ? 'Buy' : 'Sell'} order $verb.');
    _qtyCtrl.clear();
    if (widget.popOnSuccess && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? NqeColors.loss : null,
      duration: const Duration(milliseconds: 1600),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simState,
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final pal = context.nqe;
    final buy = _side == OrderSide.buy;
    final accent = buy ? NqeColors.gain : NqeColors.loss;
    final cur = simState.currency;
    final fx = _fx;
    final price = _refPrice;
    final notional = _qty * (price > 0 ? price : _last); // native quote ccy
    final feeBase = notional * SimEngine.feeRate(_market) * fx;
    final costBase =
        (_mode == TradeMode.margin ? notional / _lev : notional) * fx + feeBase;

    return SimCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              MarketBadge(_market, dense: true),
              const SizedBox(width: 8),
              Text(widget.symbol,
                  style: TextStyle(
                      color: pal.textHi,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              FlashPrice(
                price: _last,
                market: _market,
                tag: widget.symbol,
                style: TextStyle(
                    color: pal.textHi,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Spot / Margin
          if (simState.account?.marginEnabled ?? true)
            _Segmented<TradeMode>(
              value: _mode,
              items: const {TradeMode.spot: 'Spot', TradeMode.margin: 'Margin'},
              onChanged: (m) => setState(() {
                _mode = m;
                if (m == TradeMode.spot && _side == OrderSide.sell) {
                  // spot sell = close; keep as-is but reset type sanity
                }
              }),
            ),
          const SizedBox(height: 10),

          // Buy / Sell
          Row(
            children: [
              Expanded(
                child: _SideButton(
                  label: _mode == TradeMode.margin ? 'Buy / Long' : 'Buy',
                  color: NqeColors.gain,
                  selected: buy,
                  onTap: () => setState(() => _side = OrderSide.buy),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SideButton(
                  label: _mode == TradeMode.margin ? 'Sell / Short' : 'Sell',
                  color: NqeColors.loss,
                  selected: !buy,
                  onTap: () => setState(() => _side = OrderSide.sell),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Order type
          _Segmented<OrderType>(
            value: _type,
            items: const {
              OrderType.market: 'Market',
              OrderType.limit: 'Limit',
              OrderType.stop: 'Stop',
              OrderType.takeProfit: 'TP',
            },
            onChanged: (t) => setState(() => _type = t),
          ),
          const SizedBox(height: 12),

          if (_type == OrderType.limit)
            _priceField(_limitCtrl, 'Limit price'),
          if (_type == OrderType.stop || _type == OrderType.takeProfit)
            _priceField(_stopCtrl,
                _type == OrderType.stop ? 'Stop (trigger) price' : 'Take-profit price'),

          // Quantity
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Quantity',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final p in const [0.25, 0.5, 0.75, 1.0])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: p == 1.0 ? 0 : 6),
                    child: OutlinedButton(
                      onPressed: () => _setQtyPct(p),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        side: BorderSide(color: pal.line),
                        foregroundColor: pal.textHi,
                      ),
                      child: Text(p == 1.0 ? 'Max' : '${(p * 100).toInt()}%',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
            ],
          ),

          // Leverage
          if (_mode == TradeMode.margin) ...[
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final maxLev = (simState.account?.maxLeverage ?? 10);
              // Guard the Slider assertions: keep value within [1, maxLev] and
              // never let min == max (an account capped at 1x shows no slider).
              final lev = _leverage.clamp(1.0, maxLev < 1 ? 1.0 : maxLev);
              if (maxLev <= 1) {
                return Row(
                  children: [
                    Text('Leverage',
                        style: TextStyle(color: pal.textLo, fontSize: 12)),
                    const Spacer(),
                    Text('1x',
                        style: TextStyle(
                            color: pal.textHi, fontWeight: FontWeight.w800)),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('Leverage',
                          style: TextStyle(color: pal.textLo, fontSize: 12)),
                      const Spacer(),
                      Text('${lev.toStringAsFixed(0)}x',
                          style: TextStyle(
                              color: pal.textHi, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Slider(
                    value: lev,
                    min: 1,
                    max: maxLev,
                    divisions: (maxLev - 1).round().clamp(1, 100),
                    label: '${lev.toStringAsFixed(0)}x',
                    onChanged: (v) => setState(() => _leverage = v),
                  ),
                ],
              );
            }),
          ],

          const SizedBox(height: 6),
          _kv('Buying power', simMoney(_buyingPower, currency: cur)),
          _kv(_mode == TradeMode.margin ? 'Est. collateral + fee' : 'Est. cost',
              simMoney(costBase, currency: cur)),
          _kv('Est. fee', simMoney(feeBase, currency: cur)),
          if (_liqPreview != null)
            _kv('Est. liquidation', fmtPrice(_liqPreview!, _market),
                color: NqeColors.loss),

          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      '${buy ? 'Buy' : 'Sell'} ${widget.symbol}'
                      '${_type == OrderType.market ? '' : ' ($_typeLabel)'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  String get _typeLabel => switch (_type) {
        OrderType.market => 'Market',
        OrderType.limit => 'Limit',
        OrderType.stop => 'Stop',
        OrderType.takeProfit => 'TP',
      };

  Widget _priceField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Widget _kv(String k, String v, {Color? color}) {
    final pal = context.nqe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(k, style: TextStyle(color: pal.textLo, fontSize: 12)),
          const Spacer(),
          Text(v,
              style: TextStyle(
                  color: color ?? pal.textHi,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const _Segmented(
      {required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: pal.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final e in items.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? pal.bg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: e.key == value
                        ? Border.all(color: pal.line)
                        : null,
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: e.key == value ? pal.textHi : pal.textLo,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _SideButton(
      {required this.label,
      required this.color,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color : color.withOpacity(0.4), width: 1.4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
