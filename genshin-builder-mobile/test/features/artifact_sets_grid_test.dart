import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/data/amber/amber_constants.dart';
import 'package:genshin_builder_mobile/domain/artifacts/artifact_set_overview.dart';
import 'package:genshin_builder_mobile/domain/models/amber_detail_models.dart';
import 'package:genshin_builder_mobile/features/artifacts/artifact_sets_screen.dart';

void main() {
  test('artifactSetGridCrossAxisCount scales with width', () {
    expect(artifactSetGridCrossAxisCount(320), 3);
    expect(artifactSetGridCrossAxisCount(390), 4);
    expect(artifactSetGridCrossAxisCount(700), 5);
    expect(artifactSetGridCrossAxisCount(1000), 6);
  });

  test('buildIconUrl uses reliquary path for relic icons', () {
    expect(
      buildIconUrl('UI_RelicIcon_15020_4'),
      'https://gi.yatta.moe/assets/UI/reliquary/UI_RelicIcon_15020_4.png',
    );
    expect(
      buildIconUrl('UI_AvatarIcon_Ayaka'),
      'https://gi.yatta.moe/assets/UI/UI_AvatarIcon_Ayaka.png',
    );
  });

  test('resolveArtifactSetRegion uses sortOrder and overrides', () {
    expect(resolveArtifactSetRegion(id: '15020', sortOrder: 71), '稲妻');
    expect(resolveArtifactSetRegion(id: '15025', sortOrder: 82), 'スメール');
    expect(resolveArtifactSetRegion(id: '15023', sortOrder: 78), '璃月');
    expect(resolveArtifactSetRegion(id: '15001', sortOrder: 42), 'モンド');
  });

  test('groupArtifactSetOverviewsByRegion keeps region order', () {
    final sections = groupArtifactSetOverviewsByRegion([
      const ArtifactSetOverview(
        set: ArtifactSetDetail(
          id: '15025',
          name: '深林の記憶',
          iconUrl: null,
          effects: [],
          region: 'スメール',
          sortOrder: 82,
        ),
        equippedCharacters: [],
        recommendedCharacters: [],
      ),
      const ArtifactSetOverview(
        set: ArtifactSetDetail(
          id: '15020',
          name: '絶縁の旗印',
          iconUrl: null,
          effects: [],
          region: '稲妻',
          sortOrder: 71,
        ),
        equippedCharacters: [],
        recommendedCharacters: [],
      ),
    ]);
    expect(sections.map((s) => s.region), ['稲妻', 'スメール']);
  });
}
