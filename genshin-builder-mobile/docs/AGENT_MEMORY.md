# Agent Memory — Genshin Builder Mobile

セッションごとの設計判断ログ。重要な決定のみ追記する。

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
