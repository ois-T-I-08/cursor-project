# Agent Memory — Genshin Builder Mobile

セッションごとの設計判断ログ。重要な決定のみ追記する。

## 2026-07-11 — アーキテクチャ改善（段階実装）

- **Phase 0**: `genshin-mobile-ci.yml`（analyze + test）。ARCHITECTURE/AGENTS を Drift・MethodChannel 実態に更新
- **Phase 1**: `Master*` / `ArtifactStatWeights` を `domain/` へ。`OwnedCharacterSortInfo` で一覧ソートから HoYoLAB DTO 分離。Amber 詳細 DTO を `domain/models/amber_detail_models.dart`。Resolver / relic sync は data 層へ
- **Phase 2**: UI Amber 型は domain models。`CharacterDetailTabViews` で詳細タブ分割（screen ~672LOC）。曜日 UI を `features/daily_materials/widgets/` へ
- **Phase 3**: `ProgressRepository` in-memory Drift テスト。`AppDatabase.openInMemory`
- **Phase 4**: Amber JSON デコードを `Isolate.run`（32KB超）。ホーム prefetch は `ref.listen`
- **Phase 5**: `game_record` を props/owned/build/adventure に分割（barrel 維持）。golden に `snapTalentLevel` + `clampInt.below-min`
- **Phase 6（完了）**:
  - `characterDetailProvider`（`AutoDisposeNotifier`）で詳細画面の状態・debounce 保存を分離
  - Amber マスタ一覧パースを `amber_master_parsers.dart` + `Isolate.run`（characters/weapons/materials）
  - golden に `artifactMainStatValue` / `inferScoreType` / `calcPieceScore`（Web・Mobile 同一ケース）

## 2026-07-10 — 曜日別育成素材管理

- **画面**: `/daily` + ボトムナビ「曜日」。ホームにショートカット。初期タブは JST 4:00 リセット考慮の今日
- **スケジュール正本**: `assets/config/daily_material_schedule.json`（天賦本・武器突破シリーズ × 曜日）。新シリーズは JSON 追記のみ
- **不足数**: 既存 `getRangeTalentRequirements` / `getRangeLevelRequirements`。キャラ/武器紐づけは upgrade の `costItems` から自動（ハードコード一覧なし）
- **進捗**: `ProgressDao.getAllProgress` 追加。対象は保存済み `UserProgress`（天賦→10 / 武器→90）
- **起動時 prefetch**: ホームで `dailyProgressPrefetchProvider`。今日の天賦素材を使う**所持キャラ**だけ `getOrCreate` + HoYoLAB 詳細同期（並列3）。未連携時はスキップ。完了後 `dailyMaterialsPlanProvider` を invalidate
- **層**: domain planner（純関数） / data schedule+service / features UI。将来: 聖遺物秘境・週ボスは `DailyMaterialKind` 拡張

## 2026-07-10 — キャラ詳細シミュレーション機能

- **ステータス計算**: `domain/character_stats.dart`（Web `stats.ts` 移植・純Dart）。基礎×曲線＋突破＋武器＋聖遺物。セット効果・武器パッシブは対象外
- **曲線/スキル詳細**: `data/amber/amber_detail_repository.dart` — `/static/avatarCurve|weaponCurve` + avatar/weapon detail をメモリキャッシュ。失敗時 null → UI フォールバック
- **取得/シミュ分離**: `CharacterBuildSnapshot` に取得情報を保持。「取得情報に戻す」（AppBar + 想定タブ）で復元。編集状態は従来通り Drift 保存
- **UI**: 「想定」タブ（天賦↔HoYoLAB間）で現在/想定/差分表示。聖遺物タブ上部にスコア合計カード（基準選択は最下部へ移動）。天賦タブにスキル詳細（説明+レベル別倍率/CT）。武器変更時に差分確認ダイアログ
- **7–11**: 武器種フィルタ（`allowedWeaponType`）。武器/聖遺物は長押しで詳細シート。レベルタブに基礎ステ・突破ステ・次の段階素材（突破素材セクションは廃止し次の段階へ統合）。Lv90でもスライダーでシミュレーション可
- **12**: 武器選択はボトムシート一覧。行タップ=変更、ⓘ=`showWeaponDetailSheet`（変更しない）。共通行 UI は `SelectableDetailListTile`（聖遺物選択にも流用可）
- **14**: ヘッダーに命ノ星座 6 アイコン（`ConstellationIconsRow`）。取得済みは元素色。タップで Amber 凸効果。表示凸数 `_constellation` は取得データと分離（将来シミュ用）。`AvatarDetailData.constellations` を Amber からパース
- **武器並び替え**: `weapon_list_sort.dart` + 選択シート上部ドロップダウン（人気順・使用率 / レア度 / 基礎ATK）。人気順は Akasha `GET /api/builds?filter=[characterId]…&sort=_id` を最大 200 件集計（失敗時はローカル推定）。シート表示中のみ保持。フィルター用 `WeaponListFilter` を先行定義
- **テスト**: `test/domain/character_stats_test.dart` / `weapon_list_sort_test.dart`
- **次回**: 想定ステータスにセット効果を加算する場合は Amber reliquary セット効果テキストの取得が必要（詳細シートでは取得済み）

