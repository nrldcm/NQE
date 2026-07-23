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

/// PSE-listed tickers — quoted in Philippine pesos.
const Set<String> kPseTickers = {
  'SM', 'BDO', 'BPI', 'ALI', 'AC', 'JFC', 'SMPH', 'TEL', 'GLO', 'MER',
  'ICT', 'URC', 'AEV', 'ACEN', 'BLOOM', 'CNVRG', 'MONDE', 'SPNEC',
  'AGI', 'AP', 'DMC', 'EMP', 'FGEN', 'GTCAP', 'JGS', 'LTG', 'MBT', 'PGOLD',
  'RRHI', 'RLC', 'SCC', 'SECB', 'WLCON', 'DITO', 'NIKL', 'MPI', 'PCOR',
  'FB', 'MAXS', 'PIZZA', 'CEB', 'AREIT', 'CHIB', 'PNB', 'SGP',
};

/// The currency an instrument is priced in:
///   * PSE stocks → PHP
///   * Forex pairs → the pair's quote (last 3 letters, e.g. USDJPY → JPY)
///   * US stocks + crypto (USDT pairs) → USD
String quoteCurrencyFor(String symbol) {
  final up = symbol.toUpperCase();
  if (up == 'PSEI') return 'PHP'; // Philippine index, quoted in pesos
  if (kPseTickers.contains(up)) return 'PHP';
  final inst = instrumentFor(up);
  if (inst?.market == SimMarket.forex && up.length == 6) {
    return up.substring(3);
  }
  return 'USD'; // US stocks, crypto, indices & commodities
}

