// Bundled stock-symbol catalogue for the searchable "Stock code" field.
//
// Offline-first: this is a curated, static list (no network needed) covering the
// PSE main board — the fund's primary market — plus popular US tickers. The
// Stock code field remains free-text, so any symbol not listed here can still be
// typed manually; this list only powers search-as-you-type suggestions.
class StockSymbol {
  final String code;
  final String name;
  final String market; // 'PSE' or 'US'
  const StockSymbol(this.code, this.name, this.market);
}

/// Case-insensitive match on the ticker code or the company name.
Iterable<StockSymbol> searchSymbols(String query, {int limit = 20}) {
  final q = query.trim().toUpperCase();
  if (q.isEmpty) return const <StockSymbol>[];
  // Rank: code-prefix first, then code-contains, then name-contains.
  final prefix = <StockSymbol>[];
  final codeContains = <StockSymbol>[];
  final nameContains = <StockSymbol>[];
  for (final s in kStockSymbols) {
    final code = s.code.toUpperCase();
    if (code.startsWith(q)) {
      prefix.add(s);
    } else if (code.contains(q)) {
      codeContains.add(s);
    } else if (s.name.toUpperCase().contains(q)) {
      nameContains.add(s);
    }
  }
  return [...prefix, ...codeContains, ...nameContains].take(limit);
}

