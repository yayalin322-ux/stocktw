/// 熱門 ETF 近期主要成分股（權重為近似值，每季調整，實際以投信公告為準）
/// 更新參考：2026 上半年（00919 已於 2026/09 依最新資料校正）
const kEtfAsOf = '約 2026 上半年';

class Holding {
  final String code;
  final String name;
  final double weight; // %
  const Holding(this.code, this.name, this.weight);
}

const kEtfHoldings = <String, List<Holding>>{
  '0050': [
    Holding('2330', '台積電', 57.0),
    Holding('2317', '鴻海', 4.6),
    Holding('2454', '聯發科', 3.6),
    Holding('2308', '台達電', 2.9),
    Holding('2382', '廣達', 2.2),
    Holding('2881', '富邦金', 1.9),
    Holding('2882', '國泰金', 1.6),
    Holding('2891', '中信金', 1.5),
    Holding('3711', '日月光投控', 1.3),
    Holding('2303', '聯電', 1.2),
  ],
  '006208': [
    Holding('2330', '台積電', 57.5),
    Holding('2317', '鴻海', 4.7),
    Holding('2454', '聯發科', 3.7),
    Holding('2308', '台達電', 2.9),
    Holding('2382', '廣達', 2.2),
    Holding('2881', '富邦金', 1.9),
    Holding('2882', '國泰金', 1.6),
    Holding('2891', '中信金', 1.5),
    Holding('3711', '日月光投控', 1.3),
    Holding('2303', '聯電', 1.2),
  ],
  '0056': [
    Holding('2382', '廣達', 5.5),
    Holding('2454', '聯發科', 5.0),
    Holding('2303', '聯電', 4.2),
    Holding('3231', '緯創', 4.0),
    Holding('2357', '華碩', 3.6),
    Holding('3034', '聯詠', 3.4),
    Holding('2376', '技嘉', 3.1),
    Holding('2377', '微星', 3.0),
    Holding('2356', '英業達', 2.9),
    Holding('2603', '長榮', 2.7),
  ],
  '00878': [
    Holding('2382', '廣達', 4.5),
    Holding('3034', '聯詠', 3.9),
    Holding('2357', '華碩', 3.7),
    Holding('2301', '光寶科', 3.5),
    Holding('3231', '緯創', 3.4),
    Holding('2377', '微星', 3.2),
    Holding('2356', '英業達', 3.1),
    Holding('2454', '聯發科', 3.0),
    Holding('2376', '技嘉', 2.9),
    Holding('3702', '大聯大', 2.7),
  ],
  '00919': [
    Holding('2881', '富邦金', 15.23),
    Holding('2882', '國泰金', 13.05),
    Holding('2891', '中信金', 10.36),
    Holding('2382', '廣達', 10.26),
    Holding('2887', '台新新光金', 8.48),
    Holding('2357', '華碩', 6.27),
    Holding('2883', '凱基金', 5.17),
    Holding('2603', '長榮', 3.82),
    Holding('3034', '聯詠', 3.19),
    Holding('2379', '瑞昱', 2.75),
  ],
  '00929': [
    Holding('2382', '廣達', 4.0),
    Holding('3034', '聯詠', 3.8),
    Holding('3231', '緯創', 3.7),
    Holding('2379', '瑞昱', 3.6),
    Holding('2301', '光寶科', 3.5),
    Holding('2376', '技嘉', 3.4),
    Holding('2377', '微星', 3.3),
    Holding('3017', '奇鋐', 3.2),
    Holding('2356', '英業達', 3.1),
    Holding('3661', '世芯-KY', 3.0),
  ],
  '00713': [
    Holding('2412', '中華電', 6.5),
    Holding('3045', '台灣大', 5.0),
    Holding('4904', '遠傳', 4.5),
    Holding('2454', '聯發科', 4.0),
    Holding('1216', '統一', 3.8),
    Holding('2882', '國泰金', 3.5),
    Holding('2884', '玉山金', 3.3),
    Holding('5871', '中租-KY', 3.1),
    Holding('2891', '中信金', 3.0),
    Holding('2308', '台達電', 2.9),
  ],
  '00940': [
    Holding('2882', '國泰金', 4.2),
    Holding('2881', '富邦金', 4.0),
    Holding('2891', '中信金', 3.8),
    Holding('2886', '兆豐金', 3.5),
    Holding('2884', '玉山金', 3.3),
    Holding('2892', '第一金', 3.1),
    Holding('2880', '華南金', 3.0),
    Holding('2887', '台新金', 2.8),
    Holding('1216', '統一', 2.7),
    Holding('2603', '長榮', 2.5),
  ],
  '00646': [
    Holding('NVDA', 'NVIDIA 輝達', 7.5),
    Holding('MSFT', 'Microsoft 微軟', 6.5),
    Holding('AAPL', 'Apple 蘋果', 6.0),
    Holding('AMZN', 'Amazon 亞馬遜', 4.0),
    Holding('META', 'Meta', 2.6),
    Holding('AVGO', 'Broadcom 博通', 2.4),
    Holding('GOOGL', 'Alphabet A', 2.2),
    Holding('GOOG', 'Alphabet C', 1.9),
    Holding('TSLA', 'Tesla 特斯拉', 1.8),
    Holding('BRK-B', 'Berkshire B', 1.6),
  ],
  '00662': [
    Holding('NVDA', 'NVIDIA 輝達', 9.5),
    Holding('MSFT', 'Microsoft 微軟', 8.5),
    Holding('AAPL', 'Apple 蘋果', 8.0),
    Holding('AMZN', 'Amazon 亞馬遜', 5.5),
    Holding('AVGO', 'Broadcom 博通', 5.0),
    Holding('META', 'Meta', 4.0),
    Holding('GOOGL', 'Alphabet A', 2.6),
    Holding('GOOG', 'Alphabet C', 2.5),
    Holding('TSLA', 'Tesla 特斯拉', 2.4),
    Holding('NFLX', 'Netflix 網飛', 2.0),
  ],
};

/// 反查：這檔股票被哪些 ETF 持有（依權重高到低）
class EtfHold {
  final String etfCode;
  final double weight;
  const EtfHold(this.etfCode, this.weight);
}

List<EtfHold> etfsHolding(String code) {
  final out = <EtfHold>[];
  for (final e in kEtfHoldings.entries) {
    for (final h in e.value) {
      if (h.code == code) {
        out.add(EtfHold(e.key, h.weight));
        break;
      }
    }
  }
  out.sort((a, b) => b.weight.compareTo(a.weight));
  return out;
}

/// 有股票期貨（TAIFEX 掛牌）的常見台股代號（近似清單，非官方即時資料）
const kHasStockFutures = <String>{
  '2330', '2317', '2454', '2308', '2382', '2881', '2882', '2891', '2886',
  '2892', '3711', '2303', '2412', '1301', '1303', '1326', '2002', '2207',
  '2603', '2609', '2615', '3034', '3037', '3231', '3661', '4938', '5871',
  '5880', '6505', '6669', '8046', '9910', '2379', '2357', '2377', '2395',
  '2409', '2449', '2474', '2618', '2801', '2880', '2883', '2884', '2885',
  '2887', '2888', '2890', '3008', '3045', '3443', '3653', '4904', '4958',
  '5876', '6446', '6415', '6488', '9904', '9945', '00631L', '00632R',
  '0050', '0056', '00878',
};