const List<SimSymbol> kInstruments = [
  // ==== PSE stocks (prices in PHP, indicative) ====
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
  SimSymbol('AGI', 'Alliance Global Group', SimMarket.stocks, 12),
  SimSymbol('AP', 'Aboitiz Power', SimMarket.stocks, 38),
  SimSymbol('DMC', 'DMCI Holdings', SimMarket.stocks, 10),
  SimSymbol('EMP', 'Emperador Inc.', SimMarket.stocks, 18),
  SimSymbol('FGEN', 'First Gen Corporation', SimMarket.stocks, 18),
  SimSymbol('GTCAP', 'GT Capital Holdings', SimMarket.stocks, 700),
  SimSymbol('JGS', 'JG Summit Holdings', SimMarket.stocks, 40),
  SimSymbol('LTG', 'LT Group', SimMarket.stocks, 9),
  SimSymbol('MBT', 'Metrobank', SimMarket.stocks, 65),
  SimSymbol('PGOLD', 'Puregold Price Club', SimMarket.stocks, 30),
  SimSymbol('RRHI', 'Robinsons Retail', SimMarket.stocks, 45),
  SimSymbol('RLC', 'Robinsons Land', SimMarket.stocks, 15),
  SimSymbol('SCC', 'Semirara Mining & Power', SimMarket.stocks, 32),
  SimSymbol('SECB', 'Security Bank', SimMarket.stocks, 70),
  SimSymbol('WLCON', 'Wilcon Depot', SimMarket.stocks, 22),
  SimSymbol('DITO', 'DITO CME Holdings', SimMarket.stocks, 2),
  SimSymbol('NIKL', 'Nickel Asia', SimMarket.stocks, 6),
  SimSymbol('MPI', 'Metro Pacific Investments', SimMarket.stocks, 5),
  SimSymbol('PCOR', 'Petron Corporation', SimMarket.stocks, 5),
  SimSymbol('FB', 'San Miguel Food & Beverage', SimMarket.stocks, 12),
  SimSymbol('MAXS', "Max's Group", SimMarket.stocks, 6),
  SimSymbol('PIZZA', "Shakey's Pizza", SimMarket.stocks, 8),
  SimSymbol('CEB', 'Cebu Air (Cebu Pacific)', SimMarket.stocks, 40),
  SimSymbol('AREIT', 'AREIT Inc.', SimMarket.stocks, 38),
  SimSymbol('CHIB', 'China Banking Corp.', SimMarket.stocks, 55),
  SimSymbol('PNB', 'Philippine National Bank', SimMarket.stocks, 30),
  SimSymbol('SGP', 'Synergy Grid & Development', SimMarket.stocks, 12),

  // ==== US stocks + ETFs (USD) ====
  SimSymbol('AAPL', 'Apple Inc.', SimMarket.stocks, 190),
  SimSymbol('MSFT', 'Microsoft', SimMarket.stocks, 420),
  SimSymbol('NVDA', 'NVIDIA', SimMarket.stocks, 120),
  SimSymbol('AMZN', 'Amazon', SimMarket.stocks, 180),
  SimSymbol('GOOGL', 'Alphabet', SimMarket.stocks, 170),
  SimSymbol('META', 'Meta Platforms', SimMarket.stocks, 520),
  SimSymbol('TSLA', 'Tesla', SimMarket.stocks, 250),
  SimSymbol('AMD', 'Advanced Micro Devices', SimMarket.stocks, 160),
  SimSymbol('NFLX', 'Netflix', SimMarket.stocks, 620),
  SimSymbol('INTC', 'Intel', SimMarket.stocks, 30),
  SimSymbol('CRM', 'Salesforce', SimMarket.stocks, 270),
  SimSymbol('ORCL', 'Oracle', SimMarket.stocks, 140),
  SimSymbol('ADBE', 'Adobe', SimMarket.stocks, 500),
  SimSymbol('CSCO', 'Cisco Systems', SimMarket.stocks, 48),
  SimSymbol('QCOM', 'Qualcomm', SimMarket.stocks, 170),
  SimSymbol('AVGO', 'Broadcom', SimMarket.stocks, 160),
  SimSymbol('TXN', 'Texas Instruments', SimMarket.stocks, 200),
  SimSymbol('IBM', 'IBM', SimMarket.stocks, 190),
  SimSymbol('UBER', 'Uber Technologies', SimMarket.stocks, 70),
  SimSymbol('PYPL', 'PayPal', SimMarket.stocks, 65),
  SimSymbol('SHOP', 'Shopify', SimMarket.stocks, 70),
  SimSymbol('COIN', 'Coinbase', SimMarket.stocks, 230),
  SimSymbol('PLTR', 'Palantir', SimMarket.stocks, 40),
  SimSymbol('SNOW', 'Snowflake', SimMarket.stocks, 130),
  SimSymbol('MU', 'Micron Technology', SimMarket.stocks, 110),
  SimSymbol('BA', 'Boeing', SimMarket.stocks, 180),
  SimSymbol('DIS', 'Walt Disney', SimMarket.stocks, 100),
  SimSymbol('KO', 'Coca-Cola', SimMarket.stocks, 62),
  SimSymbol('PEP', 'PepsiCo', SimMarket.stocks, 170),
  SimSymbol('MCD', "McDonald's", SimMarket.stocks, 260),
  SimSymbol('NKE', 'Nike', SimMarket.stocks, 90),
  SimSymbol('SBUX', 'Starbucks', SimMarket.stocks, 95),
  SimSymbol('WMT', 'Walmart', SimMarket.stocks, 70),
  SimSymbol('COST', 'Costco', SimMarket.stocks, 850),
  SimSymbol('JPM', 'JPMorgan Chase', SimMarket.stocks, 200),
  SimSymbol('BAC', 'Bank of America', SimMarket.stocks, 40),
  SimSymbol('V', 'Visa', SimMarket.stocks, 275),
  SimSymbol('MA', 'Mastercard', SimMarket.stocks, 460),
  SimSymbol('GS', 'Goldman Sachs', SimMarket.stocks, 470),
  SimSymbol('XOM', 'Exxon Mobil', SimMarket.stocks, 115),
  SimSymbol('CVX', 'Chevron', SimMarket.stocks, 155),
  SimSymbol('PFE', 'Pfizer', SimMarket.stocks, 28),
  SimSymbol('JNJ', 'Johnson & Johnson', SimMarket.stocks, 155),
  SimSymbol('UNH', 'UnitedHealth Group', SimMarket.stocks, 500),
  SimSymbol('GM', 'General Motors', SimMarket.stocks, 45),
  SimSymbol('F', 'Ford Motor', SimMarket.stocks, 12),
  SimSymbol('T', 'AT&T', SimMarket.stocks, 18),
  SimSymbol('VZ', 'Verizon', SimMarket.stocks, 40),
  SimSymbol('GE', 'General Electric', SimMarket.stocks, 165),
  SimSymbol('CAT', 'Caterpillar', SimMarket.stocks, 340),
  SimSymbol('BABA', 'Alibaba', SimMarket.stocks, 80),
  SimSymbol('PDD', 'PDD Holdings', SimMarket.stocks, 130),
  SimSymbol('NIO', 'NIO Inc.', SimMarket.stocks, 5),
  SimSymbol('ARM', 'Arm Holdings', SimMarket.stocks, 130),
  SimSymbol('DELL', 'Dell Technologies', SimMarket.stocks, 120),
  SimSymbol('SPY', 'SPDR S&P 500 ETF', SimMarket.stocks, 550),
  SimSymbol('QQQ', 'Invesco QQQ (Nasdaq 100)', SimMarket.stocks, 480),
  SimSymbol('IWM', 'iShares Russell 2000 ETF', SimMarket.stocks, 220),
  SimSymbol('GLD', 'SPDR Gold Shares', SimMarket.stocks, 215),

  // ==== Forex — majors, minors & crosses ====
  SimSymbol('EURUSD', 'Euro / US Dollar', SimMarket.forex, 1.08),
  SimSymbol('GBPUSD', 'British Pound / US Dollar', SimMarket.forex, 1.27),
  SimSymbol('USDJPY', 'US Dollar / Japanese Yen', SimMarket.forex, 150),
  SimSymbol('USDPHP', 'US Dollar / Philippine Peso', SimMarket.forex, 57),
  SimSymbol('AUDUSD', 'Australian Dollar / US Dollar', SimMarket.forex, 0.66),
  SimSymbol('USDCAD', 'US Dollar / Canadian Dollar', SimMarket.forex, 1.36),
  SimSymbol('USDCHF', 'US Dollar / Swiss Franc', SimMarket.forex, 0.88),
  SimSymbol('NZDUSD', 'New Zealand Dollar / US Dollar', SimMarket.forex, 0.61),
  SimSymbol('EURGBP', 'Euro / British Pound', SimMarket.forex, 0.85),
  SimSymbol('EURJPY', 'Euro / Japanese Yen', SimMarket.forex, 162),
  SimSymbol('GBPJPY', 'British Pound / Japanese Yen', SimMarket.forex, 190),
  SimSymbol('EURCHF', 'Euro / Swiss Franc', SimMarket.forex, 0.95),
  SimSymbol('AUDJPY', 'Australian Dollar / Japanese Yen', SimMarket.forex, 99),
  SimSymbol('EURAUD', 'Euro / Australian Dollar', SimMarket.forex, 1.63),
  SimSymbol('GBPAUD', 'British Pound / Australian Dollar', SimMarket.forex, 1.92),
  SimSymbol('USDSGD', 'US Dollar / Singapore Dollar', SimMarket.forex, 1.35),
  SimSymbol('USDHKD', 'US Dollar / Hong Kong Dollar', SimMarket.forex, 7.8),
  SimSymbol('USDCNH', 'US Dollar / Chinese Yuan', SimMarket.forex, 7.2),
  SimSymbol('USDMXN', 'US Dollar / Mexican Peso', SimMarket.forex, 17),
  SimSymbol('USDZAR', 'US Dollar / South African Rand', SimMarket.forex, 18),
  SimSymbol('USDTRY', 'US Dollar / Turkish Lira', SimMarket.forex, 32),
  SimSymbol('USDSEK', 'US Dollar / Swedish Krona', SimMarket.forex, 10.5),
  SimSymbol('USDNOK', 'US Dollar / Norwegian Krone', SimMarket.forex, 10.6),
  SimSymbol('EURCAD', 'Euro / Canadian Dollar', SimMarket.forex, 1.47),
  SimSymbol('CADJPY', 'Canadian Dollar / Japanese Yen', SimMarket.forex, 110),
  SimSymbol('CHFJPY', 'Swiss Franc / Japanese Yen', SimMarket.forex, 170),
  SimSymbol('NZDJPY', 'New Zealand Dollar / Japanese Yen', SimMarket.forex, 91),
  SimSymbol('AUDNZD', 'Australian Dollar / New Zealand Dollar', SimMarket.forex, 1.08),

  // ==== Indices ====
  SimSymbol('PSEI', 'PSE Index (Philippines)', SimMarket.indices, 6500),
  SimSymbol('US500', 'S&P 500', SimMarket.indices, 5500),
  SimSymbol('US100', 'Nasdaq 100', SimMarket.indices, 19500),
  SimSymbol('US30', 'Dow Jones 30', SimMarket.indices, 40000),
  SimSymbol('US2000', 'Russell 2000', SimMarket.indices, 2100),
  SimSymbol('JP225', 'Nikkei 225', SimMarket.indices, 39000),
  SimSymbol('GER40', 'DAX 40 (Germany)', SimMarket.indices, 18500),
  SimSymbol('UK100', 'FTSE 100 (UK)', SimMarket.indices, 8200),
  SimSymbol('FRA40', 'CAC 40 (France)', SimMarket.indices, 7500),
  SimSymbol('EU50', 'Euro Stoxx 50', SimMarket.indices, 4900),
  SimSymbol('HK50', 'Hang Seng (Hong Kong)', SimMarket.indices, 17500),
  SimSymbol('AUS200', 'ASX 200 (Australia)', SimMarket.indices, 7800),
  SimSymbol('INDIA50', 'Nifty 50 (India)', SimMarket.indices, 24000),

  // ==== Commodities (metals, energy, agriculture) ====
  SimSymbol('XAUUSD', 'Gold', SimMarket.commodities, 2350),
  SimSymbol('XAGUSD', 'Silver', SimMarket.commodities, 30),
  SimSymbol('XPTUSD', 'Platinum', SimMarket.commodities, 1000),
  SimSymbol('XPDUSD', 'Palladium', SimMarket.commodities, 1000),
  SimSymbol('WTIUSD', 'Crude Oil (WTI)', SimMarket.commodities, 78),
  SimSymbol('BRENTUSD', 'Crude Oil (Brent)', SimMarket.commodities, 82),
  SimSymbol('NATGAS', 'Natural Gas', SimMarket.commodities, 2.5),
  SimSymbol('COPPER', 'Copper', SimMarket.commodities, 4.2),
  SimSymbol('WHEAT', 'Wheat', SimMarket.commodities, 580),
  SimSymbol('CORN', 'Corn', SimMarket.commodities, 430),
  SimSymbol('COFFEE', 'Coffee', SimMarket.commodities, 240),
  SimSymbol('SUGAR', 'Sugar', SimMarket.commodities, 20),

  // ==== Crypto (USDT pairs) ====
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
  SimSymbol('DOTUSDT', 'Polkadot', SimMarket.crypto, 7),
  SimSymbol('TRXUSDT', 'TRON', SimMarket.crypto, 0.12),
  SimSymbol('LTCUSDT', 'Litecoin', SimMarket.crypto, 85),
  SimSymbol('BCHUSDT', 'Bitcoin Cash', SimMarket.crypto, 400),
  SimSymbol('XLMUSDT', 'Stellar', SimMarket.crypto, 0.11),
  SimSymbol('ATOMUSDT', 'Cosmos', SimMarket.crypto, 8),
  SimSymbol('UNIUSDT', 'Uniswap', SimMarket.crypto, 10),
  SimSymbol('ETCUSDT', 'Ethereum Classic', SimMarket.crypto, 27),
  SimSymbol('FILUSDT', 'Filecoin', SimMarket.crypto, 5),
  SimSymbol('APTUSDT', 'Aptos', SimMarket.crypto, 9),
  SimSymbol('ARBUSDT', 'Arbitrum', SimMarket.crypto, 1),
  SimSymbol('OPUSDT', 'Optimism', SimMarket.crypto, 2.5),
  SimSymbol('NEARUSDT', 'NEAR Protocol', SimMarket.crypto, 6),
  SimSymbol('INJUSDT', 'Injective', SimMarket.crypto, 25),
  SimSymbol('SUIUSDT', 'Sui', SimMarket.crypto, 1.2),
  SimSymbol('SEIUSDT', 'Sei', SimMarket.crypto, 0.5),
  SimSymbol('RUNEUSDT', 'THORChain', SimMarket.crypto, 5),
  SimSymbol('AAVEUSDT', 'Aave', SimMarket.crypto, 100),
  SimSymbol('MKRUSDT', 'Maker', SimMarket.crypto, 2800),
  SimSymbol('GRTUSDT', 'The Graph', SimMarket.crypto, 0.25),
  SimSymbol('SANDUSDT', 'The Sandbox', SimMarket.crypto, 0.4),
  SimSymbol('MANAUSDT', 'Decentraland', SimMarket.crypto, 0.4),
  SimSymbol('AXSUSDT', 'Axie Infinity', SimMarket.crypto, 7),
  SimSymbol('FTMUSDT', 'Fantom', SimMarket.crypto, 0.7),
  SimSymbol('ALGOUSDT', 'Algorand', SimMarket.crypto, 0.18),
  SimSymbol('THETAUSDT', 'Theta Network', SimMarket.crypto, 1.8),
  SimSymbol('EOSUSDT', 'EOS', SimMarket.crypto, 0.8),
  SimSymbol('CHZUSDT', 'Chiliz', SimMarket.crypto, 0.09),
  SimSymbol('GALAUSDT', 'Gala', SimMarket.crypto, 0.03),
  SimSymbol('ENJUSDT', 'Enjin Coin', SimMarket.crypto, 0.3),
  SimSymbol('CRVUSDT', 'Curve DAO', SimMarket.crypto, 0.4),
  SimSymbol('LDOUSDT', 'Lido DAO', SimMarket.crypto, 2),
  SimSymbol('SHIBUSDT', 'Shiba Inu', SimMarket.crypto, 0.00002),
  SimSymbol('PEPEUSDT', 'Pepe', SimMarket.crypto, 0.00001),
  SimSymbol('WIFUSDT', 'dogwifhat', SimMarket.crypto, 2),
  SimSymbol('BONKUSDT', 'Bonk', SimMarket.crypto, 0.00002),
  SimSymbol('TIAUSDT', 'Celestia', SimMarket.crypto, 6),
  SimSymbol('JUPUSDT', 'Jupiter', SimMarket.crypto, 1),
  SimSymbol('RNDRUSDT', 'Render', SimMarket.crypto, 8),
  SimSymbol('IMXUSDT', 'Immutable', SimMarket.crypto, 1.5),
];
