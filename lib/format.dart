// Shared number / currency / date formatting.
import 'package:intl/intl.dart';

const Map<String, String> kCurrencySymbols = {
  'PHP': '₱',
  'EUR': '€',
  'USD': '\$',
  'GBP': '£',
};

String currencySymbol(String code) => kCurrencySymbols[code] ?? '$code ';

String money(double v, {String currency = 'PHP', int decimals = 2}) {
  final f = NumberFormat.currency(
    symbol: currencySymbol(currency),
    decimalDigits: decimals,
  );
  return f.format(v);
}

String compactMoney(double v, {String currency = 'PHP'}) {
  final f = NumberFormat.compactCurrency(
    symbol: currencySymbol(currency),
    decimalDigits: v.abs() >= 1000 ? 1 : 2,
  );
  return f.format(v);
}

String signedMoney(double v, {String currency = 'PHP'}) {
  final s = money(v.abs(), currency: currency);
  if (v > 0) return '+$s';
  if (v < 0) return '-$s';
  return s;
}

String pct(double v, {int decimals = 2}) =>
    '${(v * 100).toStringAsFixed(decimals)}%';

String signedPct(double v, {int decimals = 2}) {
  final s = '${(v.abs() * 100).toStringAsFixed(decimals)}%';
  if (v > 0) return '+$s';
  if (v < 0) return '-$s';
  return s;
}

String num2(double v) => NumberFormat('#,##0.####').format(v);

String todayIso() => DateFormat('yyyy-MM-dd').format(DateTime.now());

String prettyDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('MMM d, yyyy').format(d);
}

String shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('MMM d').format(d);
}
