import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_api.dart';
import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_http_guard.dart';

void main() {
  test('lookupRegions uses guarded HTTP parsing with a mock client', () async {
    final api = HoyolabApi(
      cookie: 'ltoken_v2=test; ltuid_v2=1;',
      client: MockClient(
        (_) async => http.Response(
          '{"retcode":0,"message":"OK","data":{"list":[{"region":"os_asia","name":"Asia","timezone":"+08:00"}]}}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final regions = await api.lookupRegions();
    expect(regions, hasLength(1));
    expect(regions.single.region, 'os_asia');
  });

  test('lookupRegions rejects malformed upstream HTML', () async {
    final api = HoyolabApi(
      cookie: 'ltoken_v2=test; ltuid_v2=1;',
      client: MockClient(
        (_) async => http.Response('<html>bad gateway</html>', 502),
      ),
    );

    await expectLater(
      api.lookupRegions(),
      throwsA(isA<HoyolabHttpException>()),
    );
  });
}
