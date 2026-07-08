import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_api.dart';

void main() {
  group('HoyolabApi response parsing', () {
    test('lookupRegions parses data.list', () async {
      final api = HoyolabApi(cookie: 'ltoken_v2=test; ltuid_v2=1;');
      final regions = await api.lookupRegions();

      expect(regions, isNotEmpty);
      expect(regions.map((r) => r.region), contains('os_asia'));
    });
  });
}