const List<StockSymbol> kStockSymbols = [
  // ---- PSE — PSEi & actively traded ----
  StockSymbol('AC', 'Ayala Corporation', 'PSE'),
  StockSymbol('ACEN', 'ACEN Corporation', 'PSE'),
  StockSymbol('AEV', 'Aboitiz Equity Ventures', 'PSE'),
  StockSymbol('AGI', 'Alliance Global Group', 'PSE'),
  StockSymbol('ALI', 'Ayala Land', 'PSE'),
  StockSymbol('AP', 'Aboitiz Power', 'PSE'),
  StockSymbol('BDO', 'BDO Unibank', 'PSE'),
  StockSymbol('BPI', 'Bank of the Philippine Islands', 'PSE'),
  StockSymbol('BLOOM', 'Bloomberry Resorts', 'PSE'),
  StockSymbol('CNVRG', 'Converge ICT Solutions', 'PSE'),
  StockSymbol('DMC', 'DMCI Holdings', 'PSE'),
  StockSymbol('EMI', 'Emperador Inc.', 'PSE'),
  StockSymbol('GLO', 'Globe Telecom', 'PSE'),
  StockSymbol('GTCAP', 'GT Capital Holdings', 'PSE'),
  StockSymbol('ICT', 'International Container Terminal Services', 'PSE'),
  StockSymbol('JFC', 'Jollibee Foods Corporation', 'PSE'),
  StockSymbol('JGS', 'JG Summit Holdings', 'PSE'),
  StockSymbol('LTG', 'LT Group', 'PSE'),
  StockSymbol('MBT', 'Metropolitan Bank & Trust (Metrobank)', 'PSE'),
  StockSymbol('MER', 'Manila Electric Company (Meralco)', 'PSE'),
  StockSymbol('MONDE', 'Monde Nissin Corporation', 'PSE'),
  StockSymbol('NIKL', 'Nickel Asia Corporation', 'PSE'),
  StockSymbol('PGOLD', 'Puregold Price Club', 'PSE'),
  StockSymbol('SM', 'SM Investments Corporation', 'PSE'),
  StockSymbol('SMC', 'San Miguel Corporation', 'PSE'),
  StockSymbol('SMPH', 'SM Prime Holdings', 'PSE'),
  StockSymbol('TEL', 'PLDT Inc.', 'PSE'),
  StockSymbol('URC', 'Universal Robina Corporation', 'PSE'),
  StockSymbol('WLCON', 'Wilcon Depot', 'PSE'),
  StockSymbol('SCC', 'Semirara Mining and Power', 'PSE'),
  StockSymbol('FGEN', 'First Gen Corporation', 'PSE'),
  StockSymbol('FPH', 'First Philippine Holdings', 'PSE'),
  StockSymbol('MEG', 'Megaworld Corporation', 'PSE'),
  StockSymbol('RLC', 'Robinsons Land Corporation', 'PSE'),
  StockSymbol('RRHI', 'Robinsons Retail Holdings', 'PSE'),
  StockSymbol('FLI', 'Filinvest Land', 'PSE'),
  StockSymbol('FDC', 'Filinvest Development Corporation', 'PSE'),
  StockSymbol('VLL', 'Vista Land & Lifescapes', 'PSE'),
  StockSymbol('CNPF', 'Century Pacific Food', 'PSE'),
  StockSymbol('PIZZA', "Shakey's Pizza Asia Ventures", 'PSE'),
  StockSymbol('MAXS', 'Max\'s Group', 'PSE'),
  StockSymbol('DITO', 'DITO CME Holdings', 'PSE'),
  StockSymbol('SGP', 'Synergy Grid & Development Phils.', 'PSE'),
  StockSymbol('SPNEC', 'SP New Energy Corporation', 'PSE'),
  StockSymbol('MWIDE', 'Megawide Construction', 'PSE'),
  StockSymbol('COSCO', 'Cosco Capital', 'PSE'),
  StockSymbol('PX', 'Philex Mining Corporation', 'PSE'),
  StockSymbol('SECB', 'Security Bank Corporation', 'PSE'),
  StockSymbol('CHIB', 'China Banking Corporation', 'PSE'),
  StockSymbol('PNB', 'Philippine National Bank', 'PSE'),
  StockSymbol('UBP', 'Union Bank of the Philippines', 'PSE'),
  StockSymbol('EW', 'East West Banking Corporation', 'PSE'),
  StockSymbol('PSE', 'Philippine Stock Exchange', 'PSE'),
  StockSymbol('ION', 'Ionics Inc.', 'PSE'),
  StockSymbol('CEB', 'Cebu Air (Cebu Pacific)', 'PSE'),
  StockSymbol('GERI', 'Global-Estate Resorts', 'PSE'),
  StockSymbol('APX', 'Apex Mining', 'PSE'),
  StockSymbol('BSC', 'Basic Energy', 'PSE'),
  StockSymbol('PXP', 'PXP Energy', 'PSE'),
  // ---- PSE — REITs ----
  StockSymbol('AREIT', 'AREIT Inc.', 'PSE'),
  StockSymbol('RCR', 'RL Commercial REIT', 'PSE'),
  StockSymbol('MREIT', 'MREIT Inc.', 'PSE'),
  StockSymbol('FILRT', 'Filinvest REIT', 'PSE'),
  StockSymbol('DDMPR', 'DDMP REIT', 'PSE'),
  StockSymbol('CREIT', 'Citicore Energy REIT', 'PSE'),
  StockSymbol('VREIT', 'VistaREIT', 'PSE'),
  StockSymbol('PREIT', 'Premiere Island Power REIT', 'PSE'),
  // ---- US — popular ----
  StockSymbol('AAPL', 'Apple Inc.', 'US'),
  StockSymbol('MSFT', 'Microsoft Corporation', 'US'),
  StockSymbol('NVDA', 'NVIDIA Corporation', 'US'),
  StockSymbol('GOOGL', 'Alphabet Inc. (Google)', 'US'),
  StockSymbol('AMZN', 'Amazon.com Inc.', 'US'),
  StockSymbol('META', 'Meta Platforms', 'US'),
  StockSymbol('TSLA', 'Tesla Inc.', 'US'),
  StockSymbol('AMD', 'Advanced Micro Devices', 'US'),
  StockSymbol('NFLX', 'Netflix Inc.', 'US'),
  StockSymbol('INTC', 'Intel Corporation', 'US'),
  StockSymbol('JPM', 'JPMorgan Chase & Co.', 'US'),
  StockSymbol('V', 'Visa Inc.', 'US'),
  StockSymbol('KO', 'The Coca-Cola Company', 'US'),
  StockSymbol('DIS', 'The Walt Disney Company', 'US'),
  StockSymbol('BABA', 'Alibaba Group', 'US'),
  StockSymbol('PLTR', 'Palantir Technologies', 'US'),
  StockSymbol('COIN', 'Coinbase Global', 'US'),
  StockSymbol('SPY', 'SPDR S&P 500 ETF Trust', 'US'),
  StockSymbol('QQQ', 'Invesco QQQ Trust', 'US'),
];
