import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/core/errors/user_facing_error.dart';
import 'package:genshin_builder_mobile/data/config/remote_json_fetch.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_http_guard.dart';

void main() {
  test('RemoteJsonFetchException toString omits URL and body', () {
    const e = RemoteJsonFetchException(
      kind: 'artifactScoreWeights',
      failure: RemoteJsonFailureKind.httpStatus,
      statusCode: 500,
    );
    final s = e.toString();
    expect(s.toLowerCase().contains('http://'), isFalse);
    expect(s.toLowerCase().contains('https://'), isFalse);
    expect(s.toLowerCase().contains('cookie'), isFalse);
    expect(s.toLowerCase().contains('password'), isFalse);
    expect(s.toLowerCase().contains('ltoken'), isFalse);
  });

  test('HoyolabHttpException toString omits secrets', () {
    const e = HoyolabHttpException(
      HoyolabHttpFailure.httpStatus,
      statusCode: 401,
    );
    final s = e.toString();
    expect(s.contains('cookie'), isFalse);
    expect(s.contains('password'), isFalse);
    expect(s.contains('ltoken'), isFalse);
  });

  test('logAppError accepts opaque errors without throwing', () {
    expect(
      () => logAppError(StateError('opaque'), null, 'test'),
      returnsNormally,
    );
  });
}
