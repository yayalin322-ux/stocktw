import 'package:dio/dio.dart';

/// TWSE MIS 即時報價（需要 Referer）
final misDio = Dio(BaseOptions(
  baseUrl: 'https://mis.twse.com.tw',
  headers: {
    'Referer': 'https://mis.twse.com.tw/stock/index.jsp',
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
  },
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 8),
));

/// Yahoo Finance chart（K 線）
final yahooDio = Dio(BaseOptions(
  headers: {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
  },
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 12),
));

/// 一般用途
final webDio = Dio(BaseOptions(
  headers: {'User-Agent': 'Mozilla/5.0'},
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 12),
));
