import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../models.dart';
import 'api.dart';

/// 個股新聞（Google News RSS，免金鑰）
class NewsService {
  Future<List<NewsItem>> fetch(String code, String name,
      {bool tw = true}) async {
    final q = Uri.encodeComponent(tw ? '$code $name 股' : name);
    final res = await webDio.get(
      'https://news.google.com/rss/search',
      queryParameters: {
        'q': q,
        'hl': tw ? 'zh-TW' : 'en-US',
        'gl': tw ? 'TW' : 'US',
        'ceid': tw ? 'TW:zh-Hant' : 'US:en',
      },
      options: Options(responseType: ResponseType.plain),
    );
    final doc = XmlDocument.parse(res.data as String);
    return doc.findAllElements('item').take(30).map((e) {
      String t(String tag) =>
          e.getElement(tag)?.innerText.trim() ?? '';
      final pub = t('pubDate');
      return NewsItem(
        t('title'),
        t('link'),
        e.getElement('source')?.innerText.trim() ?? 'Google News',
        DateTime.tryParse(pub) ?? _parseRfc822(pub),
      );
    }).toList();
  }

  DateTime? _parseRfc822(String s) {
    try {
      // e.g. "Mon, 01 Sep 2026 09:30:00 GMT"
      final months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final p = s.split(RegExp(r'[\s:]+'));
      return DateTime.utc(
        int.parse(p[3]), months[p[2]]!, int.parse(p[1]),
        int.parse(p[4]), int.parse(p[5]), int.parse(p[6]),
      );
    } catch (_) {
      return null;
    }
  }
}

final newsService = NewsService();
