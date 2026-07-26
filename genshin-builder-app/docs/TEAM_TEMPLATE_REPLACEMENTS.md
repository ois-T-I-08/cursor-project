# 編成テンプレートと入れ替え候補

## 境界とデータフロー

```text
承認済みローカルJSON（将来: 許可取得済みGenshinBuilds API）
  → TeamSource
  → Zod検証・ID/役割正規化・順序非依存teamHash
  → ImportedTeam（原本）/ ImportedTeamMember（正規化）
  → 管理者承認・重複統合
  → TeamTemplate（公開用）
  → CharacterTeamProfileから最大10〜20件を通常コードで抽出
  → 管理者操作でDeepSeek JSON評価
  → Zod検証・allowedCandidateIds照合・通常コード再評価
  → TeamReplacementResult/Candidateへ版付き保存
  → 公開GET
  → Flutterで所持・育成度を端末計算して表示
```

外部原本、正規化済みデータ、公開テンプレート、AI出力、検証済み候補、ユーザー表示結果は別レイヤーです。外部の攻略本文は取得・保存・公開しません。

## 取得元

- `LocalJsonTeamSource`: `data/team-templates/approved-teams.json`だけを最大1 MiBで読みます。
- `ManualTeamSource`: 管理コードから検証対象を注入できます。
- `GenshinBuildsTeamSource`: 交換境界だけを実装済みです。正式な第三者API URL、認証、利用条件、保存・再配布許可が確定するまで必ず`genshinBuildsApiNotConfigured`で停止します。

GenshinBuilds接続時は推測URLを追加せず、同クラス内でHTTPS固定、ホスト許可リスト、redirect拒否、応答サイズ、timeout、rate limitを追加してください。`TEAM_SOURCE_ALLOWED_HOSTS`は既定で空のため、正式URLと利用許可を確認するまで取得元URLは保存できません。

キャラクター判断データは`data/team-templates/character-profiles.json`から管理者が取り込みます。空の既定ファイルは本番データではありません。全プロフィールは既存Character IDに存在し、同じ`gameVersion`/`dataVersion`で、`isLeak=false`のものだけを生成に使います。

## API

公開API:

- `GET /api/team-templates`
- `GET /api/team-templates/:templateId/replacements/:characterId`

公開APIはAIを呼ばず、公開済みかつ検証済みの保存結果だけを返します。APIキー、AI原文、管理メタデータ、ユーザー育成情報は返しません。

管理API:

- `GET /api/admin/team-templates`: 取込、テンプレート、生成Job、ログの確認
- `POST /api/admin/team-templates`

POSTの`action`は`importProfiles`、`importLocal`、`approve`、`reject`、`generate`、`overrideResult`、`publish`、`unpublish`です。推奨順はプロフィール取込→編成取込→承認→生成→結果確認→公開です。`generate`の`force:true`で同一キーを管理者が再生成できます。`overrideResult`も同じZod Schema、一次候補許可リスト、決定論的最終検証を通るため、任意キャラクターの追加や検証回避はできません。

管理APIは`TEAM_TEMPLATE_ADMIN_SECRET`のBearer認証が必須です。未設定時は開発環境を含め503でfail closed、1 IPあたり10回/分、本文64 KiBです。レート制限は単一プロセス内の防御なので、複数インスタンスで運用する場合はリバースプロキシまたは共有ストア側にも制限を設定してください。

## DeepSeek

サーバー側の固定エンドポイント`https://api.deepseek.com/chat/completions`だけを使用します。2026-07-26時点の公式仕様に合わせ、許可モデルを`deepseek-v4-flash`/`deepseek-v4-pro`へ限定し、既定はflash、thinking無効、`response_format: json_object`です。

入力は構造化プロフィールと通常コードが許可したIDだけです。システム指示はJSON以外の禁止、未提示情報の推測禁止、データ内文字列を命令として扱わないこと、4人全体の反応・耐久・エネルギー・滞在時間評価を固定しています。

空応答、429、500、503、timeout、network errorだけを最大3回まで指数バックオフで再試行します。400/401/402/422、不正JSON、不正Schema、長さ打切りは再試行しません。失敗時は同スロットの最終正常キャッシュを維持し、存在しない場合だけ構造化プロフィールによる低信頼度fallbackを保存します。

キャッシュキー:

