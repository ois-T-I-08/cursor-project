import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' hide log;

import 'package:crypto/crypto.dart';

import 'hoyolab_constants.dart';

/// DS 署名生成（グローバル版 salt）
class HoyolabAuth {
  static const _salt = 'okr4obncj8bw5a65hbnn5oo6ixjc3l9w';

  static String generateDsToken({
    String body = '',
    Map<String, String> queryParameters = const {},
  }) {
    final t = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    final r = 100000 + Random().nextInt(100000);
    final sortedKeys = queryParameters.keys.toList()..sort();
    final q = sortedKeys
        .map(
          (key) =>
              '$key=${Uri.encodeQueryComponent(queryParameters[key] ?? '')}',
        )
        .join('&');
    final c = md5.convert(
      utf8.encode('salt=$_salt&t=$t&r=$r&b=$body&q=$q'),
    );
    return '$t,$r,${c.toString()}';
  }

  static Map<String, String> buildHeaders({
    required String cookie,
    required String appVersion,
    String? dsToken,
    String clientType = '2',
  }) {
    return {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) miHoYoBBSOversea/$appVersion',
      'Origin': 'https://act.hoyolab.com',
      'Referer': 'https://act.hoyolab.com/',
      'Accept-Encoding': 'gzip, deflate, br',
      'Cookie': cookie,
      'x-rpc-client_type': clientType,
      'x-rpc-app_version': appVersion,
      'x-rpc-language': HoyolabConstants.language,
      if (dsToken != null) 'DS': dsToken,
    };
  }

  static Map<String, String> buildRecordHeaders({
    required String cookie,
    required String appVersion,
    String? dsToken,
    bool jsonBody = false,
  }) {
    return {
      ...buildHeaders(
        cookie: cookie,
        appVersion: appVersion,
        dsToken: dsToken,
        clientType: HoyolabConstants.recordClientType,
      ),
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }
}

/// API リクエスト間隔制御（500ms）
class ApiRequestQueue {
  ApiRequestQueue({this.interval = const Duration(milliseconds: 500)});

  final Duration interval;
  final Queue<Future<void> Function()> _queue = Queue();
  bool _isProcessing = false;
  DateTime? _lastRun;

  Future<T> run<T>(Future<T> Function() action) async {
    final completer = Completer<T>();
    _queue.add(() async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    if (!_isProcessing) {
      await _processQueue();
    }
    return completer.future;
  }

  Future<void> _processQueue() async {
    _isProcessing = true;
    while (_queue.isNotEmpty) {
      final now = DateTime.now();
      if (_lastRun != null && now.difference(_lastRun!) < interval) {
        await Future.delayed(interval - now.difference(_lastRun!));
      }
      final task = _queue.removeFirst();
      await task();
      _lastRun = DateTime.now();
    }
    _isProcessing = false;
  }
}
