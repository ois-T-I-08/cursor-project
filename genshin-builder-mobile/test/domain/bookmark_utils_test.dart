import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/bookmark_utils.dart';
import 'package:genshin_builder_mobile/domain/models/bookmark.dart';

void main() {
  const character = BookmarkCharacterSource(
    characterId: 'hu-tao',
    characterName: '胡桃',
    characterIconUrl: 'https://example.com/hu-tao.png',
  );

  const ctx = CultivationBookmarkContext(
    kind: CultivationKind.characterLevel,
    targetId: 'hu-tao',
    targetName: '胡桃',
    character: character,
  );

  group('makeRangeSourceKey', () {
    test('matches Web format', () {
      expect(
        makeRangeSourceKey(ctx, 1, 90),
        'range:character-level:hu-tao:1-90',
      );
    });

    test('includes subLabel for talent', () {
      const talentCtx = CultivationBookmarkContext(
        kind: CultivationKind.talent,
        targetId: 'hu-tao',
        targetName: '胡桃',
        subLabel: '元素スキル',
        character: character,
      );
      expect(
        makeRangeSourceKey(talentCtx, 1, 10),
        'range:talent:hu-tao:元素スキル:1-10',
      );
    });
  });

  group('makeItemSourceKey', () {
    test('matches Web format for next scope', () {
      expect(
        makeItemSourceKey(ctx, 'next', '100001'),
        'item:character-level:hu-tao:next:100001',
      );
    });
  });

  group('makeBookmarkId', () {
    test('concatenates sourceKey and materialId', () {
      expect(
        makeBookmarkId('item:character-level:hu-tao:next:100001', '100001'),
        'item:character-level:hu-tao:next:100001:100001',
      );
    });
  });

  group('buildBookmarkEntries', () {
    test('creates entries with character fields', () {
      final entries = buildBookmarkEntries(
        lines: const [
          RequirementLine(materialId: '100001', name: 'テスト素材', count: 3),
        ],
        sourceKey: 'range:character-level:hu-tao:1-90',
        sourceLabel: '胡桃 キャラLv 1→90',
        character: character,
      );
      expect(entries, hasLength(1));
      expect(entries.first.id, 'range:character-level:hu-tao:1-90:100001');
      expect(entries.first.characterId, 'hu-tao');
      expect(entries.first.count, 3);
    });
  });

  group('isMaterialBookmarked', () {
    test('detects existing entry by sourceKey and materialId', () {
      const entry = MaterialBookmarkEntry(
        id: 'item:character-level:hu-tao:next:100001:100001',
        sourceKey: 'item:character-level:hu-tao:next:100001',
        sourceLabel: 'label',
        materialId: '100001',
        name: '素材',
        count: 1,
        addedAt: 0,
      );
      expect(isMaterialBookmarked([entry], entry.sourceKey, '100001'), isTrue);
      expect(isMaterialBookmarked([entry], entry.sourceKey, '999'), isFalse);
    });
  });
}
