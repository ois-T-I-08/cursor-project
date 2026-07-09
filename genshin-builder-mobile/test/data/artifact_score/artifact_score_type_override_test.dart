import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/artifact_score/local_json_artifact_score_type_override_source.dart';
import 'package:genshin_builder_mobile/domain/artifact_score.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads score type overrides from bundled json', () async {
    final source = LocalJsonArtifactScoreTypeOverrideSource();
    final byName = await source.loadByName();

    expect(byName['コロンビーナ'], ArtifactScoreType.hp);
    expect(byName['雷電将軍'], ArtifactScoreType.recharge);
    expect(byName['楓原万葉'], ArtifactScoreType.em);
    expect(byName.containsKey('リサ'), isFalse);
  });
}
