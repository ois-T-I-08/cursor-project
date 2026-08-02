import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_cookie_normalizer.dart';

void main() {
  group('HoyolabCookieNormalizer', () {
    test('accepts exact ltoken_v2 with non-empty value', () {
      final n = HoyolabCookieNormalizer.normalize(
        'ltoken_v2=dummy_token_v2; other=1',
      );
      expect(n, isNotNull);
      expect(n!.contains('ltoken_v2=dummy_token_v2'), isTrue);
      expect(n.endsWith(';'), isTrue);
    });

    test('accepts exact ltoken with non-empty value', () {
      final n = HoyolabCookieNormalizer.normalize('ltoken=dummy_legacy_token');
      expect(n, isNotNull);
      expect(n!.contains('ltoken=dummy_legacy_token'), isTrue);
    });

    test('trims surrounding whitespace', () {
      final n = HoyolabCookieNormalizer.normalize(
        '  ltoken_v2=dummy_token_v2  ',
      );
      expect(n, isNotNull);
    });

    test('adds trailing semicolon when missing', () {
      final n = HoyolabCookieNormalizer.normalize('ltoken_v2=dummy_token_v2');
      expect(n, endsWith(';'));
    });

    test('keeps equals signs inside values', () {
      final map = HoyolabCookieNormalizer.parseToMap('ltoken_v2=a=b=c; foo=1')!;
      expect(map['ltoken_v2'], 'a=b=c');
    });

    test('rejects empty token value', () {
      expect(HoyolabCookieNormalizer.normalize('ltoken_v2=; foo=1'), isNull);
    });

    test('rejects missing required token key', () {
      expect(
        HoyolabCookieNormalizer.normalize('ltuid_v2=12345; account_id_v2=9'),
        isNull,
      );
    });

    test('rejects partial-match fake token key', () {
      expect(
        HoyolabCookieNormalizer.normalize('foo_ltoken_v2=dummy_token_v2'),
        isNull,
      );
    });

    test('mergePreferBase keeps base on conflict and fills missing', () {
      final merged = HoyolabCookieNormalizer.mergePreferBase(
        base: {'ltoken_v2': 'from_webview', 'shared': 'webview_wins'},
        fill: {
          'ltoken_v2': 'from_native_ignored',
          'shared': 'native_ignored',
          'extra_native': 'filled',
        },
      );
      expect(merged['ltoken_v2'], 'from_webview');
      expect(merged['shared'], 'webview_wins');
      expect(merged['extra_native'], 'filled');
    });

    test('rejects control characters in segments', () {
      expect(
        HoyolabCookieNormalizer.normalize('ltoken_v2=dummy\x00token'),
        isNull,
      );
    });

    test('rejects pathological raw length above maxRawLength', () {
      final huge = 'ltoken_v2=${'x' * (HoyolabCookieNormalizer.maxRawLength)}';
      expect(HoyolabCookieNormalizer.normalize(huge), isNull);
    });

    test('rejects empty cookie', () {
      expect(HoyolabCookieNormalizer.normalize(''), isNull);
      expect(HoyolabCookieNormalizer.normalize(null), isNull);
      expect(HoyolabCookieNormalizer.normalize('   ;  ; '), isNull);
    });
  });
}
