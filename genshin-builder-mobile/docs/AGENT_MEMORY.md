# Agent Memory — Genshin Builder Mobile

セッションごとの設計判断ログ。重要な決定のみ追記する。

## 2026-07-12 — [P1-8B] 樹脂190 / 探索派遣5完了ローカル通知

- 状態: **実装完了・Android実機確認保留**
- 範囲: 樹脂190（予約+即時）/ 探索派遣5完了 / 設定・権限・チャネル / タップ→Home / Fresh DailyNote reconcile / 解除・切替 cancel-reset
- 非範囲: 23時デイリー、WorkManager、background isolate、flutter_timezone、Exact Alarm、FGS、P1-8A 変更
- 依存: `flutter_local_notifications 19.5.0` + `timezone 0.10.1` のみ。schedule は `TZDateTime.from(notifyAt.toUtc(), UTC)` + `AndroidScheduleMode.inexactAllowWhileIdle`
- Android: desugaring + multiDex + desugar_jdk_libs 2.1.4。Java17/AGP 据え置き。Manifest に POST_NOTIFICATIONS / BOOT_COMPLETED / VIBRATE + ScheduledNotificationReceiver/BootReceiver。Exact Alarm 権限なし
- 初期化: `NotificationBootstrap.ensureInitialized` single-flight。`main` で unawaited（権限要求なし・runApp 非ブロック）。Scheduler 各操作は ensureInitialized await
- Hook: `DailyNoteNotifier._fetchAndSave` のみ。同一 `fetchedAt` で cache 保存→Coordinator。cache 表示だけでは reconcile しない。API失敗は既存予約維持、成功だが invalid はカテゴリ cancel
- Coordinator: serial queue + sequence + account/settings generation。plugin 成功後のみメタ保存
- 設定: 既定 OFF。ON 時のみ権限要求。`effectiveEnabled = pref && OS`。OS 拒否でも希望設定は維持。端末設定導線（MethodChannel）
- 起動時 cache 再登録なし（plugin Boot receiver に委ねる）
- 変更: application/hoyolab_reminders/*、providers、settings/hoyolab settings、main、daily_note presence、disk cache fetchedAt、Android Gradle/Manifest/MainActivity、関連テスト、本メモ
- 検証: P1-8B 関連 + 保護3 + 全 test 308 成功、対象 analyze 問題なし、全体 analyze は既存 info/warning のみ（error なし）、debug APK 成功。Exact Alarm / WorkManager / flutter_timezone なし。domain 内容差分なし
- **実機未確認:** 権限ダイアログ、Doze/OEM 遅延、再起動後の予約復元、樹脂/派遣フロー、解除・切替、terminated タップ→Home、通知後の P1-8A Back
- ロールバック: P1-8B 追加ファイル削除 + 上記変更ファイル差し戻し（pubspec / Android 設定含む）

## 2026-07-12 — [P1-8A] Android システム Back（Home で終了しない）

- 状態: **実装完了・Android実機確認保留**
- 目的: Android Back で Dialog→通常 pop→トップレベルは `go('/')`→Home では消費。Home 連打でもアプリ終了しない
- 配置: `AppShell` 内（Android のみ）。`BackButtonListener`（GoRouter より先に Drawer/Home を処理）+ `PopScope`（Predictive Back の canPop）
- canPop: 既知 nested path（`/characters/:id`, `/settings/...`）かつ Drawer 閉。`GoRouter.canPop()` は Shell build 時点で stale になり得るため path 判定を採用
- Drawer: BackButtonListener で `closeEndDrawer`（ShellRoute 下では local history が Drawer より先に detail を pop するため）
- 非 Android: PopScope/Listener なし（既存挙動）
- 変更: `lib/router.dart`, `lib/navigation/android_system_back.dart`, `test/navigation/android_system_back_test.dart`
- 検証: P1-8A 19 + 保護3 + 全 test 261 成功、対象 analyze 問題なし、debug APK 成功。通知/HoYoLAB/domain/Drift 非変更
- **実機未確認:** 3ボタン/Gesture/Predictive Back アニメ、Dialog/Drawer、Home 連打、通知復帰後 Back
- ロールバック: 上記3実装ファイル + AGENT_MEMORY 差し戻し

## 2026-07-12 — [P1-7] Remote JSON 防御（streaming fetch）

- 目的: dart-define Remote JSON（weights / daily / gacha history）の timeout・status・byte 上限・decode・validator・fallback・安全ログを統一。巨大レスポンスをメモリに載せ切らない
- 共通: `fetchRemoteJsonMap`（`client.send` + stream 累積、Content-Length / 途中超過で `responseTooLarge`）。Client は Source 注入・helper は close しない
- maxBytes: weights/daily 256KiB、gacha 1MiB（local gacha ~99KiB 根拠）
- Content-Type 単独拒否なし。明らかな HTML（先頭 `<`）のみ `invalidJson`
- Composite/PreferRemote のみ `logConfigLoad`（URL/body/秘密なし）。fetch/Source はログしない
- 採用ポリシー・TTL・domain・P1-6 起動は非変更。local-only 3経路は P1-7b
- 検証: 関連+保護3+全 test 成功、対象 analyze 問題なし、debug APK 成功、3 local asset validator 通過、domain 内容差分なし
- **実機未確認:** 実 Remote URL 障害時の fallback、巨大レスポンス、低速回線

## 2026-07-12 — [P1-6] 起動パスの段階化（ローカルファースト）

- 目的: 既存ローカルがあるときネットワークを待たずホーム表示。同期必要 ≠ 起動ブロック
- 判定: `requiresBlockingBootstrap` = `characters == 0` のみ。`needsBackgroundRepair` に突破欠落・EXP・武器/素材0 など
- Home 後: `BackgroundMasterRepair`（`_inFlight` + `_startedAfterHome` + bootstrap mark + probe token）。同一プロセス冪等
- 初回同期成功時は `markMasterSyncCompletedDuringBootstrap` で同一起動の probe/再 MasterSync を省略（icons/weights/HoYoLAB のみ）
- 手動同期は BG 中 `ManualSyncStart.busy`（合流して成功扱いにしない）
- Amber probe: ホーム後・並列・15s timeout・遅延結果不採用
- 変更: `sync_status` / `initial_sync_screen` / `master_sync_runner` / `background_master_repair` / probe・Amber 件数並列 / `app.dart` / home / settings / provider / テスト
- 状態: **実装完了・実機性能確認保留**
- 検証: P1-6 + 保護3 + 全 test 成功、対象 analyze 問題なし、debug APK 成功。domain 内容差分なし
- **実機未確認:** コールド/オフライン時間、低速回線、初回同期、Home first frame、BG probe/repair、アイコン後載せ、HoYoLAB prefetch
- ロールバック: 上記ファイル差し戻し（domain/schema/Cookie 未変更）

## 2026-07-12 — [P1-3] HoYoLAB Cookie / MethodChannel 硬化

- 目的: WebView ログイン直後 Cookie を優先し、正規化→API 検証→SecureStorage までを UseCase 1 回で完結。UI には成功/失敗のみ返す
- データフロー: WebViewCookieManager → Native `fetchCookie`（欠落キーのみ補完、同一キーは WebView 優先）→ Normalizer（完全一致 `ltoken_v2`|`ltoken`）→ `CompleteHoyolabWebLoginUseCase` → 既存 `HoyolabRepository.completeLogin`（verify→roles→save 順維持）→ `Navigator.pop(true)` / Settings は `true` 時のみ Provider refresh
- MethodChannel 契約: `genshin_builder_mobile/hoyolab_cookie` / `fetchCookie`。あり=`success(string)`、なし=`success(null)`、内部例外=`COOKIE_MANAGER_ERROR`。Flutter 結果型 `ok|absent|managerError|pluginMissing`（WebView があれば継続）
- 変更ファイル: `MainActivity.kt`、`hoyolab_cookie_channel.dart`、`hoyolab_cookie_service.dart`、`hoyolab_cookie_normalizer.dart`、`native_cookie_fetch_result.dart`、`CompleteHoyolabWebLoginUseCase`、login/settings 画面、`hoyolab_providers.dart`、関連テスト
- 検証: Cookie 系 + 全 `flutter test` 成功、P1-3 対象 `flutter analyze` 問題なし、`flutter build apk --debug` 成功。`lib/domain/**` / Drift / MethodChannel 名・保護ゴールデンは内容差分なし
- **実機未確認:** WebView ログイン、CookieManager 取得、MainActivity MethodChannel、SecureStorage 実保存、連携解除
- ロールバック: 上記変更ファイルを差し戻し（Repository / domain / SecureStorage キーは未変更のため影響範囲は Cookie 収集〜UI 結果のみ）

## 2026-07-12 — [P1-2] applicationId + release signing fail-closed

- 目的: `com.example.*` 解消、release の debug 署名フォールバック廃止、CI/ローカルで安全な署名付き AAB
- 決定事項: ID=`io.github.oisti08.genshinbuilder`（namespace/MainActivity 一致）。署名検証は release タスク時のみ。Secrets は `workflow_dispatch` の release 例のみ。AAB 署名確認は jarsigner
- 状態: **実装完了 / 公開前 Release Verification 保留**（正規 keystore・実機・Secrets が無い環境では検証未完了）
- 変更ファイル: `android/app/build.gradle.kts`、MainActivity 移動、`key.properties.example`、`genshin-mobile-release-example.yml`、`docs/ANDROID_RELEASE.md`
- **公開前保留事項（チェックリスト）:**
  - [ ] 正規アップロード用 keystore を作成・バックアップする
  - [ ] `android/key.properties` をローカルで設定する
  - [ ] 署名付き AAB を生成する
  - [ ] jarsigner で AAB 署名を確認する
  - [ ] applicationId を確認する（`io.github.oisti08.genshinbuilder`）
  - [ ] 実機で起動と HoYoLAB MethodChannel を確認する
  - [ ] GitHub Secrets を設定して release workflow を確認する
  - [ ] Play Console 登録前に applicationId を最終確認する

## 2026-07-12 — [P1-5] 聖遺物セット / Akasha 負荷制限

- 目的: セット一覧オープン時の Akasha API 過剰リクエストを防止（計算・表示ロジックは維持）
- 変更内容: sample を所持+聖遺物進捗のみ、`kArtifactAkashaSampleLimit=32`、一覧 concurrency 6→4。pages/pageSize・詳細1キャラ Provider・domain は非変更
- 変更ファイル: `lib/providers/artifact_sets_page_providers.dart`、`test/data/akasha/akasha_artifact_set_usage_test.dart`
- 未完了 / 次回: `artifactSetOverviewsProvider` の invalidate 分離、Akasha 非ブロッキング後載せ、HoYoLAB detail 負荷、武器 Akasha は別 Task

## 2026-07-12 — [P1-1] パリティゲート固定

- 目的: 計算仕様を変えず、破壊検知ゲートだけを強化する
- 決定事項: mobile CI で全件 test の前に `domain_golden` / `artifact_completion` / `artifact_score` を名前付き必須実行。`genshin-domain-golden.yml` と cases.json / domain ロジックは触らない
- 変更ファイル: `.github/workflows/genshin-mobile-ci.yml`、`shared/domain-golden/README.md`、`AGENTS.md`
- 未完了 / 次回: GitHub で本 job を required check にする運用。P1-5（Akasha 負荷）など Phase1 続き

## 2026-07-12 — ホームに開催中イベント

- ennead calendar の `events[]` をホーム「開催中のイベント」カードで表示（DailyNote の下）
- 期間 0 は除外。開催中→予告、最大5件。同一 API キャッシュをガチャバナーと共有

## 2026-07-12 — ガチャ（PUバナー履歴）画面

- ドロワー「ガチャ」(`/gacha`): 個人祈願ログは対象外。PUバナー日程一覧
- 並び: 開催中（終了近い順）→ 予告 → 終了済み（開始新しい順）
- Live: `api.ennead.cc/mihoyo/genshin/calendar`。履歴: `assets/config/gacha_banner_history.json` + 任意 `GACHA_BANNER_HISTORY_URL`
- 履歴シードは paimon-moe `banners.js` → Amber EN ID 変換（`tool/convert_paimon_banners.py`）

## 2026-07-12 — フッターナビ → 右ドロワー

- `AppShell` の `NavigationBar` を廃止し `endDrawer`（`NavigationDrawer`）へ
- AppBar 右上 `ShellMenuButton` + 右端スワイプで開く

## 2026-07-12 — キャラ一覧を聖遺物と同じ地域順に

- 既定表示: 地域セクション + グリッド（聖遺物一覧と同レイアウト）
- 地域順: モンド→璃月→稲妻→スメール→フォンテーヌ→ナタ→ノド・クライ→その他（ファデュイなし）
- 例外: スカーク→ナタ、サンドローネ→ノド・クライ。他ファデュイ/旅人→その他
- `normalizeCharacterRegionForDisplay` で表示時・同期パース時に正規化

## 2026-07-11 — 聖遺物一覧 UI（グリッド＋詳細ダイアログ）

- 一覧は地域セクション付き `GridView`（幅で 3/4/5/6 列）。セルはアイコン＋セット名
- アイコン URL は `UI_RelicIcon_*` → `assets/UI/reliquary/`（直下は 404）
- 地域は Amber `sortOrder` 帯 + 層岩例外。API に region が無いため
- 装備キャラ: **`/character/detail` の relics が正本**（`/character/list` は装備なし）。進捗 JSON はフォールバック。突合はアイコン ID → 名前/route/aliases。2部位以上のみ
- 所持ビルドは最大40件バッチ＋TTLキャッシュ。HoYoLAB 反映は即保存（debounce 破棄対策）


## 2026-07-11 — 聖遺物管理（育成完了・完成率・セット一覧）

- **育成完了**: 既存 `user_progress.is_completed` を `UserProgress.artifactCompleted` として利用（新テーブルなし）。キャラ詳細聖遺物タブでチェック、オフライン永続
- **完成率**: `domain/artifact_completion.dart` で計算のみ（装備/Lv/メイン/サブ/スコア）。DB には保存しない
- **装備紐づけ**: `/character/detail` relics を主、所持 list / 進捗 `artifacts` を副

- **セット一覧**: Amber `ArtifactSetDetail` + `/artifacts` タブ。推奨は `assets/config/artifact_set_recommendations.json`（名前キー）
- **ナビ**: ホーム/キャラ/曜日/聖遺物/素材/設定（曜日は維持）

## 2026-07-11 — contentHash / Level EXP JSON / 設定検証 / SQLCipher / hook 強化

- **突破 contentHash**: `CharacterUpgrades` / `WeaponUpgrades` に `contentHash`（schema v6）。upsert 時に promotes+talents（武器は levelUpItemIds）の MD5 を保存。通常同期は未取得・空ハッシュ UNION、加えて `refreshStaleUpgrades`（既定 true）で各最大 15 件ランダム再取得。設定画面に注記
- **Level EXP**: 正本 `assets/config/level_exp_table.json` + `LevelExpTableSource`。同期は asset → DB。`getAllLevelExpSegments` 追加。計算は従来どおり `UpgradeDataCache.levelExpSegments` 優先
- **設定検証**: `config_validators.dart` を remote source の `fromJson` 前に呼ぶ。`tool/validate_config_json.dart` + `assets/config/schemas/*.schema.json`
- **SQLCipher**: `sqlcipher_flutter_libs` のみ（`sqlite3_flutter_libs` は外した）。`ENABLE_SQLCIPHER=true` 時のみ PRAGMA key。既定 false で平文 DB 維持。`docs/DB_ENCRYPTION.md`
- **auto-commit**: `EXCLUDE_PATTERNS` / `SECRET_PATTERNS` 強化。pending に `files[]`。最大 40 ファイルでスキップ。diff に ltoken/cookie/PRIVATE KEY があれば中止
- **docs**: `DAILY_MATERIAL_SCHEDULE_REMOTE.md`（URL 設定手順）

## 2026-07-11 — 機能拡張 1–10（本番 applicationId 除く）

- **1** 想定ステータスに2セット効果（Web 同等テキスト抽出）
- **2** 命ノ星座タップで凸シミュ（再タップで戻す・長押しで効果）
- **3** 曜日素材に聖遺物秘境・週ボス（スケジュール + 週ボスは天賦コスト紐づけ）
- **4** `docs/DAILY_MATERIAL_SCHEDULE_REMOTE.md`（`DAILY_MATERIAL_SCHEDULE_URL`）
- **5** 突破 `contentHash` + 同期時の stale 再取得（最大15件）
- **6** `assets/config/level_exp_table.json` を正本に
- **7** リモート設定の `config_validators` + `tool/validate_config_json.dart`
- **8** 本番 applicationId — **後回し**（未公開）
- **9** SQLCipher は `ENABLE_SQLCIPHER` オプトイン（既定オフ）`docs/DB_ENCRYPTION.md`
- **10** auto-commit: 除外強化・touched files・件数上限・秘密スキャン
- **11–13** Team / Damage / Cloud — プラン確定後

## 2026-07-11 — マスタ同期の自動更新対応

- **現状解析**: Amber 一覧は毎回 upsert。突破は **未取得 ID のみ**（`fullUpgrade` は未配線だった）。起動同期は初回のみ。曜日スケジュールは asset 固定。
- **改善**:
  - `MasterContentProbe` — Amber 一覧件数 vs ローカル件数で新コンテンツ検知
  - 起動時: `shouldAutoSyncOnLaunch`（未同期/突破不足）またはプローブ `shouldSync` で自動同期
  - 設定: 「完全再同期」で `fullUpgrade: true`（突破全件再取得）
  - `getLastSyncTime` は `success` + `partial` を対象
  - 曜日スケジュール: `DAILY_MATERIAL_SCHEDULE_URL`（dart-define）でリモート JSON。`version` がローカル以上なら採用
- **残課題（手動/将来）**: 新天賦本シリーズの JSON 追記（リモート未設定時）。既存突破の全件差分は contentHash サンプル再取得 + 完全再同期でカバー
- **恒久ルール**: 機能追加時は Sync 連携必須（`.cursor/rules/genshin-master-sync-extensibility.mdc` + `AGENTS.md` §8）

## 2026-07-11 — 拡張アーキテクチャ P0–P3

- **P0**: `application/characters`（State + Load/Save/ApplyHoyolab UseCase）。Notifier は UseCase 呼び出しに薄型化
- **P1**: `domain/repositories` 契約 + `DriftCharacterRepository` / `DriftProgressRepository`。features の master/display/weights は domain 参照へ
- **P2**: `domain/team` · `domain/damage` · `domain/meta` + Akasha→`MetaRankingSource` アダプタ
- **P3**: `UserAccount` + `CloudSyncPort` + `LocalOnlyCloudSync`（`cloudSyncPortProvider`）
- **docs**: AGENTS 層依存ルール、ARCHITECTURE 図更新

## 2026-07-11 — セキュリティ Phase 0–1

- **Release**: minify/shrink + ProGuard、`key.properties` 任意署名、`allowBackup=false` + data extraction 除外
- **HoYoLAB**: 全 HTTP に 25s timeout。cookie は `verifyLToken` + ロール取得成功後のみ SecureStorage へ
- **エラー**: `core/errors/user_facing_error.dart` でユーザー文言と debug ログを分離。生 `$e` 表示を除去
- **CI**: mobile CI に簡易 secret ガード、release 例に `--obfuscate --split-debug-info`
- **未実施（次段階）**: applicationId 本番化。SQLCipher を本番常時 ON にする場合のネイティブ衝突確認・平文→暗号マイグレーション
- **起用**: プロジェクト Skill `.cursor/skills/genshin-security-checklist/`
- **自動読込**: `.cursor/rules/genshin-security-checklist.mdc`（alwaysApply）。Read 前に「genshin-security-checklist を読みます」と宣言

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
- **Cookie 取得**: WebView 優先 + Native MethodChannel 補完（P1-3 で硬化。Pigeon は未使用）

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
