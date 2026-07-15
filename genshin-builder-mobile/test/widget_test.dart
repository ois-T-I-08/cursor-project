import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/core/errors/user_facing_error.dart';

void main() {
  test('unexpected exception details are not exposed to users', () {
    const fallback = 'safe fallback';
    const cookie = 'ltoken_v2=dummy-test-token';
    final message = userFacingError(
      Exception('$cookie at /private/path'),
      fallback: fallback,
    );

    expect(message, fallback);
    expect(message, isNot(contains('dummy-test-token')));
    expect(message, isNot(contains(cookie)));
  });
}
