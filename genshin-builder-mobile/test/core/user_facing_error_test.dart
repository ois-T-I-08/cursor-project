import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/core/errors/user_facing_error.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_exceptions.dart';

void main() {
  group('userFacingError', () {
    test('maps HoyolabApiException to userMessage', () {
      const e = HoyolabApiException(-100, 'token invalid');
      expect(userFacingError(e), contains('ログイン'));
      expect(userFacingError(e), isNot(contains('token invalid')));
    });

    test('maps TimeoutException', () {
      expect(userFacingError(TimeoutException('slow')), contains('タイムアウト'));
    });

    test('passes through non-empty String', () {
      expect(userFacingError('既に整形済み'), '既に整形済み');
    });

    test('hides raw Exception details', () {
      final message = userFacingError(Exception('https://secret.example/path'));
      expect(message, isNot(contains('secret.example')));
      expect(message, contains('失敗'));
    });
  });

  group('userFacingSyncErrors', () {
    test('reports count without raw details', () {
      final message = userFacingSyncErrors([
        'Amber API error: 500 /avatar',
        'SocketException: Failed host lookup',
      ]);
      expect(message, contains('2件'));
      expect(message, isNot(contains('SocketException')));
      expect(message, isNot(contains('/avatar')));
    });
  });
}