## 2026-07-10 — Domain Golden パリティ

- **正本**: `../shared/domain-golden/cases.json`
- **テスト**: `test/domain/domain_golden_test.dart`（Web Vitest と同一ケース）
- **CI**: `.github/workflows/genshin-domain-golden.yml`
- **方針**: 片側だけ失敗したら実装を直す。golden を安易に変更しない

## 2026-07-08 — 全体最適化（構成見直し）

- **進捗保存**: キャラ詳細スライダー変更を 800ms debounce で `user_progress` 永続化
- **DB**: `upgrade_serde.dart` 共有、マスタ同期を batch upsert に変更
- **Repository**: `progress_repository.dart` を分離、`materialsMapProvider` 追加
- **HoYoLAB**: dailyNote エラーを `HoyolabApiException.userMessage` で表示
- **Web**: `formatMora` / `isMaterialBookmarked` 重複除去、ARCHITECTURE ブックマーク追記

## 2026-07-08 — Phase 2 HoYoLAB 連携実装

- **API**: `hoyolab_api.dart` — dailyNote / verifyLToken / getUserGameRoles + `ApiRequestQueue` 500ms
- **認証**: DS 署名（`hoyolab_auth.dart`）、Cookie は `flutter_secure_storage` のみ
- **UI**: WebView ログイン、設定（連携/解除/UID選択）、ホーム `DailyNoteCard`
- **機能フラグ**: `app_settings.hoyolab_link_enabled`（Remote Config 相当）
- **Cookie 取得**: `webview_flutter` の `WebViewCookieManager`（Pigeon は未使用）

## 2026-07-08 — Phase 1 着手（bookmark_utils + Drift 土台）

- **P1-1 完了**: `domain/bookmark_utils.dart` — Web `bookmark-utils.ts` 準拠の sourceKey / エントリ生成
- **P1-0 着手**: `lib/data/db/drift/` に tables / daos / AppDatabase 定義。現行は sqflite 継続（`sqflite_database.dart`）
- **app_settings** 追加（v2 migration）— `localUserId` を DB 永続化（毎回 UUID 生成バグ修正）
- **次ステップ**: `flutter pub get && dart run build_runner build` → Drift 切替、UI パネル分割（P1-4）


- **Phase 1**: Drift DB + Web 同等の育成 UI / ブックマーク（sqflite scaffold から移行）
- **Phase 2**: HoYoLAB（WebView + Pigeon Cookie + secure storage + dailyNote）— 設計 + 骨組み
- **参考**: genshin_material の HoYoLAB 部分は MIT 尊重の上、概念参考のみで自前実装
- **ARCHITECTURE.md** を Phase 分け・UI 移植マップ・HoYoLAB シーケンス図付きで更新

## 2026-07-08 — 初回 scaffold

- **方針**: Web 版計算ロジックを `lib/domain/` に移植。UI は Flutter ネイティブ新規。
- **DB**: Phase 1 は `sqflite`（Drift は genshin_material 参考として Phase 1.5 移行候補）。
- **データ源**: Project Amber (`gi.yatta.moe`) — Web と同一。
- **HoYoLAB**: Phase 2 のみ。Cookie 非実装。
- **Flutter SDK**: 開発環境に未インストールのため、`flutter create .` は README 手順に記載。
- **匿名 userId**: Web と同様ローカル UUID（`user_progress.user_id`）。
