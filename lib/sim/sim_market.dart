// Sandbox instrument catalogue across markets: PSE + US stocks, Forex majors,
// and Crypto. Static + offline; the simulated price feed seeds from [seedPrice]
// and the live feed (when configured) overrides with real quotes.
import 'sim_models.dart';

class SimSymbol {
  final String symbol; // e.g. 'AAPL', 'EURUSD', 'BTCUSDT'
  final String name;
  final SimMarket market;
  final double seedPrice; // starting price for the simulated feed
  const SimSymbol(this.symbol, this.name, this.market, this.seedPrice);
}

/// Case-insensitive search by ticker or name, optionally filtered by market.
Iterable<SimSymbol> searchInstruments(String query,
    {SimMarket? market, int limit = 25}) {
  final q = query.trim().toUpperCase();
  final pool = market == null
      ? kInstruments
      : kInstruments.where((s) => s.market == market);
  if (q.isEmpty) return pool.take(limit);
  final prefix = <SimSymbol>[];
  final contains = <SimSymbol>[];
  final byName = <SimSymbol>[];
  for (final s in pool) {
    final code = s.symbol.toUpperCase();
    if (code.startsWith(q)) {
      prefix.add(s);
    } else if (code.contains(q)) {
      contains.add(s);
    } else if (s.name.toUpperCase().contains(q)) {
      byName.add(s);
    }
  }
  return [...prefix, ...contains, ...byName].take(limit);
}

SimSymbol? instrumentFor(String symbol) {
  final up = symbol.toUpperCase();
  for (final s in kInstruments) {
    if (s.symbol.toUpperCase() == up) return s;
  }
  return null;
}

double seedPriceFor(String symbol) => instrumentFor(symbol)?.seedPrice ?? 100.0;

const List<SimSymbol> kInstruments = [
  // ---- PSE stocks (prices in PHP, indicative) ----
  SimSymbol('SM', 'SM Investments', SimMarket.stocks, 900),
  SimSymbol('BDO', 'BDO Unibank', SimMarket.stocks, 150),
  SimSymbol('BPI', 'Bank of the Philippine Islands', SimMarket.stocks, 130),
  SimSymbol('ALI', 'Ayala Land', SimMarket.stocks, 30),
  SimSymbol('AC', 'Ayala Corporation', SimMarket.stocks, 650),
  SimSymbol('JFC', 'Jollibee Foods', SimMarket.stocks, 240),
  SimSymbol('SMPH', 'SM Prime Holdings', SimMarket.stocks, 30),
  SimSymbol('TEL', 'PLDT Inc.', SimMarket.stocks, 1300),
  SimSymbol('GLO', 'Globe Telecom', SimMarket.stocks, 1900),
  SimSymbol('MER', 'Meralco', SimMarket.stocks, 400),
  SimSymbol('ICT', 'ICTSI', SimMarket.stocks, 350),
  SimSymbol('URC', 'Universal Robina', SimMarket.stocks, 100),
  SimSymbol('AEV', 'Aboitiz Equity Ventures', SimMarket.stocks, 40),
  SimSymbol('ACEN', 'ACEN Corporation', SimMarket.stocks, 4),
  SimSymbol('BLOOM', 'Bloomberry Resorts', SimMarket.stocks, 10),
  SimSymbol('CNVRG', 'Converge ICT', SimMarket.stocks, 10),
  SimSymbol('MONDE', 'Monde Nissin', SimMarket.stocks, 10),
  SimSymbol('SPNEC', 'SP New Energy', SimMarket.stocks, 1),
  // ---- US stocks (USD) ----
  SimSymbol('AAPL', 'Apple Inc.', SimMarket.stocks, 190),
  SimSymbol('MSFT', 'Microsoft', SimMarket.stocks, 420),
  SimSymbol('NVDA', 'NVIDIA', SimMarket.stocks, 120),
  SimSymbol('AMZN', 'Amazon', SimMarket.stocks, 180),
  SimSymbol('GOOGL', 'Alphabet', SimMarket.stocks, 170),
  SimSymbol('META', 'Meta Platforms', SimMarket.stocks, 520),
  SimSymbol('TSLA', 'Tesla', SimMarket.stocks, 250),
  SimSymbol('AMD', 'Advanced Micro Devices', SimMarket.stocks, 160),
  // ---- Forex majors ----
  SimSymbol('EURUSD', 'Euro / US Dollar', SimMarket.forex, 1.08),
  SimSymbol('GBPUSD', 'British Pound / US Dollar', SimMarket.forex, 1.27),
  SimSymbol('USDJPY', 'US Dollar / Japanese Yen', SimMarket.forex, 150),
  SimSymbol('USDPHP', 'US Dollar / Philippine Peso', SimMarket.forex, 57),
  SimSymbol('AUDUSD', 'Australian Dollar / US Dollar', SimMarket.forex, 0.66),
  SimSymbol('USDCAD', 'US Dollar / Canadian Dollar', SimMarket.forex, 1.36),
  SimSymbol('USDCHF', 'US Dollar / Swiss Franc', SimMarket.forex, 0.88),
  SimSymbol('NZDUSD', 'New Zealand Dollar / US Dollar', SimMarket.forex, 0.61),
  SimSymbol('XAUUSD', 'Gold / US Dollar', SimMarket.forex, 2350),
  // ---- Crypto (USDT pairs) ----
  SimSymbol('BTCUSDT', 'Bitcoin', SimMarket.crypto, 65000),
  SimSymbol('ETHUSDT', 'Ethereum', SimMarket.crypto, 3400),
  SimSymbol('BNBUSDT', 'BNB', SimMarket.crypto, 580),
  SimSymbol('SOLUSDT', 'Solana', SimMarket.crypto, 150),
  SimSymbol('XRPUSDT', 'XRP', SimMarket.crypto, 0.6),
  SimSymbol('ADAUSDT', 'Cardano', SimMarket.crypto, 0.45),
  SimSymbol('DOGEUSDT', 'Dogecoin', SimMarket.crypto, 0.15),
  SimSymbol('AVAXUSDT', 'Avalanche', SimMarket.crypto, 35),
  SimSymbol('MATICUSDT', 'Polygon', SimMarket.crypto, 0.7),
  SimSymbol('LINKUSDT', 'Chainlink', SimMarket.crypto, 15),
];