- teamHash
- replacedCharacterId
- gameDataVersion
- characterDataVersion
- promptVersion
- rulesVersion
- modelIdentifier

Jobにはattempts、cacheHits、成功・失敗数、token usageだけを保存し、APIキーやprompt本文はログへ出しません。

## 通常コードの最終検証

Zod検証後も次を適用します。

- 許可候補外、候補重複、編成内重複、未知キャラクターを除外
- プロフィール版不一致・リークフラグを除外
- 高フィールド時間の競合、必要元素付着消失、耐久枠消失、energy battery不在、`requires_tag:*`未充足を減点
- 最終点から最適（85以上）、条件付き（65以上）、妥協（45以上）、非推奨を再分類

AIのカテゴリや高得点だけで公開判定しません。

## Flutter

承認テンプレートは既存おすすめ編成内に表示します。各スロットの「入れ替え候補」から次を確認できます。

- 編成適性: サーバーの事前評価＋決定論的検証
- 育成準備度: HoYoLAB/ローカルの所持、レベル、突破、天賦、凸、武器、聖遺物から端末計算
- 総合おすすめ度: 既定70%/30%。`teamReplacementScoreWeightsProvider`を上書き可能

フィルターは所持、育成優先、最適、条件付き、元素、役割です。候補選択後は4人をプレビューし、「編成に反映」の確認後だけBuilderの4枠を変更します。

## DB移行とNeon

追加migrationは`20260726120000_add_team_template_replacements`です。現行mainのPrisma datasourceはSQLiteなので、ローカル検証用SQLもSQLite形式です。

Neon/PostgreSQL基盤はGitHub PR #16にありますが、2026-07-26時点でDraft、mainと競合、本番migration未適用、PR本文でもmerge禁止です。この変更から同PRを推測統合していません。PR #16が正式に統合された後、同じPrismaモデルからPostgreSQL migrationを再生成し、development Neonで以下を確認してから本番適用してください。

1. migration dry-runと既存行数確認
2. 空のローカルJSON取込
3. テスト用承認データで重複upsert
4. DeepSeekモック結果のtransaction保存
5. 失敗時に最終正常結果が維持されること
6. 公開GETがAI原文・秘密情報を返さないこと

本番DBへこのSQLite migrationを直接適用してはいけません。

## 環境変数

- `TEAM_TEMPLATE_ADMIN_SECRET`（必須）
- `TEAM_SOURCE_ALLOWED_HOSTS`（既定は空。確認済みHTTPSホストだけをカンマ区切りで指定）
- `DEEPSEEK_ENABLED`（既定false）
- `DEEPSEEK_API_KEY`（server only）
- `DEEPSEEK_MODEL`
- `DEEPSEEK_TIMEOUT_MS`
- `DEEPSEEK_MAX_ATTEMPTS`
- `TEAM_REPLACEMENT_MAX_CANDIDATES`

Flutterへ新しい秘密は追加しません。既存`GENSHIN_BUILDER_API_BASE_URL`だけを使用します。

## 公式仕様参照

- DeepSeek pricing: https://api-docs.deepseek.com/quick_start/pricing
- Rate limit: https://api-docs.deepseek.com/quick_start/rate_limit
- Error codes: https://api-docs.deepseek.com/quick_start/error_codes/
- JSON output: https://api-docs.deepseek.com/guides/json_mode
- Chat completion: https://api-docs.deepseek.com/api/create-chat-completion
- Thinking mode: https://api-docs.deepseek.com/guides/thinking_mode

依存監査によりNext.js固有の2026年アドバイザリを避けるため16.2.10から最新stableの16.2.12へ更新しました。16.2.12が固定する`postcss`/`sharp`にはhigh指摘が残るため、Next.js公式previewが採用済みのsharp 0.35系と、同じPostCSS 8系の修正版をnpm overridesで適用しています。`npm audit --omit=dev`は0件です。Next.js stableが両方を取り込んだ後はoverrideを外して再監査してください。`npm audit fix --force`はNext.js 9.3.3への破壊的downgradeになるため使用しません。

開発依存を含む監査には、`eslint-config-next`配下の旧`brace-expansion`によるglob展開DoSが残ります。CIと開発用lintは固定引数で実行し、外部入力をglobへ渡しません。ESLint 10への更新は同梱React pluginが未対応でlint自体を壊すため採用せず、Next.js側のplugin更新を追跡します。
